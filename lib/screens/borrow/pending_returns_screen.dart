import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import '../../providers/auth_provider.dart';
import '../../providers/user_provider.dart';
import '../../providers/chat_provider.dart';
import '../../services/firestore_service.dart';
import '../../services/storage_service.dart';
import '../../reusable_widgets/bottom_nav_bar_widget.dart';
import '../chat_detail_screen.dart';

class PendingReturnsScreen extends StatefulWidget {
  const PendingReturnsScreen({super.key});

  @override
  State<PendingReturnsScreen> createState() => _PendingReturnsScreenState();
}

class _PendingReturnsScreenState extends State<PendingReturnsScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  final StorageService _storageService = StorageService();
  final ImagePicker _imagePicker = ImagePicker();
  bool _isLoading = true;
  List<Map<String, dynamic>> _pendingReturns = [];

  @override
  void initState() {
    super.initState();
    _loadPendingReturns();
  }

  Future<void> _loadPendingReturns() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final userId = authProvider.user?.uid;

      if (userId == null) {
        setState(() {
          _isLoading = false;
        });
        return;
      }

      final returns = await _firestoreService.getPendingReturnsForLender(
        userId,
      );
      setState(() {
        _pendingReturns = returns;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading pending returns: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  DateTime? _parseDate(dynamic dateValue) {
    if (dateValue == null) return null;
    if (dateValue is DateTime) return dateValue;
    if (dateValue is Timestamp) return dateValue.toDate();
    if (dateValue is int) {
      return DateTime.fromMillisecondsSinceEpoch(dateValue);
    }
    return null;
  }

  String _formatDate(DateTime date) {
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.day.toString().padLeft(2, '0')}, ${date.year}';
  }

  Future<void> _confirmReturn(Map<String, dynamic> returnItem) async {
    final requestId = returnItem['id'] as String?;
    if (requestId == null) return;

    // Show condition review and confirmation modal
    final confirmationData = await _showConditionReviewModal(returnItem);
    if (confirmationData == null) return; // User cancelled

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final lenderId = authProvider.user?.uid;

      if (lenderId == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please login to confirm return'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // Show loading
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        useRootNavigator: true,
        builder: (dialogContext) =>
            const Center(child: CircularProgressIndicator()),
      );

      await _firestoreService.confirmBorrowReturn(
        requestId: requestId,
        lenderId: lenderId,
        conditionAccepted: confirmationData['conditionAccepted'] as bool,
        lenderConditionNotes: confirmationData['notes'] as String?,
        lenderConditionPhotos: confirmationData['photos'] as List<String>?,
        damageReport: confirmationData['damageReport'] as Map<String, dynamic>?,
      );

      // Close loading dialog
      if (mounted) {
        final rootNav = Navigator.of(context, rootNavigator: true);
        if (rootNav.canPop()) rootNav.pop();

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Return confirmed successfully!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );

        // Refresh the list
        _loadPendingReturns();
      }
    } catch (e) {
      if (mounted) {
        final rootNav = Navigator.of(context, rootNavigator: true);
        if (rootNav.canPop()) rootNav.pop();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error confirming return: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<Map<String, dynamic>?> _showConditionReviewModal(
    Map<String, dynamic> returnItem,
  ) async {
    final borrowerCondition = returnItem['borrowerCondition'] as String?;
    final borrowerNotes = returnItem['borrowerConditionNotes'] as String?;
    final borrowerPhotos =
        (returnItem['borrowerConditionPhotos'] as List<dynamic>?)
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
                // Borrower's reported condition
                if (borrowerCondition != null) ...[
                  const Text(
                    'Borrower Reported Condition:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _getConditionColor(
                        borrowerCondition,
                      ).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _getConditionColor(borrowerCondition),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _getConditionIcon(borrowerCondition),
                          color: _getConditionColor(borrowerCondition),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _getConditionLabel(borrowerCondition),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: _getConditionColor(borrowerCondition),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                // Borrower's notes
                if (borrowerNotes != null && borrowerNotes.isNotEmpty) ...[
                  const Text(
                    'Borrower Notes:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(borrowerNotes),
                  ),
                  const SizedBox(height: 12),
                ],
                // Borrower's photos
                if (borrowerPhotos.isNotEmpty) ...[
                  const Text(
                    'Borrower Photos:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 100,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: borrowerPhotos.map((photoUrl) {
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
                                imageUrl: photoUrl,
                                fit: BoxFit.cover,
                                placeholder: (context, url) => const Center(
                                  child: CircularProgressIndicator(),
                                ),
                                errorWidget: (context, url, error) =>
                                    const Icon(Icons.error, color: Colors.red),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
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
                                ? const Color(0xFF00897B).withValues(alpha: 0.1)
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
                              Container(
                                width: 20,
                                height: 20,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: conditionAccepted
                                        ? const Color(0xFF00897B)
                                        : Colors.grey[400]!,
                                    width: 2,
                                  ),
                                  color: conditionAccepted
                                      ? const Color(0xFF00897B)
                                      : Colors.transparent,
                                ),
                                child: conditionAccepted
                                    ? const Icon(
                                        Icons.check,
                                        size: 14,
                                        color: Colors.white,
                                      )
                                    : null,
                              ),
                              const SizedBox(width: 8),
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
                                ? Colors.orange.withValues(alpha: 0.1)
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
                              Container(
                                width: 20,
                                height: 20,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: !conditionAccepted
                                        ? Colors.orange
                                        : Colors.grey[400]!,
                                    width: 2,
                                  ),
                                  color: !conditionAccepted
                                      ? Colors.orange
                                      : Colors.transparent,
                                ),
                                child: !conditionAccepted
                                    ? const Icon(
                                        Icons.check,
                                        size: 14,
                                        color: Colors.white,
                                      )
                                    : null,
                              ),
                              const SizedBox(width: 8),
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
                          children: selectedPhotos.asMap().entries.map((entry) {
                            final index = entry.key;
                            final photo = entry.value;
                            return Stack(
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
                                    child: Builder(
                                      builder: (context) {
                                        // Handle web platform where Image.file is not supported
                                        if (kIsWeb) {
                                          return FutureBuilder<List<int>>(
                                            future: photo.readAsBytes(),
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
                                          );
                                        } else {
                                          // Handle non-web platform with File
                                          try {
                                            return Image.file(
                                              File(photo.path),
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
                                            );
                                          } catch (e) {
                                            return Container(
                                              color: Colors.grey[300],
                                              child: const Icon(
                                                Icons.error_outline,
                                                color: Colors.red,
                                              ),
                                            );
                                          }
                                        }
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
                            );
                          }).toList(),
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
                          final requestId = returnItem['id'] as String? ?? '';

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

  Future<void> _messageBorrower(Map<String, dynamic> returnItem) async {
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final chatProvider = Provider.of<ChatProvider>(context, listen: false);

      if (!authProvider.isAuthenticated || authProvider.user == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please login to message borrower'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final currentUser = userProvider.currentUser;
      if (currentUser == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('User data not found'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final borrowerId = returnItem['borrowerId'] as String? ?? '';
      final borrowerName = returnItem['borrowerName'] as String? ?? 'Borrower';
      final itemId = returnItem['itemId'] as String? ?? '';
      final itemTitle =
          returnItem['title'] as String? ??
          returnItem['itemTitle'] as String? ??
          'Item';

      // Show loading
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        useRootNavigator: true,
        builder: (dialogContext) =>
            const Center(child: CircularProgressIndicator()),
      );

      // Create or get conversation
      final conversationId = await chatProvider.createOrGetConversation(
        userId1: authProvider.user!.uid,
        userId1Name: currentUser.fullName,
        userId2: borrowerId,
        userId2Name: borrowerName,
        itemId: itemId,
        itemTitle: itemTitle,
      );

      // Close loading dialog
      if (mounted) {
        final rootNav = Navigator.of(context, rootNavigator: true);
        if (rootNav.canPop()) rootNav.pop();
      }

      if (conversationId != null && mounted) {
        // Navigate to chat detail screen
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ChatDetailScreen(
              conversationId: conversationId,
              otherParticipantName: borrowerName,
              userId: authProvider.user!.uid,
            ),
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to create conversation'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        final rootNav = Navigator.of(context, rootNavigator: true);
        if (rootNav.canPop()) rootNav.pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  String _normalizeStorageUrl(String url) {
    return url;
  }

  Widget _buildPlaceholderImage() {
    return Container(
      color: Colors.grey[100],
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.image_outlined, size: 50, color: Colors.grey[400]),
            const SizedBox(height: 8),
            Text(
              'no image available',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[400],
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: const Color(0xFF00897B),
        elevation: 0,
        title: const Text(
          'Pending Returns',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadPendingReturns,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _pendingReturns.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.assignment_returned_outlined,
                    size: 64,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No pending returns',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Items waiting for return confirmation will appear here',
                    style: TextStyle(color: Colors.grey[500]),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadPendingReturns,
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _pendingReturns.length,
                itemBuilder: (context, index) {
                  final returnItem = _pendingReturns[index];
                  return _buildReturnCard(returnItem);
                },
              ),
            ),
      bottomNavigationBar: BottomNavBarWidget(
        selectedIndex: null,
        onTap: (_) {},
        navigationContext: context,
      ),
    );
  }

  Color _getConditionColor(String condition) {
    switch (condition.toLowerCase()) {
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
    switch (condition.toLowerCase()) {
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
    switch (condition.toLowerCase()) {
      case 'same':
        return 'Same Condition';
      case 'better':
        return 'Better Condition';
      case 'worse':
        return 'Worse Condition';
      case 'damaged':
        return 'Damaged';
      default:
        return condition;
    }
  }

  Widget _buildReturnCard(Map<String, dynamic> returnItem) {
    final title =
        returnItem['title'] as String? ??
        returnItem['itemTitle'] as String? ??
        'Unknown Item';
    final borrowerName = returnItem['borrowerName'] as String? ?? 'Unknown';
    final returnInitiatedAt = _parseDate(returnItem['returnInitiatedAt']);
    final images =
        (returnItem['images'] as List<dynamic>?)?.cast<String>() ?? [];
    final hasImages = images.isNotEmpty;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image
          if (hasImages)
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
              child: Container(
                height: 200,
                width: double.infinity,
                color: Colors.grey[200],
                child: CachedNetworkImage(
                  imageUrl: _normalizeStorageUrl(images.first),
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Container(
                    color: Colors.grey[200],
                    child: const Center(child: CircularProgressIndicator()),
                  ),
                  errorWidget: (context, url, error) {
                    return _buildPlaceholderImage();
                  },
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title and Status
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.orange,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        'Pending',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Borrower's Reported Condition
                if (returnItem['borrowerCondition'] != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _getConditionColor(
                        returnItem['borrowerCondition'] as String,
                      ).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _getConditionColor(
                          returnItem['borrowerCondition'] as String,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _getConditionIcon(
                            returnItem['borrowerCondition'] as String,
                          ),
                          color: _getConditionColor(
                            returnItem['borrowerCondition'] as String,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Borrower Reported: ${_getConditionLabel(returnItem['borrowerCondition'] as String)}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: _getConditionColor(
                                    returnItem['borrowerCondition'] as String,
                                  ),
                                ),
                              ),
                              if (returnItem['borrowerConditionNotes'] !=
                                      null &&
                                  (returnItem['borrowerConditionNotes']
                                          as String)
                                      .isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  returnItem['borrowerConditionNotes']
                                      as String,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[700],
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                // Borrower Info
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const CircleAvatar(
                        backgroundColor: Color(0xFF00897B),
                        child: Icon(
                          Icons.person,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Borrower',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                            Text(
                              borrowerName,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (returnInitiatedAt != null) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(
                        Icons.access_time,
                        size: 14,
                        color: Colors.grey[600],
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Return requested: ${_formatDate(returnInitiatedAt)}',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                // Action Buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _messageBorrower(returnItem),
                        icon: const Icon(Icons.message, size: 18),
                        label: const Text('Message'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF00897B),
                          side: const BorderSide(color: Color(0xFF00897B)),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _confirmReturn(returnItem),
                        icon: const Icon(Icons.check_circle, size: 18),
                        label: const Text('Confirm'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00897B),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
