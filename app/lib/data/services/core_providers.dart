import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'api_client.dart';
import 'cache_service.dart';

/// Overridden in main() with the instance loaded at startup.
final sharedPrefsProvider = Provider<SharedPreferences>((ref) => throw UnimplementedError('SharedPreferences not initialised'));

final supabaseProvider = Provider<SupabaseClient>((ref) => Supabase.instance.client);

final cacheServiceProvider = Provider<CacheService>((ref) => CacheService(ref.watch(sharedPrefsProvider)));

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient(ref.watch(supabaseProvider)));

/// Network reachability as reported by the platform (navigator.onLine on web).
final connectivityProvider = StreamProvider<bool>((ref) async* {
  final connectivity = Connectivity();
  bool online(List<ConnectivityResult> r) => r.any((e) => e != ConnectivityResult.none);
  try {
    yield online(await connectivity.checkConnectivity());
  } catch (_) {
    yield true;
  }
  yield* connectivity.onConnectivityChanged.map(online);
});

final isOnlineProvider = Provider<bool>((ref) => ref.watch(connectivityProvider).value ?? true);

/// Whether the app is in the foreground (updated by [AppLifecycleWatcher]).
class AppForegroundNotifier extends Notifier<bool> {
  @override
  bool build() => true;
  void set(bool value) {
    if (state != value) state = value;
  }
}

final appForegroundProvider = NotifierProvider<AppForegroundNotifier, bool>(AppForegroundNotifier.new);

/// Live streams and simulation ticks only run while online and in the foreground.
/// When false, screens show the last cached snapshot (read-only).
final liveSyncProvider = Provider<bool>((ref) => ref.watch(isOnlineProvider) && ref.watch(appForegroundProvider));
