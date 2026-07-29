import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Efectos de sonido cortos de la interfaz (feedback de acciones del usuario).
///
/// Usa modo de baja latencia para que el sonido responda de inmediato al toque,
/// incluso al agregar productos muy rápido en el modo turbo.
class SoundEffects {
  SoundEffects._();

  static const String _kMutedKey = 'turbo_sound_muted';

  static final AudioPlayer _player = AudioPlayer()
    ..setReleaseMode(ReleaseMode.stop)
    ..setPlayerMode(PlayerMode.lowLatency);

  static final AssetSource _addProduct = AssetSource('sounds/add_soft.wav');
  static bool _ready = false;
  static bool _muted = false;
  static bool _prefsLoaded = false;

  /// Indica si el sonido de agregar producto está silenciado.
  static bool get isMuted => _muted;

  /// Precarga el efecto y lee la preferencia de silencio guardada.
  /// Llamar una vez al abrir el modo turbo.
  static Future<void> preload() async {
    if (!_prefsLoaded) {
      try {
        final prefs = await SharedPreferences.getInstance();
        _muted = prefs.getBool(_kMutedKey) ?? false;
      } catch (_) {
        // Si falla la lectura, se asume no silenciado.
      }
      _prefsLoaded = true;
    }
    if (_ready) return;
    try {
      await _player.setSource(_addProduct);
      _ready = true;
    } catch (_) {
      // Precarga best-effort; si falla, playAddProduct lo intentará de nuevo.
    }
  }

  /// Activa o silencia el sonido de agregar producto y lo guarda de forma
  /// persistente (queda igual la próxima vez que se abre la app).
  static Future<void> setMuted(bool muted) async {
    _muted = muted;
    _prefsLoaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kMutedKey, muted);
    } catch (_) {
      // Si no se puede persistir, al menos queda aplicado en esta sesión.
    }
  }

  /// Sonido corto de confirmación al agregar un producto (POS turbo).
  /// Reinicia la reproducción en cada toque para dar respuesta inmediata.
  /// No hace nada si el usuario silenció el sonido.
  static Future<void> playAddProduct() async {
    if (_muted) return;
    try {
      await _player.stop();
      await _player.play(_addProduct, volume: 1.0);
    } catch (_) {
      // El sonido es cosmético; nunca debe interrumpir la venta.
    }
  }
}
