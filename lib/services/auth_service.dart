import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'verification_service.dart';
import 'email_service.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final VerificationService _verificationService = VerificationService();

  Future<UserCredential> registerWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      return await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      // Handle specific Firebase Auth errors
      switch (e.code) {
        case 'configuration-not-found':
          throw Exception(
            'Firebase Authentication is not properly configured. Please check your Firebase Console settings.',
          );
        case 'email-already-in-use':
          throw Exception('An account already exists with this email address.');
        case 'weak-password':
          throw Exception('The password provided is too weak.');
        case 'invalid-email':
          throw Exception('The email address is not valid.');
        default:
          throw Exception('Registration failed: ${e.message}');
      }
    } catch (e) {
      throw Exception('Registration failed: $e');
    }
  }

  Future<UserCredential> loginWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      debugPrint('AuthService: Attempting login with email: $email');
      final result = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      debugPrint('AuthService: Login successful, UID: ${result.user?.uid}');
      return result;
    } on FirebaseAuthException catch (e) {
      debugPrint(
        'AuthService: Firebase Auth Exception - Code: ${e.code}, Message: ${e.message}',
      );
      // Handle specific Firebase Auth errors
      switch (e.code) {
        case 'user-not-found':
          throw Exception('No account found with this email address.');
        case 'wrong-password':
          throw Exception('Incorrect password. Please try again.');
        case 'invalid-email':
          throw Exception('The email address is not valid.');
        case 'user-disabled':
          throw Exception('This account has been disabled.');
        case 'too-many-requests':
          throw Exception('Too many failed attempts. Please try again later.');
        case 'invalid-credential':
          throw Exception(
            'Invalid email or password. Please check your credentials.',
          );
        case 'operation-not-allowed':
          throw Exception(
            'Email/password authentication is not enabled. Please check Firebase Console.',
          );
        default:
          throw Exception('Login failed: ${e.message} (Code: ${e.code})');
      }
    } catch (e) {
      debugPrint('AuthService: General Exception: $e');
      throw Exception('Login failed: $e');
    }
  }

  Future<void> logout() async {
    await _auth.signOut();
  }

  User? get currentUser => _auth.currentUser;

  Future<void> sendEmailVerification() async {
    final user = _auth.currentUser;
    if (user != null && user.email != null) {
      try {
        // Use EmailJS to send OTP instead of Firebase's sendEmailVerification
        // Get user name from Firestore if available
        String? userName;
        try {
          // You might want to get this from UserProvider instead
          // For now, we'll use email as fallback
          userName = user.displayName ?? user.email?.split('@')[0];
        } catch (_) {
          userName = user.email?.split('@')[0];
        }

        await _verificationService.createVerificationOTP(
          userId: user.uid,
          email: user.email!,
          userName: userName,
        );
      } catch (e) {
        debugPrint(
          'AuthService: Error sending verification email via EmailJS: $e',
        );

        // If EmailJS is blocked (403 error), use Firebase's email verification directly
        if (e is EmailJSBlockedException) {
          debugPrint(
            'AuthService: EmailJS is blocked for non-browser apps. '
            'Using Firebase email verification instead.',
          );
          // Fallback to Firebase's email verification
          if (!user.emailVerified) {
            await user.sendEmailVerification();
            debugPrint(
              'AuthService: Firebase verification email sent. '
              'User should check their email for a verification link.',
            );
          }
        } else {
          // For other errors, also try Firebase fallback
          if (!user.emailVerified) {
            await user.sendEmailVerification();
            debugPrint(
              'AuthService: Fallback to Firebase email verification due to EmailJS error.',
            );
          }
        }
      }
    }
  }

  Future<User?> reloadCurrentUser() async {
    final user = _auth.currentUser;
    if (user != null) {
      await user.reload();
      return _auth.currentUser;
    }
    return null;
  }

  Future<void> sendPasswordResetEmail({required String email}) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } on FirebaseAuthException catch (e) {
      switch (e.code) {
        case 'user-not-found':
          throw Exception('No account found with this email address.');
        case 'invalid-email':
          throw Exception('The email address is not valid.');
        default:
          throw Exception('Password reset failed: ${e.message}');
      }
    } catch (e) {
      throw Exception('Password reset failed: $e');
    }
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('No user is currently signed in.');
      }

      if (user.email == null) {
        throw Exception('User email is not available.');
      }

      // Re-authenticate the user with their current password
      final credential = EmailAuthProvider.credential(
        email: user.email!,
        password: currentPassword,
      );

      await user.reauthenticateWithCredential(credential);

      // Update the password
      await user.updatePassword(newPassword);
    } on FirebaseAuthException catch (e) {
      switch (e.code) {
        case 'wrong-password':
          throw Exception('Current password is incorrect.');
        case 'weak-password':
          throw Exception(
            'The new password is too weak. Please choose a stronger password.',
          );
        case 'requires-recent-login':
          throw Exception(
            'For security reasons, please log out and log back in before changing your password.',
          );
        default:
          throw Exception('Password change failed: ${e.message}');
      }
    } catch (e) {
      if (e.toString().contains('No user is currently signed in') ||
          e.toString().contains('Current password is incorrect') ||
          e.toString().contains('weak-password') ||
          e.toString().contains('requires-recent-login')) {
        rethrow;
      }
      throw Exception('Password change failed: $e');
    }
  }
}
