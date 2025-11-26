import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:convert';
import '../../reusable_widgets/bottom_nav_bar_widget.dart';
import '../../reusable_widgets/verification_guard.dart';
import '../../providers/user_provider.dart';
import 'active_rentals_list_screen.dart';
import 'rental_history.dart';
import 'monthly_rental_tracking.dart';
import 'rental_overdue.dart';
import 'due_soon.dart';
import '../my_listings_screen.dart';

class RentItemsScreen extends StatefulWidget {
  const RentItemsScreen({super.key});

  @override
  State<RentItemsScreen> createState() => _RentItemsScreenState();
}

class _RentItemsScreenState extends State<RentItemsScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _selectedCategory = '';
  String _selectedPricingMode = '';
  String? _selectedBarangay;
  String?
  _selectedRentType; // 'item', 'apartment', 'commercial', or null for all
  double? _maxPrice;
  List<String> _barangays = [];
  bool _isFilterExpanded = false;

  final List<String> _categories = [
    'Electronics',
    'Tools',
    'Clothing',
    'Furniture',
    'Sports & Recreation',
    'Home & Garden',
    'Appliances',
    'Vehicles',
    'Commercial Rent',
    'Other',
  ];

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
    } catch (e) {
      print('Error loading barangays: $e');
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _filterListings(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    var filtered = docs;

    // Filter by search query
    if (_searchController.text.isNotEmpty) {
      final query = _searchController.text.toLowerCase();
      filtered = filtered.where((doc) {
        final listing = doc.data();
        final title = (listing['title'] ?? '').toString().toLowerCase();
        final category = (listing['category'] ?? '').toString().toLowerCase();
        final location = (listing['location'] ?? '').toString().toLowerCase();
        final description = (listing['description'] ?? '')
            .toString()
            .toLowerCase();
        return title.contains(query) ||
            category.contains(query) ||
            location.contains(query) ||
            description.contains(query);
      }).toList();
    }

    // Filter by category
    if (_selectedCategory.isNotEmpty) {
      filtered = filtered.where((doc) {
        final listing = doc.data();
        final category = (listing['category'] ?? '').toString();
        return category == _selectedCategory;
      }).toList();
    }

    // Filter by pricing mode
    if (_selectedPricingMode.isNotEmpty) {
      filtered = filtered.where((doc) {
        final listing = doc.data();
        final pricingMode = (listing['pricingMode'] ?? 'perDay').toString();
        return pricingMode.toLowerCase() == _selectedPricingMode.toLowerCase();
      }).toList();
    }

    // Filter by max price
    if (_maxPrice != null && _maxPrice! > 0) {
      filtered = filtered.where((doc) {
        final listing = doc.data();
        final pricingMode = (listing['pricingMode'] ?? 'perDay').toString();
        double? price;
        if (pricingMode == 'perMonth') {
          price = (listing['pricePerMonth'] as num?)?.toDouble();
        } else if (pricingMode == 'perWeek') {
          price = (listing['pricePerWeek'] as num?)?.toDouble();
        } else {
          price = (listing['pricePerDay'] as num?)?.toDouble();
        }
        return price != null && price <= _maxPrice!;
      }).toList();
    }

    // Filter by barangay
    if (_selectedBarangay != null && _selectedBarangay!.isNotEmpty) {
      filtered = filtered.where((doc) {
        final listing = doc.data();
        final location = (listing['location'] ?? '').toString().toLowerCase();
        return location.contains(_selectedBarangay!.toLowerCase());
      }).toList();
    }

    // Filter by rent type
    if (_selectedRentType != null && _selectedRentType!.isNotEmpty) {
      filtered = filtered.where((doc) {
        final listing = doc.data();
        final rentType = (listing['rentType'] ?? 'item')
            .toString()
            .toLowerCase();
        final selectedType = _selectedRentType!.toLowerCase();
        // Handle both 'boardinghouse' and 'boarding_house' for backward compatibility
        if (selectedType == 'boardinghouse' ||
            selectedType == 'boarding_house') {
          return rentType == 'boardinghouse' || rentType == 'boarding_house';
        }
        return rentType == selectedType;
      }).toList();
    }

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = Provider.of<UserProvider>(context).currentUser?.uid;
    final listingsQuery = FirebaseFirestore.instance
        .collection('rental_listings')
        .where('isActive', isEqualTo: true)
        .limit(50);

    // Query to get user's existing rental requests (only approved/active - not pending requests)
    // This way users can still see listings they've requested but not yet approved
    final existingRequestsQuery = currentUserId != null
        ? FirebaseFirestore.instance
              .collection('rental_requests')
              .where('renterId', isEqualTo: currentUserId)
              .where('status', whereIn: ['ownerapproved', 'active'])
              .snapshots()
        : null;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: const Color(0xFF00897B),
        elevation: 0,
        automaticallyImplyLeading: false,
        leading: Builder(
          builder: (BuildContext context) {
            return IconButton(
              icon: const Icon(Icons.menu, color: Colors.white),
              onPressed: () {
                Scaffold.of(context).openDrawer();
              },
            );
          },
        ),
        title: const Text(
          'Rent Items',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    const Color(0xFF00897B),
                    const Color(0xFF26A69A),
                    const Color(0xFF4DD0E1),
                  ],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
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
                      const SizedBox(width: 12),
                      const Text(
                        'Rental Menu',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Manage your rentals',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.pending_outlined),
              title: const Text('Pending Rent Requests'),
              onTap: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, '/rental/pending-requests');
              },
            ),
            ListTile(
              leading: const Icon(Icons.home_outlined),
              title: const Text('Active Rentals'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        const ActiveRentalsListScreen(asOwner: false),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.business_outlined),
              title: const Text('My Items Rented Out'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        const ActiveRentalsListScreen(asOwner: true),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.access_time_outlined),
              title: const Text('Due Soon'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const RentalDueSoonScreen(),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.warning_outlined),
              title: const Text('Overdue'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const RentalOverdueScreen(),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.history_outlined),
              title: const Text('Rental History'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        const RentalHistoryScreen(asOwner: null),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.calendar_month_outlined),
              title: const Text('Monthly Rental Tracking'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const MonthlyRentalTrackingScreen(),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.category_outlined),
              title: const Text('My Rental Listing'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const MyListingsScreen(initialTab: 1),
                  ),
                );
              },
            ),
          ],
        ),
      ),
      body: VerificationGuard(
        child: Column(
          children: [
            // Search and Filter Bar
            Container(
              color: Colors.white,
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // Search Bar with Filter Toggle
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            hintText: 'Search items to rent...',
                            prefixIcon: const Icon(
                              Icons.search,
                              color: Colors.grey,
                            ),
                            suffixIcon: _searchController.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(
                                      Icons.clear,
                                      color: Colors.grey,
                                    ),
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() {});
                                    },
                                  )
                                : null,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            filled: true,
                            fillColor: Colors.grey[100],
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                          ),
                          onChanged: (value) {
                            setState(() {});
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Filter Toggle Button
                      Container(
                        decoration: BoxDecoration(
                          color: _isFilterExpanded
                              ? const Color(0xFF00897B)
                              : Colors.grey[200],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: IconButton(
                          icon: Icon(
                            _isFilterExpanded
                                ? Icons.filter_alt
                                : Icons.filter_alt_outlined,
                            color: _isFilterExpanded
                                ? Colors.white
                                : Colors.grey[700],
                          ),
                          onPressed: () {
                            setState(() {
                              _isFilterExpanded = !_isFilterExpanded;
                            });
                          },
                          tooltip: _isFilterExpanded
                              ? 'Hide Filters'
                              : 'Show Filters',
                        ),
                      ),
                    ],
                  ),
                  // Collapsible Filter Section
                  AnimatedSize(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                    child: _isFilterExpanded
                        ? Column(
                            children: [
                              const SizedBox(height: 12),
                              // Rental Type Filter
                              DropdownButtonFormField<String>(
                                value: _selectedRentType,
                                decoration: InputDecoration(
                                  labelText: 'Rental Type',
                                  prefixIcon: const Icon(
                                    Icons.category_outlined,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  filled: true,
                                  fillColor: Colors.grey[100],
                                ),
                                hint: const Text('All Types'),
                                items: [
                                  const DropdownMenuItem<String>(
                                    value: null,
                                    child: Text('All Types'),
                                  ),
                                  const DropdownMenuItem<String>(
                                    value: 'item',
                                    child: Text('Item'),
                                  ),
                                  const DropdownMenuItem<String>(
                                    value: 'apartment',
                                    child: Text('Apartment'),
                                  ),
                                  const DropdownMenuItem<String>(
                                    value: 'boardinghouse',
                                    child: Text('Boarding House'),
                                  ),
                                  const DropdownMenuItem<String>(
                                    value: 'commercial',
                                    child: Text('Commercial Space'),
                                  ),
                                ],
                                onChanged: (value) {
                                  setState(() {
                                    _selectedRentType = value;
                                  });
                                },
                              ),
                              const SizedBox(height: 12),
                              // Barangay Filter Dropdown
                              DropdownButtonFormField<String>(
                                value: _selectedBarangay,
                                decoration: InputDecoration(
                                  labelText: 'Filter by Barangay',
                                  prefixIcon: const Icon(Icons.location_on),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  filled: true,
                                  fillColor: Colors.grey[100],
                                ),
                                hint: const Text('All Barangays'),
                                items: [
                                  const DropdownMenuItem<String>(
                                    value: null,
                                    child: Text('All Barangays'),
                                  ),
                                  ..._barangays.map((barangay) {
                                    return DropdownMenuItem<String>(
                                      value: barangay,
                                      child: Text(barangay),
                                    );
                                  }),
                                ],
                                onChanged: (value) {
                                  setState(() {
                                    _selectedBarangay = value;
                                  });
                                },
                              ),
                              const SizedBox(height: 12),
                              // Category Filter
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: [
                                    _buildFilterChip(
                                      'All Categories',
                                      _selectedCategory.isEmpty,
                                      () {
                                        setState(() {
                                          _selectedCategory = '';
                                        });
                                      },
                                    ),
                                    const SizedBox(width: 8),
                                    ..._categories.map((category) {
                                      final isSelected =
                                          _selectedCategory == category;
                                      return Padding(
                                        padding: const EdgeInsets.only(
                                          right: 8,
                                        ),
                                        child: _buildFilterChip(
                                          category,
                                          isSelected,
                                          () {
                                            setState(() {
                                              _selectedCategory = isSelected
                                                  ? ''
                                                  : category;
                                            });
                                          },
                                        ),
                                      );
                                    }),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),
                              // Pricing Mode Filter
                              Row(
                                children: [
                                  Expanded(
                                    child: _buildFilterChip(
                                      'All Pricing',
                                      _selectedPricingMode.isEmpty,
                                      () {
                                        setState(() {
                                          _selectedPricingMode = '';
                                        });
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: _buildFilterChip(
                                      'Per Day',
                                      _selectedPricingMode == 'perDay',
                                      () {
                                        setState(() {
                                          _selectedPricingMode =
                                              _selectedPricingMode == 'perDay'
                                              ? ''
                                              : 'perDay';
                                        });
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: _buildFilterChip(
                                      'Per Week',
                                      _selectedPricingMode == 'perWeek',
                                      () {
                                        setState(() {
                                          _selectedPricingMode =
                                              _selectedPricingMode == 'perWeek'
                                              ? ''
                                              : 'perWeek';
                                        });
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: _buildFilterChip(
                                      'Per Month',
                                      _selectedPricingMode == 'perMonth',
                                      () {
                                        setState(() {
                                          _selectedPricingMode =
                                              _selectedPricingMode == 'perMonth'
                                              ? ''
                                              : 'perMonth';
                                        });
                                      },
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              // Price Range Filter
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Max Price: ${_maxPrice != null && _maxPrice! > 0 ? '₱${_maxPrice!.toStringAsFixed(0)}' : 'Any'}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 120,
                                    child: TextField(
                                      decoration: InputDecoration(
                                        hintText: 'Max price',
                                        prefixText: '₱ ',
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          borderSide: BorderSide(
                                            color: Colors.grey[300]!,
                                          ),
                                        ),
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 8,
                                            ),
                                      ),
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                            decimal: true,
                                          ),
                                      onChanged: (value) {
                                        setState(() {
                                          _maxPrice = double.tryParse(value);
                                          if (_maxPrice != null &&
                                              _maxPrice! <= 0) {
                                            _maxPrice = null;
                                          }
                                        });
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
            // Listings
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: listingsQuery.snapshots(),
                builder: (context, snapshot) {
                  // Get existing approved/active requests to filter out listings
                  // (We don't filter 'requested' status so users can see their pending requests)
                  return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: existingRequestsQuery,
                    builder: (context, requestsSnapshot) {
                      // Build set of listing IDs that user already has requests for
                      final Set<String> requestedListingIds = {};
                      if (requestsSnapshot.hasData &&
                          requestsSnapshot.data != null) {
                        for (final doc in requestsSnapshot.data!.docs) {
                          final listingId = doc.data()['listingId'] as String?;
                          if (listingId != null) {
                            requestedListingIds.add(listingId);
                          }
                        }
                      }
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.inventory_2_outlined,
                                size: 64,
                                color: Colors.grey[400],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No rental listings available',
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Be the first to create a rental listing!',
                                style: TextStyle(
                                  color: Colors.grey[500],
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      // Filter out listings owned by the current user
                      final allDocs = snapshot.data!.docs;
                      var docs = currentUserId != null
                          ? allDocs.where((doc) {
                              final listing = doc.data();
                              final ownerId = (listing['ownerId'] ?? '')
                                  .toString();
                              return ownerId != currentUserId;
                            }).toList()
                          : allDocs;

                      // Filter out listings where user already has a request (requested, approved, or active)
                      if (currentUserId != null &&
                          requestedListingIds.isNotEmpty) {
                        docs = docs.where((doc) {
                          final listingId = doc.id;
                          return !requestedListingIds.contains(listingId);
                        }).toList();
                      }

                      // Apply filters
                      docs = _filterListings(docs);

                      if (docs.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.search_off,
                                size: 64,
                                color: Colors.grey[400],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No listings found',
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Try adjusting your search or filters',
                                style: TextStyle(
                                  color: Colors.grey[500],
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      // Group listings by rentType (fallback to 'item' if no rentType)
                      final Map<
                        String,
                        List<QueryDocumentSnapshot<Map<String, dynamic>>>
                      >
                      groupedListings = {
                        'item': [],
                        'apartment': [],
                        'boarding_house': [],
                        'commercial': [],
                      };

                      for (final doc in docs) {
                        final listing = doc.data();
                        final rentType = (listing['rentType'] ?? 'item')
                            .toString()
                            .toLowerCase();
                        // Handle both 'boardinghouse' and 'boarding_house'
                        final normalizedType =
                            (rentType == 'boardinghouse' ||
                                rentType == 'boarding_house')
                            ? 'boarding_house'
                            : (rentType == 'apartment' ||
                                      rentType == 'commercial'
                                  ? rentType
                                  : 'item');
                        groupedListings[normalizedType]?.add(doc);
                      }

                      // Build sections for each type
                      final sections = <Widget>[];

                      // Items - Grid View
                      if (groupedListings['item']!.isNotEmpty) {
                        sections.add(
                          _buildSectionHeader(
                            'Items',
                            groupedListings['item']!.length,
                          ),
                        );
                        sections.add(
                          _buildItemsGridView(
                            groupedListings['item']!,
                            currentUserId,
                            requestedListingIds,
                          ),
                        );
                      }

                      // Apartments - Card List
                      if (groupedListings['apartment']!.isNotEmpty) {
                        sections.add(
                          _buildSectionHeader(
                            'Apartments',
                            groupedListings['apartment']!.length,
                          ),
                        );
                        sections.add(
                          _buildApartmentsCardList(
                            groupedListings['apartment']!,
                            currentUserId,
                            requestedListingIds,
                          ),
                        );
                      }

                      // Boarding Houses - Card List
                      if (groupedListings['boarding_house']!.isNotEmpty) {
                        sections.add(
                          _buildSectionHeader(
                            'Boarding Houses',
                            groupedListings['boarding_house']!.length,
                          ),
                        );
                        sections.add(
                          _buildBoardingHousesCardList(
                            groupedListings['boarding_house']!,
                            currentUserId,
                            requestedListingIds,
                          ),
                        );
                      }

                      // Commercial Spaces - Business-style Cards
                      if (groupedListings['commercial']!.isNotEmpty) {
                        sections.add(
                          _buildSectionHeader(
                            'Commercial Spaces',
                            groupedListings['commercial']!.length,
                          ),
                        );
                        sections.add(
                          _buildCommercialBusinessCards(
                            groupedListings['commercial']!,
                            currentUserId,
                            requestedListingIds,
                          ),
                        );
                      }

                      if (sections.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.search_off,
                                size: 64,
                                color: Colors.grey[400],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No listings found',
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      return ListView(
                        padding: const EdgeInsets.all(12),
                        children: sections,
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavBarWidget(
        selectedIndex: 1, // Exchange tab (Rent is part of Exchange)
        onTap: (_) {},
        navigationContext: context,
      ),
    );
  }

  Widget _buildSectionHeader(String title, int count) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFF00897B),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF00897B).withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$count',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF00897B),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemsGridView(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    String? currentUserId,
    Set<String> requestedListingIds,
  ) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisExtent: 320,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: docs.length,
      itemBuilder: (context, index) {
        final doc = docs[index];
        final listing = doc.data();
        final listingId = doc.id;
        final itemId = (listing['itemId'] ?? '').toString();
        final pricePerDay = (listing['pricePerDay'] as num?)?.toDouble();
        final pricePerWeek = (listing['pricePerWeek'] as num?)?.toDouble();
        final pricePerMonth = (listing['pricePerMonth'] as num?)?.toDouble();
        final pricingMode = (listing['pricingMode'] ?? 'perDay').toString();
        final isActive = (listing['isActive'] ?? true) == true;

        final itemRef = FirebaseFirestore.instance
            .collection('items')
            .doc(itemId);

        return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          future: itemRef.get(),
          builder: (context, itemSnap) {
            final isLoading =
                itemSnap.connectionState == ConnectionState.waiting;
            final itemData = itemSnap.data?.data();
            final denormTitle = (listing['title'] as String?)?.trim();
            final denormCategory = (listing['category'] as String?)?.trim();
            final denormImage = (listing['imageUrl'] as String?)?.trim();
            final denormLocation = (listing['location'] as String?)?.trim();

            final title = denormTitle?.isNotEmpty == true
                ? denormTitle!
                : (itemData != null ? (itemData['title'] ?? 'Item') : 'Item');
            final category = denormCategory?.isNotEmpty == true
                ? denormCategory!
                : (itemData != null
                      ? (itemData['category'] ?? 'Category')
                      : 'Category');
            String? imageUrl;
            if (denormImage != null && denormImage.isNotEmpty) {
              imageUrl = denormImage;
            } else if (itemData != null) {
              final List images = (itemData['images'] as List? ?? const []);
              imageUrl = images.isNotEmpty ? images.first.toString() : null;
            }
            final location = denormLocation?.isNotEmpty == true
                ? denormLocation!
                : (itemData != null ? (itemData['location'] ?? '') : '');

            return InkWell(
              onTap: isLoading
                  ? null
                  : () {
                      Navigator.pushNamed(
                        context,
                        '/rental/rent-item',
                        arguments: {'listingId': listingId},
                      );
                    },
              borderRadius: BorderRadius.circular(16),
              child: Container(
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
                    Stack(
                      children: [
                        Container(
                          height: 180,
                          decoration: BoxDecoration(
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(16),
                              topRight: Radius.circular(16),
                            ),
                            color: Colors.grey[200],
                          ),
                          child: imageUrl != null && imageUrl.isNotEmpty
                              ? ClipRRect(
                                  borderRadius: const BorderRadius.only(
                                    topLeft: Radius.circular(16),
                                    topRight: Radius.circular(16),
                                  ),
                                  child: CachedNetworkImage(
                                    imageUrl: imageUrl,
                                    fit: BoxFit.cover,
                                    width: double.infinity,
                                    height: 180,
                                    placeholder: (context, url) => Container(
                                      color: Colors.grey[200],
                                      child: const Center(
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      ),
                                    ),
                                    errorWidget: (context, url, error) =>
                                        Container(
                                          color: Colors.grey[200],
                                          child: const Center(
                                            child: Icon(
                                              Icons
                                                  .image_not_supported_outlined,
                                              size: 48,
                                              color: Colors.grey,
                                            ),
                                          ),
                                        ),
                                  ),
                                )
                              : const Center(
                                  child: Icon(
                                    Icons.image_not_supported_outlined,
                                    size: 48,
                                    color: Colors.grey,
                                  ),
                                ),
                        ),
                        Positioned(
                          right: 12,
                          top: 12,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: isActive
                                  ? const Color(0xFF2ECC71)
                                  : Colors.grey,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              isActive ? 'available' : 'inactive',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Title and Price Row
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Title
                                Expanded(
                                  child: Text(
                                    title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      height: 1.3,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                // Price
                                Text(
                                  pricingMode == 'perMonth'
                                      ? '₱${(pricePerMonth ?? 0).toStringAsFixed(0)}/mo'
                                      : pricingMode == 'perWeek'
                                      ? '₱${(pricePerWeek ?? 0).toStringAsFixed(0)}/wk'
                                      : '₱${(pricePerDay ?? 0).toStringAsFixed(0)}/day',
                                  style: const TextStyle(
                                    color: Color(0xFF00A676),
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            // Category and Location Row
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                // Category Badge
                                Flexible(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFE8F5E9),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      category,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Color(0xFF1B5E20),
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                                if (location.isNotEmpty) ...[
                                  const SizedBox(width: 8),
                                  // Location
                                  Flexible(
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.location_on_outlined,
                                          size: 13,
                                          color: Colors.teal,
                                        ),
                                        const SizedBox(width: 4),
                                        Flexible(
                                          child: Text(
                                            location,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: Colors.grey[700],
                                              fontSize: 11,
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
                            const Spacer(),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildApartmentsCardList(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    String? currentUserId,
    Set<String> requestedListingIds,
  ) {
    return Column(
      children: docs.map((doc) {
        final listing = doc.data();
        final listingId = doc.id;
        final title = (listing['title'] ?? 'Apartment').toString();
        final address = (listing['address'] ?? listing['location'] ?? '')
            .toString();
        final bedrooms = listing['bedrooms'] as int?;
        final bathrooms = listing['bathrooms'] as int?;
        final floorArea = (listing['floorArea'] as num?)?.toDouble();
        final pricePerMonth = (listing['pricePerMonth'] as num?)?.toDouble();
        final imageUrl = (listing['imageUrl'] as String?)?.trim();
        final utilitiesIncluded =
            listing['utilitiesIncluded'] as bool? ?? false;

        return _buildApartmentCard(
          listingId: listingId,
          title: title,
          address: address,
          bedrooms: bedrooms,
          bathrooms: bathrooms,
          floorArea: floorArea,
          pricePerMonth: pricePerMonth,
          imageUrl: imageUrl,
          utilitiesIncluded: utilitiesIncluded,
        );
      }).toList(),
    );
  }

  Widget _buildBoardingHousesCardList(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    String? currentUserId,
    Set<String> requestedListingIds,
  ) {
    return Column(
      children: docs.map((doc) {
        final listing = doc.data();
        final listingId = doc.id;
        final title = (listing['title'] ?? 'Boarding House').toString();
        final address = (listing['address'] ?? listing['location'] ?? '')
            .toString();
        final maxOccupants = listing['maxOccupants'] as int?;
        final sharedCR = listing['sharedCR'] as bool? ?? false;
        final bedSpaceAvailable =
            listing['bedSpaceAvailable'] as bool? ?? false;
        final utilitiesIncluded =
            listing['utilitiesIncluded'] as bool? ?? false;
        final pricePerMonth = (listing['pricePerMonth'] as num?)?.toDouble();
        final imageUrl = (listing['imageUrl'] as String?)?.trim();

        return _buildBoardingHouseCard(
          listingId: listingId,
          title: title,
          address: address,
          maxOccupants: maxOccupants,
          sharedCR: sharedCR,
          bedSpaceAvailable: bedSpaceAvailable,
          utilitiesIncluded: utilitiesIncluded,
          pricePerMonth: pricePerMonth,
          imageUrl: imageUrl,
        );
      }).toList(),
    );
  }

  Widget _buildCommercialBusinessCards(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    String? currentUserId,
    Set<String> requestedListingIds,
  ) {
    return Column(
      children: docs.map((doc) {
        final listing = doc.data();
        final listingId = doc.id;
        final title = (listing['title'] ?? 'Commercial Space').toString();
        final address = (listing['address'] ?? listing['location'] ?? '')
            .toString();
        final floorArea = (listing['floorArea'] as num?)?.toDouble();
        final allowedBusiness = (listing['allowedBusiness'] ?? '').toString();
        final leaseTerm = listing['leaseTerm'] as int?;
        final pricePerMonth = (listing['pricePerMonth'] as num?)?.toDouble();
        final imageUrl = (listing['imageUrl'] as String?)?.trim();

        return _buildCommercialCard(
          listingId: listingId,
          title: title,
          address: address,
          floorArea: floorArea,
          allowedBusiness: allowedBusiness,
          leaseTerm: leaseTerm,
          pricePerMonth: pricePerMonth,
          imageUrl: imageUrl,
        );
      }).toList(),
    );
  }

  Widget _buildApartmentCard({
    required String listingId,
    required String title,
    required String address,
    int? bedrooms,
    int? bathrooms,
    double? floorArea,
    double? pricePerMonth,
    String? imageUrl,
    bool utilitiesIncluded = false,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () {
          Navigator.pushNamed(
            context,
            '/rental/rent-item',
            arguments: {'listingId': listingId},
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image
            if (imageUrl != null && imageUrl.isNotEmpty)
              ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(12),
                ),
                child: CachedNetworkImage(
                  imageUrl: imageUrl,
                  height: 200,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Container(
                    height: 200,
                    color: Colors.grey[200],
                    child: const Center(child: CircularProgressIndicator()),
                  ),
                  errorWidget: (context, url, error) => Container(
                    height: 200,
                    color: Colors.grey[200],
                    child: const Icon(
                      Icons.home_outlined,
                      size: 48,
                      color: Colors.grey,
                    ),
                  ),
                ),
              )
            else
              Container(
                height: 200,
                color: Colors.grey[200],
                child: const Center(
                  child: Icon(
                    Icons.home_outlined,
                    size: 48,
                    color: Colors.grey,
                  ),
                ),
              ),
            // Content
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if (pricePerMonth != null)
                        Text(
                          '₱${pricePerMonth.toStringAsFixed(0)}/mo',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF00A676),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (address.isNotEmpty)
                    Row(
                      children: [
                        const Icon(
                          Icons.location_on,
                          size: 16,
                          color: Colors.teal,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            address,
                            style: TextStyle(
                              color: Colors.grey[700],
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      if (bedrooms != null) ...[
                        _buildInfoChip('$bedrooms BR', Icons.bed),
                        const SizedBox(width: 8),
                      ],
                      if (bathrooms != null) ...[
                        _buildInfoChip('$bathrooms BA', Icons.bathtub_outlined),
                        const SizedBox(width: 8),
                      ],
                      if (floorArea != null)
                        _buildInfoChip(
                          '${floorArea.toStringAsFixed(0)} sqm',
                          Icons.square_foot,
                        ),
                    ],
                  ),
                  if (utilitiesIncluded) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.check_circle,
                          size: 16,
                          color: Colors.green[700],
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Utilities Included',
                          style: TextStyle(
                            color: Colors.green[700],
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBoardingHouseCard({
    required String listingId,
    required String title,
    required String address,
    int? maxOccupants,
    bool sharedCR = false,
    bool bedSpaceAvailable = false,
    bool utilitiesIncluded = false,
    double? pricePerMonth,
    String? imageUrl,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () {
          Navigator.pushNamed(
            context,
            '/rental/rent-item',
            arguments: {'listingId': listingId},
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image
            if (imageUrl != null && imageUrl.isNotEmpty)
              ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(12),
                ),
                child: CachedNetworkImage(
                  imageUrl: imageUrl,
                  height: 200,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Container(
                    height: 200,
                    color: Colors.grey[200],
                    child: const Center(child: CircularProgressIndicator()),
                  ),
                  errorWidget: (context, url, error) => Container(
                    height: 200,
                    color: Colors.grey[200],
                    child: const Icon(
                      Icons.hotel_outlined,
                      size: 48,
                      color: Colors.grey,
                    ),
                  ),
                ),
              )
            else
              Container(
                height: 200,
                color: Colors.grey[200],
                child: const Center(
                  child: Icon(
                    Icons.hotel_outlined,
                    size: 48,
                    color: Colors.grey,
                  ),
                ),
              ),
            // Content
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if (pricePerMonth != null)
                        Text(
                          '₱${pricePerMonth.toStringAsFixed(0)}/mo',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF00A676),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (address.isNotEmpty)
                    Row(
                      children: [
                        const Icon(
                          Icons.location_on,
                          size: 16,
                          color: Colors.teal,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            address,
                            style: TextStyle(
                              color: Colors.grey[700],
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (maxOccupants != null)
                        _buildInfoChip(
                          'Max $maxOccupants',
                          Icons.people_outline,
                        ),
                      if (sharedCR)
                        _buildInfoChip('Shared CR', Icons.bathroom_outlined),
                      if (bedSpaceAvailable)
                        _buildInfoChip('Bed Space', Icons.bed),
                      if (utilitiesIncluded)
                        _buildInfoChip('Utilities', Icons.power),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCommercialCard({
    required String listingId,
    required String title,
    required String address,
    double? floorArea,
    String allowedBusiness = '',
    int? leaseTerm,
    double? pricePerMonth,
    String? imageUrl,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: Colors.white,
      child: InkWell(
        onTap: () {
          Navigator.pushNamed(
            context,
            '/rental/rent-item',
            arguments: {'listingId': listingId},
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image
            if (imageUrl != null && imageUrl.isNotEmpty)
              ClipRRect(
                borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(12),
                ),
                child: CachedNetworkImage(
                  imageUrl: imageUrl,
                  width: 140,
                  height: 140,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Container(
                    width: 140,
                    height: 140,
                    color: Colors.grey[200],
                    child: const Center(child: CircularProgressIndicator()),
                  ),
                  errorWidget: (context, url, error) => Container(
                    width: 140,
                    height: 140,
                    color: Colors.grey[200],
                    child: const Icon(
                      Icons.business_outlined,
                      size: 48,
                      color: Colors.grey,
                    ),
                  ),
                ),
              )
            else
              Container(
                width: 140,
                height: 140,
                color: Colors.grey[200],
                child: const Center(
                  child: Icon(
                    Icons.business_outlined,
                    size: 48,
                    color: Colors.grey,
                  ),
                ),
              ),
            // Content
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF00897B).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'COMMERCIAL',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF00897B),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (address.isNotEmpty)
                      Row(
                        children: [
                          const Icon(
                            Icons.location_on,
                            size: 16,
                            color: Colors.teal,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              address,
                              style: TextStyle(
                                color: Colors.grey[700],
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        if (floorArea != null) ...[
                          _buildInfoChip(
                            '${floorArea.toStringAsFixed(0)} sqm',
                            Icons.square_foot,
                          ),
                          const SizedBox(width: 8),
                        ],
                        if (allowedBusiness.isNotEmpty)
                          _buildInfoChip(
                            allowedBusiness,
                            Icons.business_center,
                          ),
                      ],
                    ),
                    if (leaseTerm != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Lease: $leaseTerm months',
                        style: TextStyle(color: Colors.grey[600], fontSize: 12),
                      ),
                    ],
                    const SizedBox(height: 8),
                    if (pricePerMonth != null)
                      Text(
                        '₱${pricePerMonth.toStringAsFixed(0)}/month',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF00A676),
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

  Widget _buildInfoChip(String label, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.grey[700]),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[700],
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, bool isSelected, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF00897B) : Colors.grey[100],
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? const Color(0xFF00897B) : Colors.grey[300]!,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.grey[700],
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
