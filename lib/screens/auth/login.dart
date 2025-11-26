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

      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/home');
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
              // Calculate responsive values
              final isDesktop = constraints.maxWidth > 600;
              final isTablet =
                  constraints.maxWidth > 400 && constraints.maxWidth <= 600;
              final screenPadding = isDesktop ? 40.0 : (isTablet ? 30.0 : 20.0);
              final maxWidth = isDesktop ? 500.0 : constraints.maxWidth;
              final titleFontSize = isDesktop ? 28.0 : (isTablet ? 24.0 : 20.0);
              final subtitleFontSize = isDesktop
                  ? 16.0
                  : (isTablet ? 15.0 : 14.0);
              final iconSize = isDesktop ? 32.0 : (isTablet ? 28.0 : 24.0);
              final cardPadding = isDesktop
                  ? const EdgeInsets.fromLTRB(32, 24, 32, 32)
                  : (isTablet
                        ? const EdgeInsets.fromLTRB(24, 20, 24, 24)
                        : const EdgeInsets.fromLTRB(16, 18, 16, 20));

              return Container(
                width: double.infinity,
                height: double.infinity,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [primaryStart, primaryEnd, const Color(0xFF3FA8F5)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    stops: const [0.0, 0.5, 1.0],
                  ),
                ),
                child: SafeArea(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.symmetric(
                      horizontal: screenPadding,
                      vertical: screenPadding * 0.6,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: maxWidth),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const SizedBox(height: 40),
                            // Animated header
                            FadeTransition(
                              opacity: _fadeAnimation,
                              child: SlideTransition(
                                position: _slideAnimation,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    ScaleTransition(
                                      scale: _scaleAnimation,
                                      child: Container(
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          boxShadow: [
                                            BoxShadow(
                                              color: const Color(
                                                0x4DFFFFFF,
                                              ), // white with 0.3 opacity
                                              blurRadius: 20,
                                              spreadRadius: 5,
                                            ),
                                          ],
                                        ),
                                        child: CircleAvatar(
                                          radius: iconSize,
                                          backgroundColor: Colors.white,
                                          child: Icon(
                                            Icons.login_rounded,
                                            color: primaryStart,
                                            size: iconSize * 1.1,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Flexible(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            'Welcome back',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: titleFontSize,
                                              fontWeight: FontWeight.w700,
                                              shadows: [
                                                const Shadow(
                                                  color: Color(
                                                    0x1A000000,
                                                  ), // black with 0.1 opacity
                                                  blurRadius: 4,
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            'Sign in to your account',
                                            style: TextStyle(
                                              color: Colors.white70,
                                              fontSize: subtitleFontSize,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 32),
                            // Animated card
                            FadeTransition(
                              opacity: _fadeAnimation,
                              child: SlideTransition(
                                position:
                                    Tween<Offset>(
                                      begin: const Offset(0, 0.15),
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
                                child: ScaleTransition(
                                  scale: Tween<double>(begin: 0.95, end: 1.0)
                                      .animate(
                                        CurvedAnimation(
                                          parent: _scaleController,
                                          curve: const Interval(
                                            0.1,
                                            1.0,
                                            curve: Curves.easeOutBack,
                                          ),
                                        ),
                                      ),
                                  child: Card(
                                    elevation: 12,
                                    shadowColor: const Color(
                                      0x40000000,
                                    ), // black with 0.25 opacity
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(24),
                                    ),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(24),
                                        border: Border.all(
                                          color: const Color(
                                            0x33FFFFFF,
                                          ), // white with 0.2 opacity
                                          width: 1,
                                        ),
                                      ),
                                      child: Stack(
                                        children: [
                                          Padding(
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
                                                    label: 'Email',
                                                    icon: Icons.alternate_email,
                                                    keyboardType: TextInputType
                                                        .emailAddress,
                                                    validator: (v) {
                                                      final value =
                                                          v?.trim() ?? '';
                                                      if (value.isEmpty) {
                                                        return 'Required';
                                                      }

                                                      final emailRegex = RegExp(
                                                        r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{3,}$',
                                                      );
                                                      return emailRegex
                                                              .hasMatch(value)
                                                          ? null
                                                          : 'Invalid email';
                                                    },
                                                  ),
                                                  _buildPasswordField(
                                                    controller:
                                                        _passwordController,
                                                    label: 'Password',
                                                    icon: Icons.lock,
                                                  ),
                                                  const SizedBox(height: 8),
                                                  Row(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment.start,
                                                    children: [
                                                      Checkbox(
                                                        value: _rememberMe,
                                                        onChanged:
                                                            authProvider
                                                                .isLoading
                                                            ? null
                                                            : (v) async {
                                                                final newVal =
                                                                    v ?? false;
                                                                setState(
                                                                  () =>
                                                                      _rememberMe =
                                                                          newVal,
                                                                );
                                                                try {
                                                                  final prefs =
                                                                      await SharedPreferences.getInstance();
                                                                  await prefs
                                                                      .setBool(
                                                                        'remember_me',
                                                                        newVal,
                                                                      );
                                                                  if (newVal &&
                                                                      _emailController
                                                                          .text
                                                                          .trim()
                                                                          .isNotEmpty) {
                                                                    await prefs.setString(
                                                                      'remembered_email',
                                                                      _emailController
                                                                          .text
                                                                          .trim(),
                                                                    );
                                                                  }
                                                                  if (!newVal) {
                                                                    await prefs
                                                                        .remove(
                                                                          'remembered_email',
                                                                        );
                                                                  }
                                                                } catch (_) {}
                                                              },
                                                      ),
                                                      const Text(
                                                        'Remember me',
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                        ),
                                                      ),
                                                      const SizedBox(width: 35),
                                                      Flexible(
                                                        child: TextButton(
                                                          onPressed:
                                                              authProvider
                                                                  .isLoading
                                                              ? null
                                                              : _forgotPassword,
                                                          style: TextButton.styleFrom(
                                                            padding:
                                                                const EdgeInsets.symmetric(
                                                                  horizontal: 8,
                                                                  vertical: 4,
                                                                ),
                                                            minimumSize:
                                                                Size.zero,
                                                            tapTargetSize:
                                                                MaterialTapTargetSize
                                                                    .shrinkWrap,
                                                          ),
                                                          child: const Text(
                                                            'Forgot password?',
                                                            style: TextStyle(
                                                              fontSize: 12,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w600,
                                                            ),
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                            softWrap: false,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 20),
                                                  SizedBox(
                                                    height: 52,
                                                    child: ElevatedButton(
                                                      onPressed:
                                                          authProvider.isLoading
                                                          ? null
                                                          : _login,
                                                      style: ElevatedButton.styleFrom(
                                                        shape: RoundedRectangleBorder(
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                12,
                                                              ),
                                                        ),
                                                        backgroundColor:
                                                            authProvider
                                                                .isLoading
                                                            ? const Color(
                                                                0xB31E88E5,
                                                              ) // primaryStart with 0.7 opacity
                                                            : primaryStart,
                                                        foregroundColor:
                                                            Colors.white,
                                                        elevation:
                                                            authProvider
                                                                .isLoading
                                                            ? 0
                                                            : 2,
                                                        disabledBackgroundColor:
                                                            primaryStart,
                                                        disabledForegroundColor:
                                                            Colors.white,
                                                      ),
                                                      child:
                                                          authProvider.isLoading
                                                          ? Row(
                                                              mainAxisAlignment:
                                                                  MainAxisAlignment
                                                                      .center,
                                                              children: [
                                                                SizedBox(
                                                                  height: 20,
                                                                  width: 20,
                                                                  child: CircularProgressIndicator(
                                                                    strokeWidth:
                                                                        2.5,
                                                                    valueColor:
                                                                        const AlwaysStoppedAnimation<
                                                                          Color
                                                                        >(
                                                                          Colors
                                                                              .white,
                                                                        ),
                                                                  ),
                                                                ),
                                                                const SizedBox(
                                                                  width: 12,
                                                                ),
                                                                const Text(
                                                                  'Signing in...',
                                                                  style: TextStyle(
                                                                    fontSize:
                                                                        16,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w600,
                                                                    color: Colors
                                                                        .white,
                                                                  ),
                                                                ),
                                                              ],
                                                            )
                                                          : const Text(
                                                              'Sign In',
                                                              style: TextStyle(
                                                                fontSize: 16,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                              ),
                                                            ),
                                                    ),
                                                  ),
                                                  const SizedBox(height: 16),
                                                  Row(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment
                                                            .center,
                                                    children: [
                                                      const Text(
                                                        "Don't have an account? ",
                                                        style: TextStyle(
                                                          color: Colors.grey,
                                                        ),
                                                      ),
                                                      TextButton(
                                                        onPressed: () {
                                                          Navigator.pushNamed(
                                                            context,
                                                            '/register',
                                                          );
                                                        },
                                                        child: const Text(
                                                          'Sign Up',
                                                          style: TextStyle(
                                                            color: primaryStart,
                                                            fontWeight:
                                                                FontWeight.w600,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                          // Loading Overlay
                                          if (authProvider.isLoading)
                                            Positioned.fill(
                                              child: Container(
                                                decoration: BoxDecoration(
                                                  color: const Color(
                                                    0xB3FFFFFF,
                                                  ), // white with 0.7 opacity
                                                  borderRadius:
                                                      BorderRadius.circular(24),
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
                          ],
                        ),
                      ),
                    ),
                  ),
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
      prefixIcon: Icon(icon, color: const Color(0xFF1E88E5)),
      filled: true,
      fillColor: const Color(0xFFF7F9FC),
      labelStyle: const TextStyle(color: Colors.grey),
      floatingLabelStyle: const TextStyle(color: Color(0xFF1E88E5)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(
          color: Color(0xCCE3E7ED), // Color(0xFFE3E7ED) with 0.8 opacity
          width: 1.5,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFF1E88E5), width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Colors.redAccent, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        decoration: _inputDecoration(label, icon),
        textInputAction: TextInputAction.next,
        validator: validator,
        keyboardType: keyboardType,
        onTap: () => HapticFeedback.selectionClick(),
      ),
    );
  }

  Widget _buildPasswordField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        obscureText: _obscurePassword,
        decoration: _inputDecoration(label, icon).copyWith(
          suffixIcon: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _obscurePassword = !_obscurePassword);
              },
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Icon(
                  _obscurePassword ? Icons.visibility_off : Icons.visibility,
                  color: Colors.grey,
                  size: 20,
                ),
              ),
            ),
          ),
        ),
        textInputAction: TextInputAction.done,
        onFieldSubmitted: (_) => _login(),
        onTap: () => HapticFeedback.selectionClick(),
      ),
    );
  }
}
