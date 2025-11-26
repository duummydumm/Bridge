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
      if (previousUser != null && user == null) {
        debugPrint(
          'User logged out, clearing FCM token for: ${previousUser.uid}',
        );
        await FCMService().clearTokenForUser(previousUser.uid);
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
      _setLoading(true);
      _clearError();
      notifyListeners(); // Notify immediately to show loading indicator

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
      final userId = _user?.uid;
      await _authService.logout();

      // Clear FCM token for the user who logged out
      if (userId != null) {
        await FCMService().clearTokenForUser(userId);
      }

      _user = null;
      _setLoading(false);
      notifyListeners();
    } catch (e) {
      _setError(e.toString());
      _setLoading(false);
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
