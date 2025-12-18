import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../providers/auth_provider.dart';
import '../../providers/user_provider.dart';
import '../../providers/chat_provider.dart';
import '../../providers/rental_request_provider.dart';
import '../../services/firestore_service.dart';
import '../../services/report_block_service.dart';
import '../../services/storage_service.dart';
import '../../models/rental_payment_model.dart';
import '../../models/rating_model.dart';
import '../../models/rental_request_model.dart';
import '../../services/rating_service.dart';
import '../../reusable_widgets/report_dialog.dart';
import '../chat_detail_screen.dart';
import '../submit_rating_screen.dart';

class ActiveRentalDetailScreen extends StatefulWidget {
  final String requestId;

  const ActiveRentalDetailScreen({super.key, required this.requestId});

  @override
  State<ActiveRentalDetailScreen> createState() =>
      _ActiveRentalDetailScreenState();
}

class _ActiveRentalDetailScreenState extends State<ActiveRentalDetailScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  final ReportBlockService _reportBlockService = ReportBlockService();
  final RatingService _ratingService = RatingService();
  final StorageService _storageService = StorageService();
  final ImagePicker _imagePicker = ImagePicker();
  Map<String, dynamic>? _requestData;
  bool _isLoading = true;
  bool _isProcessing = false;
  List<RentalPaymentModel> _monthlyPayments = [];
  bool _isLoadingPayments = false;

  @override
  void initState() {
    super.initState();
    _loadRequest();
  }

  Future<void> _loadRequest() async {
    try {
      final data = await _firestoreService.getRentalRequest(widget.requestId);
      if (data == null) {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
        return;
      }

      // Enrich data with item title and names
      final enrichedData = Map<String, dynamic>.from(data);

      // Get item title from listing
      final listingId = data['listingId'] as String?;
      if (listingId != null) {
        try {
          final listing = await _firestoreService.getRentalListing(listingId);
          if (listing != null) {
            enrichedData['itemTitle'] = listing['title'] as String?;
            // Store rental type from listing
            enrichedData['rentType'] = listing['rentType'] as String? ?? 'item';
            // Fallback to item title if listing title not available
            if (enrichedData['itemTitle'] == null ||
                (enrichedData['itemTitle'] as String).isEmpty) {
              final itemId = data['itemId'] as String?;
              if (itemId != null) {
                final item = await _firestoreService.getItem(itemId);
                enrichedData['itemTitle'] = item?['title'] as String?;
              }
            }
          }
        } catch (_) {
          // Continue if listing fetch fails
        }
      }
      enrichedData['itemTitle'] ??= 'Rental Item';
      enrichedData['rentType'] ??= 'item';

      // Get owner name
      final ownerId = data['ownerId'] as String?;
      if (ownerId != null) {
        try {
          final owner = await _firestoreService.getUser(ownerId);
          if (owner != null) {
            final firstName = owner['firstName'] ?? '';
            final lastName = owner['lastName'] ?? '';
            enrichedData['ownerName'] = '$firstName $lastName'.trim();
          }
        } catch (_) {
          // Continue if user fetch fails
        }
      }
      enrichedData['ownerName'] ??= 'Owner';

      // Get renter name
      final renterId = data['renterId'] as String?;
      if (renterId != null) {
        try {
          final renter = await _firestoreService.getUser(renterId);
          if (renter != null) {
            final firstName = renter['firstName'] ?? '';
            final lastName = renter['lastName'] ?? '';
            enrichedData['renterName'] = '$firstName $lastName'.trim();
          }
        } catch (_) {
          // Continue if user fetch fails
        }
      }
      enrichedData['renterName'] ??= 'Renter';

      if (mounted) {
        setState(() {
          _requestData = enrichedData;
          _isLoading = false;
        });
        // Load monthly payments if this is a long-term rental
        final isLongTerm = enrichedData['isLongTerm'] as bool? ?? false;
        if (isLongTerm) {
          _loadMonthlyPayments();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading rental: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _loadMonthlyPayments() async {
    setState(() {
      _isLoadingPayments = true;
    });
    try {
      final payments = await _firestoreService.getPaymentsForRequest(
        widget.requestId,
      );
      if (mounted) {
        setState(() {
          _monthlyPayments =
              payments
                  .map((p) => RentalPaymentModel.fromMap(p, p['id'] as String))
                  .toList()
                ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
          _isLoadingPayments = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingPayments = false;
        });
      }
    }
  }

  Future<void> _messageOwner() async {
    if (_requestData == null) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);

    if (!authProvider.isAuthenticated || authProvider.user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please login to message'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final currentUser = userProvider.currentUser;
    if (currentUser == null) return;

    final ownerId = _requestData!['ownerId'] as String;
    final ownerName = _requestData!['ownerName'] as String? ?? 'Owner';
    final itemId = _requestData!['itemId'] as String;
    final itemTitle = _requestData!['itemTitle'] as String? ?? 'Rental Item';

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
      userId2: ownerId,
      userId2Name: ownerName,
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
            otherParticipantName: ownerName,
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
  }

  Future<void> _messageRenter() async {
    if (_requestData == null) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);

    if (!authProvider.isAuthenticated || authProvider.user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please login to message'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final currentUser = userProvider.currentUser;
    if (currentUser == null) return;

    final renterId = _requestData!['renterId'] as String?;
    final renterName = _requestData!['renterName'] as String? ?? 'Renter';
    final itemId = _requestData!['itemId'] as String;
    final itemTitle = _requestData!['itemTitle'] as String? ?? 'Rental Item';

    if (renterId == null || renterId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Renter information not available'),
          backgroundColor: Colors.red,
        ),
      );
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

    // Create or get conversation
    final conversationId = await chatProvider.createOrGetConversation(
      userId1: authProvider.user!.uid,
      userId1Name: currentUser.fullName,
      userId2: renterId,
      userId2Name: renterName,
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
            otherParticipantName: renterName,
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
  }

  String _formatDate(dynamic date) {
    if (date == null) return 'N/A';
    if (date is Timestamp) {
      final dt = date.toDate();
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    }
    if (date is DateTime) {
      return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    }
    return date.toString();
  }

  String _formatCurrency(double? amount) {
    if (amount == null) return '₱0.00';
    return '₱${amount.toStringAsFixed(2)}';
  }

  String _formatDateTime(DateTime? date) {
    if (date == null) return 'N/A';
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  /// Mark a specific month as paid
  Future<void> _markMonthAsPaid(int year, int month) async {
    if (_requestData == null) return;

    final monthlyAmount =
        (_requestData!['monthlyPaymentAmount'] as num?)?.toDouble() ?? 0.0;

    if (monthlyAmount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Monthly payment amount not set'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Show dialog to confirm
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Mark ${_getMonthName(month)} $year as Paid?'),
        content: Text(
          'Record payment of ${_formatCurrency(monthlyAmount)} for ${_getMonthName(month)} $year?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00897B),
              foregroundColor: Colors.white,
            ),
            child: const Text('Mark as Paid'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      // Use the first day of the target month as the payment date
      final paymentDate = DateTime(year, month, 1);

      await _firestoreService.recordMonthlyRentalPayment(
        rentalRequestId: widget.requestId,
        amount: monthlyAmount,
        paymentDate: paymentDate,
      );

      if (mounted) {
        setState(() {
          _isProcessing = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${_getMonthName(month)} $year marked as paid!'),
            backgroundColor: Colors.green,
          ),
        );

        // Reload request and payments
        await _loadRequest();
        await _loadMonthlyPayments();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error marking month as paid: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _recordMonthlyPayment() async {
    if (_requestData == null) return;

    final monthlyAmount =
        (_requestData!['monthlyPaymentAmount'] as num?)?.toDouble() ?? 0.0;

    if (monthlyAmount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Monthly payment amount not set'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Show dialog to confirm payment
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Record Monthly Payment?'),
        content: Text(
          'Record payment of ${_formatCurrency(monthlyAmount)} for this month?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00897B),
              foregroundColor: Colors.white,
            ),
            child: const Text('Record Payment'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      await _firestoreService.recordMonthlyRentalPayment(
        rentalRequestId: widget.requestId,
        amount: monthlyAmount,
        paymentDate: DateTime.now(),
      );

      if (mounted) {
        setState(() {
          _isProcessing = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Monthly payment recorded successfully!'),
            backgroundColor: Colors.green,
          ),
        );

        // Reload request and payments
        await _loadRequest();
        await _loadMonthlyPayments();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error recording payment: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _initiateReturn() async {
    if (_requestData == null) return;

    // Show condition verification modal
    final conditionData = await _showConditionVerificationModal();
    if (conditionData == null) return; // User cancelled

    setState(() {
      _isProcessing = true;
    });

    try {
      final reqProvider = Provider.of<RentalRequestProvider>(
        context,
        listen: false,
      );
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final currentUser = authProvider.user;

      if (currentUser == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('You must be logged in'),
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

      final success = await reqProvider.initiateReturn(
        widget.requestId,
        currentUser.uid,
        condition: conditionData['condition'],
        conditionNotes: conditionData['notes'],
        conditionPhotos: conditionData['photos'],
      );

      // Close loading dialog
      if (mounted) {
        final rootNav = Navigator.of(context, rootNavigator: true);
        if (rootNav.canPop()) rootNav.pop();
      }

      if (mounted) {
        setState(() {
          _isProcessing = false;
        });

        if (success) {
          final actionText = _getReturnActionText().toLowerCase();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                actionText.contains('return')
                    ? 'Return initiated successfully! Owner will verify.'
                    : actionText.contains('move out')
                    ? 'Move out initiated successfully! Owner will verify.'
                    : actionText.contains('end lease')
                    ? 'Lease termination initiated successfully! Owner will verify.'
                    : 'Rental ending initiated successfully! Owner will verify.',
              ),
              backgroundColor: Colors.orange,
            ),
          );
          // Reload request to show updated status
          _loadRequest();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                reqProvider.errorMessage ?? 'Failed to initiate return',
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        final rootNav = Navigator.of(context, rootNavigator: true);
        if (rootNav.canPop()) rootNav.pop();
        setState(() {
          _isProcessing = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  String _getReturnActionText() {
    if (_requestData == null) return 'Initiate Return';
    final rentType = (_requestData!['rentType'] as String? ?? 'item')
        .toLowerCase();
    switch (rentType) {
      case 'apartment':
        return 'End Rental';
      case 'boardinghouse':
      case 'boarding_house':
        return 'Move Out';
      case 'commercial':
        return 'End Lease';
      default:
        return 'Initiate Return';
    }
  }

  String _getReturnDialogTitle() {
    if (_requestData == null) return 'Item Condition Verification';
    final rentType = (_requestData!['rentType'] as String? ?? 'item')
        .toLowerCase();
    switch (rentType) {
      case 'apartment':
        return 'End Rental';
      case 'boardinghouse':
      case 'boarding_house':
        return 'Move Out';
      case 'commercial':
        return 'End Lease';
      default:
        return 'Item Condition Verification';
    }
  }

  String _getReturnDialogMessage() {
    if (_requestData == null)
      return 'Please report the condition of the item you are returning:';
    final rentType = (_requestData!['rentType'] as String? ?? 'item')
        .toLowerCase();
    switch (rentType) {
      case 'apartment':
        return 'Please report the condition of the apartment you are vacating:';
      case 'boardinghouse':
      case 'boarding_house':
        return 'Please report the condition of the room/space you are moving out from:';
      case 'commercial':
        return 'Please report the condition of the commercial space you are vacating:';
      default:
        return 'Please report the condition of the item you are returning:';
    }
  }

  String _getVerifyButtonText() {
    if (_requestData == null) return 'Verify Return';
    final rentType = (_requestData!['rentType'] as String? ?? 'item')
        .toLowerCase();
    switch (rentType) {
      case 'apartment':
        return 'Verify Property';
      case 'boardinghouse':
      case 'boarding_house':
        return 'Verify Property';
      case 'commercial':
      case 'commercialspace':
      case 'commercial_space':
        return 'Verify Property';
      default:
        return 'Verify Return';
    }
  }

  Future<Map<String, dynamic>?> _showConditionVerificationModal() async {
    String? selectedCondition;
    final notesController = TextEditingController();
    final List<XFile> selectedPhotos = [];
    bool isUploading = false;

    return showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(_getReturnDialogTitle()),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _getReturnDialogMessage(),
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 16),
                // Condition Selection
                const Text(
                  'Condition:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildConditionChip(
                      'same',
                      'Same',
                      selectedCondition,
                      () => setState(() => selectedCondition = 'same'),
                    ),
                    _buildConditionChip(
                      'better',
                      'Better',
                      selectedCondition,
                      () => setState(() => selectedCondition = 'better'),
                    ),
                    _buildConditionChip(
                      'worse',
                      'Worse',
                      selectedCondition,
                      () => setState(() => selectedCondition = 'worse'),
                    ),
                    _buildConditionChip(
                      'damaged',
                      'Damaged',
                      selectedCondition,
                      () => setState(() => selectedCondition = 'damaged'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Notes
                TextField(
                  controller: notesController,
                  decoration: const InputDecoration(
                    labelText: 'Additional Notes (Optional)',
                    hintText: 'Describe the condition or any issues...',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 16),
                // Photo Upload
                const Text(
                  'Photos (Optional):',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 8),
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
                  label: const Text('Add Photo'),
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
              onPressed: isUploading || selectedCondition == null
                  ? null
                  : () async {
                      if (selectedCondition == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Please select item condition'),
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

                          if (userId != null) {
                            for (final photo in selectedPhotos) {
                              try {
                                final url = await _storageService
                                    .uploadConditionPhoto(
                                      file: photo,
                                      requestId: widget.requestId,
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

                      Navigator.pop(context, {
                        'condition': selectedCondition,
                        'notes': notesController.text.trim().isNotEmpty
                            ? notesController.text.trim()
                            : null,
                        'photos': uploadedPhotoUrls.isNotEmpty
                            ? uploadedPhotoUrls
                            : null,
                      });
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
              child: Text(_getReturnActionText()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConditionChip(
    String value,
    String label,
    String? selected,
    VoidCallback onTap,
  ) {
    final isSelected = selected == value;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? _getConditionColor(value).withValues(alpha: 0.1)
              : Colors.grey[200],
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? _getConditionColor(value) : Colors.grey[300]!,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _getConditionIcon(value),
              size: 18,
              color: isSelected ? _getConditionColor(value) : Colors.grey[600],
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected
                    ? _getConditionColor(value)
                    : Colors.grey[700],
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
        return condition;
    }
  }

  Future<void> _verifyReturn() async {
    if (_requestData == null) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final currentUser = authProvider.user;

    if (currentUser == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You must be logged in'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    // Show condition review modal
    final verificationData = await _showConditionReviewModal(_requestData!);
    if (verificationData == null) return; // User cancelled

    setState(() {
      _isProcessing = true;
    });

    try {
      final reqProvider = Provider.of<RentalRequestProvider>(
        context,
        listen: false,
      );

      final success = await reqProvider.verifyReturn(
        widget.requestId,
        currentUser.uid,
        conditionAccepted: verificationData['conditionAccepted'] as bool,
        ownerConditionNotes: verificationData['notes'] as String?,
        ownerConditionPhotos: verificationData['photos'] as List<String>?,
        damageReport: verificationData['damageReport'] as Map<String, dynamic>?,
      );

      if (mounted) {
        setState(() {
          _isProcessing = false;
        });

        if (success) {
          final isPropertyRental =
              _requestData != null &&
              [
                'apartment',
                'boardinghouse',
                'boarding_house',
                'commercial',
              ].contains(
                (_requestData!['rentType'] as String? ?? 'item').toLowerCase(),
              );
          final conditionAccepted =
              verificationData['conditionAccepted'] as bool;

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                conditionAccepted
                    ? (isPropertyRental
                          ? 'Rental termination verified successfully! Rental completed.'
                          : 'Return verified successfully! Rental completed.')
                    : 'Damage reported. Rental is now disputed.',
              ),
              backgroundColor: conditionAccepted ? Colors.green : Colors.orange,
            ),
          );
          // Reload request to show updated status
          _loadRequest();
          // Prompt for rating only if condition accepted
          if (conditionAccepted) {
            await _promptForRating(widget.requestId);
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                reqProvider.errorMessage ?? 'Failed to verify return',
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
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
                                    fontSize: 14,
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
                                    fontSize: 12,
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

                          if (userId != null) {
                            for (final photo in selectedPhotos) {
                              try {
                                final url = await _storageService
                                    .uploadConditionPhoto(
                                      file: photo,
                                      requestId: widget.requestId,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Active Rental'),
        backgroundColor: const Color(0xFF00897B),
        foregroundColor: Colors.white,
        actions: [
          if (_requestData != null)
            IconButton(
              icon: const Icon(Icons.flag_outlined),
              onPressed: () => _showReportOptions(),
              tooltip: 'Report',
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _requestData == null
          ? const Center(child: Text('Rental not found'))
          : _buildRentalDetails(),
    );
  }

  Widget _buildRentalDetails() {
    final status = _requestData!['status'] as String? ?? 'active';
    final ownerName = _requestData!['ownerName'] as String? ?? 'Owner';
    final renterName = _requestData!['renterName'] as String? ?? 'Renter';
    final itemTitle = _requestData!['itemTitle'] as String? ?? 'Rental Item';
    final notes = _requestData!['notes'] as String? ?? '';
    final startDate = _requestData!['startDate'];
    final endDate = _requestData!['endDate'];
    final durationDays = _requestData!['durationDays'] as int? ?? 0;
    final priceQuote = (_requestData!['priceQuote'] as num?)?.toDouble() ?? 0.0;
    final depositAmount = (_requestData!['depositAmount'] as num?)?.toDouble();
    final ownerId = _requestData!['ownerId'] as String?;
    final renterId = _requestData!['renterId'] as String?;
    final isLongTerm = _requestData!['isLongTerm'] as bool? ?? false;

    // Check if current user is the owner
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final currentUserId = authProvider.user?.uid;
    final isOwner = currentUserId != null && ownerId == currentUserId;
    final isRenter = currentUserId != null && renterId == currentUserId;

    final isActive = status == 'active' || status == 'ownerapproved';
    final isReturnInitiated = status == 'returninitiated';
    final isReturned = status == 'returned';
    final isTerminated = status == 'terminated';
    final isDisputed = status == 'disputed';
    final damageReport = _requestData!['damageReport'] as Map<String, dynamic>?;
    final disputeResolution =
        _requestData!['disputeResolution'] as Map<String, dynamic>?;
    final resolutionStatus = disputeResolution?['status'] as String?;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Hero Card with Item Info and Status
          _buildHeroCard(
            itemTitle: itemTitle,
            status: status,
            isActive: isActive,
            isReturnInitiated: isReturnInitiated,
            isReturned: isReturned,
          ),
          const SizedBox(height: 16),

          // People Info Card
          _buildPeopleCard(
            isRenter: isRenter,
            isOwner: isOwner,
            ownerName: ownerName,
            renterName: renterName,
          ),
          const SizedBox(height: 16),

          // Rental Period Card
          _buildRentalPeriodCard(
            startDate: startDate,
            endDate: endDate,
            durationDays: durationDays,
          ),
          const SizedBox(height: 16),

          // Payment Information Card
          _buildPaymentInfoCard(
            priceQuote: priceQuote,
            depositAmount: depositAmount,
          ),
          const SizedBox(height: 16),

          // Monthly Payment Card (for long-term rentals)
          // Show for active, returned, or terminated rentals (to see final payment status)
          if (isLongTerm && (isActive || isReturned || isTerminated)) ...[
            _buildMonthlyPaymentCard(isOwner: isOwner),
            const SizedBox(height: 16),
            _buildMonthlyPaymentStatusTracker(),
            const SizedBox(height: 16),
            _buildPaymentHistoryCard(),
            const SizedBox(height: 16),
          ],

          // Notes Card
          if (notes.isNotEmpty) ...[
            _buildNotesCard(notes: notes),
            const SizedBox(height: 16),
          ],

          // Dispute Resolution Card
          if (isDisputed) ...[
            _buildDisputeResolutionCard(
              damageReport: damageReport,
              disputeResolution: disputeResolution,
              resolutionStatus: resolutionStatus,
              isOwner: isOwner,
            ),
            const SizedBox(height: 16),
          ],

          // Action Buttons Card
          if (isActive && !_isProcessing) ...[
            _buildActionButtonsCard(isRenter: isRenter),
          ] else if (isReturnInitiated && isRenter) ...[
            _buildStatusInfoCard(
              icon: Icons.hourglass_empty,
              title:
                  _getReturnActionText().replaceAll('Initiate ', '') +
                  ' Initiated',
              message: 'Waiting for owner to verify',
              color: Colors.orange,
            ),
          ] else if (isReturnInitiated && isOwner && !_isProcessing) ...[
            _buildVerifyReturnCard(),
          ] else if (isReturned) ...[
            _buildStatusInfoCard(
              icon: Icons.check_circle,
              title: 'Rental Completed',
              message:
                  _requestData != null &&
                      [
                        'apartment',
                        'boardinghouse',
                        'boarding_house',
                        'commercial',
                      ].contains(
                        (_requestData!['rentType'] as String? ?? 'item')
                            .toLowerCase(),
                      )
                  ? 'The rental has been completed successfully'
                  : 'The item has been returned successfully',
              color: Colors.green,
            ),
          ],
        ],
      ),
    );
  }

  // Card Builder Methods
  Widget _buildHeroCard({
    required String itemTitle,
    required String status,
    required bool isActive,
    required bool isReturnInitiated,
    required bool isReturned,
  }) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF00897B),
            const Color(0xFF00897B).withOpacity(0.8),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00897B).withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.home_outlined,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.25),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    status.toUpperCase().replaceAll('_', ' '),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              itemTitle,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
                height: 1.2,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Text(
              'Active Rental',
              style: TextStyle(
                color: Colors.white.withOpacity(0.9),
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPeopleCard({
    required bool isRenter,
    required bool isOwner,
    required String ownerName,
    required String renterName,
  }) {
    return _buildInfoCard(
      icon: Icons.people_outline,
      title: isRenter ? 'Property Owner' : 'Renter',
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF00897B).withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.person, color: Color(0xFF00897B), size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isRenter ? ownerName : renterName,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  isRenter ? 'Property Owner' : 'Current Renter',
                  style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRentalPeriodCard({
    required dynamic startDate,
    required dynamic endDate,
    required int durationDays,
  }) {
    return _buildInfoCard(
      icon: Icons.calendar_month,
      title: 'Rental Period',
      child: Column(
        children: [
          _buildInfoRow(
            icon: Icons.play_circle_outline,
            label: 'Start Date',
            value: _formatDate(startDate),
            iconColor: Colors.green,
          ),
          const SizedBox(height: 16),
          _buildInfoRow(
            icon: endDate == null
                ? Icons.all_inclusive
                : Icons.stop_circle_outlined,
            label: 'End Date',
            value: endDate == null
                ? 'Month-to-month (Ongoing)'
                : _formatDate(endDate),
            iconColor: endDate == null ? Colors.blue : Colors.orange,
            isItalic: endDate == null,
          ),
          if (durationDays > 0) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF00897B).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.access_time,
                    size: 18,
                    color: const Color(0xFF00897B),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Duration: $durationDays day${durationDays != 1 ? 's' : ''}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF00897B),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPaymentInfoCard({
    required double priceQuote,
    required double? depositAmount,
  }) {
    return _buildInfoCard(
      icon: Icons.payments_outlined,
      title: 'Payment Information',
      child: Column(
        children: [
          _buildPaymentRow('Base Price', priceQuote),
          if (depositAmount != null && depositAmount > 0) ...[
            const Divider(height: 24),
            _buildPaymentRow('Security Deposit', depositAmount),
          ],
        ],
      ),
    );
  }

  Widget _buildMonthlyPaymentCard({required bool isOwner}) {
    final monthlyAmount = (_requestData!['monthlyPaymentAmount'] as num?)
        ?.toDouble();
    final lastPaymentDate = (_requestData!['lastPaymentDate'] as Timestamp?)
        ?.toDate();
    final nextPaymentDue = (_requestData!['nextPaymentDueDate'] as Timestamp?)
        ?.toDate();
    final isOverdue =
        nextPaymentDue != null && nextPaymentDue.isBefore(DateTime.now());

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.blue[50]!, Colors.blue[100]!],
              ),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.blue[700],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.repeat,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Monthly Payment',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Recurring payment schedule',
                        style: TextStyle(fontSize: 12, color: Colors.black54),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _buildMonthlyPaymentRow(
                  'Monthly Amount',
                  _formatCurrency(monthlyAmount),
                  Icons.attach_money,
                ),
                const SizedBox(height: 16),
                _buildMonthlyPaymentRow(
                  'Last Payment',
                  _formatDateTime(lastPaymentDate),
                  Icons.payment,
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isOverdue ? Colors.red[50] : Colors.blue[50],
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isOverdue ? Colors.red[200]! : Colors.blue[200]!,
                      width: 1.5,
                    ),
                  ),
                  child: _buildMonthlyPaymentRow(
                    'Next Payment Due',
                    _formatDateTime(nextPaymentDue),
                    Icons.calendar_today,
                    isDueDate: true,
                  ),
                ),
              ],
            ),
          ),
          // Only show record payment button to owners
          if (isOwner) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isProcessing ? null : _recordMonthlyPayment,
                      icon: const Icon(Icons.payment, size: 20),
                      label: const Text(
                        'Record Monthly Payment',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00897B),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 2,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 16,
                          color: Colors.grey[600],
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Record payment after you have received it from the renter via GCash or other payment method',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey[700],
                              height: 1.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPaymentHistoryCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.purple[50],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.history,
                    color: Colors.purple[700],
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Payment History',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'All recorded payments',
                        style: TextStyle(fontSize: 12, color: Colors.black54),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (_isLoadingPayments)
            const Padding(
              padding: EdgeInsets.all(32.0),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_monthlyPayments.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.payment_outlined,
                      size: 48,
                      color: Colors.grey[400],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'No payment history yet',
                      style: TextStyle(color: Colors.grey[600], fontSize: 14),
                    ),
                  ],
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                children: _monthlyPayments.map((payment) {
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: payment.status == RentalPaymentStatus.succeeded
                            ? Colors.green[200]!
                            : Colors.orange[200]!,
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color:
                                payment.status == RentalPaymentStatus.succeeded
                                ? Colors.green[100]
                                : Colors.orange[100],
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            payment.status == RentalPaymentStatus.succeeded
                                ? Icons.check_circle
                                : Icons.pending,
                            color:
                                payment.status == RentalPaymentStatus.succeeded
                                ? Colors.green[700]
                                : Colors.orange[700],
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _formatCurrency(payment.amount),
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _formatDateTime(payment.createdAt),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color:
                                payment.status == RentalPaymentStatus.succeeded
                                ? Colors.green[100]
                                : Colors.orange[100],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            payment.status.name.toUpperCase(),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color:
                                  payment.status ==
                                      RentalPaymentStatus.succeeded
                                  ? Colors.green[900]
                                  : Colors.orange[900],
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDisputeResolutionCard({
    required Map<String, dynamic>? damageReport,
    required Map<String, dynamic>? disputeResolution,
    required String? resolutionStatus,
    required bool isOwner,
  }) {
    return _buildInfoCard(
      icon: Icons.gavel_outlined,
      title: 'Dispute Resolution',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Damage Report Section
          if (damageReport != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red[200]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.warning, color: Colors.red[700], size: 20),
                      const SizedBox(width: 8),
                      const Text(
                        'Damage Reported',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  if (damageReport['description'] != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      damageReport['description'] as String,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ],
                  if (damageReport['estimatedCost'] != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Estimated Cost: ₱${(damageReport['estimatedCost'] as num).toStringAsFixed(2)}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.red[700],
                        fontSize: 13,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          // Compensation Proposal Section
          if (disputeResolution != null &&
              disputeResolution['proposedAmount'] != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: resolutionStatus == 'proposal_pending'
                    ? Colors.blue.withOpacity(0.1)
                    : resolutionStatus == 'accepted'
                    ? Colors.green.withOpacity(0.1)
                    : resolutionStatus == 'resolved'
                    ? Colors.green.withOpacity(0.1)
                    : Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: resolutionStatus == 'proposal_pending'
                      ? Colors.blue.withOpacity(0.3)
                      : resolutionStatus == 'accepted'
                      ? Colors.green.withOpacity(0.3)
                      : resolutionStatus == 'resolved'
                      ? Colors.green.withOpacity(0.3)
                      : Colors.orange.withOpacity(0.3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        resolutionStatus == 'proposal_pending'
                            ? Icons.pending_outlined
                            : resolutionStatus == 'accepted'
                            ? Icons.check_circle
                            : resolutionStatus == 'resolved'
                            ? Icons.check_circle_outline
                            : Icons.cancel,
                        color: resolutionStatus == 'proposal_pending'
                            ? Colors.blue[700]
                            : resolutionStatus == 'accepted'
                            ? Colors.green[700]
                            : resolutionStatus == 'resolved'
                            ? Colors.green[700]
                            : Colors.orange[700],
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        resolutionStatus == 'proposal_pending'
                            ? 'Compensation Proposal'
                            : resolutionStatus == 'accepted'
                            ? 'Compensation Accepted'
                            : resolutionStatus == 'resolved'
                            ? 'Dispute Resolved'
                            : 'Compensation Rejected',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: resolutionStatus == 'proposal_pending'
                              ? Colors.blue[700]
                              : resolutionStatus == 'accepted'
                              ? Colors.green[700]
                              : resolutionStatus == 'resolved'
                              ? Colors.green[700]
                              : Colors.orange[700],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Proposed Amount: ₱${(disputeResolution['proposedAmount'] as num).toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (disputeResolution['proposalNotes'] != null &&
                      (disputeResolution['proposalNotes'] as String)
                          .isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      disputeResolution['proposalNotes'] as String,
                      style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                    ),
                  ],
                  if (resolutionStatus == 'resolved' &&
                      disputeResolution['paymentAmount'] != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Payment Recorded: ₱${(disputeResolution['paymentAmount'] as num).toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.green[700],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          // Action Buttons
          if (isOwner &&
              (disputeResolution == null ||
                  resolutionStatus == null ||
                  resolutionStatus == 'rejected')) ...[
            ElevatedButton.icon(
              onPressed: _proposeCompensation,
              icon: const Icon(Icons.attach_money, size: 18),
              label: Text(
                resolutionStatus == 'rejected'
                    ? 'Propose New Compensation'
                    : 'Propose Compensation',
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 40),
              ),
            ),
          ] else if (!isOwner && resolutionStatus == 'proposal_pending') ...[
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _rejectCompensation,
                    icon: const Icon(Icons.close, size: 18),
                    label: const Text('Reject'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _acceptCompensation,
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('Accept'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00897B),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ] else if (!isOwner && resolutionStatus == 'accepted') ...[
            ElevatedButton.icon(
              onPressed: _recordPayment,
              icon: const Icon(Icons.payment, size: 18),
              label: const Text('Record Payment'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 40),
              ),
            ),
          ] else if (!isOwner &&
              (disputeResolution == null || resolutionStatus == null)) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.hourglass_empty, color: Colors.orange[700]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Waiting for owner to propose compensation amount.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.orange[700],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _proposeCompensation() async {
    if (_requestData == null) return;

    final damageReport = _requestData!['damageReport'] as Map<String, dynamic>?;
    final estimatedCost = damageReport?['estimatedCost'] as num?;

    final amountController = TextEditingController(
      text: estimatedCost != null ? estimatedCost.toStringAsFixed(2) : '',
    );
    final notesController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Propose Compensation'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Enter the compensation amount you are proposing:',
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: amountController,
                decoration: const InputDecoration(
                  labelText: 'Compensation Amount *',
                  hintText: '0.00',
                  prefixText: '₱ ',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: notesController,
                decoration: const InputDecoration(
                  labelText: 'Notes (Optional)',
                  hintText: 'Additional information about the compensation...',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final amount = double.tryParse(amountController.text.trim());
              if (amount == null || amount <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please enter a valid amount'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }
              Navigator.pop(context, true);
            },
            child: const Text('Propose'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isProcessing = true);

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final ownerId = authProvider.user?.uid;

      if (ownerId == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('You must be logged in'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final amount = double.parse(amountController.text.trim());
      final notes = notesController.text.trim().isNotEmpty
          ? notesController.text.trim()
          : null;

      await _firestoreService.proposeRentalDisputeCompensation(
        requestId: widget.requestId,
        ownerId: ownerId,
        compensationAmount: amount,
        proposalNotes: notes,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Compensation proposal sent successfully'),
            backgroundColor: Colors.green,
          ),
        );
        _loadRequest();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _acceptCompensation() async {
    if (_requestData == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Accept Compensation?'),
        content: const Text(
          'Are you sure you want to accept this compensation proposal? You will need to record payment after accepting.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00897B),
            ),
            child: const Text('Accept'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isProcessing = true);

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final renterId = authProvider.user?.uid;

      if (renterId == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('You must be logged in'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      await _firestoreService.acceptRentalDisputeCompensation(
        requestId: widget.requestId,
        renterId: renterId,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Compensation accepted. Please record payment.'),
            backgroundColor: Colors.green,
          ),
        );
        _loadRequest();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _rejectCompensation() async {
    if (_requestData == null) return;

    final reasonController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reject Compensation?'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Are you sure you want to reject this compensation proposal?',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: reasonController,
                decoration: const InputDecoration(
                  labelText: 'Reason (Optional)',
                  hintText: 'Why are you rejecting this proposal?',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Reject'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isProcessing = true);

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final renterId = authProvider.user?.uid;

      if (renterId == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('You must be logged in'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final reason = reasonController.text.trim().isNotEmpty
          ? reasonController.text.trim()
          : null;

      await _firestoreService.rejectRentalDisputeCompensation(
        requestId: widget.requestId,
        renterId: renterId,
        rejectionReason: reason,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Compensation proposal rejected'),
            backgroundColor: Colors.orange,
          ),
        );
        _loadRequest();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _recordPayment() async {
    if (_requestData == null) return;

    final disputeResolution =
        _requestData!['disputeResolution'] as Map<String, dynamic>?;
    final proposedAmount = disputeResolution?['proposedAmount'] as num?;

    final amountController = TextEditingController(
      text: proposedAmount != null ? proposedAmount.toStringAsFixed(2) : '',
    );
    final methodController = TextEditingController(text: 'Cash');
    final notesController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Record Payment'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Record the compensation payment you made:',
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: amountController,
                decoration: const InputDecoration(
                  labelText: 'Payment Amount *',
                  hintText: '0.00',
                  prefixText: '₱ ',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: methodController,
                decoration: const InputDecoration(
                  labelText: 'Payment Method',
                  hintText: 'Cash, Bank Transfer, etc.',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: notesController,
                decoration: const InputDecoration(
                  labelText: 'Notes (Optional)',
                  hintText: 'Payment reference, transaction ID, etc.',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final amount = double.tryParse(amountController.text.trim());
              if (amount == null || amount <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please enter a valid amount'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }
              Navigator.pop(context, true);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('Record Payment'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isProcessing = true);

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final renterId = authProvider.user?.uid;

      if (renterId == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('You must be logged in'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final amount = double.parse(amountController.text.trim());
      final method = methodController.text.trim().isNotEmpty
          ? methodController.text.trim()
          : null;
      final notes = notesController.text.trim().isNotEmpty
          ? notesController.text.trim()
          : null;

      await _firestoreService.recordRentalDisputeCompensationPayment(
        requestId: widget.requestId,
        renterId: renterId,
        amount: amount,
        paymentMethod: method,
        paymentNotes: notes,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Payment recorded. Dispute resolved!'),
            backgroundColor: Colors.green,
          ),
        );
        _loadRequest();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Widget _buildNotesCard({required String notes}) {
    return _buildInfoCard(
      icon: Icons.note_outlined,
      title: 'Notes',
      child: Text(
        notes,
        style: const TextStyle(
          fontSize: 14,
          color: Colors.black87,
          height: 1.5,
        ),
      ),
    );
  }

  Widget _buildActionButtonsCard({required bool isRenter}) {
    // Check if item is overdue
    final endDate = _requestData!['endDate'] as Timestamp?;
    final isOverdue =
        endDate != null && endDate.toDate().isBefore(DateTime.now());
    final missingItemReported =
        _requestData!['missingItemReported'] as bool? ?? false;

    // Check if current user is owner
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final currentUserId = authProvider.user?.uid;
    final ownerId = _requestData!['ownerId'] as String?;
    final isOwner = currentUserId != null && ownerId == currentUserId;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: isRenter ? _messageOwner : _messageRenter,
                  icon: const Icon(Icons.message_outlined, size: 20),
                  label: const Text(
                    'Message',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF00897B),
                    side: const BorderSide(color: Color(0xFF00897B), width: 2),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              if (isRenter) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _initiateReturn,
                    icon: Icon(
                      _getReturnActionText().contains('Return')
                          ? Icons.assignment_return
                          : Icons.exit_to_app,
                      size: 20,
                    ),
                    label: Text(
                      _getReturnActionText().replaceAll('Initiate ', ''),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 2,
                    ),
                  ),
                ),
              ],
            ],
          ),
          // Show "Report Not Returned" button for owners when item is overdue
          if (isOwner && isOverdue && !missingItemReported) ...[
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _reportMissingItem,
              icon: const Icon(Icons.report_problem, size: 20),
              label: const Text(
                'Report Not Returned',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 2,
              ),
            ),
          ] else if (isOwner && missingItemReported) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange[200]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.orange[700], size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Not returned report has been submitted. Admins have been notified.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.orange[900],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildVerifyReturnCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange[200]!),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.orange[700], size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _requestData != null &&
                            [
                              'apartment',
                              'boardinghouse',
                              'boarding_house',
                              'commercial',
                            ].contains(
                              (_requestData!['rentType'] as String? ?? 'item')
                                  .toLowerCase(),
                            )
                        ? 'Renter has initiated ${_getReturnActionText().toLowerCase()}. Please verify that the property is in good condition.'
                        : 'Renter has initiated return. Please verify that you received the item in good condition.',
                    style: TextStyle(fontSize: 12, color: Colors.orange[900]),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _messageRenter,
                  icon: const Icon(Icons.message_outlined, size: 20),
                  label: const Text(
                    'Message',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF00897B),
                    side: const BorderSide(color: Color(0xFF00897B), width: 2),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _verifyReturn,
                  icon: const Icon(Icons.verified, size: 20),
                  label: Text(
                    _getVerifyButtonText(),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 2,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusInfoCard({
    required IconData icon,
    required String title,
    required String message,
    required Color color,
  }) {
    // Determine shade colors based on the base color
    Color lightShade;
    Color mediumShade;
    Color darkShade;
    Color textColor;

    if (color == Colors.orange) {
      lightShade = Colors.orange[50]!;
      mediumShade = Colors.orange[300]!;
      darkShade = Colors.orange[700]!;
      textColor = Colors.orange[900]!;
    } else if (color == Colors.green) {
      lightShade = Colors.green[50]!;
      mediumShade = Colors.green[300]!;
      darkShade = Colors.green[700]!;
      textColor = Colors.green[900]!;
    } else {
      lightShade = color.withOpacity(0.1);
      mediumShade = color.withOpacity(0.3);
      darkShade = color;
      textColor = color;
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: lightShade,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: mediumShade, width: 2),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color == Colors.orange
                  ? Colors.orange[100]!
                  : color == Colors.green
                  ? Colors.green[100]!
                  : color.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: darkShade, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  message,
                  style: TextStyle(
                    fontSize: 14,
                    color: color == Colors.orange
                        ? Colors.orange[800]!
                        : color == Colors.green
                        ? Colors.green[800]!
                        : textColor.withOpacity(0.8),
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Helper widget builders
  Widget _buildInfoCard({
    required IconData icon,
    required String title,
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00897B).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: const Color(0xFF00897B), size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
    required Color iconColor,
    bool isItalic = false,
  }) {
    return Row(
      children: [
        Icon(icon, size: 20, color: iconColor),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                  fontStyle: isItalic ? FontStyle.italic : FontStyle.normal,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPaymentRow(String label, double? amount) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 14, color: Colors.grey[800])),
          Text(
            _formatCurrency(amount),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.grey[800],
            ),
          ),
        ],
      ),
    );
  }

  /// Build monthly payment status tracker showing which months are paid/unpaid
  Widget _buildMonthlyPaymentStatusTracker() {
    if (_requestData == null) return const SizedBox.shrink();

    final startDate = _requestData!['startDate'] as Timestamp?;
    final endDate = _requestData!['endDate'] as Timestamp?;
    final actualReturnDate = _requestData!['actualReturnDate'] as Timestamp?;
    final status = (_requestData!['status'] as String? ?? '').toLowerCase();
    final monthlyAmount =
        (_requestData!['monthlyPaymentAmount'] as num?)?.toDouble() ?? 0.0;

    if (startDate == null || monthlyAmount == 0) return const SizedBox.shrink();

    // Calculate months from start date to return date (if returned), end date, or now
    final rentalStart = startDate.toDate();
    final now = DateTime.now();

    // Use actualReturnDate if rental is returned or terminated, otherwise use endDate or now
    DateTime? rentalEnd;
    if (actualReturnDate != null) {
      // Rental was returned or terminated - stop tracking at return/termination date
      rentalEnd = actualReturnDate.toDate();
    } else if (endDate != null) {
      // Has an end date (for fixed-term rentals)
      rentalEnd = endDate.toDate();
    } else {
      // Long-term rental without fixed end - use now if active, or endDate if exists
      rentalEnd = status == 'returned' ? (endDate?.toDate() ?? now) : now;
    }

    // Don't show future months - only up to return date or now, whichever is earlier
    final endDateForCalc = rentalEnd.isAfter(now) ? now : rentalEnd;

    // Generate list of months
    final months = <Map<String, dynamic>>[];
    DateTime currentMonth = DateTime(rentalStart.year, rentalStart.month, 1);
    final endMonth = DateTime(endDateForCalc.year, endDateForCalc.month, 1);

    while (currentMonth.isBefore(endMonth) ||
        currentMonth.isAtSameMomentAs(endMonth)) {
      months.add({
        'year': currentMonth.year,
        'month': currentMonth.month,
        'date': currentMonth,
      });
      currentMonth = DateTime(currentMonth.year, currentMonth.month + 1, 1);
    }

    // Map payments to months
    final paymentMonths = <String, RentalPaymentModel>{};
    for (final payment in _monthlyPayments) {
      if (payment.status == RentalPaymentStatus.succeeded) {
        final paymentDate = payment.createdAt;
        final monthKey = '${paymentDate.year}-${paymentDate.month}';
        paymentMonths[monthKey] = payment;
      }
    }

    // Determine which months are paid
    final monthStatuses = months.map((month) {
      final monthKey = '${month['year']}-${month['month']}';
      final isPaid = paymentMonths.containsKey(monthKey);
      final payment = paymentMonths[monthKey];
      return {
        'year': month['year'],
        'month': month['month'],
        'date': month['date'],
        'isPaid': isPaid,
        'payment': payment,
      };
    }).toList();

    if (monthStatuses.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.green[50]!, Colors.green[100]!],
              ),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.green[700],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.calendar_view_month,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Monthly Payment Status',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Track payment status by month',
                        style: TextStyle(fontSize: 12, color: Colors.black54),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Summary stats
                Row(
                  children: [
                    Expanded(
                      child: _buildStatusStat(
                        'Paid',
                        monthStatuses.where((m) => m['isPaid'] == true).length,
                        Colors.green,
                        Icons.check_circle,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildStatusStat(
                        'Unpaid',
                        monthStatuses.where((m) => m['isPaid'] == false).length,
                        Colors.red,
                        Icons.cancel,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                // Month list
                ...monthStatuses.map((status) {
                  final year = status['year'] as int;
                  final month = status['month'] as int;
                  final isPaid = status['isPaid'] as bool;
                  final payment = status['payment'] as RentalPaymentModel?;
                  final isOwner =
                      _requestData != null &&
                      Provider.of<AuthProvider>(
                            context,
                            listen: false,
                          ).user?.uid ==
                          _requestData!['ownerId'];

                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isPaid ? Colors.green[50] : Colors.red[50],
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isPaid ? Colors.green[200]! : Colors.red[200]!,
                        width: 1.5,
                      ),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: isPaid
                                    ? Colors.green[100]
                                    : Colors.red[100],
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                isPaid ? Icons.check_circle : Icons.pending,
                                color: isPaid
                                    ? Colors.green[700]
                                    : Colors.red[700],
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _getMonthName(month) + ' $year',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black87,
                                    ),
                                  ),
                                  if (payment != null) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      'Paid: ${_formatCurrency(payment.amount)} on ${_formatDate(payment.createdAt)}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  ] else ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      'Amount: ${_formatCurrency(monthlyAmount)}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: isPaid
                                    ? Colors.green[100]
                                    : Colors.red[100],
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                isPaid ? 'PAID' : 'UNPAID',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: isPaid
                                      ? Colors.green[900]
                                      : Colors.red[900],
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                        // Show "Mark as Paid" button for owners on unpaid months
                        if (!isPaid && isOwner) ...[
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: _isProcessing
                                  ? null
                                  : () => _markMonthAsPaid(year, month),
                              icon: const Icon(Icons.check_circle, size: 16),
                              label: const Text('Mark as Paid'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.green[700],
                                side: BorderSide(color: Colors.green[700]!),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                }).toList(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusStat(
    String label,
    int count,
    MaterialColor color,
    IconData icon,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                count.toString(),
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: color.shade700,
                ),
              ),
              Text(
                label,
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _getMonthName(int month) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return months[month - 1];
  }

  Widget _buildMonthlyPaymentRow(
    String label,
    String value,
    IconData icon, {
    bool isDueDate = false,
  }) {
    final nextDueDate = isDueDate
        ? (_requestData!['nextPaymentDueDate'] as Timestamp?)?.toDate()
        : null;
    final isOverdue =
        isDueDate &&
        nextDueDate != null &&
        nextDueDate.isBefore(DateTime.now());

    return Row(
      children: [
        Icon(icon, size: 18, color: const Color(0xFF00897B)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Colors.grey,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: isOverdue ? Colors.red[700] : Colors.grey[800],
          ),
        ),
        if (isOverdue) ...[
          const SizedBox(width: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.red[100],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'OVERDUE',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.bold,
                color: Colors.red[900],
              ),
            ),
          ),
        ],
      ],
    );
  }

  void _showReportOptions() {
    if (_requestData == null) return;

    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.flag_outlined, color: Colors.orange),
              title: const Text('Report Rental'),
              onTap: () {
                Navigator.pop(context);
                _reportRental();
              },
            ),
            ListTile(
              leading: const Icon(Icons.person_off, color: Colors.red),
              title: const Text('Report Other Party'),
              onTap: () {
                Navigator.pop(context);
                _reportOtherParty();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _reportRental() {
    if (_requestData == null) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final userProvider = Provider.of<UserProvider>(context, listen: false);

    if (authProvider.user == null) return;

    final itemTitle = _requestData!['itemTitle'] as String? ?? 'Rental Item';
    final ownerName = _requestData!['ownerName'] as String? ?? 'Owner';
    final ownerId = _requestData!['ownerId'] as String?;

    if (ownerId == null) return;

    ReportDialog.showReportContentDialog(
      context: context,
      contentType: 'rental',
      onSubmit:
          ({
            required String reason,
            String? description,
            List<String>? evidenceImageUrls,
          }) async {
            final reporterName =
                userProvider.currentUser?.fullName ??
                authProvider.user!.email ??
                'Unknown';

            await _reportBlockService.reportContent(
              reporterId: authProvider.user!.uid,
              reporterName: reporterName,
              contentType: 'rental',
              contentId: widget.requestId,
              contentTitle: itemTitle,
              ownerId: ownerId,
              ownerName: ownerName,
              reason: reason,
              description: description,
              evidenceImageUrls: evidenceImageUrls,
            );
          },
      successMessage:
          'Rental has been reported successfully. Thank you for keeping the community safe.',
      errorMessage: 'Error reporting rental',
    );
  }

  void _reportMissingItem() async {
    if (_requestData == null) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final currentUserId = authProvider.user?.uid;

    if (currentUserId == null) return;

    final ownerId = _requestData!['ownerId'] as String?;
    if (ownerId != currentUserId) {
      // Only owner can report missing items
      return;
    }

    final itemTitle = _requestData!['itemTitle'] as String? ?? 'Rental Item';
    final endDate = _requestData!['endDate'] as Timestamp?;
    final daysOverdue = endDate != null
        ? DateTime.now().difference(endDate.toDate()).inDays
        : 0;

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning, color: Colors.red, size: 28),
            SizedBox(width: 8),
            Text('Report Not Returned'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to report "$itemTitle" as missing?',
              style: const TextStyle(fontSize: 16),
            ),
            if (daysOverdue > 0) ...[
              const SizedBox(height: 12),
              Text(
                'This item is $daysOverdue ${daysOverdue == 1 ? 'day' : 'days'} overdue.',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.red[700],
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 12),
            const Text(
              'This will:\n'
              '• Notify admins immediately\n'
              '• Notify the renter\n'
              '• Create a high-priority report',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Report Not Returned'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // Show loading
    if (mounted) {
      setState(() {
        _isProcessing = true;
      });
    }

    try {
      await _firestoreService.reportMissingRentalItem(
        requestId: widget.requestId,
        ownerId: currentUserId,
        description:
            'Item "$itemTitle" has not been returned. '
            'Days overdue: $daysOverdue',
      );

      if (mounted) {
        // Reload request to update missingItemReported status
        await _loadRequest();

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Not returned report submitted successfully. Admins have been notified.',
            ),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error reporting item not returned: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  void _reportOtherParty() {
    if (_requestData == null) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final currentUserId = authProvider.user?.uid;

    if (currentUserId == null) return;

    final ownerId = _requestData!['ownerId'] as String?;
    final renterId = _requestData!['renterId'] as String?;
    final ownerName = _requestData!['ownerName'] as String? ?? 'Owner';
    final renterName = _requestData!['renterName'] as String? ?? 'Renter';

    // Determine which user to report (the other party)
    String? reportedUserId;
    String reportedUserName;

    if (currentUserId == ownerId) {
      // Current user is owner, report renter
      reportedUserId = renterId;
      reportedUserName = renterName;
    } else if (currentUserId == renterId) {
      // Current user is renter, report owner
      reportedUserId = ownerId;
      reportedUserName = ownerName;
    } else {
      return; // Should not happen
    }

    if (reportedUserId == null) return;

    ReportDialog.showReportUserDialog(
      context: context,
      reportedUserId: reportedUserId,
      reportedUserName: reportedUserName,
      contextType: 'rental',
      contextId: widget.requestId,
      onSubmit:
          ({
            required String reason,
            String? description,
            List<String>? evidenceImageUrls,
          }) async {
            final reporterName =
                userProvider.currentUser?.fullName ??
                authProvider.user!.email ??
                'Unknown';

            await _reportBlockService.reportUser(
              reporterId: authProvider.user!.uid,
              reporterName: reporterName,
              reportedUserId: reportedUserId!,
              reportedUserName: reportedUserName,
              reason: reason,
              description: description,
              contextType: 'rental',
              contextId: widget.requestId,
              evidenceImageUrls: evidenceImageUrls,
            );
          },
      successMessage:
          'User has been reported successfully. Thank you for keeping the community safe.',
      errorMessage: 'Error reporting user',
    );
  }
}
