import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart' show debugPrint;

/// Simple helper to wake the Render backend before critical flows (e.g. OTP)
class PingService {
  // Render backend URL (same as used in main.dart for EmailService backendApiUrl)
  // If you add a /health endpoint later, you can change this to that path.
  static const String _healthUrl =
      'https://bridge-emailjs-backend.onrender.com';

  /// Fire-and-forget call to wake the backend.
  ///
  /// This intentionally ignores errors because the first call often times out
  /// while the server is cold-starting. The important part is that the request
  /// reaches Render and starts the wake-up process.
  static Future<void> wakeBackend() async {
    debugPrint('PingService: Waking backend via $_healthUrl ...');
    final stopwatch = Stopwatch()..start();
    try {
      final response = await http
          .get(Uri.parse(_healthUrl))
          .timeout(const Duration(seconds: 10));
      stopwatch.stop();
      debugPrint(
        'PingService: Ping completed in ${stopwatch.elapsedMilliseconds} ms '
        'with status ${response.statusCode}',
      );
    } catch (e) {
      stopwatch.stop();
      debugPrint(
        'PingService: Ping failed after ${stopwatch.elapsedMilliseconds} ms: $e',
      );
      // Ignore errors – this is best-effort only.
    }
  }
}
