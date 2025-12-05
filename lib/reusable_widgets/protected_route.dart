import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import '../providers/auth_provider.dart';
import '../providers/user_provider.dart';
import '../services/verification_service.dart';

/// Wrapper widget that checks email verification before allowing access to protected routes
class ProtectedRoute extends StatelessWidget {
  final Widget child;
  final bool allowAdmins;
  final bool allowBypassEmails;

  const ProtectedRoute({
    super.key,
    required this.child,
    this.allowAdmins = true,
    this.allowBypassEmails = true,
  });

  // Bypass emails (for testing)
  static const Set<String> kVerificationBypassEmails = {
    'balafamily4231@gmail.com',
    'applejeantizon09@gmail.com',
  };

  @override
  Widget build(BuildContext context) {
    // Use listen: false for UserProvider to prevent rebuilds on user data changes
    // We only need to check auth state, not listen to every user update
    final authProvider = Provider.of<AuthProvider>(context, listen: true);
    final userProvider = Provider.of<UserProvider>(context, listen: false);

    // Check both AuthProvider and Firebase Auth directly as fallback
    // This ensures we catch the user even if AuthProvider hasn't updated yet
    final user =
        authProvider.user ?? firebase_auth.FirebaseAuth.instance.currentUser;

    // If user is not authenticated, redirect to login
    if (user == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          Navigator.of(context).pushReplacementNamed('/login');
        }
      });
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Load user profile if not loaded
    if (userProvider.currentUser == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          userProvider.loadUserProfile(user.uid);
        }
      });
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final bool isAdmin = userProvider.currentUser?.isAdmin == true;

    // Admins can bypass verification if allowed
    if (isAdmin && allowAdmins) {
      return child;
    }

    // Check bypass emails
    if (allowBypassEmails) {
      final String signedInEmail = (user.email ?? '').toLowerCase();
      final bool isBypassEmail = kVerificationBypassEmails.contains(
        signedInEmail,
      );
      if (isBypassEmail) {
        return child;
      }
    }

    // Check email verification
    // Use a key based on user.uid to prevent FutureBuilder from recreating
    return FutureBuilder<bool>(
      key: ValueKey('protected_route_verification_${user.uid}'),
      future: _checkEmailVerification(user.uid, user.emailVerified),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final bool isEmailVerified = snapshot.data ?? false;

        // If email is not verified, redirect to verification screen
        if (!isEmailVerified) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) {
              Navigator.of(context).pushReplacementNamed('/verify-email');
            }
          });
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // Email is verified, allow access
        return child;
      },
    );
  }

  Future<bool> _checkEmailVerification(
    String userId,
    bool firebaseEmailVerified,
  ) async {
    try {
      // Check Firestore emailVerified status (for EmailJS verification)
      final verificationService = VerificationService();
      final firestoreEmailVerified = await verificationService.isEmailVerified(
        userId,
      );

      // User is verified if either Firebase Auth or Firestore says so
      return firebaseEmailVerified || firestoreEmailVerified;
    } catch (e) {
      debugPrint('ProtectedRoute: Error checking email verification: $e');
      // On error, fall back to Firebase Auth verification status
      return firebaseEmailVerified;
    }
  }
}
