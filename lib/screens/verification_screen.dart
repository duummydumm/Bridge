import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import '../providers/user_provider.dart';
import '../models/user_model.dart';
import '../services/firestore_service.dart';

class VerificationScreen extends StatefulWidget {
  const VerificationScreen({super.key});

  @override
  State<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends State<VerificationScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _middleInitialController =
      TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  final TextEditingController _streetController = TextEditingController();
  final TextEditingController _barangayController = TextEditingController();
  final TextEditingController _cityController = TextEditingController();
  final TextEditingController _provinceController = TextEditingController();

  final ImagePicker _picker = ImagePicker();
  final FirestoreService _firestoreService = FirestoreService();
  XFile? _pickedImage;
  String? _barangayIdType;
  bool _isUploading = false;
  String? _rejectionReason;

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _loadRejectionReason();
  }

  Future<void> _loadRejectionReason() async {
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final user = userProvider.currentUser;
    if (user != null && user.verificationStatus == 'rejected') {
      try {
        final userData = await _firestoreService.getUser(user.uid);
        if (userData != null && mounted) {
          setState(() {
            _rejectionReason = userData['rejectionReason'] as String? ?? '';
          });
        }
      } catch (e) {
        debugPrint('Error loading rejection reason: $e');
      }
    }
  }

  void _loadUserData() {
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final user = userProvider.currentUser;
    if (user != null) {
      _firstNameController.text = user.firstName;
      _middleInitialController.text = user.middleInitial;
      _lastNameController.text = user.lastName;
      _streetController.text = user.street;
      _barangayController.text = user.barangay;
      _cityController.text = user.city;
      _provinceController.text = user.province;
      _barangayIdType = user.barangayIdType;
    }
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _middleInitialController.dispose();
    _lastNameController.dispose();
    _streetController.dispose();
    _barangayController.dispose();
    _cityController.dispose();
    _provinceController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final image = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1200,
        maxHeight: 1200,
      );
      if (image != null) {
        setState(() {
          _pickedImage = image;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error picking image: $e')));
      }
    }
  }

  Future<void> _submitVerification() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_barangayIdType == null || _barangayIdType!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a Barangay ID Type'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final user = userProvider.currentUser;
    if (user == null) return;

    setState(() => _isUploading = true);

    try {
      // Upload ID image if a new one was picked
      String? imageUrl;
      if (_pickedImage != null) {
        imageUrl = await userProvider.uploadIdImage(
          _pickedImage!,
          user.email.replaceAll('/', '_'),
        );
        if (imageUrl == null) {
          throw Exception('Failed to upload ID image');
        }
      }

      // Update user information
      final success = await userProvider.updateUserInformation(
        firstName: _firstNameController.text.trim(),
        middleInitial: _middleInitialController.text.trim(),
        lastName: _lastNameController.text.trim(),
        street: _streetController.text.trim(),
        barangay: _barangayController.text.trim(),
        city: _cityController.text.trim(),
        province: _provinceController.text.trim(),
        barangayIdType: _barangayIdType,
        barangayIdUrl: imageUrl,
      );

      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Verification information updated successfully! Your request has been resubmitted for review.',
            ),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 4),
          ),
        );
        Navigator.of(context).pop();
      } else {
        throw Exception('Failed to update information');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final userProvider = Provider.of<UserProvider>(context);
    final user = userProvider.currentUser;
    final isRejected = user?.verificationStatus == 'rejected';
    final rejectionReason = _rejectionReason ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Account Verification'),
        backgroundColor: const Color(0xFF00897B),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Status Card
              _buildStatusCard(user, isRejected, rejectionReason),
              const SizedBox(height: 24),

              // Instructions
              if (isRejected) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.orange[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange[200]!),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: Colors.orange[700],
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Update Your Information',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.orange[900],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Please review the rejection reason above and update your information accordingly. Once you submit, your verification request will be resubmitted for admin review.',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.orange[800],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],

              // Personal Information Section
              _buildSectionTitle('Personal Information'),
              const SizedBox(height: 12),
              _buildTextField(
                controller: _firstNameController,
                label: 'First Name',
                icon: Icons.person_outline,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              _buildTextField(
                controller: _middleInitialController,
                label: 'Middle Initial',
                icon: Icons.text_fields_outlined,
              ),
              const SizedBox(height: 12),
              _buildTextField(
                controller: _lastNameController,
                label: 'Last Name',
                icon: Icons.person_outline,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 24),

              // Address Section
              _buildSectionTitle('Address'),
              const SizedBox(height: 12),
              _buildTextField(
                controller: _streetController,
                label: 'Street',
                icon: Icons.streetview_outlined,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              _buildTextField(
                controller: _barangayController,
                label: 'Barangay',
                icon: Icons.home_work_outlined,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              _buildTextField(
                controller: _cityController,
                label: 'City',
                icon: Icons.location_city_outlined,
                readOnly: true,
              ),
              const SizedBox(height: 12),
              _buildTextField(
                controller: _provinceController,
                label: 'Province',
                icon: Icons.map_outlined,
                readOnly: true,
              ),
              const SizedBox(height: 24),

              // ID Section
              _buildSectionTitle('Barangay ID'),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _barangayIdType,
                decoration:
                    _inputDecoration(
                      'Barangay ID Type',
                      Icons.credit_card_outlined,
                    ).copyWith(
                      suffixIcon: IconButton(
                        tooltip: _pickedImage == null
                            ? 'Upload Barangay ID photo'
                            : 'Change Barangay ID photo',
                        onPressed: _pickImage,
                        icon: Icon(
                          _pickedImage == null
                              ? Icons.upload
                              : Icons.check_circle_outline,
                          color: _pickedImage == null
                              ? Colors.grey
                              : const Color(0xFF00897B),
                        ),
                      ),
                      helperText: _pickedImage == null
                          ? 'Photo required — tap upload icon'
                          : 'Photo attached',
                    ),
                items: const [
                  DropdownMenuItem(
                    value: "Voter's ID",
                    child: Text("Voter's ID"),
                  ),
                  DropdownMenuItem(
                    value: 'National ID',
                    child: Text('National ID'),
                  ),
                  DropdownMenuItem(
                    value: "Driver's License",
                    child: Text("Driver's License"),
                  ),
                ],
                onChanged: (val) => setState(() => _barangayIdType = val),
                validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              if (_pickedImage != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7F9FC),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE3E7ED)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.image, color: Colors.grey),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _pickedImage!.name,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const Icon(Icons.check_circle, color: Color(0xFF1E88E5)),
                    ],
                  ),
                ),
              if (user?.barangayIdUrl != null && _pickedImage == null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.image, color: Colors.grey),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Current ID uploaded',
                          style: TextStyle(color: Colors.grey[700]),
                        ),
                      ),
                      Text(
                        'Tap upload to change',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 32),

              // Submit Button
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: (_isUploading || userProvider.isLoading)
                      ? null
                      : _submitVerification,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00897B),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isUploading || userProvider.isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        )
                      : Text(
                          isRejected
                              ? 'Resubmit for Verification'
                              : 'Update & Submit',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusCard(
    UserModel? user,
    bool isRejected,
    String rejectionReason,
  ) {
    final isVerified = user?.isVerified ?? false;

    Color statusColor;
    IconData statusIcon;
    String statusText;

    if (isVerified) {
      statusColor = Colors.green;
      statusIcon = Icons.verified;
      statusText = 'Verified';
    } else if (isRejected) {
      statusColor = Colors.red;
      statusIcon = Icons.cancel;
      statusText = 'Rejected';
    } else {
      statusColor = Colors.orange;
      statusIcon = Icons.pending;
      statusText = 'Pending Review';
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: statusColor.withOpacity(0.3), width: 2),
        boxShadow: [
          BoxShadow(
            color: statusColor.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(statusIcon, color: statusColor, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Verification Status',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      statusText,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: statusColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (isRejected && rejectionReason.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.orange[700],
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Rejection Reason:',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.orange[900],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        rejectionReason,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.orange[800],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: Color(0xFF1A1A1A),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? Function(String?)? validator,
    bool readOnly = false,
  }) {
    return TextFormField(
      controller: controller,
      decoration: _inputDecoration(label, icon),
      validator: validator,
      readOnly: readOnly,
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: const Color(0xFF00897B)),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey[300]!),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF00897B), width: 2),
      ),
    );
  }
}
