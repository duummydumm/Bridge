import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:io';
import '../../providers/auth_provider.dart';
import '../../providers/user_provider.dart';
import '../../services/firestore_service.dart';
// import '../../services/ping_service.dart'; // Old Render backend wake-up (no longer used with Cloud Functions)
import '../../services/verification_service.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _middleInitialController =
      TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _cityController = TextEditingController(
    text: 'Oroquieta',
  );
  final TextEditingController _provinceController = TextEditingController(
    text: 'Misamis Occidental',
  );
  final TextEditingController _streetController = TextEditingController();
  final TextEditingController _barangayIdUrlController =
      TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  String _role = 'both'; // Default: All users can borrow AND lend
  bool _uploadingImage = false;
  String? _barangayIdType; // required
  XFile? _pickedImageFront; // Front of ID
  XFile? _pickedImageBack; // Back of ID (optional but recommended)
  bool _consentGiven = false; // Privacy Policy consent
  bool _termsAccepted = false; // Terms of Service acceptance
  double _passwordStrength = 0.0;
  List<String> _barangays = [];
  String? _selectedBarangay;

  // Email availability checking
  Timer? _emailCheckTimer;
  bool _isCheckingEmail = false;
  bool?
  _isEmailAvailable; // null = not checked, true = available, false = taken
  String _lastCheckedEmail = '';

  // Animation controllers
  late AnimationController _fadeController;
  late AnimationController _slideController;
  late AnimationController _scaleController;
  late AnimationController _successController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<double> _successScaleAnimation;
  late Animation<double> _successRotationAnimation;

  // OTP / email verification service (EmailJS + Firestore)
  final VerificationService _verificationService = VerificationService();

  @override
  void initState() {
    super.initState();
    // Old behavior (Render backend): wake backend early so OTP/email services
    // were ready by the time user submits.
    // PingService.wakeBackend();
    _loadBarangays();

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
    _successController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
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

    _successScaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _successController,
        curve: const Interval(0.0, 0.6, curve: Curves.elasticOut),
      ),
    );

    _successRotationAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _successController, curve: Curves.easeInOut),
    );

    // Start animations
    _fadeController.forward();
    _slideController.forward();
    _scaleController.forward();
  }

  Future<void> _loadBarangays() async {
    try {
      final String jsonString = await rootBundle.loadString(
        'assets/data/oroquieta_barangays.json',
      );
      final List<dynamic> jsonData = json.decode(jsonString);
      setState(() {
        _barangays = jsonData.cast<String>();
      });
      print('Loaded ${_barangays.length} barangays');
    } catch (e) {
      print('Error loading barangays: $e');
      // Show error to user if needed
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading barangays: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _emailCheckTimer?.cancel();
    _fadeController.dispose();
    _slideController.dispose();
    _scaleController.dispose();
    _successController.dispose();
    _firstNameController.dispose();
    _middleInitialController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _cityController.dispose();
    _provinceController.dispose();
    _streetController.dispose();
    _barangayIdUrlController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  // Debounced email availability check
  void _checkEmailAvailability(String email) {
    _emailCheckTimer?.cancel();

    final trimmedEmail = email.trim();

    // Reset state if email is empty or invalid
    if (trimmedEmail.isEmpty ||
        !RegExp(
          r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{3,}$',
        ).hasMatch(trimmedEmail)) {
      setState(() {
        _isEmailAvailable = null;
        _isCheckingEmail = false;
      });
      return;
    }

    // Don't check if it's the same email we just checked
    if (trimmedEmail == _lastCheckedEmail) {
      return;
    }

    setState(() {
      _isCheckingEmail = true;
      _isEmailAvailable = null;
    });

    _emailCheckTimer = Timer(const Duration(milliseconds: 800), () async {
      if (!mounted) return;

      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final emailExists = await userProvider.checkEmailExists(trimmedEmail);

      if (mounted && trimmedEmail == _emailController.text.trim()) {
        setState(() {
          _isCheckingEmail = false;
          _isEmailAvailable = !emailExists;
          _lastCheckedEmail = trimmedEmail;
        });
      }
    });
  }

  // Pick and crop image (front or back)
  Future<void> _pickAndCropImage({required bool isFront}) async {
    try {
      final picker = ImagePicker();
      final image = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1200,
        maxHeight: 1200,
      );

      if (image == null || !mounted) return;

      // Validate that the image file exists and is accessible
      try {
        final file = File(image.path);
        if (!file.existsSync()) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Selected image file not found. Please try again.',
                ),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }
      } catch (fileError) {
        debugPrint('Error checking image file: $fileError');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Error accessing image file. Please try again.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // Try to crop the image, but fall back to original if cropping fails
      XFile? finalImage;
      try {
        final croppedFile = await ImageCropper().cropImage(
          sourcePath: image.path,
          aspectRatio: const CropAspectRatio(ratioX: 1.0, ratioY: 1.0),
          uiSettings: [
            AndroidUiSettings(
              toolbarTitle: 'Crop ID Image',
              toolbarColor: const Color(0xFF1E88E5),
              toolbarWidgetColor: Colors.white,
              initAspectRatio: CropAspectRatioPreset.square,
              lockAspectRatio: true,
            ),
            IOSUiSettings(title: 'Crop ID Image', aspectRatioLockEnabled: true),
          ],
        );

        if (croppedFile != null) {
          // Verify cropped file exists
          try {
            final croppedFileCheck = File(croppedFile.path);
            if (croppedFileCheck.existsSync()) {
              finalImage = XFile(croppedFile.path);
            } else {
              debugPrint('Cropped file does not exist, using original');
              finalImage = image;
            }
          } catch (e) {
            debugPrint('Error verifying cropped file: $e');
            finalImage = image;
          }
        } else {
          // User cancelled cropping, use original
          finalImage = image;
        }
      } catch (cropError) {
        debugPrint(
          'Image cropping not available, using original image: $cropError',
        );
        // Fall back to original image if cropping fails
        finalImage = image;

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Using original image. Please restart the app to enable image cropping.',
              ),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 3),
            ),
          );
        }
      }

      if (mounted) {
        setState(() {
          if (isFront) {
            _pickedImageFront = finalImage!;
          } else {
            _pickedImageBack = finalImage!;
          }
        });
      }
    } catch (e, stackTrace) {
      debugPrint('Error picking image: $e');
      debugPrint('Stack trace: $stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error selecting image: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (!_termsAccepted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please accept the Terms of Service to continue'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (!_consentGiven) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please accept the Privacy Policy to continue'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (_barangayIdType == null || _barangayIdType!.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please select an ID type')));
      return;
    }

    // Require at least front image, back is optional but recommended
    if (_pickedImageFront == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please upload at least the front of your ID. Back side is recommended if your ID has information on both sides.',
          ),
        ),
      );
      return;
    }

    // Validate image sizes (< 5 MB each)
    try {
      final int frontBytes = await _pickedImageFront!.length();
      const int maxBytes = 5 * 1024 * 1024;
      if (frontBytes > maxBytes) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Front image too large. Max size is 5 MB per image.'),
          ),
        );
        return;
      }

      if (_pickedImageBack != null) {
        final int backBytes = await _pickedImageBack!.length();
        if (backBytes > maxBytes) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Back image too large. Max size is 5 MB per image.',
              ),
            ),
          );
          return;
        }
      }
    } catch (_) {}

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final userProvider = Provider.of<UserProvider>(context, listen: false);

    try {
      print('Starting registration process...');

      // Check for duplicate email in Firestore before attempting registration
      final email = _emailController.text.trim();
      final emailExists = await userProvider.checkEmailExists(email);
      if (emailExists) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'An account with this email already exists. Please use a different email or try logging in.',
              ),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 5),
            ),
          );
        }
        return;
      }

      // Check for duplicate account by name and address
      // This prevents the same person from creating multiple accounts
      print('🔍 Checking for duplicate account...');
      print('   First Name: ${_firstNameController.text.trim()}');
      print('   Last Name: ${_lastNameController.text.trim()}');
      print('   Street: ${_streetController.text.trim()}');
      print('   Barangay: ${_selectedBarangay ?? ''}');
      print('   City: ${_cityController.text.trim()}');

      final duplicateExists = await userProvider
          .checkUserExistsByNameAndAddress(
            firstName: _firstNameController.text.trim(),
            lastName: _lastNameController.text.trim(),
            street: _streetController.text.trim(),
            barangay: _selectedBarangay ?? '',
            city: _cityController.text.trim(),
          );

      print('🔍 Duplicate check result: $duplicateExists');

      if (duplicateExists) {
        print('❌ Registration blocked: Duplicate account found');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'An account with this name and address already exists. Each person can only have one account. If you already have an account, please log in instead.',
              ),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 6),
            ),
          );
        }
        return;
      }

      print('✅ No duplicate found, proceeding with registration...');

      // Additional diagnostic: Check if there are any users with similar data
      // This helps debug why the duplicate check might not be working
      try {
        final allUsers = await userProvider.findPotentialDuplicates(
          firstName: _firstNameController.text.trim(),
          lastName: _lastNameController.text.trim(),
          street: _streetController.text.trim(),
          barangay: _selectedBarangay ?? '',
          city: _cityController.text.trim(),
        );
        if (allUsers.isNotEmpty) {
          print(
            '⚠️ WARNING: Found ${allUsers.length} potential duplicate(s) but exact match check returned false!',
          );
          print('   This might indicate a data normalization issue.');
        }
      } catch (e) {
        print('⚠️ Could not check for potential duplicates: $e');
      }

      String? imageUrlFront;
      String? imageUrlBack;

      // Try to upload front image first (required)
      try {
        print('Starting front image upload...');
        setState(() {
          _uploadingImage = true;
        });

        final userHint = _emailController.text.trim().isEmpty
            ? 'anonymous'
            : _emailController.text.trim().replaceAll('/', '_');

        imageUrlFront = await userProvider.uploadIdImage(
          _pickedImageFront!,
          userHint,
          isFront: true,
        );
        print('Front image upload successful: $imageUrlFront');

        // Upload back image if provided (optional)
        if (_pickedImageBack != null) {
          try {
            print('Starting back image upload...');
            imageUrlBack = await userProvider.uploadIdImage(
              _pickedImageBack!,
              userHint,
              isFront: false,
            );
            print('Back image upload successful: $imageUrlBack');
          } catch (e) {
            print('Back image upload failed (non-critical): $e');
            // Don't fail registration if back image fails
            imageUrlBack = null;
          }
        }
      } catch (e) {
        print('Front image upload failed: $e');
        // Continue with registration even if image upload fails
        imageUrlFront = 'pending_upload';
      } finally {
        setState(() {
          _uploadingImage = false;
        });
      }

      // Create Firebase Auth user
      final authSuccess = await authProvider.registerWithEmail(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      if (!authSuccess) {
        throw Exception(authProvider.errorMessage ?? 'Registration failed');
      }

      final uid = authProvider.user!.uid;
      print('Auth user created with UID: $uid');

      // Create user profile
      final profileSuccess = await userProvider.createUserProfile(
        uid: uid,
        firstName: _firstNameController.text.trim(),
        middleInitial: _middleInitialController.text.trim(),
        lastName: _lastNameController.text.trim(),
        email: _emailController.text.trim(),
        province: _provinceController.text.trim(),
        city: _cityController.text.trim(),
        barangay: _selectedBarangay ?? '',
        street: _streetController.text.trim(),
        role: _role,
        barangayIdType: _barangayIdType!,
        barangayIdUrl: imageUrlFront ?? 'pending_upload',
        barangayIdUrlBack: imageUrlBack,
      );

      if (!profileSuccess) {
        throw Exception(userProvider.errorMessage ?? 'Profile creation failed');
      }

      // Create activity log for user registration
      try {
        final firestoreService = FirestoreService();
        await firestoreService.createActivityLog(
          category: 'user',
          action: 'user_registered',
          actorId: uid,
          actorName:
              '${_firstNameController.text.trim()} ${_lastNameController.text.trim()}'
                  .trim(),
          description: 'New user registered on the platform',
          metadata: {
            'email': _emailController.text.trim(),
            'method': 'email',
            'province': _provinceController.text.trim(),
            'city': _cityController.text.trim(),
            'barangay': _selectedBarangay ?? '',
            'role': _role,
          },
          severity: 'info',
        );
      } catch (e) {
        // Don't fail registration if logging fails
        debugPrint('Error creating activity log for registration: $e');
      }

      // Send OTP email (via EmailJS) and navigate to verification screen
      if (mounted) {
        // Trigger success animation
        _successController.forward();

        // Wait for animation to play before navigating
        await Future.delayed(const Duration(milliseconds: 800));

        bool emailSent = false;

        try {
          // Build a friendly display name for the OTP email
          String userName =
              '${_firstNameController.text.trim()} ${_lastNameController.text.trim()}'
                  .trim();
          if (userName.isEmpty) {
            userName = _emailController.text.trim().split('@').first;
          }

          // Directly create OTP + send email via VerificationService
          await _verificationService.createVerificationOTP(
            userId: uid,
            email: _emailController.text.trim(),
            userName: userName,
          );
          emailSent = true;
        } catch (e) {
          debugPrint('Registration: Failed to send OTP verification email: $e');
        }

        // Navigate to verification screen
        Navigator.pushReplacementNamed(context, '/verify-email');

        // Show appropriate message based on email sending result
        if (!emailSent) {
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text(
                    'Account created, but verification email failed to send. '
                    'Please use "Resend code" on the verification screen.',
                  ),
                  backgroundColor: Colors.orange,
                  duration: const Duration(seconds: 6),
                  action: SnackBarAction(
                    label: 'OK',
                    textColor: Colors.white,
                    onPressed: () {},
                  ),
                ),
              );
            }
          });
        }
      }
    } catch (e) {
      print('Registration error: $e');
      if (mounted) {
        String errorMessage = 'Failed to register: $e';

        // Provide more specific error messages
        if (e.toString().contains('configuration-not-found')) {
          errorMessage =
              'Firebase Authentication not configured. Please check Firebase Console.';
        } else if (e.toString().contains('email-already-in-use')) {
          errorMessage = 'An account already exists with this email.';
        } else if (e.toString().contains('weak-password')) {
          errorMessage =
              'Password is too weak. Please use at least 6 characters.';
        } else if (e.toString().contains('invalid-email')) {
          errorMessage = 'Please enter a valid email address.';
        } else if (e.toString().contains('network') ||
            e.toString().contains('network-request-failed')) {
          errorMessage =
              'Network error. Please check your internet connection.';
        } else if (e.toString().contains('too-many-requests')) {
          errorMessage = 'Too many requests. Please try again later.';
        } else if (e.toString().contains('operation-not-allowed')) {
          errorMessage =
              'Email/password sign-in is disabled. Please contact support.';
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      // Error handling is done in the catch block above
    }
  }

  @override
  Widget build(BuildContext context) {
    const primaryStart = Color(0xFF1E88E5);
    const primaryEnd = Color(0xFF42A5F5);

    return Consumer2<AuthProvider, UserProvider>(
      builder: (context, authProvider, userProvider, child) {
        return Scaffold(
          body: Stack(
            children: [
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [primaryStart, primaryEnd],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: SafeArea(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      // Calculate responsive values
                      final isDesktop = constraints.maxWidth > 600;
                      final isTablet =
                          constraints.maxWidth > 400 &&
                          constraints.maxWidth <= 600;
                      final screenPadding = isDesktop
                          ? 40.0
                          : (isTablet ? 30.0 : 20.0);
                      final maxWidth = isDesktop ? 800.0 : constraints.maxWidth;
                      final titleFontSize = isDesktop
                          ? 28.0
                          : (isTablet ? 24.0 : 20.0);
                      final subtitleFontSize = isDesktop
                          ? 16.0
                          : (isTablet ? 15.0 : 14.0);
                      final iconSize = isDesktop
                          ? 32.0
                          : (isTablet ? 28.0 : 24.0);
                      final cardPadding = isDesktop
                          ? const EdgeInsets.fromLTRB(32, 24, 32, 32)
                          : (isTablet
                                ? const EdgeInsets.fromLTRB(24, 20, 24, 24)
                                : const EdgeInsets.fromLTRB(16, 18, 16, 20));

                      return SingleChildScrollView(
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
                                const SizedBox(height: 8),
                                // Animated Header
                                FadeTransition(
                                  opacity: _fadeAnimation,
                                  child: SlideTransition(
                                    position: _slideAnimation,
                                    child: ScaleTransition(
                                      scale: _scaleAnimation,
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          CircleAvatar(
                                            radius: iconSize,
                                            backgroundColor: Colors.white,
                                            child: Icon(
                                              Icons.person_add_alt_1,
                                              color: primaryStart,
                                              size: iconSize * 1.1,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  'Create your account',
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                    fontSize: titleFontSize,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  'Tell us about you to get started',
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
                                ),
                                const SizedBox(height: 16),
                                // Form Card
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
                                    child: Card(
                                      elevation: 6,
                                      color: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16),
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
                                              _buildAnimatedField(
                                                index: 0,
                                                child: _buildTextField(
                                                  controller:
                                                      _firstNameController,
                                                  label: 'First Name',
                                                  icon: Icons.badge_outlined,
                                                  validator: (v) =>
                                                      (v == null ||
                                                          v.trim().isEmpty)
                                                      ? 'Required'
                                                      : null,
                                                ),
                                              ),
                                              _buildAnimatedField(
                                                index: 1,
                                                child: _buildTextField(
                                                  controller:
                                                      _middleInitialController,
                                                  label: 'Middle Initial',
                                                  icon: Icons
                                                      .text_fields_outlined,
                                                ),
                                              ),
                                              _buildAnimatedField(
                                                index: 2,
                                                child: _buildTextField(
                                                  controller:
                                                      _lastNameController,
                                                  label: 'Last Name',
                                                  icon: Icons.badge_outlined,
                                                  validator: (v) =>
                                                      (v == null ||
                                                          v.trim().isEmpty)
                                                      ? 'Required'
                                                      : null,
                                                ),
                                              ),
                                              _buildAnimatedField(
                                                index: 3,
                                                child: _buildEmailField(),
                                              ),
                                              _buildAnimatedField(
                                                index: 4,
                                                child: _buildPasswordField(
                                                  controller:
                                                      _passwordController,
                                                  label: 'Password',
                                                  icon: Icons.lock,
                                                  onStrengthChanged: (s) =>
                                                      setState(() {
                                                        _passwordStrength = s;
                                                      }),
                                                ),
                                              ),
                                              _buildAnimatedField(
                                                index: 5,
                                                child: _PasswordStrengthBar(
                                                  strength: _passwordStrength,
                                                ),
                                              ),
                                              _buildAnimatedField(
                                                index: 6,
                                                child: _buildPasswordField(
                                                  controller:
                                                      _confirmPasswordController,
                                                  label: 'Confirm Password',
                                                  icon:
                                                      Icons.lock_clock_outlined,
                                                  validator: (v) {
                                                    if (v !=
                                                        _passwordController
                                                            .text) {
                                                      return 'Passwords do not match';
                                                    }
                                                    return null;
                                                  },
                                                ),
                                              ),
                                              _buildTextField(
                                                controller: _provinceController,
                                                label: 'Province',
                                                icon: Icons.map_outlined,
                                                validator: (v) =>
                                                    (v == null ||
                                                        v.trim().isEmpty)
                                                    ? 'Required'
                                                    : null,
                                                readOnly: true,
                                              ),
                                              _buildTextField(
                                                controller: _cityController,
                                                label: 'City',
                                                icon: Icons
                                                    .location_city_outlined,
                                                validator: (v) =>
                                                    (v == null ||
                                                        v.trim().isEmpty)
                                                    ? 'Required'
                                                    : null,
                                                readOnly: true,
                                              ),
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                  bottom: 12,
                                                ),
                                                child: DropdownButtonFormField<String>(
                                                  value: _selectedBarangay,
                                                  decoration:
                                                      _inputDecoration(
                                                        'Barangay',
                                                        Icons
                                                            .home_work_outlined,
                                                      ).copyWith(
                                                        hintText:
                                                            _barangays.isEmpty
                                                            ? 'Loading barangays...'
                                                            : 'Select barangay',
                                                      ),
                                                  hint: Text(
                                                    _barangays.isEmpty
                                                        ? 'Loading barangays...'
                                                        : 'Select barangay',
                                                  ),
                                                  items: _barangays.map((
                                                    barangay,
                                                  ) {
                                                    return DropdownMenuItem<
                                                      String
                                                    >(
                                                      value: barangay,
                                                      child: Text(barangay),
                                                    );
                                                  }).toList(),
                                                  onChanged: _barangays.isEmpty
                                                      ? null
                                                      : (value) {
                                                          setState(() {
                                                            _selectedBarangay =
                                                                value;
                                                          });
                                                        },
                                                  validator: (v) =>
                                                      (v == null || v.isEmpty)
                                                      ? 'Required'
                                                      : null,
                                                ),
                                              ),
                                              _buildTextField(
                                                controller: _streetController,
                                                label: 'Street',
                                                icon: Icons.streetview_outlined,
                                                validator: (v) =>
                                                    (v == null ||
                                                        v.trim().isEmpty)
                                                    ? 'Required'
                                                    : null,
                                              ),
                                              const SizedBox(height: 4),
                                              DropdownButtonFormField<String>(
                                                initialValue: _role,
                                                decoration:
                                                    _inputDecoration(
                                                      'Primary Role Preference',
                                                      Icons.person_outline,
                                                    ).copyWith(
                                                      helperText:
                                                          'Note: You can borrow AND lend regardless of selection',
                                                    ),
                                                items: const [
                                                  DropdownMenuItem(
                                                    value: 'both',
                                                    child: Text(
                                                      'Both (Recommended)',
                                                    ),
                                                  ),
                                                  DropdownMenuItem(
                                                    value: 'borrower',
                                                    child: Text(
                                                      'Borrower Only',
                                                    ),
                                                  ),
                                                  DropdownMenuItem(
                                                    value: 'lender',
                                                    child: Text('Lender Only'),
                                                  ),
                                                ],
                                                onChanged: (val) => setState(
                                                  () => _role = val ?? 'both',
                                                ),
                                              ),
                                              const SizedBox(height: 12),
                                              DropdownButtonFormField<String>(
                                                initialValue: _barangayIdType,
                                                decoration: _inputDecoration(
                                                  'Barangay ID Type',
                                                  Icons.credit_card_outlined,
                                                ),
                                                items: const [
                                                  DropdownMenuItem(
                                                    value: 'Voter\'s ID',
                                                    child: Text("Voter's ID"),
                                                  ),
                                                  DropdownMenuItem(
                                                    value: 'National ID',
                                                    child: Text('National ID'),
                                                  ),
                                                  DropdownMenuItem(
                                                    value: 'Driver\'s License',
                                                    child: Text(
                                                      "Driver's License",
                                                    ),
                                                  ),
                                                ],
                                                onChanged: (val) => setState(
                                                  () => _barangayIdType = val,
                                                ),
                                                validator: (v) =>
                                                    (v == null || v.isEmpty)
                                                    ? 'Required'
                                                    : null,
                                              ),
                                              const SizedBox(height: 16),
                                              // ID Image Upload Section
                                              Text(
                                                'ID Verification Photos',
                                                style: TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w600,
                                                  color: Colors.grey[800],
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                'Upload front of ID (required). Back side is recommended if your ID has information on both sides.',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey[600],
                                                ),
                                              ),
                                              const SizedBox(height: 12),
                                              // Front ID Upload
                                              _buildIdUploadSection(
                                                label: 'Front of ID',
                                                isRequired: true,
                                                isFront: true,
                                                image: _pickedImageFront,
                                              ),
                                              const SizedBox(height: 12),
                                              // Back ID Upload
                                              _buildIdUploadSection(
                                                label: 'Back of ID (Optional)',
                                                isRequired: false,
                                                isFront: false,
                                                image: _pickedImageBack,
                                              ),
                                              const SizedBox(height: 16),
                                              // Terms of Service Checkbox
                                              Container(
                                                padding: const EdgeInsets.all(
                                                  12,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: Colors.grey[50],
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                  border: Border.all(
                                                    color: Colors.grey[300]!,
                                                    width: 1,
                                                  ),
                                                ),
                                                child: Row(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Checkbox(
                                                      value: _termsAccepted,
                                                      onChanged: (v) {
                                                        setState(() {
                                                          _termsAccepted =
                                                              v ?? false;
                                                        });
                                                      },
                                                      activeColor: const Color(
                                                        0xFF1E88E5,
                                                      ),
                                                    ),
                                                    Expanded(
                                                      child: Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        children: [
                                                          Text(
                                                            'Terms of Service',
                                                            style: TextStyle(
                                                              fontSize: 13,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w600,
                                                              color: Colors
                                                                  .grey[800],
                                                            ),
                                                          ),
                                                          const SizedBox(
                                                            height: 4,
                                                          ),
                                                          Text(
                                                            'I agree to the Terms of Service and agree to be bound by them.',
                                                            style: TextStyle(
                                                              fontSize: 12,
                                                              color: Colors
                                                                  .grey[600],
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              const SizedBox(height: 12),
                                              // Privacy Policy Checkbox
                                              Container(
                                                padding: const EdgeInsets.all(
                                                  12,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: Colors.grey[50],
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                  border: Border.all(
                                                    color: Colors.grey[300]!,
                                                    width: 1,
                                                  ),
                                                ),
                                                child: Row(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Checkbox(
                                                      value: _consentGiven,
                                                      onChanged: (v) {
                                                        setState(() {
                                                          _consentGiven =
                                                              v ?? false;
                                                        });
                                                      },
                                                      activeColor: const Color(
                                                        0xFF1E88E5,
                                                      ),
                                                    ),
                                                    Expanded(
                                                      child: Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        children: [
                                                          Text(
                                                            'Privacy Policy',
                                                            style: TextStyle(
                                                              fontSize: 13,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w600,
                                                              color: Colors
                                                                  .grey[800],
                                                            ),
                                                          ),
                                                          const SizedBox(
                                                            height: 4,
                                                          ),
                                                          Text(
                                                            'I agree to the Privacy Policy and consent to processing my ID for verification.',
                                                            style: TextStyle(
                                                              fontSize: 12,
                                                              color: Colors
                                                                  .grey[600],
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              const SizedBox(height: 12),
                                              const SizedBox(height: 8),
                                              const SizedBox(height: 20),
                                              SizedBox(
                                                height: 52,
                                                child: ElevatedButton(
                                                  onPressed:
                                                      (authProvider.isLoading ||
                                                          userProvider
                                                              .isLoading ||
                                                          _uploadingImage ||
                                                          !_termsAccepted ||
                                                          !_consentGiven)
                                                      ? null
                                                      : _submit,
                                                  style: ElevatedButton.styleFrom(
                                                    shape: RoundedRectangleBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            12,
                                                          ),
                                                    ),
                                                    backgroundColor:
                                                        primaryStart,
                                                    foregroundColor:
                                                        Colors.white,
                                                  ),
                                                  child:
                                                      (authProvider.isLoading ||
                                                          userProvider
                                                              .isLoading ||
                                                          _uploadingImage)
                                                      ? Row(
                                                          mainAxisAlignment:
                                                              MainAxisAlignment
                                                                  .center,
                                                          children: [
                                                            const SizedBox(
                                                              height: 20,
                                                              width: 20,
                                                              child:
                                                                  CircularProgressIndicator(
                                                                    strokeWidth:
                                                                        2,
                                                                    color: Colors
                                                                        .white,
                                                                  ),
                                                            ),
                                                            const SizedBox(
                                                              width: 8,
                                                            ),
                                                            Text(
                                                              _uploadingImage
                                                                  ? 'Uploading image...'
                                                                  : 'Creating account...',
                                                              style: const TextStyle(
                                                                fontSize: 14,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w500,
                                                              ),
                                                            ),
                                                          ],
                                                        )
                                                      : const Text(
                                                          'Create Account',
                                                          style: TextStyle(
                                                            fontSize: 16,
                                                            fontWeight:
                                                                FontWeight.w600,
                                                          ),
                                                        ),
                                                ),
                                              ),
                                              const SizedBox(height: 16),
                                              Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: [
                                                  const Text(
                                                    "Already have an account? ",
                                                    style: TextStyle(
                                                      color: Colors.grey,
                                                    ),
                                                  ),
                                                  TextButton(
                                                    onPressed: () {
                                                      Navigator.pushNamed(
                                                        context,
                                                        '/login',
                                                      );
                                                    },
                                                    child: const Text(
                                                      'Sign In',
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
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 24),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              // Success Animation Overlay
              AnimatedBuilder(
                animation: _successController,
                builder: (context, child) {
                  if (_successController.value == 0) {
                    return const SizedBox.shrink();
                  }
                  return Container(
                    color: Colors.black.withOpacity(
                      0.7 * _successController.value,
                    ),
                    child: Center(
                      child: Transform.scale(
                        scale: _successScaleAnimation.value,
                        child: Transform.rotate(
                          angle: _successRotationAnimation.value * 0.1,
                          child: Container(
                            padding: const EdgeInsets.all(32),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.3),
                                  blurRadius: 20,
                                  spreadRadius: 5,
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.check_circle,
                              size: 80,
                              color: Colors.green,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  // Animated field wrapper for staggered animations
  Widget _buildAnimatedField({required int index, required Widget child}) {
    final delay = index * 0.05; // 50ms delay between each field
    final animation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _fadeController,
        curve: Interval(
          delay.clamp(0.0, 0.8),
          (delay + 0.2).clamp(0.0, 1.0),
          curve: Curves.easeOut,
        ),
      ),
    );

    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero)
            .animate(
              CurvedAnimation(
                parent: _slideController,
                curve: Interval(
                  delay.clamp(0.0, 0.8),
                  (delay + 0.2).clamp(0.0, 1.0),
                  curve: Curves.easeOut,
                ),
              ),
            ),
        child: child,
      ),
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      filled: true,
      fillColor: const Color(0xFFF7F9FC),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE3E7ED)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF1E88E5)),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.redAccent),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.redAccent),
      ),
      contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
    );
  }

  // Email field with real-time availability check
  Widget _buildEmailField() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: _emailController,
        decoration: _inputDecoration('Email', Icons.alternate_email).copyWith(
          suffixIcon: _isCheckingEmail
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: Padding(
                    padding: EdgeInsets.all(12.0),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Color(0xFF1E88E5),
                      ),
                    ),
                  ),
                )
              : _isEmailAvailable == null
              ? null
              : Icon(
                  _isEmailAvailable == true ? Icons.check_circle : Icons.cancel,
                  color: _isEmailAvailable == true ? Colors.green : Colors.red,
                ),
          helperText: _isEmailAvailable == null
              ? null
              : _isEmailAvailable == true
              ? 'Email is available'
              : 'Email is already taken',
          helperMaxLines: 2,
          helperStyle: TextStyle(
            color: _isEmailAvailable == null
                ? null
                : _isEmailAvailable == true
                ? Colors.green
                : Colors.red,
          ),
        ),
        keyboardType: TextInputType.emailAddress,
        textInputAction: TextInputAction.next,
        onChanged: _checkEmailAvailability,
        validator: (v) {
          final value = v?.trim() ?? '';
          if (value.isEmpty) return 'Required';
          final emailRegex = RegExp(
            r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{3,}$',
          );
          if (!emailRegex.hasMatch(value)) {
            return 'Invalid email';
          }
          if (_isEmailAvailable == false) {
            return 'Email is already taken';
          }
          return null;
        },
      ),
    );
  }

  // ID Upload Section Widget
  Widget _buildIdUploadSection({
    required String label,
    required bool isRequired,
    required bool isFront,
    XFile? image,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.grey[800],
              ),
            ),
            if (isRequired) ...[
              const SizedBox(width: 4),
              const Text(
                '*',
                style: TextStyle(color: Colors.red, fontSize: 14),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        if (image != null)
          _buildImagePreview(image: image, isFront: isFront)
        else
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF7F9FC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isRequired ? Colors.grey[300]! : Colors.grey[200]!,
                width: 1.5,
              ),
            ),
            child: InkWell(
              onTap: () => _pickAndCropImage(isFront: isFront),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Icon(
                      Icons.add_photo_alternate_outlined,
                      size: 48,
                      color: Colors.grey[400],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      isRequired
                          ? 'Tap to upload $label'
                          : 'Tap to upload $label (optional)',
                      style: TextStyle(color: Colors.grey[600], fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  // Image preview widget
  Widget _buildImagePreview({required XFile image, required bool isFront}) {
    // Safely get the image file
    File? imageFile;
    try {
      final path = image.path;
      if (path.isNotEmpty) {
        final file = File(path);
        if (file.existsSync()) {
          imageFile = file;
        }
      }
    } catch (e) {
      debugPrint('Error accessing image file: $e');
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE3E7ED), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Image preview
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            child: imageFile != null
                ? Image.file(
                    imageFile,
                    height: 200,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      debugPrint('Error loading image: $error');
                      return _buildImageErrorPlaceholder();
                    },
                  )
                : _buildImageErrorPlaceholder(),
          ),
          // Image info and actions
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const Icon(Icons.image, color: Color(0xFF1E88E5), size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        image.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w500,
                          fontSize: 14,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        imageFile != null
                            ? '${isFront ? "Front" : "Back"} ID ready'
                            : 'Image selected',
                        style: TextStyle(color: Colors.grey[600], fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.edit, size: 20),
                  color: const Color(0xFF1E88E5),
                  tooltip: 'Edit/Crop image',
                  onPressed: () => _pickAndCropImage(isFront: isFront),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20),
                  color: Colors.red,
                  tooltip: 'Remove image',
                  onPressed: () {
                    setState(() {
                      if (isFront) {
                        _pickedImageFront = null;
                      } else {
                        _pickedImageBack = null;
                      }
                    });
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageErrorPlaceholder() {
    return Container(
      height: 200,
      color: Colors.grey[200],
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, color: Colors.grey, size: 48),
            SizedBox(height: 8),
            Text(
              'Unable to load image',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    bool readOnly = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        decoration: _inputDecoration(label, icon),
        textInputAction: TextInputAction.next,
        validator: validator,
        keyboardType: keyboardType,
        readOnly: readOnly,
      ),
    );
  }

  Widget _buildPasswordField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? Function(String?)? validator,
    void Function(double)? onStrengthChanged,
  }) {
    bool obscure = true;
    return StatefulBuilder(
      builder: (context, setState) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TextFormField(
            controller: controller,
            obscureText: obscure,
            decoration: _inputDecoration(label, icon).copyWith(
              suffixIcon: IconButton(
                icon: Icon(
                  obscure ? Icons.visibility_off : Icons.visibility,
                  color: Colors.grey,
                ),
                onPressed: () => setState(() => obscure = !obscure),
              ),
            ),
            onChanged: (v) {
              if (onStrengthChanged != null) {
                onStrengthChanged(_estimatePasswordStrength(v));
              }
            },
            validator: validator ?? _passwordValidator,
          ),
        );
      },
    );
  }

  String? _passwordValidator(String? v) {
    final value = v ?? '';
    if (value.isEmpty) return 'Required';
    if (value.length < 8) return 'Use at least 8 characters';
    final hasUpper = RegExp(r'[A-Z]').hasMatch(value);
    final hasLower = RegExp(r'[a-z]').hasMatch(value);
    final hasDigit = RegExp(r'\d').hasMatch(value);
    final hasSpecial = RegExp(r'[!@#\$%^&*(),.?":{}|<>]').hasMatch(value);
    if (!(hasUpper && hasLower && hasDigit && hasSpecial)) {
      return 'Use upper, lower, number, and special character';
    }
    return null;
  }

  double _estimatePasswordStrength(String value) {
    if (value.isEmpty) return 0.0;
    int score = 0;
    if (value.length >= 8) score++;
    if (RegExp(r'[A-Z]').hasMatch(value)) score++;
    if (RegExp(r'[a-z]').hasMatch(value)) score++;
    if (RegExp(r'\d').hasMatch(value)) score++;
    if (RegExp(r'[!@#\$%^&*(),.?":{}|<>]').hasMatch(value)) score++;
    return (score / 5).clamp(0.0, 1.0);
  }

  // Visual indicator for password strength
  Widget _PasswordStrengthBar({required double strength}) {
    Color color;
    if (strength < 0.4) {
      color = Colors.redAccent;
    } else if (strength < 0.7) {
      color = Colors.orange;
    } else {
      color = const Color(0xFF1E88E5);
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: LinearProgressIndicator(
          minHeight: 6,
          value: strength,
          color: color,
          backgroundColor: const Color(0xFFE3E7ED),
        ),
      ),
    );
  }
}
