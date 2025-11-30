import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import '../../services/firestore_service.dart';
import '../../services/pricing_service.dart';
import '../../services/report_block_service.dart';
import '../../models/rental_listing_model.dart';
import '../../models/rental_request_model.dart';
import '../../providers/rental_request_provider.dart';
import '../../providers/user_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/chat_provider.dart';
import '../user_public_profile_screen.dart';

class RentItemScreen extends StatefulWidget {
  const RentItemScreen({super.key});

  @override
  State<RentItemScreen> createState() => _RentItemScreenState();
}

class _RentItemScreenState extends State<RentItemScreen> {
  final _firestore = FirestoreService();
  final _pricing = const PricingService();
  final _reportBlockService = ReportBlockService();

  RentalListingModel? _listing;
  Map<String, dynamic>? _rawData; // Store raw data for denormalized fields
  Map<String, dynamic>? _itemData; // Fallback item data
  bool _loading = true;
  String? _error;

  DateTime? _start;
  DateTime? _end;
  Map<String, dynamic>? _quote;
  Map<String, dynamic>? _existingRequest; // Track if user already has a request
  Map<String, dynamic>?
  _occupancyInfo; // For boarding houses: current occupancy data
  int _currentImageIndex = 0;
  StreamSubscription<QuerySnapshot>? _requestSubscription;
  PaymentMethod _selectedPaymentMethod =
      PaymentMethod.meetup; // Default to meetup

  Widget _buildPageIndicator(bool isActive) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      height: 8,
      width: isActive ? 24 : 8,
      decoration: BoxDecoration(
        color: isActive ? const Color(0xFF00897B) : Colors.grey[400],
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }

  Future<void> _checkExistingRequest(String listingId, String userId) async {
    try {
      final existing = await _firestore.getExistingRentalRequest(
        listingId,
        userId,
      );
      if (mounted) {
        setState(() {
          _existingRequest = existing;
        });
      }
    } catch (e) {
      // Silently fail - allow user to proceed
    }
  }

  void _setupRequestListener(String listingId, String userId) {
    // Cancel existing subscription if any
    _requestSubscription?.cancel();

    // Listen for changes to rental requests for this listing and user
    _requestSubscription = FirebaseFirestore.instance
        .collection('rental_requests')
        .where('listingId', isEqualTo: listingId)
        .where('renterId', isEqualTo: userId)
        .where('status', whereIn: ['requested', 'ownerapproved', 'active'])
        .limit(1)
        .snapshots()
        .listen(
          (snapshot) {
            if (mounted) {
              if (snapshot.docs.isNotEmpty) {
                final data = snapshot.docs.first.data();
                data['id'] = snapshot.docs.first.id;
                setState(() {
                  _existingRequest = data;
                });
              } else {
                setState(() {
                  _existingRequest = null;
                });
              }
            }
          },
          onError: (error) {
            // Silently handle errors - don't break the UI
            print('Error listening to rental requests: $error');
          },
        );
  }

  Future<void> _loadListing(String listingId) async {
    try {
      setState(() {
        _loading = true;
        _error = null;
      });
      final data = await _firestore.getRentalListing(listingId);
      if (data == null) {
        setState(() {
          _error = 'Listing not found';
          _loading = false;
        });
        return;
      }
      setState(() {
        _listing = RentalListingModel.fromMap(data, data['id'] as String);
        _rawData = data; // Store raw data for title, ownerName, imageUrl, etc.
      });

      // Fetch item data as fallback if denormalized fields are missing
      final itemId = (data['itemId'] as String?)?.trim();
      if (itemId != null && itemId.isNotEmpty) {
        try {
          final itemRef = await _firestore.getItem(itemId);
          if (itemRef != null) {
            setState(() {
              _itemData = itemRef;
            });
          }
        } catch (e) {
          // Silently fail - denormalized data should be available
        }
      }

      // Check if current user already has a request for this listing
      final currentUserId = context.read<UserProvider>().currentUser?.uid;
      if (currentUserId != null) {
        _checkExistingRequest(listingId, currentUserId);
        // Set up real-time listener for status changes
        _setupRequestListener(listingId, currentUserId);
      }

      // Load occupancy info for boarding houses
      if (_listing?.rentType == RentalType.boardingHouse) {
        try {
          final occupancy = await _firestore.getBoardingHouseOccupancy(
            listingId,
          );
          setState(() {
            _occupancyInfo = occupancy;
          });
        } catch (e) {
          print('Error loading occupancy info: $e');
        }
      }

      setState(() {
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map && args['listingId'] is String) {
      _loadListing(args['listingId'] as String);
    } else if (_loading) {
      setState(() {
        _error = 'Missing listingId in route arguments';
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _requestSubscription?.cancel();
    super.dispose();
  }

  Future<void> _pickStart() async {
    final now = DateTime.now();
    final res = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 2),
      initialDate: _start ?? now,
    );
    if (res != null) setState(() => _start = res);
  }

  Future<void> _pickEnd() async {
    final base = _start ?? DateTime.now();
    final res = await showDatePicker(
      context: context,
      firstDate: base,
      lastDate: DateTime(base.year + 2),
      initialDate: _end ?? base.add(const Duration(days: 1)),
    );
    if (res != null) setState(() => _end = res);
  }

  void _recalculateQuote() {
    if (_listing == null || _start == null) return;

    // For long-term rentals (monthly), end date is optional
    final isLongTerm =
        _listing!.pricingMode == PricingMode.perMonth ||
        _listing!.allowMultipleRentals;

    if (!isLongTerm && _end == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select an end date')),
      );
      return;
    }

    try {
      // For long-term rentals without end date, calculate for first month only
      final endDateForQuote = _end ?? _start!.add(const Duration(days: 30));

      final q = _pricing.quote(
        listing: _listing!,
        startDate: _start!,
        endDate: endDateForQuote,
      );
      setState(() {
        _quote = q;
      });
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final reqProvider = context.watch<RentalRequestProvider>();
    final currentUserId = context.read<UserProvider>().currentUser?.uid;

    // Check if current user is the owner
    final isOwner =
        currentUserId != null &&
        _listing != null &&
        _listing!.ownerId == currentUserId;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: const Color(0xFF00897B),
        elevation: 0,
        title: const Text(
          'Rent Item',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (_listing != null && !isOwner)
            IconButton(
              icon: const Icon(Icons.flag_outlined, color: Colors.white),
              onPressed: () => _showReportOptions(),
              tooltip: 'Report',
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text(_error!))
          : _listing == null
          ? const Center(child: Text('No listing'))
          : isOwner
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.block, size: 64, color: Colors.red),
                  const SizedBox(height: 16),
                  const Text(
                    'Cannot Rent Your Own Item',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      'You cannot rent items that you have listed for rent.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Go Back'),
                  ),
                ],
              ),
            )
          : SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Item Images Gallery
                  Builder(
                    builder: (context) {
                      List<String> imageUrls = [];

                      // Try denormalized images first
                      if (_rawData?['images'] is List) {
                        imageUrls = List<String>.from(
                          _rawData!['images'] ?? [],
                        );
                      } else if (_rawData?['imageUrl'] is String) {
                        final denormImage = (_rawData!['imageUrl'] as String)
                            .trim();
                        if (denormImage.isNotEmpty) {
                          imageUrls = [denormImage];
                        }
                      }

                      // Fallback to item images
                      if (imageUrls.isEmpty && _itemData != null) {
                        final List images =
                            (_itemData!['images'] as List? ?? const []);
                        imageUrls = images
                            .map((img) => img.toString())
                            .toList();
                      }

                      if (imageUrls.isEmpty) {
                        return Container(
                          width: double.infinity,
                          height: 300,
                          decoration: BoxDecoration(
                            color: Colors.grey[200],
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Center(
                            child: Icon(
                              Icons.image_not_supported_outlined,
                              size: 64,
                              color: Colors.grey,
                            ),
                          ),
                        );
                      }

                      return Column(
                        children: [
                          Container(
                            width: double.infinity,
                            height: 300,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              color: Colors.grey[200],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: PageView.builder(
                                onPageChanged: (index) {
                                  setState(() {
                                    _currentImageIndex = index;
                                  });
                                },
                                itemCount: imageUrls.length,
                                itemBuilder: (context, index) {
                                  return Image.network(
                                    imageUrls[index],
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) {
                                      return const Center(
                                        child: Icon(
                                          Icons.image_not_supported,
                                          size: 64,
                                          color: Colors.grey,
                                        ),
                                      );
                                    },
                                  );
                                },
                              ),
                            ),
                          ),
                          if (imageUrls.length > 1) ...[
                            const SizedBox(height: 12),
                            // Page indicators (dots)
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: List.generate(
                                imageUrls.length,
                                (index) => _buildPageIndicator(
                                  index == _currentImageIndex,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Center(
                              child: Text(
                                '${_currentImageIndex + 1} of ${imageUrls.length}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                  // Item Details Card
                  Container(
                    color: Colors.white,
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Title
                        Builder(
                          builder: (context) {
                            final denormTitle = (_rawData?['title'] as String?)
                                ?.trim();
                            final title = denormTitle?.isNotEmpty == true
                                ? denormTitle!
                                : (_itemData?['title'] as String?) ??
                                      'Rental Item';
                            return Text(
                              title,
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1A1A1A),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 12),
                        // Price and Category
                        Row(
                          children: [
                            Builder(
                              builder: (context) {
                                final denormCategory =
                                    (_rawData?['category'] as String?)?.trim();
                                final category =
                                    denormCategory?.isNotEmpty == true
                                    ? denormCategory!
                                    : (_itemData?['category'] as String?) ??
                                          'Category';
                                return Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFE8F5E9),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    category,
                                    style: const TextStyle(
                                      color: Color(0xFF1B5E20),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                );
                              },
                            ),
                            const Spacer(),
                            Text(
                              _getPriceText(),
                              style: const TextStyle(
                                color: Color(0xFF00A676),
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        // Owner Information
                        InkWell(
                          onTap: _listing?.ownerId != null
                              ? () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => UserPublicProfileScreen(
                                        userId: _listing!.ownerId,
                                      ),
                                    ),
                                  );
                                }
                              : null,
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 8,
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.person_outline,
                                  size: 20,
                                  color: Colors.grey,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    (_rawData?['ownerName'] as String?)
                                            ?.trim() ??
                                        'Owner',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                      color: _listing?.ownerId != null
                                          ? const Color(0xFF00897B)
                                          : const Color(0xFF424242),
                                    ),
                                  ),
                                ),
                                if (_listing?.ownerId != null)
                                  Icon(
                                    Icons.arrow_forward_ios,
                                    size: 14,
                                    color: Colors.grey[400],
                                  ),
                              ],
                            ),
                          ),
                        ),
                        // Location
                        Builder(
                          builder: (context) {
                            final denormLocation =
                                (_rawData?['location'] as String?)?.trim();
                            final location = denormLocation?.isNotEmpty == true
                                ? denormLocation!
                                : (_itemData?['location'] as String?)?.trim();
                            if (location != null && location.isNotEmpty) {
                              return Column(
                                children: [
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.location_on_outlined,
                                        size: 20,
                                        color: Colors.grey,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          location,
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: Colors.grey[700],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              );
                            }
                            return const SizedBox.shrink();
                          },
                        ),
                        // Description
                        Builder(
                          builder: (context) {
                            final denormDescription =
                                (_rawData?['description'] as String?)?.trim();
                            final description =
                                denormDescription?.isNotEmpty == true
                                ? denormDescription!
                                : (_itemData?['description'] as String?)
                                      ?.trim();
                            if (description != null && description.isNotEmpty) {
                              return Column(
                                children: [
                                  const SizedBox(height: 16),
                                  const Divider(),
                                  const SizedBox(height: 12),
                                  Text(
                                    'Description',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.grey[800],
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    description,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey[700],
                                      height: 1.5,
                                    ),
                                  ),
                                ],
                              );
                            }
                            return const SizedBox.shrink();
                          },
                        ),
                        // Additional details per rent type (apartments, boarding, commercial)
                        if (_listing != null &&
                            _listing!.rentType != RentalType.item)
                          Column(
                            children: [
                              const SizedBox(height: 16),
                              const Divider(),
                              const SizedBox(height: 12),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  'Details',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey[800],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              if (_listing!.rentType ==
                                  RentalType.apartment) ...[
                                if (_listing!.bedrooms != null)
                                  _buildDetailRow(
                                    icon: Icons.bed,
                                    label: 'Bedrooms',
                                    value: '${_listing!.bedrooms}',
                                  ),
                                if (_listing!.bathrooms != null)
                                  _buildDetailRow(
                                    icon: Icons.bathtub_outlined,
                                    label: 'Bathrooms',
                                    value: '${_listing!.bathrooms}',
                                  ),
                                if (_listing!.floorArea != null)
                                  _buildDetailRow(
                                    icon: Icons.square_foot,
                                    label: 'Floor area',
                                    value:
                                        '${_listing!.floorArea!.toStringAsFixed(0)} sqm',
                                  ),
                                if (_listing!.utilitiesIncluded == true)
                                  _buildDetailRow(
                                    icon: Icons.electric_bolt,
                                    label: 'Utilities',
                                    value: 'Included',
                                  ),
                              ] else if (_listing!.rentType ==
                                  RentalType.boardingHouse) ...[
                                if (_listing!.numberOfRooms != null)
                                  _buildDetailRow(
                                    icon: Icons.door_front_door,
                                    label: 'Number of rooms',
                                    value: '${_listing!.numberOfRooms}',
                                  ),
                                if (_listing!.occupantsPerRoom != null)
                                  _buildDetailRow(
                                    icon: Icons.person_outline,
                                    label: 'Occupants per room',
                                    value: '${_listing!.occupantsPerRoom}',
                                  ),
                                if (_listing!.maxOccupants != null)
                                  _buildDetailRow(
                                    icon: Icons.people_outline,
                                    label: 'Max occupants',
                                    value: '${_listing!.maxOccupants}',
                                  ),
                                if (_occupancyInfo != null) ...[
                                  _buildDetailRow(
                                    icon: Icons.people,
                                    label: 'Current occupancy',
                                    value:
                                        '${_occupancyInfo!['currentOccupants']}/${_occupancyInfo!['maxOccupants']}',
                                  ),
                                  if (_occupancyInfo!['availableSlots'] !=
                                          null &&
                                      (_occupancyInfo!['availableSlots']
                                              as int) >
                                          0)
                                    _buildDetailRow(
                                      icon: Icons.event_available,
                                      label: 'Available slots',
                                      value:
                                          '${_occupancyInfo!['availableSlots']}',
                                    ),
                                  if (_occupancyInfo!['occupiedRooms'] !=
                                          null &&
                                      (_occupancyInfo!['occupiedRooms'] as List)
                                          .isNotEmpty)
                                    _buildDetailRow(
                                      icon: Icons.hotel,
                                      label: 'Occupied rooms',
                                      value:
                                          'Rooms ${(_occupancyInfo!['occupiedRooms'] as List).join(', ')}',
                                    ),
                                ],
                                if ((_listing!.genderPreference ?? '')
                                    .isNotEmpty)
                                  _buildDetailRow(
                                    icon: Icons.person_outline,
                                    label: 'Gender preference',
                                    value: _listing!.genderPreference == 'Any'
                                        ? 'Any'
                                        : _listing!.genderPreference == 'Male'
                                        ? 'Male Only'
                                        : _listing!.genderPreference == 'Female'
                                        ? 'Female Only'
                                        : _listing!.genderPreference == 'Mixed'
                                        ? 'Mixed (Male & Female)'
                                        : _listing!.genderPreference!,
                                  ),
                                if (_listing!.sharedCR == true)
                                  _buildDetailRow(
                                    icon: Icons.bathroom_outlined,
                                    label: 'Comfort room',
                                    value: 'Shared',
                                  ),
                                if (_listing!.bedSpaceAvailable == true)
                                  _buildDetailRow(
                                    icon: Icons.bed,
                                    label: 'Bed space',
                                    value: 'Available',
                                  ),
                                if (_listing!.utilitiesIncluded == true)
                                  _buildDetailRow(
                                    icon: Icons.electric_bolt,
                                    label: 'Utilities',
                                    value: 'Included',
                                  ),
                                if ((_listing!.curfewRules ?? '').isNotEmpty)
                                  _buildDetailRow(
                                    icon: Icons.schedule,
                                    label: 'Curfew',
                                    value: _listing!.curfewRules!,
                                  ),
                              ] else if (_listing!.rentType ==
                                  RentalType.commercial) ...[
                                if (_listing!.floorArea != null)
                                  _buildDetailRow(
                                    icon: Icons.square_foot,
                                    label: 'Floor area',
                                    value:
                                        '${_listing!.floorArea!.toStringAsFixed(0)} sqm',
                                  ),
                                if ((_listing!.allowedBusiness ?? '')
                                    .isNotEmpty)
                                  _buildDetailRow(
                                    icon: Icons.business_center,
                                    label: 'Allowed business',
                                    value: _listing!.allowedBusiness!,
                                  ),
                                if (_listing!.leaseTerm != null)
                                  _buildDetailRow(
                                    icon: Icons.event_note,
                                    label: 'Lease term',
                                    value: '${_listing!.leaseTerm} months',
                                  ),
                                if (_listing!.utilitiesIncluded == true)
                                  _buildDetailRow(
                                    icon: Icons.electric_bolt,
                                    label: 'Utilities',
                                    value: 'Included',
                                  ),
                              ],
                            ],
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Rental Period Card
                  Container(
                    color: Colors.white,
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Select Rental Period',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1A1A1A),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: InkWell(
                                onTap: _pickStart,
                                child: Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: Colors.grey[300]!,
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Start Date',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        _start == null
                                            ? 'Select date'
                                            : _formatDate(_start!),
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: _start == null
                                              ? Colors.grey[400]
                                              : Colors.black87,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Builder(
                                builder: (context) {
                                  // For long-term rentals, end date is optional
                                  final isLongTerm =
                                      _listing?.pricingMode ==
                                          PricingMode.perMonth ||
                                      _listing?.allowMultipleRentals == true;

                                  return InkWell(
                                    onTap: isLongTerm
                                        ? null
                                        : _pickEnd, // Disable for long-term
                                    child: Container(
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        border: Border.all(
                                          color: isLongTerm
                                              ? Colors.grey[200]!
                                              : Colors.grey[300]!,
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                        color: isLongTerm
                                            ? Colors.grey[50]
                                            : Colors.white,
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Text(
                                                'End Date',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey[600],
                                                ),
                                              ),
                                              if (isLongTerm) ...[
                                                const SizedBox(width: 4),
                                                Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 6,
                                                        vertical: 2,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: Colors.orange[100],
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          4,
                                                        ),
                                                  ),
                                                  child: Text(
                                                    'Optional',
                                                    style: TextStyle(
                                                      fontSize: 9,
                                                      color: Colors.orange[800],
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            isLongTerm && _end == null
                                                ? 'Month-to-month'
                                                : _end == null
                                                ? 'Select date'
                                                : _formatDate(_end!),
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600,
                                              color: isLongTerm && _end == null
                                                  ? const Color(0xFF00897B)
                                                  : _end == null
                                                  ? Colors.grey[400]
                                                  : Colors.black87,
                                            ),
                                          ),
                                          if (isLongTerm && _end == null)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                top: 4,
                                              ),
                                              child: Text(
                                                'Ongoing rental',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: Colors.grey[600],
                                                  fontStyle: FontStyle.italic,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _recalculateQuote,
                            icon: const Icon(Icons.calculate),
                            label: const Text('Calculate Quote'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF00897B),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Payment Method Selection (only for items, not for apartments/commercial/boarding house)
                  if (_quote != null &&
                      _listing != null &&
                      _listing!.rentType == RentalType.item) ...[
                    const SizedBox(height: 16),
                    Container(
                      color: Colors.white,
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Payment Method',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1A1A1A),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: _buildPaymentMethodOption(
                                  PaymentMethod.online,
                                  'Online Payment',
                                  Icons.payment,
                                  'Pay securely through the app',
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildPaymentMethodOption(
                                  PaymentMethod.meetup,
                                  'Meetup Payment',
                                  Icons.handshake,
                                  'Pay cash in person when meeting',
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                  // Quote Card
                  if (_quote != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      color: Colors.white,
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Rental Summary',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1A1A1A),
                            ),
                          ),
                          const SizedBox(height: 16),
                          _buildQuoteRow(
                            'Rental Duration',
                            '${_quote!['durationDays']} ${_quote!['durationDays'] == 1 ? 'day' : 'days'}',
                          ),
                          const Divider(height: 24),
                          _buildQuoteRow(
                            'Base Price',
                            '₱${(_quote!['priceQuote'] as num).toStringAsFixed(2)}',
                          ),
                          if ((_quote!['depositAmount'] as num) > 0)
                            _buildQuoteRow(
                              'Security Deposit',
                              '₱${(_quote!['depositAmount'] as num).toStringAsFixed(2)}',
                            ),
                          const Divider(height: 24),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Total Amount',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF1A1A1A),
                                ),
                              ),
                              Text(
                                '₱${(_quote!['totalDue'] as num).toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF00A676),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE3F2FD),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: const Color(0xFF2196F3),
                                width: 1,
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(
                                  Icons.info_outline,
                                  color: Color(0xFF1976D2),
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Payment Breakdown:',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF1976D2),
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        _selectedPaymentMethod ==
                                                PaymentMethod.online
                                            ? '• Base Price: Pay online via GCash or payment gateway\n'
                                                  '• Deposit: Pay online, refundable after return'
                                            : '• Base Price: Pay cash to owner during meetup\n'
                                                  '• Deposit: Pay cash to owner during meetup, refundable after return',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey[700],
                                          height: 1.4,
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
                  ],
                  // Submit Button
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed:
                            _existingRequest != null ||
                                reqProvider.isLoading ||
                                _start == null ||
                                _quote == null
                            ? null
                            : () async {
                                if (_start == null || _quote == null) return;

                                // Double-check: prevent owner from renting their own item
                                if (currentUserId != null &&
                                    _listing != null &&
                                    _listing!.ownerId == currentUserId) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'You cannot rent your own item',
                                      ),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                  return;
                                }

                                final renterId = currentUserId ?? '';

                                // Determine if this is a long-term rental (monthly)
                                // Long-term if: pricing mode is perMonth OR allowMultipleRentals is true
                                final isLongTermRental =
                                    _listing!.pricingMode ==
                                        PricingMode.perMonth ||
                                    _listing!.allowMultipleRentals;

                                // For long-term rentals, end date is optional
                                // If no end date provided, it's month-to-month
                                DateTime? endDate = _end;
                                int? durationDays;

                                if (isLongTermRental && endDate == null) {
                                  // Month-to-month rental - no fixed end date
                                  durationDays = null;
                                } else if (endDate != null) {
                                  // Calculate duration if end date is provided
                                  durationDays = _quote!['durationDays'] as int;
                                } else {
                                  // Short-term rental requires end date
                                  if (!mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Please select an end date',
                                      ),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                  return;
                                }

                                // For long-term rentals, set monthly payment info
                                double? monthlyPaymentAmount;
                                DateTime? nextPaymentDueDate;
                                if (isLongTermRental &&
                                    _listing!.pricePerMonth != null) {
                                  monthlyPaymentAmount =
                                      _listing!.pricePerMonth;
                                  // First payment due 30 days from start date
                                  nextPaymentDueDate = DateTime(
                                    _start!.year,
                                    _start!.month + 1,
                                    _start!.day,
                                  );
                                }

                                // For apartment, commercial, and boarding house, default to meetup
                                // For items, use the selected payment method
                                final paymentMethod =
                                    (_listing!.rentType ==
                                            RentalType.apartment ||
                                        _listing!.rentType ==
                                            RentalType.commercial ||
                                        _listing!.rentType ==
                                            RentalType.boardingHouse)
                                    ? PaymentMethod.meetup
                                    : _selectedPaymentMethod;

                                final id = await reqProvider.createRequest(
                                  listingId: _listing!.id,
                                  itemId: _listing!.itemId,
                                  ownerId: _listing!.ownerId,
                                  renterId: renterId,
                                  startDate: _start!,
                                  endDate:
                                      endDate, // Can be null for month-to-month
                                  durationDays:
                                      durationDays, // Can be null for month-to-month
                                  priceQuote: (_quote!['priceQuote'] as num)
                                      .toDouble(),
                                  fees: (_quote!['fees'] as num).toDouble(),
                                  totalDue: (_quote!['totalDue'] as num)
                                      .toDouble(),
                                  depositAmount:
                                      (_quote!['depositAmount'] as num)
                                          .toDouble(),
                                  // Long-term rental parameters
                                  isLongTerm: isLongTermRental,
                                  monthlyPaymentAmount: monthlyPaymentAmount,
                                  nextPaymentDueDate: nextPaymentDueDate,
                                  // Payment method
                                  paymentMethod: paymentMethod,
                                );
                                if (!mounted) return;
                                if (id != null) {
                                  // Update state to show "Requested" button
                                  setState(() {
                                    _existingRequest = {
                                      'id': id,
                                      'status': 'requested',
                                    };
                                  });

                                  // After creating the rental request, seed a chat so both parties can align
                                  try {
                                    final authProvider =
                                        Provider.of<AuthProvider>(
                                          context,
                                          listen: false,
                                        );
                                    final userProvider =
                                        Provider.of<UserProvider>(
                                          context,
                                          listen: false,
                                        );
                                    final chatProvider =
                                        Provider.of<ChatProvider>(
                                          context,
                                          listen: false,
                                        );

                                    final currentUser =
                                        userProvider.currentUser;
                                    if (currentUser != null &&
                                        authProvider.user != null) {
                                      // Get item title
                                      final denormTitle =
                                          (_rawData?['title'] as String?)
                                              ?.trim();
                                      final itemTitle =
                                          denormTitle?.isNotEmpty == true
                                          ? denormTitle!
                                          : (_itemData?['title'] as String?) ??
                                                'Rental Item';

                                      // Get owner name
                                      final ownerName =
                                          (_rawData?['ownerName'] as String?)
                                              ?.trim() ??
                                          'Owner';

                                      // Get image URL
                                      String? imageUrl;
                                      final denormImage =
                                          (_rawData?['imageUrl'] as String?)
                                              ?.trim();
                                      if (denormImage != null &&
                                          denormImage.isNotEmpty) {
                                        imageUrl = denormImage;
                                      } else if (_itemData != null) {
                                        final List images =
                                            (_itemData!['images'] as List? ??
                                            const []);
                                        imageUrl = images.isNotEmpty
                                            ? images.first.toString()
                                            : null;
                                      }

                                      // Create or get conversation
                                      final conversationId = await chatProvider
                                          .createOrGetConversation(
                                            userId1: authProvider.user!.uid,
                                            userId1Name: currentUser.fullName,
                                            userId2: _listing!.ownerId,
                                            userId2Name: ownerName,
                                            itemId: _listing!.itemId,
                                            itemTitle: itemTitle,
                                          );

                                      if (conversationId != null) {
                                        // Seed default message with optional first image of the item
                                        final String content =
                                            'I want to rent this: $itemTitle';
                                        await chatProvider.sendMessage(
                                          conversationId: conversationId,
                                          senderId: authProvider.user!.uid,
                                          senderName: currentUser.fullName,
                                          content: content,
                                          imageUrl: imageUrl,
                                        );
                                      }
                                    }
                                  } catch (_) {
                                    // best-effort; failure to seed chat shouldn't block the request
                                  }

                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Rental request submitted successfully!',
                                      ),
                                      backgroundColor: Colors.green,
                                    ),
                                  );
                                  Navigator.pop(context);
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        reqProvider.errorMessage ??
                                            'Failed to submit request',
                                      ),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _existingRequest != null
                              ? Colors.grey[400]
                              : const Color(0xFF26A69A),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: _existingRequest != null ? 0 : 2,
                        ),
                        child: reqProvider.isLoading
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
                                _existingRequest != null
                                    ? 'Requested'
                                    : 'Submit Rental Request',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  String _getPriceText() {
    if (_listing == null) return '₱0/day';
    if (_listing!.pricingMode == PricingMode.perMonth) {
      return '₱${(_listing!.pricePerMonth ?? 0).toStringAsFixed(0)}/month';
    } else if (_listing!.pricingMode == PricingMode.perWeek) {
      return '₱${(_listing!.pricePerWeek ?? 0).toStringAsFixed(0)}/week';
    } else {
      return '₱${(_listing!.pricePerDay ?? 0).toStringAsFixed(0)}/day';
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
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  Widget _buildDetailRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.teal),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[700],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1A1A1A),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuoteRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 14, color: Colors.grey[700])),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1A1A1A),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentMethodOption(
    PaymentMethod method,
    String title,
    IconData icon,
    String description,
  ) {
    final isSelected = _selectedPaymentMethod == method;
    return InkWell(
      onTap: () {
        setState(() {
          _selectedPaymentMethod = method;
        });
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(
            color: isSelected ? const Color(0xFF00897B) : Colors.grey[300]!,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
          color: isSelected
              ? const Color(0xFF00897B).withOpacity(0.05)
              : Colors.grey[50],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  icon,
                  color: isSelected
                      ? const Color(0xFF00897B)
                      : Colors.grey[600],
                  size: 24,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isSelected
                          ? const Color(0xFF00897B)
                          : Colors.grey[800],
                    ),
                  ),
                ),
                if (isSelected)
                  const Icon(
                    Icons.check_circle,
                    color: Color(0xFF00897B),
                    size: 20,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              description,
              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }

  void _showReportOptions() {
    if (_listing == null) return;

    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.flag_outlined, color: Colors.orange),
              title: const Text('Report Rental Listing'),
              onTap: () {
                Navigator.pop(context);
                _reportRentalListing();
              },
            ),
            ListTile(
              leading: const Icon(Icons.person_off, color: Colors.red),
              title: const Text('Report Owner'),
              onTap: () {
                Navigator.pop(context);
                _reportOwner();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _reportRentalListing() {
    if (_listing == null) return;

    String selectedReason = 'spam';
    final TextEditingController descriptionController = TextEditingController();

    final title =
        (_rawData?['title'] as String?)?.trim() ??
        (_itemData?['title'] as String?) ??
        'Rental Item';
    final ownerName = (_rawData?['ownerName'] as String?)?.trim() ?? 'Owner';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Report Rental Listing'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Please select a reason for reporting:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                RadioListTile<String>(
                  title: const Text('Spam'),
                  value: 'spam',
                  groupValue: selectedReason,
                  onChanged: (value) {
                    setDialogState(() {
                      selectedReason = value!;
                    });
                  },
                ),
                RadioListTile<String>(
                  title: const Text('Inappropriate Content'),
                  value: 'inappropriate_content',
                  groupValue: selectedReason,
                  onChanged: (value) {
                    setDialogState(() {
                      selectedReason = value!;
                    });
                  },
                ),
                RadioListTile<String>(
                  title: const Text('Fraud'),
                  value: 'fraud',
                  groupValue: selectedReason,
                  onChanged: (value) {
                    setDialogState(() {
                      selectedReason = value!;
                    });
                  },
                ),
                RadioListTile<String>(
                  title: const Text('Other'),
                  value: 'other',
                  groupValue: selectedReason,
                  onChanged: (value) {
                    setDialogState(() {
                      selectedReason = value!;
                    });
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Additional details (optional)',
                    hintText: 'Please provide more information...',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                // Store parent context before closing dialog
                final parentContext = context;
                Navigator.pop(parentContext);

                final authProvider = Provider.of<AuthProvider>(
                  parentContext,
                  listen: false,
                );
                final userProvider = Provider.of<UserProvider>(
                  parentContext,
                  listen: false,
                );

                if (authProvider.user == null) return;

                final reporterName =
                    userProvider.currentUser?.fullName ??
                    authProvider.user!.email ??
                    'Unknown';

                try {
                  await _reportBlockService.reportContent(
                    reporterId: authProvider.user!.uid,
                    reporterName: reporterName,
                    contentType: 'rental',
                    contentId: _listing!.id,
                    contentTitle: title,
                    ownerId: _listing!.ownerId,
                    ownerName: ownerName,
                    reason: selectedReason,
                    description: descriptionController.text.trim().isNotEmpty
                        ? descriptionController.text.trim()
                        : null,
                  );

                  if (mounted) {
                    ScaffoldMessenger.of(parentContext).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Rental listing has been reported successfully. Thank you for keeping the community safe.',
                        ),
                        backgroundColor: Colors.green,
                        duration: Duration(seconds: 3),
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(parentContext).showSnackBar(
                      SnackBar(
                        content: Text('Error reporting rental listing: $e'),
                        backgroundColor: Colors.red,
                        duration: const Duration(seconds: 3),
                      ),
                    );
                  }
                }
              },
              child: const Text(
                'Report',
                style: TextStyle(color: Colors.orange),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _reportOwner() {
    if (_listing == null) return;

    String selectedReason = 'spam';
    final TextEditingController descriptionController = TextEditingController();

    final ownerName = (_rawData?['ownerName'] as String?)?.trim() ?? 'Owner';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Report Owner'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Please select a reason for reporting:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                RadioListTile<String>(
                  title: const Text('Spam'),
                  value: 'spam',
                  groupValue: selectedReason,
                  onChanged: (value) {
                    setDialogState(() {
                      selectedReason = value!;
                    });
                  },
                ),
                RadioListTile<String>(
                  title: const Text('Harassment'),
                  value: 'harassment',
                  groupValue: selectedReason,
                  onChanged: (value) {
                    setDialogState(() {
                      selectedReason = value!;
                    });
                  },
                ),
                RadioListTile<String>(
                  title: const Text('Inappropriate Content'),
                  value: 'inappropriate_content',
                  groupValue: selectedReason,
                  onChanged: (value) {
                    setDialogState(() {
                      selectedReason = value!;
                    });
                  },
                ),
                RadioListTile<String>(
                  title: const Text('Fraud'),
                  value: 'fraud',
                  groupValue: selectedReason,
                  onChanged: (value) {
                    setDialogState(() {
                      selectedReason = value!;
                    });
                  },
                ),
                RadioListTile<String>(
                  title: const Text('Other'),
                  value: 'other',
                  groupValue: selectedReason,
                  onChanged: (value) {
                    setDialogState(() {
                      selectedReason = value!;
                    });
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Additional details (optional)',
                    hintText: 'Please provide more information...',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                // Store parent context before closing dialog
                final parentContext = context;
                Navigator.pop(parentContext);

                final authProvider = Provider.of<AuthProvider>(
                  parentContext,
                  listen: false,
                );
                final userProvider = Provider.of<UserProvider>(
                  parentContext,
                  listen: false,
                );

                if (authProvider.user == null) return;

                final reporterName =
                    userProvider.currentUser?.fullName ??
                    authProvider.user!.email ??
                    'Unknown';

                try {
                  await _reportBlockService.reportUser(
                    reporterId: authProvider.user!.uid,
                    reporterName: reporterName,
                    reportedUserId: _listing!.ownerId,
                    reportedUserName: ownerName,
                    reason: selectedReason,
                    description: descriptionController.text.trim().isNotEmpty
                        ? descriptionController.text.trim()
                        : null,
                    contextType: 'rental',
                    contextId: _listing!.id,
                  );

                  if (mounted) {
                    ScaffoldMessenger.of(parentContext).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Owner has been reported successfully. Thank you for keeping the community safe.',
                        ),
                        backgroundColor: Colors.green,
                        duration: Duration(seconds: 3),
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(parentContext).showSnackBar(
                      SnackBar(
                        content: Text('Error reporting owner: $e'),
                        backgroundColor: Colors.red,
                        duration: const Duration(seconds: 3),
                      ),
                    );
                  }
                }
              },
              child: const Text(
                'Report',
                style: TextStyle(color: Colors.orange),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
