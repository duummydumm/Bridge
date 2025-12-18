import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../services/firestore_service.dart';
import '../../services/storage_service.dart';
import '../../providers/auth_provider.dart';
import '../../providers/rental_request_provider.dart';
import '../../models/rating_model.dart';
import '../../models/rental_request_model.dart';
import '../../services/rating_service.dart';
import 'package:provider/provider.dart';
import 'active_rental_detail_screen.dart';
import 'boarding_house_renters_screen.dart';
import '../submit_rating_screen.dart';

class ActiveRentalsListScreen extends StatefulWidget {
  final bool?
  asOwner; // null = auto-detect, true = owner view, false = renter view

  const ActiveRentalsListScreen({super.key, this.asOwner});

  @override
  State<ActiveRentalsListScreen> createState() =>
      _ActiveRentalsListScreenState();
}

class _ActiveRentalsListScreenState extends State<ActiveRentalsListScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  final RatingService _ratingService = RatingService();
  final StorageService _storageService = StorageService();
  final ImagePicker _imagePicker = ImagePicker();
  List<Map<String, dynamic>> _activeRentals = [];
  bool _isLoading = true;
  bool _viewingAsOwner = false; // Track which view we're showing

  @override
  void initState() {
    super.initState();
    _loadActiveRentals();
  }

  Future<void> _loadActiveRentals() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final userId = authProvider.user?.uid;

      if (userId == null) {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
        return;
      }

      // Determine which view to show
      bool showAsOwner = widget.asOwner ?? false; // Default to renter view

      // If auto-detect (null), check which has more active rentals
      if (widget.asOwner == null) {
        final ownerRentals = await _firestoreService.getRentalRequestsByUser(
          userId,
          asOwner: true,
        );
        final renterRentals = await _firestoreService.getRentalRequestsByUser(
          userId,
          asOwner: false,
        );

        final activeOwnerRentals = ownerRentals.where((req) {
          final status = (req['status'] ?? 'requested')
              .toString()
              .toLowerCase();
          return status == 'ownerapproved' ||
              status == 'active' ||
              status == 'returninitiated';
        }).length;

        final activeRenterRentals = renterRentals.where((req) {
          final status = (req['status'] ?? 'requested')
              .toString()
              .toLowerCase();
          return status == 'ownerapproved' ||
              status == 'active' ||
              status == 'returninitiated';
        }).length;

        // Show owner view if they have more active rentals as owner
        showAsOwner = activeOwnerRentals > activeRenterRentals;
      }

      final rentRequests = await _firestoreService.getRentalRequestsByUser(
        userId,
        asOwner: showAsOwner,
      );

      // Filter for active rentals
      final activeRentals = rentRequests.where((req) {
        final status = (req['status'] ?? 'requested').toString().toLowerCase();
        return status == 'ownerapproved' ||
            status == 'active' ||
            status == 'returninitiated';
      }).toList();

      // Enrich rental data with item title and names
      final enrichedRentals = <Map<String, dynamic>>[];
      for (final rental in activeRentals) {
        final enrichedRental = Map<String, dynamic>.from(rental);

        // Get item title from listing
        final listingId = rental['listingId'] as String?;
        if (listingId != null) {
          try {
            final listing = await _firestoreService.getRentalListing(listingId);
            if (listing != null) {
              enrichedRental['itemTitle'] = listing['title'] as String?;
              // Store rental type from listing
              enrichedRental['rentType'] =
                  listing['rentType'] as String? ?? 'item';
              // Fallback to item title if listing title not available
              if (enrichedRental['itemTitle'] == null ||
                  (enrichedRental['itemTitle'] as String).isEmpty) {
                final itemId = rental['itemId'] as String?;
                if (itemId != null) {
                  final item = await _firestoreService.getItem(itemId);
                  enrichedRental['itemTitle'] = item?['title'] as String?;
                }
              }
            }
          } catch (_) {
            // Continue if listing fetch fails
          }
        }
        enrichedRental['itemTitle'] ??= 'Rental Item';
        enrichedRental['rentType'] ??= 'item';

        // Get names based on view
        if (showAsOwner) {
          // When viewing as owner, show renter name
          final renterId = rental['renterId'] as String?;
          if (renterId != null) {
            try {
              final renter = await _firestoreService.getUser(renterId);
              if (renter != null) {
                final firstName = renter['firstName'] ?? '';
                final lastName = renter['lastName'] ?? '';
                enrichedRental['renterName'] = '$firstName $lastName'.trim();
              }
            } catch (_) {
              // Continue if user fetch fails
            }
          }
          enrichedRental['renterName'] ??= 'Renter';
        } else {
          // When viewing as renter, show owner name
          final ownerId = rental['ownerId'] as String?;
          if (ownerId != null) {
            try {
              final owner = await _firestoreService.getUser(ownerId);
              if (owner != null) {
                final firstName = owner['firstName'] ?? '';
                final lastName = owner['lastName'] ?? '';
                enrichedRental['ownerName'] = '$firstName $lastName'.trim();
              }
            } catch (_) {
              // Continue if user fetch fails
            }
          }
          enrichedRental['ownerName'] ??= 'Owner';
        }

        enrichedRentals.add(enrichedRental);
      }

      // Sort by createdAt descending (most recent first)
      enrichedRentals.sort((a, b) {
        final aDate =
            (a['createdAt'] as Timestamp?)?.toDate() ?? DateTime(1970);
        final bDate =
            (b['createdAt'] as Timestamp?)?.toDate() ?? DateTime(1970);
        return bDate.compareTo(aDate);
      });

      // Group boarding houses by listingId when viewing as owner
      if (showAsOwner) {
        final groupedRentals = <String, List<Map<String, dynamic>>>{};
        final nonBoardingHouseRentals = <Map<String, dynamic>>[];

        for (final rental in enrichedRentals) {
          final rentType = (rental['rentType'] ?? 'item')
              .toString()
              .toLowerCase();
          final isBoardingHouse =
              rentType == 'boardinghouse' || rentType == 'boarding_house';
          final listingId = rental['listingId'] as String?;

          if (isBoardingHouse && listingId != null) {
            groupedRentals.putIfAbsent(listingId, () => []).add(rental);
          } else {
            nonBoardingHouseRentals.add(rental);
          }
        }

        // Create grouped cards for boarding houses
        final groupedCards = <Map<String, dynamic>>[];
        for (final entry in groupedRentals.entries) {
          final listingId = entry.key;
          final rentals = entry.value;

          // Get common info from first rental (all should have same listing)
          final firstRental = rentals.first;
          final itemTitle = firstRental['itemTitle'] ?? 'Boarding House';

          groupedCards.add({
            'type': 'boarding_house_group',
            'listingId': listingId,
            'itemTitle': itemTitle,
            'rentals': rentals,
            'renterCount': rentals.length,
          });
        }

        // Combine grouped boarding houses with other rentals
        final allCards = [...groupedCards, ...nonBoardingHouseRentals];

        // Sort: boarding house groups first, then others by date
        allCards.sort((a, b) {
          if (a['type'] == 'boarding_house_group' &&
              b['type'] != 'boarding_house_group') {
            return -1;
          }
          if (a['type'] != 'boarding_house_group' &&
              b['type'] == 'boarding_house_group') {
            return 1;
          }
          // Both same type, sort by date
          final aDate =
              (a['createdAt'] as Timestamp?)?.toDate() ??
              (a['rentals'] != null && (a['rentals'] as List).isNotEmpty
                  ? ((a['rentals'] as List).first['createdAt'] as Timestamp?)
                            ?.toDate() ??
                        DateTime(1970)
                  : DateTime(1970));
          final bDate =
              (b['createdAt'] as Timestamp?)?.toDate() ??
              (b['rentals'] != null && (b['rentals'] as List).isNotEmpty
                  ? ((b['rentals'] as List).first['createdAt'] as Timestamp?)
                            ?.toDate() ??
                        DateTime(1970)
                  : DateTime(1970));
          return bDate.compareTo(aDate);
        });

        if (mounted) {
          setState(() {
            _activeRentals = allCards;
            _viewingAsOwner = showAsOwner;
            _isLoading = false;
          });
        }
      } else {
        // For renter view, show all rentals normally
        if (mounted) {
          setState(() {
            _activeRentals = enrichedRentals;
            _viewingAsOwner = showAsOwner;
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading active rentals: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
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

  String _formatCurrency(double? amount) {
    if (amount == null) return '₱0.00';
    return '₱${amount.toStringAsFixed(2)}';
  }

  String _getStatusLabel(String status) {
    switch (status.toLowerCase()) {
      case 'ownerapproved':
        return 'Approved';
      case 'active':
        return 'Active';
      case 'returninitiated':
        return 'Return Initiated';
      case 'terminated':
        return 'Terminated';
      default:
        return status;
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'ownerapproved':
        return Colors.blue;
      case 'active':
        return Colors.green;
      case 'returninitiated':
        return Colors.orange;
      case 'terminated':
        return Colors.redAccent;
      default:
        return Colors.grey;
    }
  }

  String _getReturnActionText(Map<String, dynamic> rental) {
    final rentType = (rental['rentType'] as String? ?? 'item').toLowerCase();
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

  String _getVerifyButtonText(Map<String, dynamic> rental) {
    final rentType = (rental['rentType'] as String? ?? 'item').toLowerCase();
    switch (rentType) {
      case 'apartment':
        return 'Mark as Completed';
      case 'boardinghouse':
      case 'boarding_house':
        return 'Mark as Completed';
      case 'commercial':
      case 'commercialspace':
      case 'commercial_space':
        return 'Mark as Completed';
      default:
        return 'Mark as Returned';
    }
  }

  String _getReturnDialogTitle(Map<String, dynamic> rental) {
    final rentType = (rental['rentType'] as String? ?? 'item').toLowerCase();
    switch (rentType) {
      case 'apartment':
        return 'End Rental?';
      case 'boardinghouse':
      case 'boarding_house':
        return 'Move Out?';
      case 'commercial':
        return 'End Lease?';
      default:
        return 'Initiate Return?';
    }
  }

  String _getReturnDialogMessage(Map<String, dynamic> rental) {
    final rentType = (rental['rentType'] as String? ?? 'item').toLowerCase();
    switch (rentType) {
      case 'apartment':
        return 'Are you sure you want to end this rental? The owner will be notified to verify that the apartment is in good condition.';
      case 'boardinghouse':
      case 'boarding_house':
        return 'Are you sure you want to move out? The owner will be notified to verify that the room/space is in good condition.';
      case 'commercial':
        return 'Are you sure you want to end this lease? The owner will be notified to verify that the commercial space is in good condition.';
      default:
        return 'Are you sure you want to initiate the return? The owner will be notified to verify the return.';
    }
  }

  String _getReturnSuccessMessage(Map<String, dynamic> rental) {
    final rentType = (rental['rentType'] as String? ?? 'item').toLowerCase();
    switch (rentType) {
      case 'apartment':
        return 'Rental ending initiated successfully! Owner will verify.';
      case 'boardinghouse':
      case 'boarding_house':
        return 'Move out initiated successfully! Owner will verify.';
      case 'commercial':
        return 'Lease termination initiated successfully! Owner will verify.';
      default:
        return 'Return initiated successfully! Owner will verify.';
    }
  }

  String _getOwnerTerminateDialogTitle(Map<String, dynamic> rental) {
    final rentType = (rental['rentType'] as String? ?? 'item').toLowerCase();
    switch (rentType) {
      case 'apartment':
        return 'Force End Rental?';
      case 'boardinghouse':
      case 'boarding_house':
        return 'Force Move Out?';
      case 'commercial':
        return 'Force End Lease?';
      default:
        return 'End Rental?';
    }
  }

  String _getOwnerTerminateDialogMessage(Map<String, dynamic> rental) {
    final rentType = (rental['rentType'] as String? ?? 'item').toLowerCase();
    switch (rentType) {
      case 'apartment':
        return 'Are you sure you want to forcibly end this apartment rental? '
            'This should only be used for serious issues like non-payment or violations.';
      case 'boardinghouse':
      case 'boarding_house':
        return 'Are you sure you want to forcibly move this renter out? '
            'This should only be used for serious issues like non-payment or violations.';
      case 'commercial':
        return 'Are you sure you want to forcibly end this lease? '
            'This should only be used for serious issues like non-payment or violations.';
      default:
        return 'Are you sure you want to end this rental? '
            'This should only be used for serious issues like non-payment or violations.';
    }
  }

  String _getOwnerTerminateSuccessMessage(Map<String, dynamic> rental) {
    final rentType = (rental['rentType'] as String? ?? 'item').toLowerCase();
    switch (rentType) {
      case 'apartment':
        return 'Apartment rental has been terminated.';
      case 'boardinghouse':
      case 'boarding_house':
        return 'Boarding house rental has been terminated.';
      case 'commercial':
        return 'Commercial lease has been terminated.';
      default:
        return 'Rental has been terminated.';
    }
  }

  Future<void> _initiateReturn(String requestId) async {
    // Find the rental data
    final rental = _activeRentals.firstWhere(
      (r) => (r['id'] as String?) == requestId,
      orElse: () => <String, dynamic>{},
    );

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_getReturnDialogTitle(rental)),
        content: Text(_getReturnDialogMessage(rental)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
            child: Text(_getReturnActionText(rental)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

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

      final success = await reqProvider.initiateReturn(
        requestId,
        currentUser.uid,
      );

      if (mounted) {
        if (success) {
          // Find the rental data for success message
          final rental = _activeRentals.firstWhere(
            (r) => (r['id'] as String?) == requestId,
            orElse: () => <String, dynamic>{},
          );
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_getReturnSuccessMessage(rental)),
              backgroundColor: Colors.orange,
            ),
          );
          // Reload list to show updated status
          _loadActiveRentals();
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _verifyReturn(String requestId) async {
    // Get request data for condition review
    final requestData = await _firestoreService.getRentalRequest(requestId);
    if (requestData == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Rental request not found'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

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
    final verificationData = await _showConditionReviewModal(
      requestData,
      requestId,
    );
    if (verificationData == null) return; // User cancelled

    try {
      final reqProvider = Provider.of<RentalRequestProvider>(
        context,
        listen: false,
      );

      final success = await reqProvider.verifyReturn(
        requestId,
        currentUser.uid,
        conditionAccepted: verificationData['conditionAccepted'] as bool,
        ownerConditionNotes: verificationData['notes'] as String?,
        ownerConditionPhotos: verificationData['photos'] as List<String>?,
        damageReport: verificationData['damageReport'] as Map<String, dynamic>?,
      );

      if (mounted) {
        if (success) {
          final conditionAccepted =
              verificationData['conditionAccepted'] as bool;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                conditionAccepted
                    ? 'Return verified! Rental completed.'
                    : 'Damage reported. Rental is now disputed.',
              ),
              backgroundColor: conditionAccepted ? Colors.green : Colors.orange,
            ),
          );
          // Reload list to show updated status
          _loadActiveRentals();
          // Prompt for rating only if condition accepted
          if (conditionAccepted) {
            await _promptForRating(requestId);
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<Map<String, dynamic>?> _showConditionReviewModal(
    Map<String, dynamic> requestData,
    String requestId,
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
        return condition;
    }
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

  Future<void> _ownerTerminateRental(String requestId) async {
    // Find the rental data
    final rental = _activeRentals.firstWhere(
      (r) => (r['id'] as String?) == requestId,
      orElse: () => <String, dynamic>{},
    );

    final TextEditingController reasonController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_getOwnerTerminateDialogTitle(rental)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_getOwnerTerminateDialogMessage(rental)),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                labelText: 'Reason (optional)',
                hintText: 'e.g., Non-payment, repeated violations',
              ),
              maxLines: 2,
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
            child: const Text('Force End Rental'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

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

      final success = await reqProvider.ownerTerminateRental(
        requestId,
        currentUser.uid,
        reason: reasonController.text.trim().isEmpty
            ? null
            : reasonController.text.trim(),
      );

      if (mounted) {
        if (success) {
          final rental = _activeRentals.firstWhere(
            (r) => (r['id'] as String?) == requestId,
            orElse: () => <String, dynamic>{},
          );
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_getOwnerTerminateSuccessMessage(rental)),
              backgroundColor: Colors.redAccent,
            ),
          );
          _loadActiveRentals();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                reqProvider.errorMessage ?? 'Failed to terminate rental',
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_viewingAsOwner ? 'My Rentals' : 'Active Rentals'),
        backgroundColor: const Color(0xFF00897B),
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _activeRentals.isEmpty
          ? _buildEmptyState()
          : RefreshIndicator(
              onRefresh: _loadActiveRentals,
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _activeRentals.length,
                itemBuilder: (context, index) {
                  return _buildRentalCard(_activeRentals[index]);
                },
              ),
            ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.home_outlined, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            _viewingAsOwner ? 'No Active Rentals' : 'No Active Rentals',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _viewingAsOwner
                ? 'Items you\'ve rented out will appear here'
                : 'Your active rentals will appear here',
            style: TextStyle(color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  Widget _buildRentalCard(Map<String, dynamic> rental) {
    // Check if this is a grouped boarding house card
    if (rental['type'] == 'boarding_house_group') {
      return _buildBoardingHouseGroupCard(rental);
    }

    // Regular rental card
    final itemTitle = (rental['itemTitle'] ?? 'Rental Item').toString();
    final ownerName = (rental['ownerName'] ?? 'Owner').toString();
    final renterName = (rental['renterName'] ?? 'Renter').toString();
    final status = (rental['status'] ?? 'active').toString().toLowerCase();
    final startDate =
        (rental['startDate'] as Timestamp?)?.toDate() ?? DateTime.now();
    final endDate = (rental['endDate'] as Timestamp?)?.toDate();
    final monthlyAmount = (rental['monthlyPaymentAmount'] as num?)?.toDouble();
    final isLongTerm = rental['isLongTerm'] as bool? ?? false;
    final nextPaymentDue = (rental['nextPaymentDueDate'] as Timestamp?)
        ?.toDate();
    final requestId = rental['id'] as String? ?? '';

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: () {
          if (requestId.isNotEmpty) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) =>
                    ActiveRentalDetailScreen(requestId: requestId),
              ),
            ).then((_) {
              // Reload when returning from detail screen
              _loadActiveRentals();
            });
          }
        },
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00897B).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.home_outlined,
                      color: Color(0xFF00897B),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          itemTitle,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: _getStatusColor(status).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            _getStatusLabel(status),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _getStatusColor(status),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: Colors.grey),
                ],
              ),
              const SizedBox(height: 16),
              // Person info (Owner when viewing as renter, Renter when viewing as owner)
              Row(
                children: [
                  Icon(Icons.person, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _viewingAsOwner
                          ? 'Rented by: $renterName'
                          : 'Owner: $ownerName',
                      style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.calendar_today, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Started: ${_formatDate(startDate)}',
                      style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                    ),
                  ),
                ],
              ),
              if (endDate != null) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.event, size: 16, color: Colors.grey[600]),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Ends: ${_formatDate(endDate)}',
                        style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                      ),
                    ),
                  ],
                ),
              ] else if (isLongTerm) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.event, size: 16, color: Colors.grey[600]),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Month-to-month (Ongoing)',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[700],
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              if (isLongTerm && monthlyAmount != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.attach_money,
                        size: 18,
                        color: Colors.blue[700],
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Monthly Payment',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                            Text(
                              _formatCurrency(monthlyAmount),
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue[900],
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (nextPaymentDue != null) ...[
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              'Next Due',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey[600],
                              ),
                            ),
                            Text(
                              _formatDate(nextPaymentDue),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: nextPaymentDue.isBefore(DateTime.now())
                                    ? Colors.red[700]
                                    : Colors.blue[900],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              // Return button only for renters (not owners)
              // Owners verify returns, renters initiate them
              if (!_viewingAsOwner &&
                  (status.toLowerCase() == 'active' ||
                      status.toLowerCase() == 'ownerapproved')) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _initiateReturn(requestId),
                    icon: Icon(
                      _getReturnActionText(rental).contains('Return')
                          ? Icons.assignment_return
                          : Icons.exit_to_app,
                      size: 18,
                    ),
                    label: Text(_getReturnActionText(rental)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ],
              // Mark as Returned button for owners when return is initiated
              if (_viewingAsOwner &&
                  status.toLowerCase() == 'returninitiated') ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _verifyReturn(requestId),
                    icon: const Icon(Icons.check_circle, size: 18),
                    label: Text(_getVerifyButtonText(rental)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ],
              // Force-terminate button for owners on active/approved rentals
              if (_viewingAsOwner &&
                  (status.toLowerCase() == 'active' ||
                      status.toLowerCase() == 'ownerapproved')) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _ownerTerminateRental(requestId),
                    icon: const Icon(Icons.warning_amber_rounded, size: 18),
                    label: const Text('Force End Rental'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.redAccent,
                      side: const BorderSide(color: Colors.redAccent),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Build a grouped card for boarding house showing all renters
  Widget _buildBoardingHouseGroupCard(Map<String, dynamic> group) {
    final listingId = group['listingId'] as String? ?? '';
    final itemTitle = (group['itemTitle'] ?? 'Boarding House').toString();
    final rentals = group['rentals'] as List<Map<String, dynamic>>? ?? [];
    final renterCount = group['renterCount'] as int? ?? rentals.length;

    // Get status summary (show most critical status)
    String overallStatus = 'active';
    for (final rental in rentals) {
      final status = (rental['status'] ?? 'active').toString().toLowerCase();
      if (status == 'returninitiated') {
        overallStatus = 'returninitiated';
        break;
      } else if (status == 'ownerapproved' && overallStatus == 'active') {
        overallStatus = 'ownerapproved';
      }
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: () {
          if (listingId.isNotEmpty) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => BoardingHouseRentersScreen(
                  listingId: listingId,
                  itemTitle: itemTitle,
                ),
              ),
            ).then((_) {
              // Reload when returning from renter list
              _loadActiveRentals();
            });
          }
        },
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00897B).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.home_outlined,
                      color: Color(0xFF00897B),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          itemTitle,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: _getStatusColor(
                                  overallStatus,
                                ).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                _getStatusLabel(overallStatus),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: _getStatusColor(overallStatus),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.blue.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.people,
                                    size: 14,
                                    color: Colors.blue,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '$renterCount Renter${renterCount != 1 ? 's' : ''}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.blue,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: Colors.grey),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Tap to view all renters and manage individual rentals',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[600],
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
