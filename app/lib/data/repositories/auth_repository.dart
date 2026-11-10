import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/env.dart';
import '../models/profile.dart';
import '../services/core_providers.dart';

class AuthRepository {
  AuthRepository(this._db);
  final SupabaseClient _db;

  Session? get session => _db.auth.currentSession;
  User? get user => _db.auth.currentUser;
  Stream<AuthState> get changes => _db.auth.onAuthStateChange;

  Future<void> signIn(String email, String password) async {
    try {
      await _db.auth.signInWithPassword(email: email.trim(), password: password);
    } on AuthException catch (e) {
      throw Exception(_friendly(e));
    }
  }

  Future<void> signOut() => _db.auth.signOut();

  Future<void> sendPasswordReset(String email) async {
    final redirect = kIsWeb
        ? '${Env.webAppUrl.isNotEmpty ? Env.webAppUrl : Uri.base.origin}/reset-password'
        : Env.mobileRedirectUrl;
    try {
      await _db.auth.resetPasswordForEmail(email.trim(), redirectTo: redirect);
    } on AuthException catch (e) {
      throw Exception(_friendly(e));
    }
  }

  Future<void> updatePassword(String newPassword) async {
    try {
      await _db.auth.updateUser(UserAttributes(password: newPassword));
    } on AuthException catch (e) {
      throw Exception(_friendly(e));
    }
  }

  /// Re-authenticates with the current password before changing it.
  Future<void> changePassword(String currentPassword, String newPassword) async {
    final email = user?.email;
    if (email == null) throw Exception('You are not signed in.');
    try {
      await _db.auth.signInWithPassword(email: email, password: currentPassword);
    } on AuthException {
      throw Exception('The current password is incorrect.');
    }
    await updatePassword(newPassword);
  }

  static String _friendly(AuthException e) {
    final m = e.message.toLowerCase();
    if (m.contains('invalid login') || m.contains('invalid credentials')) return 'Incorrect email or password.';
    if (m.contains('email not confirmed')) return 'Please confirm your email address before signing in.';
    if (m.contains('rate limit') || e.statusCode == '429') return 'Too many attempts. Please wait a minute and try again.';
    if (m.contains('should be different')) return 'The new password must be different from the current one.';
    if (m.contains('password should be')) return e.message;
    if (m.contains('failed host lookup') || m.contains('socket') || m.contains('network')) {
      return 'Cannot reach the authentication server. Check your connection.';
    }
    return e.message;
  }
}

class ProfileRepository {
  ProfileRepository(this._db);
  final SupabaseClient _db;

  Future<Profile> fetch(String id) async {
    final row = await _db.from('profiles').select().eq('id', id).single();
    return Profile.fromJson(row);
  }

  Future<List<Profile>> listAll() async {
    final rows = await _db.from('profiles').select().order('full_name', ascending: true);
    return rows.map(Profile.fromJson).toList();
  }

  Future<void> update(String id, Map<String, dynamic> fields) async {
    await _db.from('profiles').update(fields).eq('id', id);
  }

  Future<String> uploadAvatar(String userId, Uint8List bytes, String extension) async {
    final ext = extension.toLowerCase().replaceAll('jpeg', 'jpg');
    final path = '$userId/avatar.$ext';
    await _db.storage.from('avatars').uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(upsert: true, contentType: ext == 'png' ? 'image/png' : 'image/jpeg'),
        );
    final url = '${_db.storage.from('avatars').getPublicUrl(path)}?v=${DateTime.now().millisecondsSinceEpoch}';
    await update(userId, {'avatar_url': url});
    return url;
  }
}

final authRepositoryProvider = Provider<AuthRepository>((ref) => AuthRepository(ref.watch(supabaseProvider)));
final profileRepositoryProvider = Provider<ProfileRepository>((ref) => ProfileRepository(ref.watch(supabaseProvider)));

/// Emits on every sign-in / sign-out / token refresh.
final authStateProvider = StreamProvider<AuthState>((ref) => ref.watch(authRepositoryProvider).changes);

final currentUserIdProvider = Provider<String?>((ref) {
  ref.watch(authStateProvider);
  return ref.watch(authRepositoryProvider).user?.id;
});

/// Signed-in user's profile (role drives navigation and permissions).
class CurrentProfileNotifier extends AsyncNotifier<Profile?> {
  @override
  Future<Profile?> build() async {
    final uid = ref.watch(currentUserIdProvider);
    if (uid == null) return null;
    final cache = ref.read(cacheServiceProvider);
    try {
      final profile = await ref.read(profileRepositoryProvider).fetch(uid);
      await cache.write('profile.$uid', [
        {
          'id': profile.id,
          'email': profile.email,
          'full_name': profile.fullName,
          'role': profile.role.name,
          'job_title': profile.jobTitle,
          'phone': profile.phone,
          'avatar_url': profile.avatarUrl,
          'preferences': profile.preferences,
        }
      ]);
      return profile;
    } catch (e) {
      final cached = cache.read('profile.$uid');
      if (cached != null && cached.rows.isNotEmpty) return Profile.fromJson(cached.rows.first);
      rethrow;
    }
  }

  Future<void> save(Map<String, dynamic> fields) async {
    final p = state.value;
    if (p == null) return;
    await ref.read(profileRepositoryProvider).update(p.id, fields);
    ref.invalidateSelf();
    await future;
  }

  Future<void> uploadAvatar(Uint8List bytes, String ext) async {
    final p = state.value;
    if (p == null) return;
    await ref.read(profileRepositoryProvider).uploadAvatar(p.id, bytes, ext);
    ref.invalidateSelf();
    await future;
  }
}

final currentProfileProvider = AsyncNotifierProvider<CurrentProfileNotifier, Profile?>(CurrentProfileNotifier.new);

final currentRoleProvider = Provider<UserRole?>((ref) => ref.watch(currentProfileProvider).value?.role);

final allProfilesProvider = FutureProvider<List<Profile>>((ref) => ref.watch(profileRepositoryProvider).listAll());
