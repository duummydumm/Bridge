import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart';
import '../services/fcm_service.dart';

class AuthProvider extends ChangeNotifier {
  final AuthService _authService = AuthService();

  User? _user;
  bool _isLoading = false;
  String? _errorMessage;

  // Getters
  User? get user => _user;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get isAuthenticated => _user != null;

  // Initialize auth state
  AuthProvider() {
    _user = _authService.currentUser;
    String? _previousUserId;

    FirebaseAuth.instance.authStateChanges().listen((User? user) async {
      final previousUser = _user;
      _user = user;

      // Clear FCM token for previous user if they logged out
      // Note: This may fail if user is already logged out, but that's okay
      // The logout() method handles clearing the token before logout
      if (previousUser != null && user == null) {
        debugPrint(
          'User logged out, attempting to clear FCM token for: ${previousUser.uid}',
        );
        try {
          await FCMService().clearTokenForUser(previousUser.uid);
        } catch (e) {
          // If this fails, it's likely because the user is already logged out
          // and doesn't have permission. This is expected and not critical.
          debugPrint(
            'Note: Could not clear FCM token in authStateChanges (user already logged out): $e',
          );
        }
      }

      // Update FCM token when user changes (login/switch account)
      if (user != null) {
        // If switching accounts, clear the previous user's token first
        final previousUserId = _previousUserId;
        if (previousUserId != null && previousUserId != user.uid) {
          debugPrint(
            'User switched accounts, clearing FCM token for previous user: $previousUserId',
          );
          await FCMService().clearTokenForUser(previousUserId);
        }
        debugPrint('Updating FCM token for new user: ${user.uid}');
        await FCMService().updateTokenForCurrentUser();
        _previousUserId = user.uid;
      } else {
        _previousUserId = null;
      }

      notifyListeners();
    });
  }

  // Login method
  Future<bool> loginWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      // If already loading, wait a bit to avoid race conditions
      if (_isLoading) {
        await Future.delayed(const Duration(milliseconds: 200));
      }

      _setLoading(true);
      _clearError();
      notifyListeners(); // Notify immediately to show loading indicator

      // Ensure we're not still logged in from a previous session
      final currentUser = _authService.currentUser;
      if (currentUser != null && _user == null) {
        // Auth state is inconsistent, wait for it to sync
        await Future.delayed(const Duration(milliseconds: 100));
      }

      final credential = await _authService.loginWithEmail(
        email: email,
        password: password,
      );

      _user = credential.user;
      _setLoading(false);
      // Update FCM token for the newly logged in user (await to ensure it completes)
      if (_user != null) {
        await FCMService().updateTokenForCurrentUser();
      }
      notifyListeners();
      return true;
    } catch (e) {
      _setError(e.toString());
      _setLoading(false);
      notifyListeners();
      return false;
    }
  }

  // Register method
  Future<bool> registerWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      _setLoading(true);
      _clearError();

      final credential = await _authService.registerWithEmail(
        email: email,
        password: password,
      );

      _user = credential.user;
      _setLoading(false);
      // Update FCM token for the newly registered user (await to ensure it completes)
      if (_user != null) {
        await FCMService().updateTokenForCurrentUser();
      }
      notifyListeners();
      return true;
    } catch (e) {
      _setError(e.toString());
      _setLoading(false);
      notifyListeners();
      return false;
    }
  }

  // Logout method
  Future<void> logout() async {
    try {
      _setLoading(true);
      _clearError(); // Clear any previous errors
      notifyListeners(); // Notify to update UI immediately

      final userId = _user?.uid;
      
      // Clear FCM token BEFORE logging out (while user is still authenticated)
      if (userId != null) {
        await FCMService().clearTokenForUser(userId);
      }

      await _authService.logout();

      // Wait a brief moment to ensure authStateChanges listener has processed
      await Future.delayed(const Duration(milliseconds: 100));

      _user = null;
      _clearError(); // Ensure error is cleared
      _setLoading(false);
      notifyListeners();
    } catch (e) {
      _setError(e.toString());
      _setLoading(false);
      _user = null; // Ensure user is cleared even on error
      notifyListeners();
    }
  }

  Future<bool> sendPasswordReset({required String email}) async {
    try {
      _setLoading(true);
      _clearError();
      await _authService.sendPasswordResetEmail(email: email);
      _setLoading(false);
      notifyListeners();
      return true;
    } catch (e) {
      _setError(e.toString());
      _setLoading(false);
      notifyListeners();
      return false;
    }
  }

  Future<void> sendEmailVerification() async {
    try {
      await _authService.sendEmailVerification();
    } catch (e) {
      _setError(e.toString());
      notifyListeners();
    }
  }

  Future<bool> reloadCurrentUser() async {
    try {
      final user = await _authService.reloadCurrentUser();
      _user = user;
      notifyListeners();
      return user?.emailVerified == true;
    } catch (e) {
      _setError(e.toString());
      notifyListeners();
      return false;
    }
  }

  Future<bool> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
      _setLoading(true);
      _clearError();
      await _authService.changePassword(
        currentPassword: currentPassword,
        newPassword: newPassword,
      );
      _setLoading(false);
      notifyListeners();
      return true;
    } catch (e) {
      _setError(e.toString());
      _setLoading(false);
      notifyListeners();
      return false;
    }
  }

  // Helper methods
  void _setLoading(bool loading) {
    _isLoading = loading;
  }

  void _setError(String error) {
    _errorMessage = error;
  }

  void _clearError() {
    _errorMessage = null;
  }

  void clearError() {
    _clearError();
    notifyListeners();
  }
}
