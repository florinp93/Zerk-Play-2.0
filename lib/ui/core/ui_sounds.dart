import 'ui_sounds_stub.dart'
    if (dart.library.ffi) 'ui_sounds_win.dart' as backend;

enum UiSound { move, select, back, bump, error }

abstract final class UiSounds {
  static bool enabled = true;
  static DateTime _lastMove = DateTime(0);

  static Future<void> load() => backend.load();

  static void play(UiSound sound) {
    if (!enabled) return;
    if (sound == UiSound.move) {
      final now = DateTime.now();
      if (now.difference(_lastMove) < const Duration(milliseconds: 45)) return;
      _lastMove = now;
    }
    backend.play(sound);
  }
}
