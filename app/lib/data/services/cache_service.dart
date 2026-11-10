import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class CachedRows {
  const CachedRows(this.rows, this.savedAt);
  final List<Map<String, dynamic>> rows;
  final DateTime savedAt;
}

/// Persists the last rows received for each live query so the app can show
/// a read-only snapshot when offline or right after a cold start.
class CacheService {
  CacheService(this._prefs);
  final SharedPreferences _prefs;
  static const _prefix = 'cache.v1.';

  CachedRows? read(String key) {
    final raw = _prefs.getString('$_prefix$key');
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final rows = (decoded['rows'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      return CachedRows(rows, DateTime.parse(decoded['savedAt'] as String));
    } catch (_) {
      return null;
    }
  }

  Future<void> write(String key, List<Map<String, dynamic>> rows) async {
    await _prefs.setString(
      '$_prefix$key',
      jsonEncode({'savedAt': DateTime.now().toIso8601String(), 'rows': rows}),
    );
  }

  DateTime? savedAt(String key) => read(key)?.savedAt;

  Future<int> clear() async {
    final keys = _prefs.getKeys().where((k) => k.startsWith(_prefix)).toList();
    for (final k in keys) {
      await _prefs.remove(k);
    }
    return keys.length;
  }
}
