import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/cliente_mayorista.dart';
import '../models/cobro_mayorista.dart';
import '../models/pago_mayorista.dart';
import '../models/venta_enums.dart';
import '../models/producto.dart';
import '../models/carrito_item.dart';
import '../../features/pos/pos_receipt_pdf.dart';
import 'supabase_providers.dart';

final mayoristasRepositoryProvider = Provider<MayoristasRepository>((ref) {
  return MayoristasRepository(ref.watch(supabaseClientProvider));
});

class MayoristasRepository {
  const MayoristasRepository(this._client);

  final SupabaseClient _client;

  Future<List<ClienteMayorista>> getClientes() async {
    final rows = await _client
        .from('clientes_mayoristas')
        .select()
        .eq('activo', true)
        .order('nombre');
    return rows.map(ClienteMayorista.fromJson).toList();
  }

  Future<void> upsertCliente(ClienteMayorista c) async {
    final values = _withoutNulls(c.toJson());
    if ((values['id'] as String?)?.isEmpty ?? false) {
      values.remove('id');
    }

    await _client.from('clientes_mayoristas').upsert(values);
  }

  Future<List<CobroMayorista>> getCobrosCliente(String clienteId) async {
    final rows = await _client
        .from('cobros_mayoristas')
        .select()
        .eq('cliente_id', clienteId)
        .order('created_at', ascending: false);
    return rows.map(CobroMayorista.fromJson).toList();
  }

  Future<List<Map<String, dynamic>>> getVentasProductosCliente(String clienteId) async {
    final rows = await _client
        .from('detalle_ventas')
        .select('''
          venta_id,
          producto_id,
          cantidad,
          precio_unitario,
          productos (nombre, categorias(nombre)),
          ventas!inner (
            fecha,
            cliente_id
          )
        ''')
        .eq('ventas.cliente_id', clienteId)
        .order('created_at', ascending: false);
    return rows.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  Future<List<Map<String, dynamic>>> getEstadoCuentaMayoristas() async {
    final rows = await _client.from('estado_cuenta_mayoristas').select();
    return rows.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  Future<void> registrarPago(PagoMayorista pago) async {
    final values = _withoutNulls(pago.toJson());
    if ((values['id'] as String?)?.isEmpty ?? false) {
      values.remove('id');
    }

    await _client.from('pagos_mayoristas').insert(values);
  }

  Future<void> registrarPagoCliente({
    required String clienteId,
    required num monto,
    required MetodoPago metodoPago,
    String? notas,
  }) async {
    var restante = monto;
    final cobros = await getCobrosCliente(clienteId);
    final pendientes =
        cobros
            .where(
              (cobro) => cobro.estado != EstadoCobro.pagado && cobro.saldo > 0,
            )
            .toList()
          ..sort((a, b) {
            final aDate = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            final bDate = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            return aDate.compareTo(bDate);
          });

    for (final cobro in pendientes) {
      if (restante <= 0) break;

      final abono = restante > cobro.saldo ? cobro.saldo : restante;
      await registrarPago(
        PagoMayorista(
          id: '',
          cobroId: cobro.id,
          monto: abono,
          metodoPago: metodoPago,
          notas: notas,
        ),
      );
      restante -= abono;
    }
  }

  Future<PosReceiptData> getVentaConDetalles(String ventaId) async {
    final row = await _client
        .from('ventas')
        .select('''
          id,
          fecha,
          subtotal,
          descuento,
          total,
          metodo_pago,
          clientes_mayoristas (
            nombre
          ),
          detalle_ventas (
            cantidad,
            precio_unitario,
            productos (
              id,
              nombre,
              precio_publico,
              precio_mayorista,
              costo,
              stock_actual,
              stock_minimo,
              categoria_id,
              codigo_barras,
              activo
            )
          )
        ''')
        .eq('id', ventaId)
        .single();

    final clienteNombre = (row['clientes_mayoristas'] as Map?)?['nombre'] as String?;
    final metodoPago = MetodoPago.fromJson(row['metodo_pago'] as String);
    final fecha = DateTime.parse(row['fecha'] as String);

    final List<CarritoItem> items = [];
    final detalles = row['detalle_ventas'] as List;
    for (final det in detalles) {
      final prodJson = det['productos'] as Map<String, dynamic>;
      final producto = Producto.fromJson(prodJson);
      final cantidad = det['cantidad'] as int;
      final precioUnitario = det['precio_unitario'] as num;
      items.add(CarritoItem(
        producto: producto,
        cantidad: cantidad,
        precioUnitario: precioUnitario,
      ));
    }

    return PosReceiptData(
      ventaId: row['id'] as String,
      fecha: fecha,
      items: items,
      subtotal: row['subtotal'] as num,
      descuento: row['descuento'] as num,
      total: row['total'] as num,
      metodoPago: metodoPago,
      clienteNombre: clienteNombre,
    );
  }
}

Map<String, dynamic> _withoutNulls(Map<String, dynamic> values) {
  return Map.fromEntries(values.entries.where((entry) => entry.value != null));
}
