import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Which experience the user is currently in. Only meaningful for users with a
/// management role; players are always effectively [AppMode.play].
enum AppMode { play, management }

const _modeKey = 'app_mode';

/// Holds the current [AppMode] and persists changes to [SharedPreferences] so
/// the choice survives app restarts.
class AppModeController extends StateNotifier<AppMode> {
  AppModeController(this._prefs) : super(_read(_prefs));

  final SharedPreferences _prefs;

  static AppMode _read(SharedPreferences p) =>
      p.getString(_modeKey) == 'management' ? AppMode.management : AppMode.play;

  Future<void> set(AppMode mode) async {
    state = mode;
    await _prefs.setString(
      _modeKey,
      mode == AppMode.management ? 'management' : 'play',
    );
  }
}

/// Overridden in `main()` with the loaded instance.
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('sharedPreferencesProvider must be overridden');
});

final appModeProvider =
    StateNotifierProvider<AppModeController, AppMode>((ref) {
  return AppModeController(ref.watch(sharedPreferencesProvider));
});
