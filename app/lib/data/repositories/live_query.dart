import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/json.dart';
import '../services/core_providers.dart';

class OfflineNoDataException implements Exception {
  @override
  String toString() => 'You are offline and no saved data is available yet. Connect once to download the latest plant data.';
}

/// Live Supabase query with offline cache:
///  1. emits the cached snapshot immediately (if any),
///  2. while [liveSyncProvider] is true, subscribes to Realtime and keeps the cache fresh,
///  3. when offline / in background the subscription is closed and the snapshot stays visible.
Stream<List<T>> liveQuery<T>(
  Ref ref, {
  required String cacheKey,
  required Stream<List<Json>> Function(SupabaseClient db) query,
  required T Function(Json row) parse,
  List<T> Function(List<T> items)? transform,
}) async* {
  final cache = ref.read(cacheServiceProvider);
  final live = ref.watch(liveSyncProvider);
  List<T> map(List<Json> rows) {
    final items = rows.map(parse).toList();
    return transform == null ? items : transform(items);
  }

  var emitted = false;
  final cached = cache.read(cacheKey);
  if (cached != null) {
    yield map(cached.rows);
    emitted = true;
  }
  if (!live) {
    if (!emitted) throw OfflineNoDataException();
    return;
  }

  try {
    await for (final rows in query(ref.read(supabaseProvider))) {
      unawaited(cache.write(cacheKey, rows));
      yield map(rows);
      emitted = true;
    }
  } catch (e) {
    // Keep showing the last data if the socket drops; surface errors only when we have nothing.
    if (!emitted) rethrow;
  }
}

/// One-shot query with offline fallback to the last cached result.
Future<List<T>> cachedFetch<T>(
  Ref ref, {
  required String cacheKey,
  required Future<List<Json>> Function(SupabaseClient db) query,
  required T Function(Json row) parse,
  bool preferCache = false,
}) async {
  final cache = ref.read(cacheServiceProvider);
  // Reference data: show the cached copy instantly and refresh it in the background.
  final cachedFirst = preferCache ? cache.read(cacheKey) : null;
  if (cachedFirst != null) {
    if (ref.read(isOnlineProvider)) {
      unawaited(query(ref.read(supabaseProvider)).then((rows) => cache.write(cacheKey, rows)).catchError((_) {}));
    }
    return cachedFirst.rows.map(parse).toList();
  }
  if (ref.read(isOnlineProvider)) {
    try {
      final rows = await query(ref.read(supabaseProvider));
      unawaited(cache.write(cacheKey, rows));
      return rows.map(parse).toList();
    } catch (e) {
      final cached = cache.read(cacheKey);
      if (cached == null) rethrow;
      return cached.rows.map(parse).toList();
    }
  }
  final cached = cache.read(cacheKey);
  if (cached == null) throw OfflineNoDataException();
  return cached.rows.map(parse).toList();
}
