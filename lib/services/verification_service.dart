import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:flutter/foundation.dart';
import 'email_service.dart';

/// Service for managing email verification tokens
class VerificationService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final EmailService _emailService = EmailService();

  /// Generate a 6-digit OTP code
  String _generateOTP() {
    final random = Random.secure();
    // Generate a 6-digit number (100000 to 999999)
    final otp = 100000 + random.nextInt(900000);
    return otp.toString();
  }

  /// Create a verification OTP and send verification email
  ///
  /// [userId] - The user's UID
  /// [email] - The user's email address
  /// [userName] - The user's name (optional)
  ///
  /// Returns the OTP code
  Future<String> createVerificationOTP({
    required String userId,
    required String email,
    String? userName,
  }) async {
    try {
      // Generate a 6-digit OTP
      final otp = _generateOTP();

      // Calculate expiration time (10 minutes from now)
      final expiresAt = DateTime.now().add(const Duration(minutes: 10));

      // Store the OTP in Firestore (use userId as document ID for easy lookup)
      await _db.collection('email_verifications').doc(userId).set({
        'userId': userId,
        'email': email,
        'otp': otp,
        'createdAt': FieldValue.serverTimestamp(),
        'expiresAt': Timestamp.fromDate(expiresAt),
        'verified': false,
        'attempts': 0, // Track verification attempts
      });

      // Send verification email via EmailJS with OTP
      try {
        await _emailService.sendVerificationEmail(
          toEmail: email,
          toName: userName,
          otp: otp,
        );

        debugPrint(
          'VerificationService: OTP created and email sent for user $userId',
        );
        return otp;
      } catch (e) {
        // If EmailJS is blocked (403 error), delete the OTP and rethrow
        // The auth service will handle the fallback to Firebase email verification
        debugPrint('VerificationService: EmailJS failed, cleaning up OTP: $e');
        try {
          await _db.collection('email_verifications').doc(userId).delete();
        } catch (_) {
          // Ignore cleanup errors
        }
        rethrow;
      }
    } catch (e) {
      debugPrint('VerificationService: Error creating verification OTP: $e');
      rethrow;
    }
  }

  /// Verify an OTP and mark the user as verified
  ///
  /// [userId] - The user's UID
  /// [otp] - The OTP code entered by the user
  ///
  /// Returns true if verification was successful, false otherwise
  Future<bool> verifyOTP({required String userId, required String otp}) async {
    try {
      // Get the verification document
      final doc = await _db.collection('email_verifications').doc(userId).get();

      if (!doc.exists) {
        debugPrint('VerificationService: OTP not found for user $userId');
        return false;
      }

      final data = doc.data()!;

      // Check if already verified
      if (data['verified'] == true) {
        debugPrint(
          'VerificationService: Email already verified for user $userId',
        );
        return false;
      }

      // Check if OTP has expired
      final expiresAt = (data['expiresAt'] as Timestamp).toDate();
      if (DateTime.now().isAfter(expiresAt)) {
        debugPrint('VerificationService: OTP expired for user $userId');
        // Delete expired OTP
        await _db.collection('email_verifications').doc(userId).delete();
        return false;
      }

      // Check verification attempts (max 5 attempts)
      final attempts = (data['attempts'] as int? ?? 0);
      if (attempts >= 5) {
        debugPrint('VerificationService: Too many attempts for user $userId');
        // Delete OTP after too many attempts
        await _db.collection('email_verifications').doc(userId).delete();
        return false;
      }

      // Verify OTP
      final storedOTP = data['otp'] as String;
      if (otp != storedOTP) {
        // Increment attempts
        await _db.collection('email_verifications').doc(userId).update({
          'attempts': FieldValue.increment(1),
        });
        debugPrint('VerificationService: Invalid OTP for user $userId');
        return false;
      }

      // Mark OTP as verified
      await _db.collection('email_verifications').doc(userId).update({
        'verified': true,
        'verifiedAt': FieldValue.serverTimestamp(),
      });

      // Update user's emailVerified status in Firestore
      await _db.collection('users').doc(userId).update({
        'emailVerified': true,
        'emailVerifiedAt': FieldValue.serverTimestamp(),
      });

      // Get user data for welcome email
      String? userEmail;
      String? userName;
      try {
        final userDoc = await _db.collection('users').doc(userId).get();
        if (userDoc.exists) {
          final userData = userDoc.data()!;
          userEmail = userData['email'] as String?;
          // Try to get full name or first name
          final firstName = userData['firstName'] as String? ?? '';
          final lastName = userData['lastName'] as String? ?? '';
          if (firstName.isNotEmpty && lastName.isNotEmpty) {
            userName = '$firstName $lastName';
          } else if (firstName.isNotEmpty) {
            userName = firstName;
          } else {
            userName = userEmail?.split('@')[0];
          }
        }
      } catch (e) {
        debugPrint('VerificationService: Error getting user data: $e');
      }

      // Reload Firebase Auth user to refresh emailVerified status
      try {
        final user = fb_auth.FirebaseAuth.instance.currentUser;
        if (user != null && user.uid == userId) {
          await user.reload();
          // Use Firebase Auth email if Firestore email is not available
          if (userEmail == null && user.email != null) {
            userEmail = user.email;
          }
        }
      } catch (e) {
        debugPrint(
          'VerificationService: Error reloading Firebase Auth user: $e',
        );
      }

      // Send welcome email after successful verification
      if (userEmail != null) {
        try {
          await _emailService.sendWelcomeEmail(
            toEmail: userEmail,
            toName: userName,
          );
          debugPrint('VerificationService: Welcome email sent to $userEmail');
        } catch (e) {
          // Don't fail verification if welcome email fails
          debugPrint('VerificationService: Error sending welcome email: $e');
        }
      }

      // Delete the OTP document after successful verification
      await _db.collection('email_verifications').doc(userId).delete();

      debugPrint(
        'VerificationService: OTP verified successfully for user $userId',
      );
      return true;
    } catch (e) {
      debugPrint('VerificationService: Error verifying OTP: $e');
      return false;
    }
  }

  /// Check if a user's email is verified
  ///
  /// [userId] - The user's UID
  ///
  /// Returns true if the user's email is verified
  Future<bool> isEmailVerified(String userId) async {
    try {
      final userDoc = await _db.collection('users').doc(userId).get();
      if (!userDoc.exists) {
        return false;
      }
      final data = userDoc.data()!;
      return data['emailVerified'] == true;
    } catch (e) {
      debugPrint('VerificationService: Error checking email verification: $e');
      return false;
    }
  }

  /// Resend verification email with new OTP
  ///
  /// [userId] - The user's UID
  /// [email] - The user's email address
  /// [userName] - The user's name (optional)
  Future<void> resendVerificationEmail({
    required String userId,
    required String email,
    String? userName,
  }) async {
    try {
      // Delete any existing unverified OTP for this user
      final existingDoc = await _db
          .collection('email_verifications')
          .doc(userId)
          .get();
      if (existingDoc.exists) {
        await existingDoc.reference.delete();
      }

      // Create a new verification OTP
      await createVerificationOTP(
        userId: userId,
        email: email,
        userName: userName,
      );

      debugPrint(
        'VerificationService: Verification email resent for user $userId',
      );
    } catch (e) {
      debugPrint('VerificationService: Error resending verification email: $e');
      rethrow;
    }
  }
}
