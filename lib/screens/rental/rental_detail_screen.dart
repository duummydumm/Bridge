import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../providers/rental_request_provider.dart';
import '../../providers/rental_payment_provider.dart';
import '../../providers/auth_provider.dart';
import '../../models/rental_request_model.dart';
import '../../models/rating_model.dart';
import '../../services/firestore_service.dart';
import '../../services/rating_service.dart';
import '../../services/storage_service.dart';
import '../submit_rating_screen.dart';

class RentalDetailScreen extends StatefulWidget {
  const RentalDetailScreen({super.key});

  @override
  State<RentalDetailScreen> createState() => _RentalDetailScreenState();
}

class _RentalDetailScreenState extends State<RentalDetailScreen> {
  final _requestIdCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final FirestoreService _firestoreService = FirestoreService();
  final RatingService _ratingService = RatingService();
  final StorageService _storageService = StorageService();
  final ImagePicker _imagePicker = ImagePicker();

  @override
  void dispose() {
    _requestIdCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reqProvider = context.watch<RentalRequestProvider>();
    final payProvider = context.watch<RentalPaymentsProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('Rental Detail')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            TextField(
              controller: _requestIdCtrl,
              decoration: const InputDecoration(labelText: 'Rental Request ID'),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton(
                  onPressed: reqProvider.isLoading
                      ? null
                      : () async {
                          final ok = await reqProvider.setStatus(
                            _requestIdCtrl.text.trim(),
                            RentalRequestStatus.ownerApproved,
                          );
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(ok ? 'Approved' : 'Failed')),
                          );
                        },
                  child: const Text('Approve'),
                ),
                ElevatedButton(
                  onPressed: reqProvider.isLoading
                      ? null
                      : () async {
                          final ok = await reqProvider.setStatus(
                            _requestIdCtrl.text.trim(),
                            RentalRequestStatus.active,
                          );
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(ok ? 'Activated' : 'Failed'),
                            ),
                          );
                        },
                  child: const Text('Mark Active'),
                ),
                // Return verification buttons
                ElevatedButton(
                  onPressed: reqProvider.isLoading
                      ? null
                      : () async {
                          final requestId = _requestIdCtrl.text.trim();
                          final authProvider = Provider.of<AuthProvider>(
                            context,
                            listen: false,
                          );
                          final currentUser = authProvider.user;
                          if (currentUser == null) return;

                          // Get request to check if user is renter or owner
                          final requestData = await _firestoreService
                              .getRentalRequest(requestId);
                          if (requestData == null) {
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Request not found'),
                              ),
                            );
                            return;
                          }

                          final request = RentalRequestModel.fromMap(
                            requestData,
                            requestId,
                          );
                          final isRenter = currentUser.uid == request.renterId;
                          final isOwner = currentUser.uid == request.ownerId;

                          bool ok = false;
                          if (isRenter &&
                              request.status == RentalRequestStatus.active) {
                            // Renter initiates return
                            ok = await reqProvider.initiateReturn(
                              requestId,
                              currentUser.uid,
                            );
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  ok
                                      ? 'Return initiated. Waiting for owner verification.'
                                      : 'Failed to initiate return',
                                ),
                                backgroundColor: ok
                                    ? Colors.orange
                                    : Colors.red,
                              ),
                            );
                          } else if (isOwner &&
                              request.status ==
                                  RentalRequestStatus.returnInitiated) {
                            // Owner verifies return - show condition review modal
                            final verificationData =
                                await _showConditionReviewModal(requestData);
                            if (verificationData == null)
                              return; // User cancelled

                            // Show loading
                            if (!mounted) return;
                            showDialog(
                              context: context,
                              barrierDismissible: false,
                              useRootNavigator: true,
                              builder: (dialogContext) => const Center(
                                child: CircularProgressIndicator(),
                              ),
                            );

                            ok = await reqProvider.verifyReturn(
                              requestId,
                              currentUser.uid,
                              conditionAccepted:
                                  verificationData['conditionAccepted'] as bool,
                              ownerConditionNotes:
                                  verificationData['notes'] as String?,
                              ownerConditionPhotos:
                                  verificationData['photos'] as List<String>?,
                              damageReport:
                                  verificationData['damageReport']
                                      as Map<String, dynamic>?,
                            );

                            // Close loading dialog
                            if (mounted) {
                              final rootNav = Navigator.of(
                                context,
                                rootNavigator: true,
                              );
                              if (rootNav.canPop()) rootNav.pop();
                            }

                            if (!mounted) return;
                            if (ok) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    verificationData['conditionAccepted']
                                            as bool
                                        ? 'Return verified successfully!'
                                        : 'Damage reported. Rental is now disputed.',
                                  ),
                                  backgroundColor:
                                      verificationData['conditionAccepted']
                                          as bool
                                      ? Colors.green
                                      : Colors.orange,
                                ),
                              );
                              // Prompt for rating only if condition accepted
                              if (verificationData['conditionAccepted']
                                  as bool) {
                                await _promptForRating(requestId);
                              }
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    reqProvider.errorMessage ??
                                        'Failed to verify return',
                                  ),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          } else {
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  isRenter
                                      ? 'Return already initiated or rental not active'
                                      : isOwner
                                      ? 'Return not initiated by renter yet'
                                      : 'You are not authorized',
                                ),
                                backgroundColor: Colors.orange,
                              ),
                            );
                          }
                        },
                  child: const Text('Initiate/Verify Return'),
                ),
              ],
            ),
            const Divider(height: 32),
            TextField(
              controller: _amountCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Payment Amount (manual)',
              ),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: payProvider.isLoading
                  ? null
                  : () async {
                      final id = await payProvider.recordManualPayment(
                        rentalRequestId: _requestIdCtrl.text.trim(),
                        amount: double.tryParse(_amountCtrl.text.trim()) ?? 0,
                      );
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            id != null ? 'Payment saved' : 'Payment failed',
                          ),
                        ),
                      );
                    },
              child: const Text('Record Manual Payment'),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: reqProvider.isLoading
                  ? null
                  : () async {
                      final ok = await reqProvider.setPaymentStatus(
                        _requestIdCtrl.text.trim(),
                        PaymentStatus.captured,
                      );
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            ok ? 'Payment marked captured' : 'Failed',
                          ),
                        ),
                      );
                    },
              child: const Text('Mark Payment Captured'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _promptForRating(String requestId) async {
    try {
      // Get rental request details
      final requestData = await _firestoreService.getRentalRequest(requestId);
      if (requestData == null) return;

      final request = RentalRequestModel.fromMap(requestData, requestId);

      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final currentUser = authProvider.user;

      if (currentUser == null) return;

      // Determine who to rate based on current user
      final isOwner = currentUser.uid == request.ownerId;
      final ratedUserId = isOwner ? request.renterId : request.ownerId;
      final ratedUserName = isOwner ? 'Renter' : 'Owner';

      // Check if already rated
      final hasRated = await _ratingService.hasRated(
        raterUserId: currentUser.uid,
        ratedUserId: ratedUserId,
        transactionId: requestId,
      );

      if (hasRated) {
        // Already rated, skip prompt
        return;
      }

      // Get rated user's name if available
      String? ratedUserNameFull;
      try {
        final ratedUserData = await _firestoreService.getUser(ratedUserId);
        if (ratedUserData != null) {
          ratedUserNameFull =
              '${ratedUserData['firstName']} ${ratedUserData['lastName']}';
        }
      } catch (e) {
        // Silent fail, use default
      }

      // Show rating dialog
      if (!mounted) return;

      final shouldRate = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Rate Your Experience'),
          content: Text(
            'How was your rental experience with ${ratedUserNameFull ?? ratedUserName}?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Maybe Later'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00897B),
              ),
              child: const Text('Rate Now'),
            ),
          ],
        ),
      );

      if (shouldRate == true && mounted) {
        // Navigate to rating screen
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => SubmitRatingScreen(
              ratedUserId: ratedUserId,
              ratedUserName: ratedUserNameFull ?? ratedUserName,
              context: RatingContext.rental,
              transactionId: requestId,
              role: isOwner ? 'owner' : 'renter',
            ),
          ),
        );
      }
    } catch (e) {
      // Silent fail - don't interrupt user flow
      debugPrint('Error prompting for rating: $e');
    }
  }

  Future<Map<String, dynamic>?> _showConditionReviewModal(
    Map<String, dynamic> requestData,
  ) async {
    final renterCondition = requestData['renterCondition'] as String?;
    final renterNotes = requestData['renterConditionNotes'] as String?;
    final renterPhotos =
        (requestData['renterConditionPhotos'] as List<dynamic>?)
            ?.cast<String>() ??
        [];

    bool conditionAccepted = true;
    final notesController = TextEditingController();
    final damageDescriptionController = TextEditingController();
    final damageCostController = TextEditingController();
    final List<XFile> selectedPhotos = [];
    bool isUploading = false;
    bool showDamageForm = false;

    return showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Review Item Condition'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Renter's reported condition
                if (renterCondition != null) ...[
                  const Text(
                    'Renter Reported Condition:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _getConditionColor(
                        renterCondition,
                      ).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _getConditionColor(renterCondition),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _getConditionIcon(renterCondition),
                          color: _getConditionColor(renterCondition),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _getConditionLabel(renterCondition),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: _getConditionColor(renterCondition),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                // Renter's notes
                if (renterNotes != null && renterNotes.isNotEmpty) ...[
                  const Text(
                    'Renter Notes:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(renterNotes),
                  ),
                  const SizedBox(height: 12),
                ],
                // Renter's photos
                if (renterPhotos.isNotEmpty) ...[
                  const Text(
                    'Renter Photos:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 100,
                    child: ListView.builder(
                      shrinkWrap: true,
                      scrollDirection: Axis.horizontal,
                      itemCount: renterPhotos.length,
                      itemBuilder: (context, index) {
                        return Container(
                          margin: const EdgeInsets.only(right: 8),
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: CachedNetworkImage(
                              imageUrl: renterPhotos[index],
                              fit: BoxFit.cover,
                              placeholder: (context, url) => const Center(
                                child: CircularProgressIndicator(),
                              ),
                              errorWidget: (context, url, error) =>
                                  const Icon(Icons.error, color: Colors.red),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                // Condition acceptance
                const Divider(),
                const SizedBox(height: 8),
                const Text(
                  'Do you accept this condition?',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () {
                          setState(() {
                            conditionAccepted = true;
                            showDamageForm = false;
                          });
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 2,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: conditionAccepted
                                ? const Color(0xFF00897B).withOpacity(0.1)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: conditionAccepted
                                  ? const Color(0xFF00897B)
                                  : Colors.grey[300]!,
                              width: conditionAccepted ? 2 : 1,
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Radio<bool>(
                                value: true,
                                groupValue: conditionAccepted,
                                onChanged: (value) {
                                  setState(() {
                                    conditionAccepted = value!;
                                    showDamageForm = false;
                                  });
                                },
                                activeColor: const Color(0xFF00897B),
                              ),
                              const Expanded(
                                child: Text(
                                  'Accept',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w500,
                                    fontSize: 10,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: InkWell(
                        onTap: () {
                          setState(() {
                            conditionAccepted = false;
                            showDamageForm = true;
                          });
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 2,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: !conditionAccepted
                                ? Colors.orange.withOpacity(0.1)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: !conditionAccepted
                                  ? Colors.orange
                                  : Colors.grey[300]!,
                              width: !conditionAccepted ? 2 : 1,
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Radio<bool>(
                                value: false,
                                groupValue: conditionAccepted,
                                onChanged: (value) {
                                  setState(() {
                                    conditionAccepted = value!;
                                    showDamageForm = true;
                                  });
                                },
                                activeColor: Colors.orange,
                              ),
                              const Expanded(
                                child: Text(
                                  'Dispute / Report Damage',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w500,
                                    fontSize: 10,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                // Damage reporting form
                if (showDamageForm) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'Damage Report:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: damageDescriptionController,
                    decoration: const InputDecoration(
                      labelText: 'Damage Description *',
                      hintText: 'Describe the damage or issues...',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: damageCostController,
                    decoration: const InputDecoration(
                      labelText: 'Estimated Repair Cost (Optional)',
                      hintText: '0.00',
                      prefixText: '₱ ',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: notesController,
                    decoration: const InputDecoration(
                      labelText: 'Additional Notes',
                      hintText: 'Any additional information...',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 12),
                  // Photo upload for damage
                  if (selectedPhotos.isNotEmpty)
                    SizedBox(
                      height: 100,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: List.generate(
                            selectedPhotos.length,
                            (index) => Stack(
                              children: [
                                Container(
                                  margin: const EdgeInsets.only(right: 8),
                                  width: 100,
                                  height: 100,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.grey),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: kIsWeb
                                        ? FutureBuilder<List<int>>(
                                            future: selectedPhotos[index]
                                                .readAsBytes(),
                                            builder: (context, snapshot) {
                                              if (snapshot.connectionState ==
                                                  ConnectionState.waiting) {
                                                return Container(
                                                  color: Colors.grey[300],
                                                  child: const Center(
                                                    child:
                                                        CircularProgressIndicator(),
                                                  ),
                                                );
                                              }
                                              if (snapshot.hasError ||
                                                  !snapshot.hasData) {
                                                return Container(
                                                  color: Colors.grey[300],
                                                  child: const Icon(
                                                    Icons.error_outline,
                                                    color: Colors.red,
                                                  ),
                                                );
                                              }
                                              return Image.memory(
                                                Uint8List.fromList(
                                                  snapshot.data!,
                                                ),
                                                fit: BoxFit.cover,
                                                errorBuilder:
                                                    (
                                                      context,
                                                      error,
                                                      stackTrace,
                                                    ) {
                                                      return Container(
                                                        color: Colors.grey[300],
                                                        child: const Icon(
                                                          Icons.error_outline,
                                                          color: Colors.red,
                                                        ),
                                                      );
                                                    },
                                              );
                                            },
                                          )
                                        : Image.file(
                                            File(selectedPhotos[index].path),
                                            fit: BoxFit.cover,
                                            errorBuilder:
                                                (context, error, stackTrace) {
                                                  return Container(
                                                    color: Colors.grey[300],
                                                    child: const Icon(
                                                      Icons.error_outline,
                                                      color: Colors.red,
                                                    ),
                                                  );
                                                },
                                          ),
                                  ),
                                ),
                                Positioned(
                                  top: 4,
                                  right: 4,
                                  child: IconButton(
                                    icon: const Icon(Icons.close, size: 20),
                                    color: Colors.red,
                                    onPressed: () {
                                      setState(() {
                                        selectedPhotos.removeAt(index);
                                      });
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: isUploading
                        ? null
                        : () async {
                            try {
                              final XFile? photo = await _imagePicker.pickImage(
                                source: ImageSource.gallery,
                                imageQuality: 85,
                              );
                              if (photo != null) {
                                setState(() {
                                  selectedPhotos.add(photo);
                                });
                              }
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Error picking image: $e'),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                              }
                            }
                          },
                    icon: const Icon(Icons.add_photo_alternate),
                    label: const Text('Add Damage Photo'),
                  ),
                  if (isUploading) ...[
                    const SizedBox(height: 8),
                    const Center(child: CircularProgressIndicator()),
                    const Center(
                      child: Text(
                        'Uploading photos...',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isUploading
                  ? null
                  : () => Navigator.pop(context, null),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed:
                  isUploading ||
                      (showDamageForm &&
                          damageDescriptionController.text.trim().isEmpty)
                  ? null
                  : () async {
                      if (showDamageForm &&
                          damageDescriptionController.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Please provide damage description'),
                            backgroundColor: Colors.orange,
                          ),
                        );
                        return;
                      }

                      setState(() => isUploading = true);

                      // Upload photos if any
                      final List<String> uploadedPhotoUrls = [];
                      if (selectedPhotos.isNotEmpty) {
                        try {
                          final authProvider = Provider.of<AuthProvider>(
                            context,
                            listen: false,
                          );
                          final userId = authProvider.user?.uid;
                          final requestId = _requestIdCtrl.text.trim();

                          if (userId != null && requestId.isNotEmpty) {
                            for (final photo in selectedPhotos) {
                              try {
                                final url = await _storageService
                                    .uploadConditionPhoto(
                                      file: photo,
                                      requestId: requestId,
                                      userId: userId,
                                    );
                                uploadedPhotoUrls.add(url);
                              } catch (e) {
                                debugPrint('Error uploading photo: $e');
                              }
                            }
                          }
                        } catch (e) {
                          debugPrint('Error uploading photos: $e');
                        }
                      }

                      Map<String, dynamic>? damageReport;
                      if (showDamageForm) {
                        damageReport = {
                          'type': 'damage',
                          'description': damageDescriptionController.text
                              .trim(),
                          'estimatedCost':
                              damageCostController.text.trim().isNotEmpty
                              ? double.tryParse(
                                  damageCostController.text.trim(),
                                )
                              : null,
                          'photos': uploadedPhotoUrls,
                        };
                      }

                      Navigator.pop(context, {
                        'conditionAccepted': conditionAccepted,
                        'notes': notesController.text.trim().isNotEmpty
                            ? notesController.text.trim()
                            : null,
                        'photos': uploadedPhotoUrls.isNotEmpty
                            ? uploadedPhotoUrls
                            : null,
                        'damageReport': damageReport,
                      });
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: conditionAccepted
                    ? const Color(0xFF00897B)
                    : Colors.red,
                foregroundColor: Colors.white,
              ),
              child: Text(
                conditionAccepted ? 'Confirm Return' : 'Report Damage',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getConditionColor(String condition) {
    switch (condition) {
      case 'same':
        return Colors.green;
      case 'better':
        return Colors.blue;
      case 'worse':
        return Colors.orange;
      case 'damaged':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  IconData _getConditionIcon(String condition) {
    switch (condition) {
      case 'same':
        return Icons.check_circle;
      case 'better':
        return Icons.trending_up;
      case 'worse':
        return Icons.trending_down;
      case 'damaged':
        return Icons.warning;
      default:
        return Icons.help;
    }
  }

  String _getConditionLabel(String condition) {
    switch (condition) {
      case 'same':
        return 'Same Condition';
      case 'better':
        return 'Better Condition';
      case 'worse':
        return 'Worse Condition';
      case 'damaged':
        return 'Damaged';
      default:
        return 'Unknown';
    }
  }
}
