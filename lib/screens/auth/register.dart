import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import '../../providers/auth_provider.dart';
import '../../providers/user_provider.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
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
  XFile? _pickedImage;
  bool _consentGiven = false;
  double _passwordStrength = 0.0;
  List<String> _barangays = [];
  String? _selectedBarangay;

  @override
  void initState() {
    super.initState();
    _loadBarangays();
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

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (!_consentGiven) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please accept the privacy policy to continue'),
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

    if (_pickedImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please upload a photo of your ID')),
      );
      return;
    }

    // Validate image size (< 5 MB)
    try {
      final int bytes = await _pickedImage!.length();
      const int maxBytes = 5 * 1024 * 1024;
      if (bytes > maxBytes) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Image too large. Max size is 5 MB.')),
        );
        return;
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

      String? imageUrl;

      // Try to upload image first, but don't fail registration if it fails
      try {
        print('Starting image upload...');
        setState(() {
          _uploadingImage = true;
        });

        imageUrl = await userProvider.uploadIdImage(
          _pickedImage!,
          _emailController.text.trim().isEmpty
              ? 'anonymous'
              : _emailController.text.trim().replaceAll('/', '_'),
        );
        print('Image upload successful: $imageUrl');
      } catch (e) {
        print('Image upload failed: $e');
        // Continue with registration even if image upload fails
        imageUrl = 'pending_upload';
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
        barangayIdUrl: imageUrl ?? 'pending_upload',
      );

      if (!profileSuccess) {
        throw Exception(userProvider.errorMessage ?? 'Profile creation failed');
      }

      // Send email verification and navigate to verification screen
      if (mounted) {
        bool emailSent = false;

        try {
          await Provider.of<AuthProvider>(
            context,
            listen: false,
          ).sendEmailVerification();
          emailSent = true;
        } catch (e) {
          debugPrint('Registration: Failed to send verification email: $e');
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
          body: Container(
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
                      constraints.maxWidth > 400 && constraints.maxWidth <= 600;
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
                  final iconSize = isDesktop ? 32.0 : (isTablet ? 28.0 : 24.0);
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
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
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
                            const SizedBox(height: 16),
                            Card(
                              elevation: 6,
                              color: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Padding(
                                padding: cardPadding,
                                child: Form(
                                  key: _formKey,
                                  autovalidateMode:
                                      AutovalidateMode.onUserInteraction,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      _buildTextField(
                                        controller: _firstNameController,
                                        label: 'First Name',
                                        icon: Icons.badge_outlined,
                                        validator: (v) =>
                                            (v == null || v.trim().isEmpty)
                                            ? 'Required'
                                            : null,
                                      ),
                                      _buildTextField(
                                        controller: _middleInitialController,
                                        label: 'Middle Initial',
                                        icon: Icons.text_fields_outlined,
                                      ),
                                      _buildTextField(
                                        controller: _lastNameController,
                                        label: 'Last Name',
                                        icon: Icons.badge_outlined,
                                        validator: (v) =>
                                            (v == null || v.trim().isEmpty)
                                            ? 'Required'
                                            : null,
                                      ),
                                      _buildTextField(
                                        controller: _emailController,
                                        label: 'Email',
                                        icon: Icons.alternate_email,
                                        keyboardType:
                                            TextInputType.emailAddress,
                                        validator: (v) {
                                          final value = v?.trim() ?? '';
                                          if (value.isEmpty) return 'Required';
                                          final emailRegex = RegExp(
                                            r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{3,}$',
                                          );
                                          return emailRegex.hasMatch(value)
                                              ? null
                                              : 'Invalid email';
                                        },
                                      ),
                                      _buildPasswordField(
                                        controller: _passwordController,
                                        label: 'Password',
                                        icon: Icons.lock,
                                        onStrengthChanged: (s) => setState(() {
                                          _passwordStrength = s;
                                        }),
                                      ),
                                      _PasswordStrengthBar(
                                        strength: _passwordStrength,
                                      ),
                                      _buildPasswordField(
                                        controller: _confirmPasswordController,
                                        label: 'Confirm Password',
                                        icon: Icons.lock_clock_outlined,
                                        validator: (v) {
                                          if (v != _passwordController.text) {
                                            return 'Passwords do not match';
                                          }
                                          return null;
                                        },
                                      ),
                                      _buildTextField(
                                        controller: _provinceController,
                                        label: 'Province',
                                        icon: Icons.map_outlined,
                                        validator: (v) =>
                                            (v == null || v.trim().isEmpty)
                                            ? 'Required'
                                            : null,
                                        readOnly: true,
                                      ),
                                      _buildTextField(
                                        controller: _cityController,
                                        label: 'City',
                                        icon: Icons.location_city_outlined,
                                        validator: (v) =>
                                            (v == null || v.trim().isEmpty)
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
                                                Icons.home_work_outlined,
                                              ).copyWith(
                                                hintText: _barangays.isEmpty
                                                    ? 'Loading barangays...'
                                                    : 'Select barangay',
                                              ),
                                          hint: Text(
                                            _barangays.isEmpty
                                                ? 'Loading barangays...'
                                                : 'Select barangay',
                                          ),
                                          items: _barangays.map((barangay) {
                                            return DropdownMenuItem<String>(
                                              value: barangay,
                                              child: Text(barangay),
                                            );
                                          }).toList(),
                                          onChanged: _barangays.isEmpty
                                              ? null
                                              : (value) {
                                                  setState(() {
                                                    _selectedBarangay = value;
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
                                            (v == null || v.trim().isEmpty)
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
                                            child: Text('Both (Recommended)'),
                                          ),
                                          DropdownMenuItem(
                                            value: 'borrower',
                                            child: Text('Borrower Only'),
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
                                        decoration:
                                            _inputDecoration(
                                              'Barangay ID Type',
                                              Icons.credit_card_outlined,
                                            ).copyWith(
                                              suffixIcon: IconButton(
                                                tooltip: _pickedImage == null
                                                    ? 'Upload Barangay ID photo'
                                                    : 'Change Barangay ID photo',
                                                onPressed: () async {
                                                  final picker = ImagePicker();
                                                  final image = await picker.pickImage(
                                                    source: ImageSource.gallery,
                                                    imageQuality:
                                                        85, // Better quality
                                                    maxWidth:
                                                        1200, // Larger max width
                                                    maxHeight:
                                                        1200, // Larger max height
                                                  );
                                                  if (image != null) {
                                                    setState(
                                                      () =>
                                                          _pickedImage = image,
                                                    );
                                                  }
                                                },
                                                icon: Icon(
                                                  _pickedImage == null
                                                      ? Icons.upload
                                                      : Icons
                                                            .check_circle_outline,
                                                  color: _pickedImage == null
                                                      ? Colors.grey
                                                      : primaryStart,
                                                ),
                                              ),
                                              helperText: _pickedImage == null
                                                  ? 'Photo required — tap upload icon'
                                                  : 'Photo attached',
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
                                            child: Text("Driver's License"),
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
                                      const SizedBox(height: 8),
                                      if (_pickedImage != null)
                                        Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFF7F9FC),
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                            border: Border.all(
                                              color: const Color(0xFFE3E7ED),
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              const Icon(
                                                Icons.image,
                                                color: Colors.grey,
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  _pickedImage!.name,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                              const Icon(
                                                Icons.check_circle,
                                                color: Color(0xFF1E88E5),
                                              ),
                                            ],
                                          ),
                                        ),
                                      const SizedBox(height: 12),
                                      Row(
                                        children: [
                                          Checkbox(
                                            value: _consentGiven,
                                            onChanged: (v) {
                                              setState(() {
                                                _consentGiven = v ?? false;
                                              });
                                            },
                                          ),
                                          const Expanded(
                                            child: Text(
                                              'I agree to the Privacy Policy and consent to processing my ID for verification.',
                                              style: TextStyle(fontSize: 12),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      const SizedBox(height: 8),
                                      const SizedBox(height: 20),
                                      SizedBox(
                                        height: 52,
                                        child: ElevatedButton(
                                          onPressed:
                                              (authProvider.isLoading ||
                                                  userProvider.isLoading ||
                                                  _uploadingImage ||
                                                  !_consentGiven)
                                              ? null
                                              : _submit,
                                          style: ElevatedButton.styleFrom(
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            backgroundColor: primaryStart,
                                            foregroundColor: Colors.white,
                                          ),
                                          child:
                                              (authProvider.isLoading ||
                                                  userProvider.isLoading ||
                                                  _uploadingImage)
                                              ? Row(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.center,
                                                  children: [
                                                    const SizedBox(
                                                      height: 20,
                                                      width: 20,
                                                      child:
                                                          CircularProgressIndicator(
                                                            strokeWidth: 2,
                                                            color: Colors.white,
                                                          ),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Text(
                                                      _uploadingImage
                                                          ? 'Uploading image...'
                                                          : 'Creating account...',
                                                      style: const TextStyle(
                                                        fontSize: 14,
                                                        fontWeight:
                                                            FontWeight.w500,
                                                      ),
                                                    ),
                                                  ],
                                                )
                                              : const Text(
                                                  'Create Account',
                                                  style: TextStyle(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.w600,
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
                                                fontWeight: FontWeight.w600,
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
        );
      },
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
