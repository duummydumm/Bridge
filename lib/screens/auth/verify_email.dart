import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../providers/auth_provider.dart';
import '../../services/verification_service.dart';
import '../../providers/user_provider.dart';

class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({super.key});

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  bool _sending = false;
  bool _verifying = false;
  bool _checkingVerification = false;
  bool _usingFirebaseVerification = false;
  final VerificationService _verificationService = VerificationService();
  final List<TextEditingController> _otpControllers = List.generate(
    6,
    (_) => TextEditingController(),
  );
  final List<FocusNode> _otpFocusNodes = List.generate(6, (_) => FocusNode());
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _checkIfAdminAndRedirect();
    _checkVerificationMethod();
    // Periodically check if email is verified (for Firebase link verification)
    _startVerificationCheck();
  }

  Future<void> _checkIfAdminAndRedirect() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final user = authProvider.user;

    if (user != null) {
      // Load user profile if not loaded
      if (userProvider.currentUser == null) {
        await userProvider.loadUserProfile(user.uid);
      }

      // Check if user is admin
      final bool isAdmin = userProvider.currentUser?.isAdmin == true;

      // If admin, redirect to home immediately
      if (isAdmin && mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          Navigator.of(context).pushReplacementNamed('/home');
        });
      }
    }
  }

  @override
  void dispose() {
    for (var controller in _otpControllers) {
      controller.dispose();
    }
    for (var node in _otpFocusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  Future<void> _checkVerificationMethod() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final user = authProvider.user;

    if (user != null) {
      // Check if OTP exists in Firestore (EmailJS verification)
      try {
        final otpDoc = await FirebaseFirestore.instance
            .collection('email_verifications')
            .doc(user.uid)
            .get();

        setState(() {
          _usingFirebaseVerification = !otpDoc.exists;
        });
      } catch (e) {
        // If check fails, assume OTP method
        setState(() {
          _usingFirebaseVerification = false;
        });
      }
    }
  }

  void _startVerificationCheck() {
    // Check every 3 seconds if using Firebase verification
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && _usingFirebaseVerification) {
        _checkEmailVerification();
        _startVerificationCheck(); // Continue checking
      }
    });
  }

  Future<void> _checkEmailVerification() async {
    if (_checkingVerification) return;

    setState(() {
      _checkingVerification = true;
    });

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final user = authProvider.user;

      if (user != null) {
        // Reload user to get latest verification status
        await authProvider.reloadCurrentUser();

        // Check both Firebase Auth and Firestore verification
        final bool firebaseEmailVerified = user.emailVerified;
        bool firestoreEmailVerified = false;

        try {
          firestoreEmailVerified = await _verificationService.isEmailVerified(
            user.uid,
          );
        } catch (e) {
          // Ignore errors
        }

        final bool isEmailVerified =
            firebaseEmailVerified || firestoreEmailVerified;

        if (isEmailVerified && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Email verified successfully!'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pushReplacementNamed(context, '/home');
          return;
        }
      }
    } catch (e) {
      debugPrint('Error checking email verification: $e');
    } finally {
      if (mounted) {
        setState(() {
          _checkingVerification = false;
        });
      }
    }
  }

  Future<void> _resend() async {
    setState(() {
      _sending = true;
      _errorMessage = null;
      // Clear OTP fields
      for (var controller in _otpControllers) {
        controller.clear();
      }
    });
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final user = authProvider.user;

      if (user != null && user.email != null) {
        // Get user name from UserProvider if available
        String? userName;
        try {
          final currentUser = userProvider.currentUser;
          if (currentUser != null) {
            userName = currentUser.fullName.isNotEmpty
                ? currentUser.fullName
                : currentUser.firstName;
          }
          if (userName == null || userName.isEmpty) {
            userName = user.email!.split('@')[0];
          }
        } catch (_) {
          userName = user.email!.split('@')[0];
        }

        // Resend verification email via EmailJS
        await _verificationService.resendVerificationEmail(
          userId: user.uid,
          email: user.email!,
          userName: userName,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Verification code sent. Please check your inbox.'),
            ),
          );
        }
      } else {
        // Fallback to AuthProvider's method
        await authProvider.sendEmailVerification();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Verification email sent.')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error sending email: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _onOTPChanged(int index, String value) {
    if (value.length == 1 && index < 5) {
      // Move to next field
      _otpFocusNodes[index + 1].requestFocus();
    } else if (value.isEmpty && index > 0) {
      // Move to previous field
      _otpFocusNodes[index - 1].requestFocus();
    }

    // Check if all fields are filled
    final allFilled = _otpControllers.every((c) => c.text.isNotEmpty);
    if (allFilled) {
      _verifyOTP();
    }
  }

  Future<void> _verifyOTP() async {
    // Get the complete OTP
    final otp = _otpControllers.map((c) => c.text).join();

    if (otp.length != 6) {
      setState(() {
        _errorMessage = 'Please enter a 6-digit code';
      });
      return;
    }

    setState(() {
      _verifying = true;
      _errorMessage = null;
    });

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final user = authProvider.user;

      if (user != null) {
        final success = await _verificationService.verifyOTP(
          userId: user.uid,
          otp: otp,
        );

        if (mounted) {
          setState(() {
            _verifying = false;
          });

          if (success) {
            // Reload user to update state
            await authProvider.reloadCurrentUser();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Email verified successfully!'),
                  backgroundColor: Colors.green,
                ),
              );
              Navigator.pushReplacementNamed(context, '/home');
            }
          } else {
            setState(() {
              _errorMessage = 'Invalid or expired code. Please try again.';
            });
            // Clear OTP fields
            for (var controller in _otpControllers) {
              controller.clear();
            }
            _otpFocusNodes[0].requestFocus();
          }
        }
      } else {
        if (mounted) {
          setState(() {
            _verifying = false;
            _errorMessage = 'No user found. Please log in again.';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _verifying = false;
          _errorMessage = 'Error verifying code: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const primary = Color(0xFF1E88E5);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final user = authProvider.user;
    final email = user?.email ?? 'your email';

    return WillPopScope(
      onWillPop: () async {
        // Check if user is admin - admins can always go back
        final authProvider = Provider.of<AuthProvider>(context, listen: false);
        final userProvider = Provider.of<UserProvider>(context, listen: false);
        final user = authProvider.user;

        if (user != null) {
          // Load user profile if not loaded
          if (userProvider.currentUser == null) {
            await userProvider.loadUserProfile(user.uid);
          }

          // Check if user is admin
          final bool isAdmin = userProvider.currentUser?.isAdmin == true;

          // Admins can always go back
          if (isAdmin) {
            return true;
          }

          // For non-admins, check if email is verified
          final bool firebaseEmailVerified = user.emailVerified;
          bool firestoreEmailVerified = false;

          try {
            firestoreEmailVerified = await _verificationService.isEmailVerified(
              user.uid,
            );
          } catch (e) {
            // Ignore errors
          }

          final bool isEmailVerified =
              firebaseEmailVerified || firestoreEmailVerified;

          if (!isEmailVerified) {
            // Show message that verification is required
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Please verify your email to continue.'),
                backgroundColor: Colors.orange,
                duration: Duration(seconds: 3),
              ),
            );
            return false; // Prevent going back
          }
        }

        return true; // Allow going back if verified or admin
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Verify your email'),
          backgroundColor: primary,
          foregroundColor: Colors.white,
          automaticallyImplyLeading: false, // Remove back button
        ),
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),
              Text(
                _usingFirebaseVerification
                    ? 'Check your email'
                    : 'Enter verification code',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              if (_usingFirebaseVerification) ...[
                Text(
                  'We sent a verification link to $email',
                  style: const TextStyle(fontSize: 16, color: Colors.black54),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Click the link in your email to verify your account. '
                  'The app will automatically detect when your email is verified.',
                  style: TextStyle(fontSize: 14, color: Colors.black54),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: Colors.orange.shade700,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Can\'t find the email? Check your spam/junk folder. '
                          'The email may take a few minutes to arrive.',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.orange.shade900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 40),
                // Check Verification Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _checkingVerification
                        ? null
                        : _checkEmailVerification,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primary,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _checkingVerification
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'Check Verification Status',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
              ] else ...[
                Text(
                  'We sent a 6-digit verification code to $email',
                  style: const TextStyle(fontSize: 16, color: Colors.black54),
                ),
                const SizedBox(height: 40),
                // OTP Input Fields
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: List.generate(6, (index) {
                    return SizedBox(
                      width: 45,
                      height: 55,
                      child: TextField(
                        controller: _otpControllers[index],
                        focusNode: _otpFocusNodes[index],
                        textAlign: TextAlign.center,
                        keyboardType: TextInputType.number,
                        maxLength: 1,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                        decoration: InputDecoration(
                          counterText: '',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: _errorMessage != null
                                  ? Colors.red
                                  : Colors.grey[300]!,
                              width: 2,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: _errorMessage != null
                                  ? Colors.red
                                  : Colors.grey[300]!,
                              width: 2,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: primary,
                              width: 2,
                            ),
                          ),
                          filled: true,
                          fillColor: Colors.grey[50],
                        ),
                        onChanged: (value) => _onOTPChanged(index, value),
                      ),
                    );
                  }),
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.red, fontSize: 14),
                  ),
                ],
                const Spacer(),
                if (!_usingFirebaseVerification) ...[
                  // Verify Button (only for OTP method)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _verifying ? null : _verifyOTP,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primary,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _verifying
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Verify',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Resend Button
                  Center(
                    child: TextButton(
                      onPressed: _sending ? null : _resend,
                      child: _sending
                          ? const Text('Sending...')
                          : const Text('Resend code'),
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}
