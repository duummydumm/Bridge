import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Exception thrown when EmailJS API calls are blocked (e.g., 403 error for non-browser apps)
class EmailJSBlockedException implements Exception {
  final String message;
  EmailJSBlockedException(this.message);

  @override
  String toString() => message;
}

/// EmailJS service for sending emails
///
/// To use this service, you need to:
/// 1. Sign up at https://www.emailjs.com/
/// 2. Create an email service (Gmail, Outlook, etc.)
/// 3. Create an email template
/// 4. Get your Service ID, Template ID, and Public Key (User ID)
/// 5. Configure these values using configure() method or set them in SharedPreferences
class EmailService {
  static final EmailService _instance = EmailService._internal();
  factory EmailService() => _instance;
  EmailService._internal();

  // EmailJS configuration keys for SharedPreferences
  static const String _prefServiceId = 'emailjs_service_id';
  static const String _prefTemplateId = 'emailjs_template_id';
  static const String _prefWelcomeTemplateId = 'emailjs_welcome_template_id';
  static const String _prefPublicKey = 'emailjs_public_key';
  static const String _prefBackendApiUrl = 'emailjs_backend_api_url';

  static const String _emailJsApiUrl =
      'https://api.emailjs.com/api/v1.0/email/send';

  String? _serviceId;
  String? _templateId;
  String? _welcomeTemplateId;
  String? _publicKey;
  String? _backendApiUrl; // Backend API endpoint URL (optional)

  /// Initialize EmailJS configuration from SharedPreferences
  Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _serviceId = prefs.getString(_prefServiceId);
      _templateId = prefs.getString(_prefTemplateId);
      _welcomeTemplateId = prefs.getString(_prefWelcomeTemplateId);
      _publicKey = prefs.getString(_prefPublicKey);
      _backendApiUrl = prefs.getString(_prefBackendApiUrl);

      if (_serviceId != null && _templateId != null && _publicKey != null) {
        debugPrint('EmailJS: Configuration loaded from SharedPreferences');
        if (_backendApiUrl != null) {
          debugPrint('EmailJS: Backend API URL configured: $_backendApiUrl');
        }
      }
    } catch (e) {
      debugPrint('EmailJS: Error loading configuration: $e');
    }
  }

  /// Configure EmailJS credentials
  ///
  /// [serviceId] - Your EmailJS Service ID
  /// [templateId] - Your EmailJS Template ID (for verification emails)
  /// [publicKey] - Your EmailJS Public Key (User ID)
  /// [welcomeTemplateId] - Your EmailJS Welcome Template ID (optional)
  /// [backendApiUrl] - Your backend API URL for mobile apps (optional, recommended for mobile)
  /// [saveToPrefs] - Whether to save credentials to SharedPreferences (default: true)
  Future<void> configure({
    required String serviceId,
    required String templateId,
    required String publicKey,
    String? welcomeTemplateId,
    String? backendApiUrl,
    bool saveToPrefs = true,
  }) async {
    _serviceId = serviceId;
    _templateId = templateId;
    _welcomeTemplateId = welcomeTemplateId;
    _publicKey = publicKey;
    _backendApiUrl = backendApiUrl;

    if (saveToPrefs) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_prefServiceId, serviceId);
        await prefs.setString(_prefTemplateId, templateId);
        if (welcomeTemplateId != null) {
          await prefs.setString(_prefWelcomeTemplateId, welcomeTemplateId);
        }
        await prefs.setString(_prefPublicKey, publicKey);
        if (backendApiUrl != null) {
          await prefs.setString(_prefBackendApiUrl, backendApiUrl);
        }
        debugPrint('EmailJS: Configuration saved to SharedPreferences');
      } catch (e) {
        debugPrint('EmailJS: Error saving configuration: $e');
      }
    }

    debugPrint('EmailJS: Configuration updated');
    if (_backendApiUrl != null) {
      debugPrint('EmailJS: Backend API enabled - OTP will work on mobile');
    }
  }

  /// Check if EmailJS is configured
  bool get isConfigured {
    return _serviceId != null &&
        _serviceId!.isNotEmpty &&
        _templateId != null &&
        _templateId!.isNotEmpty &&
        _publicKey != null &&
        _publicKey!.isNotEmpty;
  }

  /// Sends a verification email with OTP using EmailJS
  ///
  /// [toEmail] - The recipient's email address
  /// [toName] - The recipient's name (optional)
  /// [otp] - The OTP code to include in the email
  ///
  /// Returns true if the email was sent successfully, false otherwise
  Future<bool> sendVerificationEmail({
    required String toEmail,
    String? toName,
    required String otp,
  }) async {
    try {
      // Validate email address
      if (toEmail.isEmpty || !toEmail.contains('@')) {
        debugPrint('EmailJS: Invalid email address: $toEmail');
        throw Exception('Invalid email address: $toEmail');
      }

      // Load configuration if not already loaded
      if (!isConfigured) {
        await initialize();
      }

      // Validate configuration
      if (!isConfigured) {
        debugPrint(
          'EmailJS: Configuration not set. Please configure EmailJS credentials.',
        );
        throw Exception(
          'EmailJS configuration not set. Please configure your EmailJS credentials using EmailService().configure().',
        );
      }

      debugPrint('EmailJS: Sending email to: $toEmail');
      debugPrint('EmailJS: Using service: $_serviceId, template: $_templateId');

      // Prepare the email data
      final emailData = {
        'service_id': _serviceId,
        'template_id': _templateId,
        'user_id': _publicKey,
        'template_params': {
          'to_email': toEmail,
          'to_name': toName ?? 'User',
          'otp': otp,
          'reply_to': toEmail,
        },
      };

      debugPrint('EmailJS: Request data: ${jsonEncode(emailData)}');

      // Use backend API if configured (for mobile apps), otherwise use EmailJS directly
      final apiUrl = _backendApiUrl != null && _backendApiUrl!.isNotEmpty
          ? '$_backendApiUrl/send-verification-email'
          : _emailJsApiUrl;

      debugPrint('EmailJS: Using API endpoint: $apiUrl');

      // Send the email via EmailJS API or backend API
      http.Response response;
      try {
        response = await http
            .post(
              Uri.parse(apiUrl),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(emailData),
            )
            .timeout(
              const Duration(
                seconds: 30,
              ), // Increased timeout for mobile networks
              onTimeout: () {
                debugPrint('EmailJS: Request timed out after 30 seconds');
                debugPrint('EmailJS: Check if server is running at: $apiUrl');
                throw Exception(
                  'Email sending timed out. Check:\n'
                  '1. Is the backend server running? (node server.js)\n'
                  '2. Is your phone on the same Wi-Fi network?\n'
                  '3. Can you access http://192.168.1.11:3000/health from your phone browser?',
                );
              },
            );
        debugPrint(
          'EmailJS: Response received. Status: ${response.statusCode}',
        );
      } catch (e) {
        debugPrint('EmailJS: Network error: $e');
        if (e.toString().contains('Failed host lookup') ||
            e.toString().contains('Connection refused') ||
            e.toString().contains('SocketException')) {
          throw Exception(
            'Cannot connect to backend server at $apiUrl. '
            'Make sure the server is running and your phone is on the same Wi-Fi network.',
          );
        }
        rethrow;
      }

      if (response.statusCode == 200) {
        debugPrint('EmailJS: Verification email sent successfully to $toEmail');
        return true;
      } else {
        final errorBody = response.body;
        debugPrint(
          'EmailJS: Failed to send email. Status: ${response.statusCode}, Body: $errorBody',
        );

        // Check for 403 error (API calls disabled for non-browser applications)
        if (response.statusCode == 403) {
          throw EmailJSBlockedException(
            'EmailJS API calls are disabled for non-browser applications. '
            'Please use Firebase email verification or set up a backend service.',
          );
        }

        // Provide more specific error message
        String errorMessage = 'Failed to send email: ${response.statusCode}';
        if (errorBody.contains('recipients address is empty')) {
          errorMessage =
              'EmailJS template error: The "To Email" field in your EmailJS template must be set to use {{to_email}} parameter. Please check your template configuration in EmailJS dashboard.';
        } else if (errorBody.contains('template')) {
          errorMessage =
              'EmailJS template error: Please check your template configuration.';
        }

        throw Exception(errorMessage);
      }
    } catch (e) {
      debugPrint('EmailJS: Error sending verification email: $e');
      rethrow;
    }
  }

  /// Sends a welcome email using EmailJS
  ///
  /// [toEmail] - The recipient's email address
  /// [toName] - The recipient's name (optional)
  ///
  /// Returns true if the email was sent successfully, false otherwise
  Future<bool> sendWelcomeEmail({
    required String toEmail,
    String? toName,
  }) async {
    try {
      // Load configuration if not already loaded
      if (!isConfigured) {
        await initialize();
      }

      // Validate configuration
      if (!isConfigured) {
        debugPrint(
          'EmailJS: Configuration not set. Please configure EmailJS credentials.',
        );
        throw Exception(
          'EmailJS configuration not set. Please configure your EmailJS credentials using EmailService().configure().',
        );
      }

      // Check if welcome template is configured
      if (_welcomeTemplateId == null || _welcomeTemplateId!.isEmpty) {
        debugPrint(
          'EmailJS: Welcome template not configured. Skipping welcome email.',
        );
        return false;
      }

      // Prepare the email data
      final emailData = {
        'service_id': _serviceId,
        'template_id': _welcomeTemplateId,
        'user_id': _publicKey,
        'template_params': {
          'to_email': toEmail,
          'to_name': toName ?? 'User',
          'reply_to': toEmail,
        },
      };

      // Use backend API if configured (for mobile apps), otherwise use EmailJS directly
      final apiUrl = _backendApiUrl != null && _backendApiUrl!.isNotEmpty
          ? '$_backendApiUrl/send-welcome-email'
          : _emailJsApiUrl;

      // Send the email via EmailJS API or backend API
      final response = await http
          .post(
            Uri.parse(apiUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(emailData),
          )
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              throw Exception('Email sending timed out');
            },
          );

      if (response.statusCode == 200) {
        debugPrint('EmailJS: Welcome email sent successfully to $toEmail');
        return true;
      } else {
        debugPrint(
          'EmailJS: Failed to send welcome email. Status: ${response.statusCode}, Body: ${response.body}',
        );
        throw Exception('Failed to send welcome email: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('EmailJS: Error sending welcome email: $e');
      // Don't rethrow - welcome email failure shouldn't break verification
      return false;
    }
  }
}
