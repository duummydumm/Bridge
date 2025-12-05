import 'dart:ui';
import 'package:flutter/material.dart';
// import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../providers/auth_provider.dart';
import '../../providers/user_provider.dart';
import '../../services/verification_service.dart';

// Replace with your sample/testing emails to bypass email verification
const Set<String> kVerificationBypassEmails = {
  'balafamily4231@gmail.com',
  'applejeantizon09@gmail.com',
};

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _rememberMe = false;

  late AnimationController _fadeController;
  late AnimationController _slideController;
  late AnimationController _scaleController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _loadRememberedCredentials();

    // Initialize animations
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut),
    );

    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.2), end: Offset.zero).animate(
          CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic),
        );

    _scaleAnimation = Tween<double>(begin: 0.9, end: 1.0).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.easeOutBack),
    );

    // Start animations
    _fadeController.forward();
    _slideController.forward();
    _scaleController.forward();
  }

  Future<void> _loadRememberedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final savedRemember = prefs.getBool('remember_me') ?? false;
    final savedEmail = prefs.getString('remembered_email') ?? '';
    if (savedRemember && savedEmail.isNotEmpty) {
      setState(() {
        _rememberMe = true;
        _emailController.text = savedEmail;
      });
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _fadeController.dispose();
    _slideController.dispose();
    _scaleController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final userProvider = Provider.of<UserProvider>(context, listen: false);

    // Wait for next frame to ensure UI can update before async operation
    await Future.delayed(Duration.zero);

    final success = await authProvider.loginWithEmail(
      email: _emailController.text.trim(),
      password: _passwordController.text.trim(),
    );

    if (!mounted) return;

    if (success) {
      // Load user profile first so we can check admin role
      await userProvider.loadUserProfile(authProvider.user?.uid ?? '');

      if (!mounted) return;

      final bool isAdmin = userProvider.currentUser?.isAdmin == true;
      final String signedInEmail = (authProvider.user?.email ?? '')
          .toLowerCase();
      final bool isBypassEmail = kVerificationBypassEmails
          .map((e) => e.toLowerCase())
          .contains(signedInEmail);

      // Check email verification status (check both Firebase Auth and Firestore)
      final bool firebaseEmailVerified =
          authProvider.user?.emailVerified == true;

      // Check Firestore emailVerified status (for EmailJS verification)
      bool firestoreEmailVerified = false;
      if (authProvider.user?.uid != null) {
        try {
          final verificationService = VerificationService();
          firestoreEmailVerified = await verificationService.isEmailVerified(
            authProvider.user!.uid,
          );
        } catch (e) {
          debugPrint('Login: Error checking Firestore email verification: $e');
        }
      }

      final bool isEmailVerified =
          firebaseEmailVerified || firestoreEmailVerified;

      // For non-admins, enforce email verification
      if (!isAdmin && !isBypassEmail && !isEmailVerified) {
        try {
          await authProvider.sendEmailVerification();
        } catch (_) {}
        if (!mounted) return;
        HapticFeedback.mediumImpact();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.email_outlined, color: Colors.white, size: 20),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Please verify your email to continue.',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            margin: const EdgeInsets.all(16),
            duration: const Duration(seconds: 4),
          ),
        );
        Navigator.pushReplacementNamed(context, '/verify-email');
        return;
      }

      // Persist remember me preference and email
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('remember_me', _rememberMe);
        if (_rememberMe) {
          await prefs.setString(
            'remembered_email',
            _emailController.text.trim(),
          );
        } else {
          await prefs.remove('remembered_email');
        }
      } catch (_) {}
      if (!mounted) return;

      // Get the user's name
      final userName =
          userProvider.currentUser?.fullName ??
          userProvider.currentUser?.firstName ??
          authProvider.user?.email ??
          'User';

      // Haptic feedback for success
      HapticFeedback.lightImpact();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Welcome back, $userName!',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          margin: const EdgeInsets.all(16),
          duration: const Duration(seconds: 3),
        ),
      );

      // Wait a moment for auth state to fully sync before navigating
      // This prevents the refresh loop issue
      await Future.delayed(const Duration(milliseconds: 100));

      if (!mounted) return;

      // Navigate to home and clear the route stack to prevent refresh loops
      // Using pushNamedAndRemoveUntil ensures a clean navigation without conflicts
      Navigator.of(context).pushNamedAndRemoveUntil(
        '/home',
        (route) => false, // Remove all previous routes including login
      );
    } else {
      // Haptic feedback for error
      HapticFeedback.mediumImpact();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.white, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  authProvider.errorMessage ?? 'Login failed',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          margin: const EdgeInsets.all(16),
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  Future<void> _forgotPassword() async {
    HapticFeedback.selectionClick();
    // Get provider before any async operations to avoid BuildContext across async gaps
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final emailText = _emailController.text.trim();
    String tempEmail = emailText;

    if (tempEmail.isEmpty) {
      final result = await showDialog<String>(
        context: context,
        builder: (context) {
          final TextEditingController dialogController = TextEditingController(
            text: tempEmail,
          );
          return Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0x1A1E88E5), // 0.1 opacity
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.lock_reset,
                          color: Color(0xFF1E88E5),
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Reset Password',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Enter your email address and we\'ll send you a link to reset your password.',
                    style: TextStyle(color: Colors.grey, fontSize: 14),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: dialogController,
                    keyboardType: TextInputType.emailAddress,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: 'Email',
                      prefixIcon: const Icon(Icons.email_outlined),
                      filled: true,
                      fillColor: const Color(0xFFF7F9FC),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: Color(0x4D9E9E9E), // grey with 0.3 opacity
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: Color(0x4D9E9E9E), // grey with 0.3 opacity
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: Color(0xFF1E88E5),
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(
                          context,
                          dialogController.text.trim(),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1E88E5),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                        ),
                        child: const Text('Send Reset Link'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      );
      if (result == null || result.isEmpty) return;
      tempEmail = result;
    }

    final ok = await authProvider.sendPasswordReset(email: tempEmail);
    if (!mounted) return;
    if (ok) {
      HapticFeedback.lightImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white, size: 20),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Password reset email sent. Check your inbox.',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          margin: const EdgeInsets.all(16),
          duration: const Duration(seconds: 4),
        ),
      );
    } else {
      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.white, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  authProvider.errorMessage ?? 'Failed to send reset email',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    const primaryStart = Color(0xFF1E88E5);
    const primaryEnd = Color(0xFF42A5F5);

    return Consumer<AuthProvider>(
      builder: (context, authProvider, child) {
        return Scaffold(
          body: LayoutBuilder(
            builder: (context, constraints) {
              // Responsive calculations
              final isDesktop = constraints.maxWidth > 600;
              final isTablet =
                  constraints.maxWidth > 400 && constraints.maxWidth <= 600;
              final screenPadding = isDesktop ? 40.0 : (isTablet ? 30.0 : 20.0);
              final maxWidth = isDesktop ? 480.0 : constraints.maxWidth;
              final titleFontSize = isDesktop ? 32.0 : (isTablet ? 28.0 : 24.0);
              final subtitleFontSize = isDesktop
                  ? 16.0
                  : (isTablet ? 15.0 : 14.0);
              final cardPadding = isDesktop
                  ? const EdgeInsets.all(40)
                  : (isTablet
                        ? const EdgeInsets.all(32)
                        : const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 32,
                          ));

              return Container(
                width: double.infinity,
                height: double.infinity,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Color(0xFF1565C0), // Darker Blue
                      primaryStart, // Primary Blue
                      primaryEnd, // Lighter Blue
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Stack(
                  children: [
                    // Decorative Background Circles
                    Positioned(
                      top: -100,
                      right: -100,
                      child: Container(
                        width: 300,
                        height: 300,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withOpacity(0.1),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: -50,
                      left: -50,
                      child: Container(
                        width: 200,
                        height: 200,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withOpacity(0.1),
                        ),
                      ),
                    ),

                    // Main Content
                    SafeArea(
                      child: Center(
                        child: SingleChildScrollView(
                          padding: EdgeInsets.symmetric(
                            horizontal: screenPadding,
                            vertical: 20,
                          ),
                          child: ConstrainedBox(
                            constraints: BoxConstraints(maxWidth: maxWidth),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // Animated Header
                                FadeTransition(
                                  opacity: _fadeAnimation,
                                  child: SlideTransition(
                                    position: _slideAnimation,
                                    child: Column(
                                      children: [
                                        ScaleTransition(
                                          scale: _scaleAnimation,
                                          child: ShaderMask(
                                            shaderCallback: (Rect bounds) {
                                              return const LinearGradient(
                                                colors: [
                                                  Color(0xFF00897B),
                                                  Color(0xFF26A69A),
                                                  Color(0xFF4DB6AC),
                                                ],
                                                begin: Alignment.topLeft,
                                                end: Alignment.bottomRight,
                                              ).createShader(bounds);
                                            },
                                            child: Text(
                                              'BRIDGE',
                                              style: TextStyle(
                                                fontSize: titleFontSize * 2.5,
                                                fontWeight: FontWeight.bold,
                                                letterSpacing: 2.0,
                                                color: Colors.white,
                                              ),
                                              textAlign: TextAlign.center,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          'Sign in to continue to your dashboard',
                                          style: TextStyle(
                                            color: Colors.white.withOpacity(
                                              0.9,
                                            ),
                                            fontSize: subtitleFontSize,
                                            fontWeight: FontWeight.w400,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 40),

                                // Glassmorphism Card
                                FadeTransition(
                                  opacity: _fadeAnimation,
                                  child: SlideTransition(
                                    position:
                                        Tween<Offset>(
                                          begin: const Offset(0, 0.1),
                                          end: Offset.zero,
                                        ).animate(
                                          CurvedAnimation(
                                            parent: _slideController,
                                            curve: const Interval(
                                              0.2,
                                              1.0,
                                              curve: Curves.easeOutCubic,
                                            ),
                                          ),
                                        ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(24),
                                      child: BackdropFilter(
                                        filter: ImageFilter.blur(
                                          sigmaX: 10,
                                          sigmaY: 10,
                                        ),
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: Colors.white.withOpacity(
                                              0.85,
                                            ), // Semi-transparent white
                                            borderRadius: BorderRadius.circular(
                                              24,
                                            ),
                                            border: Border.all(
                                              color: Colors.white.withOpacity(
                                                0.6,
                                              ),
                                              width: 1.5,
                                            ),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black.withOpacity(
                                                  0.1,
                                                ),
                                                blurRadius: 20,
                                                spreadRadius: 5,
                                                offset: const Offset(0, 10),
                                              ),
                                            ],
                                          ),
                                          child: Padding(
                                            padding: cardPadding,
                                            child: Form(
                                              key: _formKey,
                                              autovalidateMode: AutovalidateMode
                                                  .onUserInteraction,
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.stretch,
                                                children: [
                                                  _buildTextField(
                                                    controller:
                                                        _emailController,
                                                    label: 'Email Address',
                                                    icon: Icons.email_outlined,
                                                    keyboardType: TextInputType
                                                        .emailAddress,
                                                    validator: (v) {
                                                      final value =
                                                          v?.trim() ?? '';
                                                      if (value.isEmpty) {
                                                        return 'Email is required';
                                                      }
                                                      final emailRegex = RegExp(
                                                        r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{3,}$',
                                                      );
                                                      return emailRegex
                                                              .hasMatch(value)
                                                          ? null
                                                          : 'Enter a valid email';
                                                    },
                                                  ),
                                                  const SizedBox(height: 20),
                                                  _buildPasswordField(
                                                    controller:
                                                        _passwordController,
                                                    label: 'Password',
                                                    icon: Icons.lock_outline,
                                                  ),
                                                  const SizedBox(height: 12),

                                                  // Remember Me & Forgot Password
                                                  Row(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment
                                                            .spaceBetween,
                                                    children: [
                                                      Row(
                                                        children: [
                                                          SizedBox(
                                                            height: 24,
                                                            width: 24,
                                                            child: Checkbox(
                                                              value:
                                                                  _rememberMe,
                                                              activeColor:
                                                                  primaryStart,
                                                              shape: RoundedRectangleBorder(
                                                                borderRadius:
                                                                    BorderRadius.circular(
                                                                      4,
                                                                    ),
                                                              ),
                                                              onChanged:
                                                                  authProvider
                                                                      .isLoading
                                                                  ? null
                                                                  : (v) async {
                                                                      final newVal =
                                                                          v ??
                                                                          false;
                                                                      setState(
                                                                        () => _rememberMe =
                                                                            newVal,
                                                                      );
                                                                      try {
                                                                        final prefs =
                                                                            await SharedPreferences.getInstance();
                                                                        await prefs.setBool(
                                                                          'remember_me',
                                                                          newVal,
                                                                        );
                                                                        if (newVal &&
                                                                            _emailController.text.trim().isNotEmpty) {
                                                                          await prefs.setString(
                                                                            'remembered_email',
                                                                            _emailController.text.trim(),
                                                                          );
                                                                        } else if (!newVal) {
                                                                          await prefs.remove(
                                                                            'remembered_email',
                                                                          );
                                                                        }
                                                                      } catch (
                                                                        _
                                                                      ) {}
                                                                    },
                                                            ),
                                                          ),
                                                          const SizedBox(
                                                            width: 8,
                                                          ),
                                                          Text(
                                                            'Remember me',
                                                            style: TextStyle(
                                                              fontSize: 13,
                                                              color: Colors
                                                                  .grey[700],
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w500,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                      TextButton(
                                                        onPressed:
                                                            authProvider
                                                                .isLoading
                                                            ? null
                                                            : _forgotPassword,
                                                        style: TextButton.styleFrom(
                                                          padding:
                                                              EdgeInsets.zero,
                                                          minimumSize:
                                                              Size.zero,
                                                          tapTargetSize:
                                                              MaterialTapTargetSize
                                                                  .shrinkWrap,
                                                          foregroundColor:
                                                              primaryStart,
                                                        ),
                                                        child: const Text(
                                                          'Forgot Password?',
                                                          style: TextStyle(
                                                            fontSize: 13,
                                                            fontWeight:
                                                                FontWeight.w600,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 32),

                                                  // Sign In Button
                                                  SizedBox(
                                                    height: 56,
                                                    child: ElevatedButton(
                                                      onPressed:
                                                          authProvider.isLoading
                                                          ? null
                                                          : _login,
                                                      style: ElevatedButton.styleFrom(
                                                        backgroundColor:
                                                            primaryStart,
                                                        foregroundColor:
                                                            Colors.white,
                                                        elevation: 4,
                                                        shadowColor:
                                                            primaryStart
                                                                .withOpacity(
                                                                  0.4,
                                                                ),
                                                        shape: RoundedRectangleBorder(
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                16,
                                                              ),
                                                        ),
                                                        disabledBackgroundColor:
                                                            primaryStart
                                                                .withOpacity(
                                                                  0.6,
                                                                ),
                                                        disabledForegroundColor:
                                                            Colors.white,
                                                      ),
                                                      child:
                                                          authProvider.isLoading
                                                          ? const SizedBox(
                                                              height: 24,
                                                              width: 24,
                                                              child: CircularProgressIndicator(
                                                                strokeWidth:
                                                                    2.5,
                                                                valueColor:
                                                                    AlwaysStoppedAnimation<
                                                                      Color
                                                                    >(
                                                                      Colors
                                                                          .white,
                                                                    ),
                                                              ),
                                                            )
                                                          : const Text(
                                                              'Sign In',
                                                              style: TextStyle(
                                                                fontSize: 16,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                                letterSpacing:
                                                                    0.5,
                                                              ),
                                                            ),
                                                    ),
                                                  ),

                                                  const SizedBox(height: 24),

                                                  // Sign Up Link
                                                  Row(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment
                                                            .center,
                                                    children: [
                                                      Text(
                                                        "Don't have an account? ",
                                                        style: TextStyle(
                                                          color:
                                                              Colors.grey[600],
                                                          fontSize: 14,
                                                        ),
                                                      ),
                                                      GestureDetector(
                                                        onTap: () {
                                                          Navigator.pushNamed(
                                                            context,
                                                            '/register',
                                                          );
                                                        },
                                                        child: Text(
                                                          'Sign Up',
                                                          style: TextStyle(
                                                            color: primaryStart,
                                                            fontWeight:
                                                                FontWeight.bold,
                                                            fontSize: 14,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: const Color(0xFF1E88E5), size: 22),
      filled: true,
      fillColor: Colors.grey[50], // Very light grey
      labelStyle: TextStyle(color: Colors.grey[600], fontSize: 14),
      floatingLabelStyle: const TextStyle(
        color: Color(0xFF1E88E5),
        fontWeight: FontWeight.w600,
      ),
      contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.grey[200]!, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFF1E88E5), width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Colors.redAccent, width: 1),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Colors.redAccent, width: 2),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
  }) {
    return TextFormField(
      controller: controller,
      decoration: _inputDecoration(label, icon),
      textInputAction: TextInputAction.next,
      validator: validator,
      keyboardType: keyboardType,
      style: const TextStyle(fontSize: 15, color: Colors.black87),
      onTap: () => HapticFeedback.selectionClick(),
    );
  }

  Widget _buildPasswordField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: _obscurePassword,
      decoration: _inputDecoration(label, icon).copyWith(
        suffixIcon: IconButton(
          icon: Icon(
            _obscurePassword
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
            color: Colors.grey[500],
            size: 20,
          ),
          onPressed: () {
            HapticFeedback.selectionClick();
            setState(() => _obscurePassword = !_obscurePassword);
          },
        ),
      ),
      textInputAction: TextInputAction.done,
      onFieldSubmitted: (_) => _login(),
      style: const TextStyle(fontSize: 15, color: Colors.black87),
      onTap: () => HapticFeedback.selectionClick(),
    );
  }
}
