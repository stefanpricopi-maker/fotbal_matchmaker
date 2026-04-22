import 'dart:convert';
import 'dart:io';

/// Debug logger (NDJSON) pentru sesiunea curentă.
///
/// IMPORTANT:
/// - Nu loga secrete (chei, token-uri, parole).
/// - Fișierul e gestionat de Cursor debug mode.
class DebugLog {
  static const String sessionId = 'dd8f38';
  static const String serverEndpoint =
      'http://127.0.0.1:7274/ingest/70d39716-07a5-44c8-b3d0-c6137c52d5f4';
  static const String path =
      '/Users/pricopistefan/Documents/fotbal_matchmaker/.cursor/debug-dd8f38.log';

  static Future<void> writeAsync({
    required String runId,
    required String hypothesisId,
    required String location,
    required String message,
    Map<String, Object?> data = const {},
  }) async {
    final payload = <String, Object?>{
      'sessionId': sessionId,
      'runId': runId,
      'hypothesisId': hypothesisId,
      'location': location,
      'message': message,
      'data': data,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    await _post(payload);
    _appendFileFallback(payload);
    // Always echo to stdout so we can capture evidence from `flutter run` logs
    // even if sandbox blocks filesystem/network logging.
    // ignore: avoid_print
    print('SIMF_DEBUG ${jsonEncode(payload)}');
  }

  static void write({
    required String runId,
    required String hypothesisId,
    required String location,
    required String message,
    Map<String, Object?> data = const {},
  }) {
    final payload = <String, Object?>{
      'sessionId': sessionId,
      'runId': runId,
      'hypothesisId': hypothesisId,
      'location': location,
      'message': message,
      'data': data,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    _post(payload);
    _appendFileFallback(payload);
    // ignore: avoid_print
    print('SIMF_DEBUG ${jsonEncode(payload)}');
  }

  static Future<void> _post(Map<String, Object?> payload) async {
    try {
      final uri = Uri.parse(serverEndpoint);
      final client = HttpClient();
      final req = await client.postUrl(uri);
      req.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      req.headers.set('X-Debug-Session-Id', sessionId);
      req.add(utf8.encode(jsonEncode(payload)));
      final res = await req.close();
      await res.drain();
      client.close(force: true);
    } catch (_) {
      // ignore
    }
  }

  static void _appendFileFallback(Map<String, Object?> payload) {
    try {
      final line = '${jsonEncode(payload)}\n';
      File(path).writeAsStringSync(line, mode: FileMode.append, flush: true);
    } catch (_) {
      // ignore
    }
  }
}

