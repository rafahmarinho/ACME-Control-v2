import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/env.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.status, this.code});
  final String message;
  final int? status;
  final String? code;
  @override
  String toString() => message;
}

/// Client for the ACME Control API (Vercel). Sends the Supabase access token
/// so the API can verify the user and their role.
class ApiClient {
  ApiClient(this._supabase, {http.Client? httpClient}) : _http = httpClient ?? http.Client();

  final SupabaseClient _supabase;
  final http.Client _http;
  static const _timeout = Duration(seconds: 30);

  Uri _uri(String path) => Uri.parse('${Env.apiBaseUrl}$path');

  Map<String, String> get _headers {
    final token = _supabase.auth.currentSession?.accessToken;
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<Map<String, dynamic>> get(String path) => _send(() => _http.get(_uri(path), headers: _headers));

  Future<Map<String, dynamic>> post(String path, [Map<String, dynamic> body = const {}]) =>
      _send(() => _http.post(_uri(path), headers: _headers, body: jsonEncode(body)));

  Future<Map<String, dynamic>> _send(Future<http.Response> Function() request) async {
    http.Response res;
    try {
      res = await request().timeout(_timeout);
    } on TimeoutException {
      throw ApiException('The ACME Control API did not respond in time. Please try again.');
    } catch (_) {
      throw ApiException('Cannot reach the ACME Control API. Check your connection.');
    }

    Map<String, dynamic> data = {};
    if (res.body.isNotEmpty) {
      try {
        final decoded = jsonDecode(res.body);
        if (decoded is Map<String, dynamic>) data = decoded;
      } catch (_) {
        // Non-JSON response (e.g. gateway error page)
      }
    }

    if (res.statusCode >= 200 && res.statusCode < 300) return data;
    final err = data['error'];
    final message = err is Map ? (err['message'] as String? ?? 'Request failed') : 'Request failed (HTTP ${res.statusCode})';
    throw ApiException(message, status: res.statusCode, code: err is Map ? err['code'] as String? : null);
  }

  // Endpoints -----------------------------------------------------------------

  Future<Map<String, dynamic>> sendCommand({
    required String plantId,
    required String equipmentId,
    required String action,
    String? note,
  }) =>
      post('/api/commands', {'plantId': plantId, 'equipmentId': equipmentId, 'action': action, 'note': ?note});

  Future<Map<String, dynamic>> tick(String plantId) => post('/api/simulation/tick', {'plantId': plantId});

  Future<Map<String, dynamic>> advance(String plantId, int minutes) =>
      post('/api/simulation/advance', {'plantId': plantId, 'minutes': minutes});

  Future<Map<String, dynamic>> setScenario(String plantId, String scenarioId) =>
      post('/api/simulation/scenario', {'plantId': plantId, 'scenarioId': scenarioId});

  Future<Map<String, dynamic>> setAutoRun(String plantId, bool autoRun) =>
      post('/api/simulation/control', {'plantId': plantId, 'autoRun': autoRun});

  Future<Map<String, dynamic>> resetDemo() => post('/api/simulation/reset');

  Future<Map<String, dynamic>> proposeSetpoint(String setpointId, double value, String reason) =>
      post('/api/setpoints/propose', {'setpointId': setpointId, 'proposedValue': value, 'reason': reason});

  Future<Map<String, dynamic>> reviewProposal(String proposalId, bool approve, String? note) => post(
        '/api/setpoints/review',
        {'proposalId': proposalId, 'decision': approve ? 'approve' : 'reject', 'note': ?note},
      );

  Future<Map<String, dynamic>> setLockout(String workOrderId, bool apply) =>
      post('/api/maintenance/lockout', {'workOrderId': workOrderId, 'apply': apply});

  Future<Map<String, dynamic>> cmmsSync(String workOrderId) =>
      post('/api/integrations/cmms-sync', {'workOrderId': workOrderId});

  Future<Map<String, dynamic>> integrationStatus() => get('/api/integrations/status');

  Future<Map<String, dynamic>> health() => get('/api/health');
}
