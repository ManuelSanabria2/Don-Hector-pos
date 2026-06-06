import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;

import '../../data/models/carrito_item.dart';
import '../../data/models/cliente_mayorista.dart';
import '../../data/models/producto.dart';
import '../../data/models/venta_enums.dart';
import '../../data/repositories/inventario_repository.dart';
import '../../data/repositories/mayoristas_repository.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'pos_providers.dart';
import '../mayoristas/mayoristas_providers.dart';

class AsistenteState {
  const AsistenteState({
    this.isListening = false,
    this.textSpoken = '',
    this.aiResponse = '',
    this.isProcessing = false,
    this.hasError = false,
    this.errorMessage = '',
    this.soundLevel = 0.0,
  });

  final bool isListening;
  final String textSpoken;
  final String aiResponse;
  final bool isProcessing;
  final bool hasError;
  final String errorMessage;
  final double soundLevel;

  AsistenteState copyWith({
    bool? isListening,
    String? textSpoken,
    String? aiResponse,
    bool? isProcessing,
    bool? hasError,
    String? errorMessage,
    double? soundLevel,
  }) {
    return AsistenteState(
      isListening: isListening ?? this.isListening,
      textSpoken: textSpoken ?? this.textSpoken,
      aiResponse: aiResponse ?? this.aiResponse,
      isProcessing: isProcessing ?? this.isProcessing,
      hasError: hasError ?? this.hasError,
      errorMessage: errorMessage ?? this.errorMessage,
      soundLevel: soundLevel ?? this.soundLevel,
    );
  }
}

final posAsistenteProvider =
    StateNotifierProvider<PosAsistenteController, AsistenteState>((ref) {
  return PosAsistenteController(ref);
});

// A local in-memory storage for draft orders (pedidos pendientes) by client name/ID
final pedidosPendientesProvider = StateProvider<Map<String, List<CarritoItem>>>((ref) => {});

class PosAsistenteController extends StateNotifier<AsistenteState> {
  PosAsistenteController(this._ref) : super(const AsistenteState()) {
    _initGlobal();
  }

  final Ref _ref;
  final SpeechToText _speech = SpeechToText();
  final FlutterTts _tts = FlutterTts();
  bool _speechEnabled = false;

  void resetState() {
    state = state.copyWith(textSpoken: '', errorMessage: '', hasError: false, aiResponse: '');
  }

  Future<void> _initGlobal() async {
    try {
      _speechEnabled = await _speech.initialize(
        onError: (val) {
          if (!mounted) return;
          if (val.errorMsg.contains('no-speech') || val.errorMsg.contains('error_speech_timeout') || val.errorMsg.contains('error_no_match')) {
             state = state.copyWith(isListening: false);
             return;
          }
          state = state.copyWith(hasError: true, errorMessage: 'Error de micrófono: ${val.errorMsg}');
        },
        onStatus: (val) {
          if (!mounted) return;
          if (val == 'done' || val == 'notListening') {
            state = state.copyWith(isListening: false);
          }
        },
      );

      await _tts.setLanguage('es-CO');
      await _tts.setSpeechRate(0.95);
      await _tts.setPitch(1.3); // Tono más agudo para emular voz femenina si la por defecto es masculina
      
      // Intentar buscar explícitamente una voz femenina instalada
      List<dynamic>? voices = await _tts.getVoices;
      if (voices != null) {
        for (var v in voices) {
          final name = v["name"]?.toString().toLowerCase() ?? '';
          final locale = v["locale"]?.toString().toLowerCase() ?? '';
          if (locale.contains('es') && (name.contains('female') || name.contains('mujer') || name.contains('sabina') || name.contains('helena'))) {
            await _tts.setVoice({"name": v["name"], "locale": v["locale"]});
            break;
          }
        }
      }
    } catch (e) {
      if (kDebugMode) print('Error initializing Global TTS/Voice: $e');
    }
  }

  Future<void> speakText(String text) async {
    if (!mounted) return;
    state = state.copyWith(aiResponse: text);
    await _tts.speak(text);
  }

  Future<void> stopSpeaking() async {
    await _tts.stop();
  }

  Future<void> startListening() async {
    await stopSpeaking();
    if (!_speechEnabled) {
      state = state.copyWith(hasError: true, errorMessage: 'Servicio de reconocimiento no disponible.');
      return;
    }

    state = state.copyWith(isListening: true, textSpoken: '', hasError: false, errorMessage: '', soundLevel: 0.0);
    
    await _speech.listen(
      onResult: (result) {
        if (!mounted) return;
        state = state.copyWith(textSpoken: result.recognizedWords);
        if (result.finalResult) {
          state = state.copyWith(isListening: false, soundLevel: 0.0);
          _processVoiceCommand(result.recognizedWords);
        }
      },
      localeId: kIsWeb ? null : 'es_CO', // Usa el idioma del navegador en Web para evitar errores
      pauseFor: kIsWeb ? null : const Duration(seconds: 3),
      onSoundLevelChange: kIsWeb ? null : (level) {
        if (!mounted) return;
        state = state.copyWith(soundLevel: level);
      },
    );
  }

  Future<void> stopListening() async {
    await _speech.stop();
    state = state.copyWith(isListening: false);
  }

  Future<void> _processVoiceCommand(String text) async {
    if (text.trim().isEmpty) return;

    state = state.copyWith(isProcessing: true, errorMessage: '', hasError: false);

    try {
      // 1. Get products and clients from database to supply to LLM context
      final repository = _ref.read(inventarioRepositoryProvider);
      final listProductos = await repository.getProductos();
      
      final listClientes = await _ref.read(mayoristasClientesProvider.future);

      // 2. Call Gemini
      final responseJson = await _queryGemini(text, listProductos, listClientes);
      
      if (responseJson == null) {
        throw Exception('No se obtuvo respuesta de la IA.');
      }

      final action = responseJson['action'] as String?;
      final clientName = responseJson['clientName'] as String?;
      final clientId = responseJson['clientId'] as String?;
      final items = responseJson['items'] as List<dynamic>? ?? [];
      final responseMsg = responseJson['message'] as String? ?? 'Comando procesado.';

      if (action == 'REGISTRAR') {
        // Build items list
        final List<CarritoItem> listItems = [];
        for (final item in items) {
          final prodId = item['productId'] as String?;
          final cantidad = (item['quantity'] as num?)?.toInt() ?? 0;
          if (prodId != null && cantidad > 0) {
            final prod = listProductos.firstWhere((p) => p.id == prodId);
            listItems.add(
              CarritoItem(
                producto: prod,
                cantidad: cantidad,
                precioUnitario: prod.precioPublico,
              ),
            );
          }
        }

        if (listItems.isNotEmpty && clientId != null) {
          // Store locally in-memory
          final currentMap = _ref.read(pedidosPendientesProvider);
          _ref.read(pedidosPendientesProvider.notifier).state = {
            ...currentMap,
            clientId: listItems,
          };
          await speakText(responseMsg);
        } else {
          await speakText('No pude identificar los licores o el proveedor en tu frase. Por favor intenta de nuevo.');
        }
      } 
      else if (action == 'ALISTAR') {
        if (clientId == null) {
          await speakText('No encontré a ningún proveedor con ese nombre.');
        } else {
          final currentMap = _ref.read(pedidosPendientesProvider);
          final savedItems = currentMap[clientId];
          if (savedItems == null || savedItems.isEmpty) {
            await speakText('No tengo ningún pedido pendiente registrado para $clientName.');
          } else {
            // Speak the items
            final itemsDescription = savedItems.map((item) => '${item.cantidad} ${item.producto.nombre}').join(' y ');
            final msgText = 'El pedido de $clientName contiene: $itemsDescription. ¿Deseas cargarlo en la pantalla?';
            await speakText(msgText);
          }
        }
      } 
      else if (action == 'CARGAR') {
        if (clientId != null) {
          final currentMap = _ref.read(pedidosPendientesProvider);
          final savedItems = currentMap[clientId];
          if (savedItems != null && savedItems.isNotEmpty) {
            // Load items into the POS screen cart
            final cartNotifier = _ref.read(posCartProvider.notifier);
            cartNotifier.clear();
            cartNotifier.setTipoVenta(TipoVenta.mayorista);
            cartNotifier.setCliente(clientId);
            
            for (final item in savedItems) {
              cartNotifier.addProduct(item.producto, cantidad: item.cantidad);
            }
            await speakText('Pedido cargado. Ya puedes verificar y facturar en el POS.');
          } else {
            await speakText('No hay pedido para cargar.');
          }
        } else {
          await speakText('No sé qué pedido cargar.');
        }
      }
      else {
        // Fallback for simple conversational response or error
        await speakText(responseMsg);
      }
    } catch (e) {
      if (kDebugMode) print('Error processing command: $e');
      state = state.copyWith(
        hasError: true,
        errorMessage: 'Error al procesar con IA: $e',
      );
      await speakText('Disculpa, no pude procesar la instrucción.');
    } finally {
      state = state.copyWith(isProcessing: false);
    }
  }

  Future<Map<String, dynamic>?> _queryGemini(
    String speechText,
    List<Producto> productos,
    List<ClienteConCuenta> clientes,
  ) async {
    final apiKey = dotenv.env['GEMINI_API_KEY'] ?? '';
    if (apiKey.isEmpty) {
      // Return a simulated response if no api key to avoid crashes
      return _generateSimulatedResponse(speechText, productos, clientes);
    }

    final url = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=$apiKey');

    final productsJson = productos.map((p) => {'id': p.id, 'nombre': p.nombre}).toList();
    final clientsJson = clientes.map((c) => {'id': c.cliente.id, 'nombre': c.cliente.nombre}).toList();

    final systemInstruction = '''
Eres un asistente de voz inteligente para la distribuidora de licores "Don Héctor". Tu trabajo es interpretar las órdenes de voz del usuario y mapearlas a comandos estructurados JSON.

Aquí tienes el catálogo de productos actual:
${jsonEncode(productsJson)}

Aquí tienes el listado de clientes/proveedores registrados:
${jsonEncode(clientsJson)}

Debes reconocer tres acciones posibles en español:
1. "REGISTRAR": El usuario dice que tiene que llevar o guardar un pedido de licores para un proveedor/cliente.
   Ejemplo: "Tengo que llevar 10 cervezas y 2 aguardientes a Manuel Gomez"
   - Busca el cliente que más se parezca a "Manuel Gomez" en el listado y obtén su "clientId".
   - Mapea las cantidades y productos a sus IDs correspondientes.
   - Retorna en JSON:
     {
       "action": "REGISTRAR",
       "clientName": "Manuel Gomez",
       "clientId": "ID_DE_MANUEL",
       "items": [
         {"productId": "ID_PRODUCTO", "quantity": 10}
       ],
       "message": "Excelente, he registrado el pedido de 10 cervezas y 2 aguardientes para Manuel Gomez."
     }

2. "ALISTAR": El usuario dice que va a empacar, alistar, o preparar el pedido de alguien.
   Ejemplo: "Vamos a alistar el pedido de Manuel"
   - Busca el cliente "Manuel".
   - Retorna en JSON:
     {
       "action": "ALISTAR",
       "clientName": "Manuel Gomez",
       "clientId": "ID_DE_MANUEL",
       "message": "Buscando el pedido de Manuel."
     }

3. "CARGAR": El usuario responde afirmativamente para cargar el pedido en el carrito/pantalla del POS.
   Ejemplo: "sí", "cárgalo", "de acuerdo", "por favor"
   - Si la frase es afirmativa tras alistar el pedido de un cliente, deduce el cliente anterior si es posible o simplemente retorna:
     {
       "action": "CARGAR",
       "clientId": "ID_DEL_ULTIMO_CLIENTE_SELECCIONADO",
       "message": "Perfecto, cargando productos."
     }

Si no entiendes el comando o es una conversación genérica, responde en JSON con la acción "CONVERSAR" y un mensaje de voz amigable en "message".

SIEMPRE responde ÚNICAMENTE con el formato JSON crudo, sin bloques de código ```json o texto adicional.
''';

    final requestBody = {
      'contents': [
        {
          'parts': [
            {'text': speechText}
          ]
        }
      ],
      'systemInstruction': {
        'parts': [
          {'text': systemInstruction}
        ]
      },
      'generationConfig': {
        'responseMimeType': 'application/json',
      }
    };

    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(requestBody),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final textResponse = data['candidates'][0]['content']['parts'][0]['text'] as String;
      return jsonDecode(textResponse.trim()) as Map<String, dynamic>;
    } else {
      throw Exception('Gemini HTTP ${response.statusCode}: ${response.body}');
    }
  }

  // A local mock processor in case the API key is not configured yet
  Map<String, dynamic> _generateSimulatedResponse(
    String speechText,
    List<Producto> productos,
    List<ClienteConCuenta> clientes,
  ) {
    final text = speechText.toLowerCase();
    
    // Simple heuristic-based simulation for testing
    if (text.contains('llevar') || text.contains('guardar') || text.contains('pedido')) {
      // Find client
      ClienteConCuenta? matchedClient;
      for (final c in clientes) {
        if (text.contains(c.cliente.nombre.toLowerCase())) {
          matchedClient = c;
          break;
        }
      }
      
      // Find products
      final List<Map<String, dynamic>> items = [];
      for (final p in productos) {
        if (text.contains(p.nombre.toLowerCase()) || 
            (p.nombre.toLowerCase().contains('cerveza') && text.contains('cerveza')) ||
            (p.nombre.toLowerCase().contains('aguardiente') && text.contains('aguardiente'))) {
          // extract quantity or default to 1
          int cant = 1;
          final regExp = RegExp(r'(\d+)\s+' + RegExp.escape(p.nombre.toLowerCase().substring(0, 4)));
          final match = regExp.firstMatch(text);
          if (match != null) {
            cant = int.tryParse(match.group(1) ?? '1') ?? 1;
          }
          items.add({'productId': p.id, 'quantity': cant});
        }
      }

      final cName = matchedClient?.cliente.nombre ?? 'Cliente';
      final cId = matchedClient?.cliente.id ?? 'cliente_anon';

      return {
        'action': 'REGISTRAR',
        'clientName': cName,
        'clientId': cId,
        'items': items,
        'message': 'Simulado: He registrado el pedido para $cName con ${items.length} productos.'
      };
    } 
    else if (text.contains('alistar') || text.contains('preparar')) {
      ClienteConCuenta? matchedClient;
      for (final c in clientes) {
        if (text.contains(c.cliente.nombre.toLowerCase())) {
          matchedClient = c;
          break;
        }
      }
      final cName = matchedClient?.cliente.nombre ?? 'Cliente';
      final cId = matchedClient?.cliente.id ?? 'cliente_anon';
      return {
        'action': 'ALISTAR',
        'clientName': cName,
        'clientId': cId,
        'message': 'Simulado: Buscando pedido de $cName.'
      };
    }
    else if (text.contains('si') || text.contains('cárgalo') || text.contains('cargar') || text.contains('favor')) {
      // Match last client in database
      final cId = clientes.isNotEmpty ? clientes.first.cliente.id : 'cliente_anon';
      return {
        'action': 'CARGAR',
        'clientId': cId,
        'message': 'Simulado: Cargando productos.'
      };
    }

    return {
      'action': 'CONVERSAR',
      'message': 'Hola, soy el asistente de voz de Don Héctor. ¿En qué te puedo ayudar hoy?'
    };
  }
}
