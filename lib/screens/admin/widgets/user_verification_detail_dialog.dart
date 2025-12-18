import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../providers/admin_provider.dart';

class UserVerificationDetailDialog extends StatefulWidget {
  final String uid;
  final Map<String, dynamic> userData;
  final AdminProvider admin;

  const UserVerificationDetailDialog({
    super.key,
    required this.uid,
    required this.userData,
    required this.admin,
  });

  @override
  State<UserVerificationDetailDialog> createState() =>
      _UserVerificationDetailDialogState();
}

class _UserVerificationDetailDialogState
    extends State<UserVerificationDetailDialog> {
  final TransformationController _frontImageController =
      TransformationController();
  final TransformationController _backImageController =
      TransformationController();
  bool _isLoading = false;
  bool _nameVerified = false;
  bool _addressVerified = false;
  bool _idTypeVerified = false;
  int _selectedImageTab = 0; // 0 for front, 1 for back

  @override
  void dispose() {
    _frontImageController.dispose();
    _backImageController.dispose();
    super.dispose();
  }

  void _resetZoom({required bool isFront}) {
    if (isFront) {
      _frontImageController.value = Matrix4.identity();
    } else {
      _backImageController.value = Matrix4.identity();
    }
  }

  void _zoomIn({required bool isFront}) {
    if (isFront) {
      _frontImageController.value = Matrix4.identity()..scale(1.5);
    } else {
      _backImageController.value = Matrix4.identity()..scale(1.5);
    }
  }

  void _zoomOut({required bool isFront}) {
    if (isFront) {
      _frontImageController.value = Matrix4.identity()..scale(0.75);
    } else {
      _backImageController.value = Matrix4.identity()..scale(0.75);
    }
  }

  @override
  Widget build(BuildContext context) {
    final firstName = widget.userData['firstName'] ?? '';
    final middleInitial = widget.userData['middleInitial'] ?? '';
    final lastName = widget.userData['lastName'] ?? '';
    final fullName = middleInitial.isNotEmpty
        ? '$firstName $middleInitial. $lastName'
        : '$firstName $lastName';
    final email = widget.userData['email'] ?? '';
    final barangay = widget.userData['barangay'] ?? '';
    final city = widget.userData['city'] ?? '';
    final province = widget.userData['province'] ?? '';
    final address = '$barangay, $city, $province'.trim();
    final idType = widget.userData['barangayIdType'] ?? '';
    final idUrlFront = widget.userData['barangayIdUrl'] as String?;
    final idUrlBack = widget.userData['barangayIdUrlBack'] as String?;
    final profilePhotoUrl = widget.userData['profilePhotoUrl'] as String?;

    final createdAtTs = widget.userData['createdAt'];
    String joinedDate = '';
    if (createdAtTs is Timestamp) {
      final d = createdAtTs.toDate();
      joinedDate = '${d.month}/${d.day}/${d.year}';
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final isWideScreen = screenWidth > 1000;

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: isWideScreen ? 1200 : 900,
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF00897B),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.verified_user,
                    color: Colors.white,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'User Verification Details',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: _isLoading
                        ? null
                        : () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            // Content
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: isWideScreen
                    ? _buildWideScreenLayout(
                        fullName: fullName,
                        email: email,
                        address: address,
                        idType: idType,
                        joinedDate: joinedDate,
                        profilePhotoUrl: profilePhotoUrl,
                        idUrlFront: idUrlFront,
                        idUrlBack: idUrlBack,
                      )
                    : _buildMobileLayout(
                        fullName: fullName,
                        email: email,
                        address: address,
                        idType: idType,
                        joinedDate: joinedDate,
                        profilePhotoUrl: profilePhotoUrl,
                        idUrlFront: idUrlFront,
                        idUrlBack: idUrlBack,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWideScreenLayout({
    required String fullName,
    required String email,
    required String address,
    required String idType,
    required String joinedDate,
    required String? profilePhotoUrl,
    required String? idUrlFront,
    required String? idUrlBack,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left Side: User Information
        Expanded(
          flex: 1,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildUserProfileHeader(
                fullName: fullName,
                email: email,
                profilePhotoUrl: profilePhotoUrl,
              ),
              const SizedBox(height: 24),
              _buildVerificationChecklist(),
              const SizedBox(height: 24),
              _buildUserInfoCard(
                fullName: fullName,
                email: email,
                address: address,
                idType: idType,
                joinedDate: joinedDate,
              ),
            ],
          ),
        ),
        const SizedBox(width: 24),
        // Right Side: ID Images
        Expanded(
          flex: 1,
          child: _buildIdImageSection(
            idUrlFront: idUrlFront,
            idUrlBack: idUrlBack,
          ),
        ),
      ],
    );
  }

  Widget _buildMobileLayout({
    required String fullName,
    required String email,
    required String address,
    required String idType,
    required String joinedDate,
    required String? profilePhotoUrl,
    required String? idUrlFront,
    required String? idUrlBack,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildUserProfileHeader(
          fullName: fullName,
          email: email,
          profilePhotoUrl: profilePhotoUrl,
        ),
        const SizedBox(height: 24),
        _buildVerificationChecklist(),
        const SizedBox(height: 24),
        _buildUserInfoCard(
          fullName: fullName,
          email: email,
          address: address,
          idType: idType,
          joinedDate: joinedDate,
        ),
        const SizedBox(height: 24),
        _buildIdImageSection(idUrlFront: idUrlFront, idUrlBack: idUrlBack),
      ],
    );
  }

  Widget _buildUserProfileHeader({
    required String fullName,
    required String email,
    required String? profilePhotoUrl,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            CircleAvatar(
              radius: 45,
              backgroundColor: Colors.grey[300],
              backgroundImage:
                  profilePhotoUrl != null && profilePhotoUrl.isNotEmpty
                  ? NetworkImage(profilePhotoUrl)
                  : null,
              child: profilePhotoUrl == null || profilePhotoUrl.isEmpty
                  ? const Icon(Icons.person, size: 45)
                  : null,
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fullName.isEmpty ? email : fullName,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF00897B),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.email, size: 16, color: Colors.grey[600]),
                      const SizedBox(width: 6),
                      Text(
                        email,
                        style: TextStyle(fontSize: 15, color: Colors.grey[700]),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.orange[50],
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.orange[300]!),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.pending_actions,
                          size: 16,
                          color: Colors.orange,
                        ),
                        SizedBox(width: 6),
                        Text(
                          'Pending Verification',
                          style: TextStyle(
                            color: Colors.orange,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVerificationChecklist() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.checklist, color: const Color(0xFF00897B), size: 22),
                const SizedBox(width: 10),
                const Text(
                  'Verification Checklist',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            VerificationChecklistItem(
              label: 'Name matches ID',
              isChecked: _nameVerified,
              onChanged: (value) {
                setState(() => _nameVerified = value ?? false);
              },
            ),
            const SizedBox(height: 12),
            VerificationChecklistItem(
              label: 'Address matches ID',
              isChecked: _addressVerified,
              onChanged: (value) {
                setState(() => _addressVerified = value ?? false);
              },
            ),
            const SizedBox(height: 12),
            VerificationChecklistItem(
              label: 'ID Type is valid',
              isChecked: _idTypeVerified,
              onChanged: (value) {
                setState(() => _idTypeVerified = value ?? false);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserInfoCard({
    required String fullName,
    required String email,
    required String address,
    required String idType,
    required String joinedDate,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.person_outline,
                  color: const Color(0xFF00897B),
                  size: 22,
                ),
                const SizedBox(width: 10),
                const Text(
                  'User Information',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 20),
            VerificationInfoRow(
              icon: Icons.badge_outlined,
              label: 'Full Name',
              value: fullName.isEmpty ? 'Not provided' : fullName,
            ),
            const SizedBox(height: 16),
            VerificationInfoRow(
              icon: Icons.email_outlined,
              label: 'Email',
              value: email,
            ),
            const SizedBox(height: 16),
            VerificationInfoRow(
              icon: Icons.location_on_outlined,
              label: 'Address',
              value: address.isEmpty ? 'Not provided' : address,
            ),
            const SizedBox(height: 16),
            VerificationInfoRow(
              icon: Icons.credit_card_outlined,
              label: 'ID Type',
              value: idType.isEmpty ? 'Not provided' : idType,
            ),
            const SizedBox(height: 16),
            VerificationInfoRow(
              icon: Icons.calendar_today_outlined,
              label: 'Joined Date',
              value: joinedDate,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIdImageSection({
    required String? idUrlFront,
    required String? idUrlBack,
  }) {
    final hasFront = idUrlFront != null && idUrlFront.isNotEmpty;
    final hasBack = idUrlBack != null && idUrlBack.isNotEmpty;
    final hasAnyImage = hasFront || hasBack;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.perm_identity,
                  color: const Color(0xFF00897B),
                  size: 22,
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Barangay ID Images',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Compare the ID images with the user information',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 16),
            // Tab selector if both images exist
            if (hasFront && hasBack)
              Container(
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () => setState(() => _selectedImageTab = 0),
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(8),
                          bottomLeft: Radius.circular(8),
                        ),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: _selectedImageTab == 0
                                ? const Color(0xFF00897B)
                                : Colors.transparent,
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(8),
                              bottomLeft: Radius.circular(8),
                            ),
                          ),
                          child: Text(
                            'Front',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: _selectedImageTab == 0
                                  ? Colors.white
                                  : Colors.grey[700],
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: InkWell(
                        onTap: () => setState(() => _selectedImageTab = 1),
                        borderRadius: const BorderRadius.only(
                          topRight: Radius.circular(8),
                          bottomRight: Radius.circular(8),
                        ),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: _selectedImageTab == 1
                                ? const Color(0xFF00897B)
                                : Colors.transparent,
                            borderRadius: const BorderRadius.only(
                              topRight: Radius.circular(8),
                              bottomRight: Radius.circular(8),
                            ),
                          ),
                          child: Text(
                            'Back',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: _selectedImageTab == 1
                                  ? Colors.white
                                  : Colors.grey[700],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (hasFront && hasBack) const SizedBox(height: 16),
            // Image display area
            Container(
              height: 500,
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[300]!),
              ),
              clipBehavior: Clip.antiAlias,
              child: hasAnyImage
                  ? _buildImageDisplay(
                      imageUrl: _selectedImageTab == 0 ? idUrlFront : idUrlBack,
                      isFront: _selectedImageTab == 0,
                    )
                  : Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.image_not_supported,
                            size: 64,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'No ID image uploaded',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageDisplay({
    required String? imageUrl,
    required bool isFront,
  }) {
    if (imageUrl == null || imageUrl.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.image_not_supported, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 12),
            Text(
              'No ${isFront ? "front" : "back"} image uploaded',
              style: TextStyle(color: Colors.grey[600], fontSize: 16),
            ),
          ],
        ),
      );
    }

    return Stack(
      children: [
        InteractiveViewer(
          transformationController: isFront
              ? _frontImageController
              : _backImageController,
          minScale: 0.5,
          maxScale: 4.0,
          child: CachedNetworkImage(
            imageUrl: imageUrl,
            fit: BoxFit.contain,
            placeholder: (context, url) =>
                const Center(child: CircularProgressIndicator()),
            errorWidget: (context, url, error) => Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 48),
                  const SizedBox(height: 8),
                  Text(
                    'Failed to load ID image',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
          ),
        ),
        // Zoom controls overlay
        Positioned(
          top: 8,
          right: 8,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.9),
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.zoom_out),
                  tooltip: 'Zoom Out',
                  onPressed: () => _zoomOut(isFront: isFront),
                  color: const Color(0xFF00897B),
                  iconSize: 20,
                ),
                IconButton(
                  icon: const Icon(Icons.zoom_in),
                  tooltip: 'Zoom In',
                  onPressed: () => _zoomIn(isFront: isFront),
                  color: const Color(0xFF00897B),
                  iconSize: 20,
                ),
                IconButton(
                  icon: const Icon(Icons.fit_screen),
                  tooltip: 'Reset Zoom',
                  onPressed: () => _resetZoom(isFront: isFront),
                  color: const Color(0xFF00897B),
                  iconSize: 20,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class VerificationChecklistItem extends StatelessWidget {
  final String label;
  final bool isChecked;
  final ValueChanged<bool?> onChanged;

  const VerificationChecklistItem({
    super.key,
    required this.label,
    required this.isChecked,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Checkbox(
          value: isChecked,
          onChanged: onChanged,
          activeColor: const Color(0xFF00897B),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 15,
              fontWeight: isChecked ? FontWeight.w600 : FontWeight.normal,
              color: isChecked ? const Color(0xFF00897B) : Colors.grey[700],
              decoration: isChecked ? TextDecoration.none : TextDecoration.none,
            ),
          ),
        ),
        if (isChecked)
          const Icon(Icons.check_circle, color: Color(0xFF43A047), size: 20),
      ],
    );
  }
}

class VerificationInfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const VerificationInfoRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: Colors.grey[600]),
        const SizedBox(width: 12),
        SizedBox(
          width: 100,
          child: Text(
            '$label:',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: Colors.grey[700],
              fontSize: 15,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }
}
