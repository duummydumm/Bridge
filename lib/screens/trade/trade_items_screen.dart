import 'package:bridge_app/screens/my_listings_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import '../../models/trade_item_model.dart';
import '../../reusable_widgets/bottom_nav_bar_widget.dart';
import '../../reusable_widgets/verification_guard.dart';
import '../../providers/auth_provider.dart';
import '../../providers/chat_provider.dart';
import '../../providers/user_provider.dart';
import '../../services/firestore_service.dart';
import '../../services/trade_matching_service.dart';
import '../chat_detail_screen.dart';

class TradeItemsScreen extends StatefulWidget {
  const TradeItemsScreen({super.key});

  @override
  State<TradeItemsScreen> createState() => _TradeItemsScreenState();
}

class _TradeItemsScreenState extends State<TradeItemsScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  String _selectedCategory = 'All';
  String? _selectedBarangay;
  late TabController _tabController;
  List<String> _barangays = [];
  bool _isFilterExpanded = false;
  List<TradeItemModel> _userTradeItems = []; // User's own listings for matching
  int _pageSize = 50;
  static const int _pageIncrement = 50;

  final List<String> _categories = [
    'All',
    'Electronics',
    'Tools',
    'Furniture',
    'Clothing',
    'Books',
    'Others',
  ];

  // BRIDGE Trade theme color
  static const Color _primaryColor = Color(0xFF2A7A9E);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this); // Added Matches tab
    _tabController.addListener(() {
      // Reload user trade items when switching to Matches tab (index 1)
      if (_tabController.index == 1 && !_tabController.indexIsChanging) {
        _loadUserTradeItems();
      }
    });
    _loadBarangays();
    _loadUserTradeItems();
  }

  Future<void> _loadUserTradeItems() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final currentUserId = authProvider.user?.uid ?? '';

    if (currentUserId.isEmpty) return;

    try {
      final firestoreService = FirestoreService();
      final userItemsData = await firestoreService.getTradeItemsByUser(
        currentUserId,
      );
      setState(() {
        _userTradeItems = userItemsData
            .map((data) => TradeItemModel.fromMap(data, data['id'] as String))
            .toList();
      });
    } catch (e) {
      // Silently fail - matching is optional
      print('Error loading user trade items for matching: $e');
    }
  }

  Future<bool> _checkIfHasPendingOffer(String tradeItemId) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final currentUserId = authProvider.user?.uid;

    if (currentUserId == null || currentUserId.isEmpty) {
      return false;
    }

    try {
      final firestoreService = FirestoreService();
      return await firestoreService.hasPendingOrApprovedTradeOffer(
        tradeItemId: tradeItemId,
        userId: currentUserId,
      );
    } catch (e) {
      // Return false on error to allow the button to be enabled
      return false;
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
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final currentUserId = authProvider.user?.uid ?? '';

    // Trade Feed Query - All open trade items (no inequality filter to avoid index requirement)
    Query<Map<String, dynamic>> tradeFeedQuery = FirebaseFirestore.instance
        .collection('trade_items')
        .where('status', isEqualTo: 'Open')
        .limit(_pageSize);

    // My Trades Query - User's own trade items
    final myTradesQuery = currentUserId.isNotEmpty
        ? FirebaseFirestore.instance
              .collection('trade_items')
              .where('offeredBy', isEqualTo: currentUserId)
              .limit(_pageSize)
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
          'Trade',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () {
              Navigator.pushNamed(context, '/trade/add-item');
            },
            tooltip: 'List Item for Trade',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(icon: Icon(Icons.store), text: 'Trade Feed'),
            Tab(icon: Icon(Icons.auto_awesome), text: 'Matches'),
            Tab(icon: Icon(Icons.swap_horiz), text: 'My Trades'),
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
                          Icons.swap_horiz,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'Trade Menu',
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
                    'Manage your trades',
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
              leading: const Icon(Icons.inbox),
              title: const Text('Incoming Offers'),
              onTap: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, '/trade/incoming-offers');
              },
            ),
            ListTile(
              leading: const Icon(Icons.send_outlined),
              title: const Text('Pending Offers'),
              onTap: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, '/trade/pending-requests');
              },
            ),
            ListTile(
              leading: const Icon(Icons.outbox_outlined),
              title: const Text('Your Trade Offers'),
              onTap: () {
                Navigator.pop(context);
                Navigator.pushNamed(
                  context,
                  '/trade/history',
                  arguments: {'filter': 'outgoing'},
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.check_circle_outline),
              title: const Text('Accepted Trades'),
              onTap: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, '/trade/accepted-trades');
              },
            ),
            ListTile(
              leading: const Icon(Icons.history_outlined),
              title: const Text('Trade History'),
              onTap: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, '/trade/history');
              },
            ),
            ListTile(
              leading: const Icon(Icons.gavel_outlined),
              title: const Text('Disputed Trades'),
              onTap: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, '/trade/disputed-trades');
              },
            ),
            ListTile(
              leading: const Icon(Icons.inventory_2_outlined),
              title: const Text('My Trades Listing'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const MyListingsScreen(initialTab: 2),
                  ),
                );
              },
            ),
          ],
        ),
      ),
      body: VerificationGuard(
        child: TabBarView(
          controller: _tabController,
          children: [
            // Trade Feed Tab
            _buildTradeFeedTab(tradeFeedQuery, currentUserId),
            // Matches Tab
            _buildMatchesTab(tradeFeedQuery, currentUserId),
            // My Trades Tab
            _buildMyTradesTab(myTradesQuery, currentUserId),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavBarWidget(
        selectedIndex: 1, // Exchange tab (Trade is part of Exchange)
        onTap: (_) {},
        navigationContext: context,
      ),
    );
  }

  // Trade Feed Tab - Shows all open trade items
  Widget _buildTradeFeedTab(
    Query<Map<String, dynamic>> tradeQuery,
    String currentUserId,
  ) {
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
                        hintText: 'Search trade items...',
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
        // Trade Items List
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: tradeQuery.snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 64,
                        color: Colors.red[300],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Error loading trade items',
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        snapshot.error.toString(),
                        style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                );
              }
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.store_outlined,
                        size: 64,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No trade items available',
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Tap the + button above to get started!',
                        style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                      ),
                    ],
                  ),
                );
              }
              final docs = snapshot.data!.docs;
              // Exclude my own listings client-side to avoid composite index
              final notMine = currentUserId.isEmpty
                  ? docs
                  : docs
                        .where(
                          (d) => (d.data()['offeredBy'] ?? '') != currentUserId,
                        )
                        .toList();
              final filteredDocs = _filterItems(notMine);
              // Sort newest first client-side (avoids composite index)
              filteredDocs.sort((a, b) {
                final aTs = a.data()['createdAt'];
                final bTs = b.data()['createdAt'];
                final aDate = (aTs is Timestamp)
                    ? aTs.toDate()
                    : DateTime.fromMillisecondsSinceEpoch(0);
                final bDate = (bTs is Timestamp)
                    ? bTs.toDate()
                    : DateTime.fromMillisecondsSinceEpoch(0);
                return bDate.compareTo(aDate);
              });
              if (filteredDocs.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.search_off, size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text(
                        'No items match your search',
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
              return Column(
                children: [
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: filteredDocs.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 16),
                      itemBuilder: (context, index) {
                        final doc = filteredDocs[index];
                        final data = doc.data();
                        final tradeItemId = doc.id;
                        final tradeItem = TradeItemModel.fromMap(
                          data,
                          tradeItemId,
                        );
                        // Hide offer button for my own listings
                        final auth = Provider.of<AuthProvider>(
                          context,
                          listen: false,
                        );
                        final isMine = auth.user?.uid == tradeItem.offeredBy;
                        return _buildTradeItemCard(
                          tradeItem,
                          showMakeOffer: !isMine,
                        );
                      },
                    ),
                  ),
                  if (docs.length >= _pageSize)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () {
                            setState(() {
                              _pageSize += _pageIncrement;
                            });
                          },
                          icon: const Icon(Icons.more_horiz),
                          label: const Text('Load more items'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _primaryColor,
                            side: BorderSide(color: _primaryColor),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  // Matches Tab - Shows smart matched trades
  Widget _buildMatchesTab(
    Query<Map<String, dynamic>> tradeQuery,
    String currentUserId,
  ) {
    if (currentUserId.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.auto_awesome, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'Please log in to see matches',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey[600],
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'We\'ll find trades that match what you\'re offering or looking for',
              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: tradeQuery.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
                const SizedBox(height: 16),
                Text(
                  'Error loading matches',
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  snapshot.error.toString(),
                  style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.auto_awesome_outlined,
                  size: 64,
                  color: Colors.grey[400],
                ),
                const SizedBox(height: 16),
                Text(
                  'No matches found',
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'List items for trade to see smart matches!',
                  style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                ),
              ],
            ),
          );
        }

        // Get all open trades
        final allTrades = snapshot.data!.docs
            .map((doc) {
              try {
                return TradeItemModel.fromMap(doc.data(), doc.id);
              } catch (e) {
                return null;
              }
            })
            .whereType<TradeItemModel>()
            .toList();

        // Get matches
        final matches = TradeMatchingService.getMatches(
          userTradeItems: _userTradeItems,
          allOpenTrades: allTrades,
          currentUserId: currentUserId,
        );

        if (matches.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.auto_awesome_outlined,
                  size: 64,
                  color: Colors.grey[400],
                ),
                const SizedBox(height: 16),
                Text(
                  'No matches found',
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'List items for trade and specify what you\'re looking for to see matches',
                  style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: matches.length,
          separatorBuilder: (_, __) => const SizedBox(height: 16),
          itemBuilder: (context, index) {
            final match = matches[index];
            return _buildMatchedTradeItemCard(match);
          },
        );
      },
    );
  }

  // My Trades Tab - Shows user's own trade items
  Widget _buildMyTradesTab(
    Query<Map<String, dynamic>>? myTradesQuery,
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
              'Please log in to view your trades',
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

    if (myTradesQuery == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: myTradesQuery.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
                const SizedBox(height: 16),
                Text(
                  'Error loading your trades',
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  snapshot.error.toString(),
                  style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.swap_horiz, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  'No trade items yet',
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Tap the + button above to list an item for trade!',
                  style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }
        final docs = snapshot.data!.docs;
        final filteredDocs = _filterItems(docs);
        // Sort user's trades so newest listings appear first
        filteredDocs.sort((a, b) {
          final aTs = a.data()['createdAt'];
          final bTs = b.data()['createdAt'];
          final aDate = (aTs is Timestamp)
              ? aTs.toDate()
              : DateTime.fromMillisecondsSinceEpoch(0);
          final bDate = (bTs is Timestamp)
              ? bTs.toDate()
              : DateTime.fromMillisecondsSinceEpoch(0);
          return bDate.compareTo(aDate);
        });
        if (filteredDocs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.search_off, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  'No items match your search',
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
        return Column(
          children: [
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: filteredDocs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 16),
                itemBuilder: (context, index) {
                  final doc = filteredDocs[index];
                  final data = doc.data();
                  final tradeItemId = doc.id;
                  final tradeItem = TradeItemModel.fromMap(data, tradeItemId);
                  return _buildTradeItemCard(tradeItem, showMakeOffer: false);
                },
              ),
            ),
            if (docs.length >= _pageSize)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      setState(() {
                        _pageSize += _pageIncrement;
                      });
                    },
                    icon: const Icon(Icons.more_horiz),
                    label: const Text('Load more my trades'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _primaryColor,
                      side: BorderSide(color: _primaryColor),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _filterItems(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    var filtered = docs;

    // Filter by search query
    if (_searchController.text.isNotEmpty) {
      final query = _searchController.text.toLowerCase();
      filtered = filtered.where((doc) {
        final data = doc.data();
        final offeredName = (data['offeredItemName'] ?? '')
            .toString()
            .toLowerCase();
        final desiredName = (data['desiredItemName'] ?? '')
            .toString()
            .toLowerCase();
        final description = (data['offeredDescription'] ?? '')
            .toString()
            .toLowerCase();
        return offeredName.contains(query) ||
            desiredName.contains(query) ||
            description.contains(query);
      }).toList();
    }

    // Filter by category
    if (_selectedCategory != 'All') {
      filtered = filtered.where((doc) {
        final data = doc.data();
        final category = (data['offeredCategory'] ?? '').toString();
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

  Widget _buildMatchedTradeItemCard(TradeMatch match) {
    final tradeItem = match.tradeItem;
    final matchColor = TradeMatchingService.getMatchBadgeColor(match.matchType);
    final matchBadgeText = TradeMatchingService.getMatchBadgeText(
      match.matchType,
    );
    final matchPercentage = (match.matchScore * 100).toInt();

    Color badgeColor;
    switch (matchColor) {
      case 'green':
        badgeColor = Colors.green;
        break;
      case 'blue':
        badgeColor = Colors.blue;
        break;
      case 'orange':
        badgeColor = Colors.orange;
        break;
      default:
        badgeColor = _primaryColor;
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: badgeColor.withOpacity(0.3), width: 2),
        boxShadow: [
          BoxShadow(
            color: badgeColor.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Match Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: badgeColor.withOpacity(0.1),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.auto_awesome, color: badgeColor, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    matchBadgeText,
                    style: TextStyle(
                      color: badgeColor,
                      fontSize: 14,
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
                    color: badgeColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$matchPercentage% Match',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Match Reason
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.05),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: Colors.blue[700]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      match.matchReason,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.blue[900],
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Trade Item Card Content
          _buildTradeItemCardContent(
            tradeItem,
            showMakeOffer: true,
            match: match,
          ),
        ],
      ),
    );
  }

  Widget _buildTradeItemCard(
    TradeItemModel tradeItem, {
    bool showMakeOffer = true,
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
      child: _buildTradeItemCardContent(
        tradeItem,
        showMakeOffer: showMakeOffer,
      ),
    );
  }

  Widget _buildTradeItemCardContent(
    TradeItemModel tradeItem, {
    bool showMakeOffer = true,
    TradeMatch? match,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Image Section - Multiple Images Carousel
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
              ),
              child: tradeItem.hasImage && tradeItem.offeredImageUrls.isNotEmpty
                  ? PageView.builder(
                      itemCount: tradeItem.offeredImageUrls.length,
                      itemBuilder: (context, index) {
                        return Container(
                          decoration: BoxDecoration(
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(16),
                              topRight: Radius.circular(16),
                            ),
                            image: DecorationImage(
                              image: NetworkImage(
                                tradeItem.offeredImageUrls[index],
                              ),
                              fit: BoxFit.cover,
                              onError: (_, __) {},
                            ),
                          ),
                        );
                      },
                    )
                  : const Center(
                      child: Icon(
                        Icons.image_not_supported_outlined,
                        size: 48,
                        color: Colors.grey,
                      ),
                    ),
            ),
            // Image indicator dots
            if (tradeItem.hasImage && tradeItem.offeredImageUrls.length > 1)
              Positioned(
                bottom: 8,
                left: 0,
                right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    tradeItem.offeredImageUrls.length,
                    (index) => Container(
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withOpacity(0.7),
                      ),
                    ),
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
                  color: tradeItem.isOpen
                      ? const Color(0xFF2ECC71)
                      : Colors.grey,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  tradeItem.statusDisplay,
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
              // Offered Item Section
              Row(
                children: [
                  Icon(Icons.inventory_2, color: _primaryColor, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      tradeItem.offeredItemName,
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
              // Category and Description
              Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
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
                      tradeItem.offeredCategory,
                      style: TextStyle(
                        color: _primaryColor,
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
                tradeItem.offeredDescription,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.grey[700], fontSize: 14),
              ),
              // Desired Item Section (if exists)
              if (tradeItem.desiredItemName != null ||
                  tradeItem.desiredCategory != null) ...[
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(Icons.search, color: _primaryColor, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Looking for:',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            tradeItem.desiredItemName ?? 'Any item',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                          ),
                          if (tradeItem.desiredCategory != null) ...[
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.orange.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                tradeItem.desiredCategory!,
                                style: TextStyle(
                                  color: Colors.orange[700],
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
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
                      tradeItem.location,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.grey[700], fontSize: 12),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Action Buttons
              if (showMakeOffer)
                Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _messageOwner(
                              context,
                              tradeItem.offeredBy,
                              tradeItem.offeredItemName,
                              tradeItem.id,
                            ),
                            icon: const Icon(Icons.message),
                            label: const Text('Message Owner'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _primaryColor,
                              side: BorderSide(color: _primaryColor),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FutureBuilder<bool>(
                            future: _checkIfHasPendingOffer(tradeItem.id),
                            builder: (context, snapshot) {
                              final hasPendingOffer = snapshot.data ?? false;
                              return ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: hasPendingOffer
                                      ? Colors.grey
                                      : _primaryColor,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                onPressed: hasPendingOffer
                                    ? null
                                    : () {
                                        final args = <String, dynamic>{
                                          'tradeItemId': tradeItem.id,
                                        };
                                        // If this is a match, pass the matched user trade item data
                                        if (match != null &&
                                            match.matchedUserTradeItem !=
                                                null) {
                                          final matchedItem =
                                              match.matchedUserTradeItem!;
                                          args['matchedItemName'] =
                                              matchedItem.offeredItemName;
                                          args['matchedItemDescription'] =
                                              matchedItem.offeredDescription;
                                          args['matchedItemImageUrls'] =
                                              matchedItem.offeredImageUrls;
                                          args['isMatched'] = 'true';
                                        }
                                        Navigator.pushNamed(
                                          context,
                                          '/trade/make-offer',
                                          arguments: args,
                                        );
                                      },
                                child: Text(
                                  hasPendingOffer
                                      ? 'Offer Pending'
                                      : 'Make Offer',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                )
              else
              // Only show buttons if item is not traded
              if (tradeItem.status != TradeStatus.traded)
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          // Navigate to edit trade screen
                          Navigator.pushNamed(
                            context,
                            '/trade/add-item',
                            arguments: {'tradeItemId': tradeItem.id},
                          );
                        },
                        icon: const Icon(Icons.edit),
                        label: const Text('Edit'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _primaryColor,
                          side: BorderSide(color: _primaryColor),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pushNamed(
                            context,
                            '/trade/incoming-offers',
                            arguments: {'tradeItemId': tradeItem.id},
                          );
                        },
                        icon: const Icon(Icons.visibility),
                        label: const Text('View Offers'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _primaryColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ],
                )
              else
                // Show message when item is traded
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.check_circle,
                        color: Colors.green[700],
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'This item has been traded',
                        style: TextStyle(
                          color: Colors.grey[700],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  // Message owner function
  Future<void> _messageOwner(
    BuildContext context,
    String ownerId,
    String itemName,
    String tradeItemId,
  ) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final firestoreService = FirestoreService();

    // Check if user is authenticated
    if (authProvider.user == null || authProvider.user!.uid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please log in to message the owner'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final currentUserId = authProvider.user!.uid;
    final currentUser = userProvider.currentUser;

    // Prevent messaging yourself
    if (currentUserId == ownerId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You cannot message yourself'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Show loading dialog
    if (!context.mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) =>
          const Center(child: CircularProgressIndicator()),
    );

    try {
      // Fetch owner's information
      final ownerData = await firestoreService.getUser(ownerId);
      if (ownerData == null) {
        if (context.mounted) {
          Navigator.of(context, rootNavigator: true).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Owner not found'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final ownerName = ownerData['fullName'] ?? ownerData['email'] ?? 'Owner';

      // Create or get conversation
      final conversationId = await chatProvider.createOrGetConversation(
        userId1: currentUserId,
        userId1Name: currentUser?.fullName ?? 'You',
        userId2: ownerId,
        userId2Name: ownerName,
        itemId: tradeItemId,
        itemTitle: itemName,
      );

      // Close loading dialog
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }

      if (conversationId != null && context.mounted) {
        // Navigate to chat detail screen
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ChatDetailScreen(
              conversationId: conversationId,
              otherParticipantName: ownerName,
              userId: currentUserId,
            ),
          ),
        );
      } else if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to start conversation'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
