import 'package:bridge_app/screens/my_listings_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import '../../models/giveaway_listing_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/giveaway_provider.dart';
import '../../providers/calamity_provider.dart';
import '../../models/calamity_event_model.dart';
import '../../reusable_widgets/bottom_nav_bar_widget.dart';
import '../../reusable_widgets/verification_guard.dart';
import 'pending_claims.dart';
import 'approved_claims.dart';
import 'completed_donations.dart';

class GiveawaysScreen extends StatefulWidget {
  const GiveawaysScreen({super.key});

  @override
  State<GiveawaysScreen> createState() => _GiveawaysScreenState();
}

class _GiveawaysScreenState extends State<GiveawaysScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  String _selectedCategory = 'All';
  String? _selectedBarangay;
  late TabController _tabController;
  List<String> _barangays = [];
  bool _isFilterExpanded = false;

  final List<String> _categories = [
    'All',
    'Electronics',
    'Tools',
    'Furniture',
    'Clothing',
    'Books',
    'Toys',
    'Appliances',
    'Others',
  ];

  static const Color _primaryColor = Color(0xFF2A7A9E);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_handleTabChange);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final giveawayProvider = Provider.of<GiveawayProvider>(
        context,
        listen: false,
      );
      giveawayProvider.loadActiveGiveaways();
      final calamityProvider = Provider.of<CalamityProvider>(
        context,
        listen: false,
      );
      calamityProvider.loadActiveCalamityEvents();
    });
    _loadBarangays();
  }

  void _handleTabChange() {
    if (!_tabController.indexIsChanging) {
      // Reload data when tab changes
      if (_tabController.index == 2) {
        // Calamity Donations tab
        WidgetsBinding.instance.addPostFrameCallback((_) {
          Provider.of<CalamityProvider>(
            context,
            listen: false,
          ).loadActiveCalamityEvents();
        });
      } else if (_tabController.index == 0) {
        // Available Giveaways tab
        WidgetsBinding.instance.addPostFrameCallback((_) {
          Provider.of<GiveawayProvider>(
            context,
            listen: false,
          ).loadActiveGiveaways();
        });
      }
    }
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
    _tabController.removeListener(_handleTabChange);
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final currentUserId = authProvider.user?.uid ?? '';

    // Active Giveaways Query
    final activeGiveawaysQuery = FirebaseFirestore.instance
        .collection('giveaways')
        .where('status', isEqualTo: 'active')
        .limit(50);

    // My Giveaways Query
    final myGiveawaysQuery = currentUserId.isNotEmpty
        ? FirebaseFirestore.instance
              .collection('giveaways')
              .where('donorId', isEqualTo: currentUserId)
              .limit(50)
        : null;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: _primaryColor,
        foregroundColor: Colors.white,
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
          'Donate',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () {
              Navigator.pushNamed(context, '/giveaway/add');
            },
            tooltip: 'Post Giveaway',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          isScrollable: true,
          tabAlignment: TabAlignment.center,
          tabs: const [
            Tab(icon: Icon(Icons.card_giftcard), text: 'Available'),
            Tab(icon: Icon(Icons.inventory), text: 'My Giveaways'),
            Tab(icon: Icon(Icons.emergency_outlined), text: 'Calamity'),
          ],
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
                    _primaryColor,
                    _primaryColor.withOpacity(0.8),
                    _primaryColor.withOpacity(0.6),
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
                          Icons.card_giftcard_outlined,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'Donate Menu',
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
                    'Manage your donations',
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
            // Giveaways Section
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Text(
                'Giveaways',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[600],
                  letterSpacing: 0.5,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.pending_outlined),
              title: const Text('Pending Claims'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const PendingClaimsScreen(),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.check_circle_outline),
              title: const Text('Approved Claims'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const ApprovedClaimsScreen(),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.inventory),
              title: const Text('My Donation Listings'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const MyListingsScreen(initialTab: 3),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.history_outlined),
              title: const Text('Completed Donations'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const CompletedDonationsScreen(),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.analytics_outlined),
              title: const Text('Analytics Dashboard'),
              onTap: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, '/giveaway/analytics');
              },
            ),
            // Divider between Giveaway and Calamity sections
            const Divider(),
            // Calamity Donations Section
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Text(
                'Calamity Relief',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[600],
                  letterSpacing: 0.5,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.emergency_outlined),
              title: const Text('Active Calamity Events'),
              onTap: () {
                Navigator.pop(context);
                _tabController.animateTo(
                  2,
                ); // Navigate to Calamity Donations tab
              },
            ),
            if (currentUserId.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.inventory_2_outlined),
                title: const Text('My Calamity Donations'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.pushNamed(context, '/calamity/my-donations');
                },
              ),
          ],
        ),
      ),
      body: VerificationGuard(
        child: TabBarView(
          controller: _tabController,
          children: [
            // Available Giveaways Tab
            _buildAvailableTab(activeGiveawaysQuery),
            // My Giveaways Tab
            _buildMyGiveawaysTab(myGiveawaysQuery, currentUserId),
            // Calamity Donations Tab
            _buildCalamityDonationsTab(),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavBarWidget(
        selectedIndex: 1, // Exchange tab (Give is part of Exchange)
        onTap: (_) {},
        navigationContext: context,
      ),
    );
  }

  Widget _buildAvailableTab(Query<Map<String, dynamic>> giveawaysQuery) {
    final authProvider = Provider.of<AuthProvider>(context);
    final currentUserId = authProvider.user?.uid ?? '';

    // Require login to view available giveaways
    if (currentUserId.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.login, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'Please log in to view available giveaways',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey[600],
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'You need to be logged in to browse and claim items',
              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () {
                Navigator.pushNamed(context, '/login');
              },
              child: const Text(
                'Log In',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Search and Filter Section
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.white,
          child: Column(
            children: [
              // Search Bar with Filter Toggle
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Search giveaways...',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  setState(() {
                                    _searchController.clear();
                                  });
                                },
                              )
                            : null,
                        filled: true,
                        fillColor: Colors.grey[100],
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
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
                          ? _primaryColor
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
                          SizedBox(
                            height: 40,
                            child: ListView.builder(
                              scrollDirection: Axis.horizontal,
                              itemCount: _categories.length,
                              itemBuilder: (context, index) {
                                final category = _categories[index];
                                final isSelected =
                                    _selectedCategory == category;
                                return Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: FilterChip(
                                    label: Text(category),
                                    selected: isSelected,
                                    onSelected: (selected) {
                                      setState(() {
                                        _selectedCategory = category;
                                      });
                                    },
                                    selectedColor: _primaryColor.withOpacity(
                                      0.2,
                                    ),
                                    checkmarkColor: _primaryColor,
                                    labelStyle: TextStyle(
                                      color: isSelected
                                          ? _primaryColor
                                          : Colors.grey[700],
                                      fontWeight: isSelected
                                          ? FontWeight.w600
                                          : FontWeight.normal,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
        // Giveaways List
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: giveawaysQuery.snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.card_giftcard,
                        size: 64,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No giveaways available',
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Tap the + button above to post a giveaway!',
                        style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                      ),
                    ],
                  ),
                );
              }
              final docs = snapshot.data!.docs;
              final filteredDocs = _filterGiveaways(docs);
              if (filteredDocs.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.search_off, size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text(
                        'No giveaways match your search',
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: filteredDocs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 16),
                itemBuilder: (context, index) {
                  final data = filteredDocs[index].data();
                  final giveawayId = filteredDocs[index].id;
                  final giveaway = GiveawayListingModel.fromMap(
                    data,
                    giveawayId,
                  );
                  return _buildGiveawayCard(giveaway, showClaim: true);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildMyGiveawaysTab(
    Query<Map<String, dynamic>>? myGiveawaysQuery,
    String currentUserId,
  ) {
    if (currentUserId.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.login, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'Please log in to view your giveaways',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey[600],
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    if (myGiveawaysQuery == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: myGiveawaysQuery.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.inventory, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  'No giveaways yet',
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Tap the + button to post your first giveaway!',
                  style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                ),
              ],
            ),
          );
        }
        final docs = snapshot.data!.docs;
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 16),
          itemBuilder: (context, index) {
            final data = docs[index].data();
            final giveawayId = docs[index].id;
            final giveaway = GiveawayListingModel.fromMap(data, giveawayId);
            return _buildGiveawayCard(giveaway, showClaim: false);
          },
        );
      },
    );
  }

  // Filter for real Firestore data
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _filterGiveaways(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    var filtered = docs;

    // Filter by search query
    if (_searchController.text.isNotEmpty) {
      final query = _searchController.text.toLowerCase();
      filtered = filtered.where((doc) {
        final data = doc.data();
        final title = (data['title'] ?? '').toString().toLowerCase();
        final description = (data['description'] ?? '')
            .toString()
            .toLowerCase();
        return title.contains(query) || description.contains(query);
      }).toList();
    }

    // Filter by category
    if (_selectedCategory != 'All') {
      filtered = filtered.where((doc) {
        final data = doc.data();
        final category = (data['category'] ?? '').toString();
        return category == _selectedCategory;
      }).toList();
    }

    // Filter by barangay
    if (_selectedBarangay != null && _selectedBarangay!.isNotEmpty) {
      filtered = filtered.where((doc) {
        final data = doc.data();
        final location = (data['location'] ?? '').toString().toLowerCase();
        return location.contains(_selectedBarangay!.toLowerCase());
      }).toList();
    }

    return filtered;
  }

  Widget _buildGiveawayCard(
    GiveawayListingModel giveaway, {
    bool showClaim = true,
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image Section
          Stack(
            children: [
              Container(
                height: 220,
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                  ),
                  color: Colors.grey[200],
                  image: giveaway.hasImages && giveaway.images.isNotEmpty
                      ? DecorationImage(
                          image: NetworkImage(giveaway.images.first),
                          fit: BoxFit.cover,
                          onError: (_, __) {},
                        )
                      : null,
                ),
                child: !giveaway.hasImages
                    ? const Center(
                        child: Icon(
                          Icons.image_not_supported_outlined,
                          size: 48,
                          color: Colors.grey,
                        ),
                      )
                    : null,
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
                    color: giveaway.isAvailable
                        ? const Color(0xFF2ECC71)
                        : Colors.grey,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    giveaway.statusDisplay,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              if (giveaway.images.length > 1)
                Positioned(
                  right: 12,
                  bottom: 12,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '+${giveaway.images.length - 1}',
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
          // Content Section
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title and Category
                Row(
                  children: [
                    Icon(Icons.card_giftcard, color: _primaryColor, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        giveaway.title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: _primaryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        giveaway.category,
                        style: TextStyle(
                          color: _primaryColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        giveaway.claimModeDisplay,
                        style: TextStyle(
                          color: Colors.orange[700],
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Description
                Text(
                  giveaway.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.grey[700], fontSize: 14),
                ),
                const SizedBox(height: 12),
                // Donor Info
                Row(
                  children: [
                    Icon(
                      Icons.person_outline,
                      size: 16,
                      color: Colors.grey[600],
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        giveaway.donorName,
                        style: TextStyle(color: Colors.grey[700], fontSize: 12),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Location
                Row(
                  children: [
                    Icon(
                      Icons.location_on_outlined,
                      size: 16,
                      color: _primaryColor,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        giveaway.location,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Colors.grey[700], fontSize: 12),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Action Button
                if (showClaim && giveaway.isAvailable)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: () {
                        Navigator.pushNamed(
                          context,
                          '/giveaway/detail',
                          arguments: {'giveawayId': giveaway.id},
                        );
                      },
                      child: const Text(
                        'View Details',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  )
                else if (!showClaim)
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pushNamed(
                              context,
                              '/giveaway/detail',
                              arguments: {'giveawayId': giveaway.id},
                            );
                          },
                          icon: const Icon(Icons.visibility),
                          label: const Text('View'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _primaryColor,
                            side: BorderSide(color: _primaryColor),
                            padding: const EdgeInsets.symmetric(vertical: 12),
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

  Widget _buildCalamityDonationsTab() {
    return Consumer<CalamityProvider>(
      builder: (context, provider, _) {
        // Auto-load if not loaded yet
        if (provider.activeCalamityEvents.isEmpty && !provider.isLoading) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            provider.loadActiveCalamityEvents();
          });
        }

        if (provider.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        if (provider.activeCalamityEvents.isEmpty) {
          return RefreshIndicator(
            onRefresh: () async {
              await provider.loadActiveCalamityEvents();
            },
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.7,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.event_busy, size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text(
                        'No active calamity events',
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Check back later for relief efforts',
                        style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: () {
                          provider.loadActiveCalamityEvents();
                        },
                        icon: const Icon(Icons.refresh),
                        label: const Text('Refresh'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _primaryColor,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: () async {
            await provider.loadActiveCalamityEvents();
          },
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: provider.activeCalamityEvents.length,
            separatorBuilder: (_, __) => const SizedBox(height: 16),
            itemBuilder: (context, index) {
              final event = provider.activeCalamityEvents[index];
              return _buildCalamityEventCard(context, event);
            },
          ),
        );
      },
    );
  }

  Widget _buildCalamityEventCard(
    BuildContext context,
    CalamityEventModel event,
  ) {
    final isExpired = event.deadline.isBefore(DateTime.now());
    final daysRemaining = event.deadline.difference(DateTime.now()).inDays;

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
          // Banner Image
          if (event.bannerUrl.isNotEmpty)
            ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
              child: Stack(
                children: [
                  Image.network(
                    event.bannerUrl,
                    height: 220,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        height: 220,
                        color: Colors.grey[300],
                        child: const Icon(Icons.image_not_supported, size: 48),
                      );
                    },
                  ),
                  if (isExpired)
                    Container(
                      height: 220,
                      color: Colors.black54,
                      child: const Center(
                        child: Text(
                          'EXPIRED',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          // Content Section
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title and Calamity Type
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        event.title,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.blue),
                      ),
                      child: Text(
                        event.calamityType,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.blue[700],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Deadline
                Row(
                  children: [
                    Icon(
                      Icons.event,
                      size: 16,
                      color: isExpired ? Colors.red[700] : Colors.orange[700],
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        isExpired
                            ? 'Deadline passed: ${_formatDate(event.deadline)}'
                            : daysRemaining > 0
                            ? 'Deadline: ${_formatDate(event.deadline)} (${daysRemaining} days left)'
                            : 'Deadline: ${_formatDate(event.deadline)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: isExpired ? Colors.red[700] : Colors.grey[700],
                          fontWeight: isExpired
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Needed Items Preview
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: event.neededItems.take(4).map((item) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _primaryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        item,
                        style: TextStyle(
                          fontSize: 11,
                          color: _primaryColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    );
                  }).toList(),
                ),
                if (event.neededItems.length > 4)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '+${event.neededItems.length - 4} more items',
                      style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                    ),
                  ),
                const SizedBox(height: 16),
                // Donate Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: isExpired
                        ? null
                        : () {
                            Navigator.pushNamed(
                              context,
                              '/calamity/detail',
                              arguments: {'eventId': event.eventId},
                            );
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: Text(
                      isExpired ? 'Event Expired' : 'Donate',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
