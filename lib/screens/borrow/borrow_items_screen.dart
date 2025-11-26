import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import '../../providers/item_provider.dart';
import '../../providers/user_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/chat_provider.dart';
import '../../models/item_model.dart';
import '../../reusable_widgets/bottom_nav_bar_widget.dart';
import '../../reusable_widgets/verification_guard.dart';
import '../../services/firestore_service.dart';
import '../chat_detail_screen.dart';
import '../user_public_profile_screen.dart';
import '../my_listings_screen.dart';

class BorrowItemsScreen extends StatefulWidget {
  const BorrowItemsScreen({super.key});

  @override
  State<BorrowItemsScreen> createState() => _BorrowItemsScreenState();
}

class _BorrowItemsScreenState extends State<BorrowItemsScreen> {
  final TextEditingController _searchController = TextEditingController();
  int _selectedIndex = 1; // Exchange tab (Borrow is part of Exchange)
  String _selectedCategory = '';
  String? _selectedBarangay;
  int _viewMode = 0; // 0: Grid, 1: List
  final Set<String> _requestedItemIds = <String>{};
  final FirestoreService _firestoreService = FirestoreService();
  List<String> _barangays = [];
  bool _isFilterExpanded = false;

  // Comprehensive list of all available categories
  final List<String> _allCategories = [
    'Tools',
    'Electronics',
    'Furniture',
    'Clothing',
    'Books',
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final itemProvider = Provider.of<ItemProvider>(context, listen: false);
      itemProvider.loadAvailableItems();
      _preloadPendingRequests();
    });
  }

  Future<void> _loadBarangays() async {
    try {
      final String jsonString = await rootBundle.loadString(
        'assets/data/oroquieta_barangays.json',
      );
      final List<dynamic> jsonData = json.decode(jsonString);
      if (mounted) {
        setState(() {
          _barangays = jsonData.cast<String>();
        });
      }
    } catch (e) {
      print('Error loading barangays: $e');
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final itemProvider = Provider.of<ItemProvider>(context);
    final userProvider = Provider.of<UserProvider>(context);
    final availableItems = _getFilteredItems(itemProvider, userProvider);

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
          'Borrow',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        actions: [
          IconButton(
            icon: Icon(_viewMode == 0 ? Icons.list : Icons.grid_view),
            onPressed: () {
              setState(() {
                _viewMode = _viewMode == 0 ? 1 : 0;
              });
            },
            tooltip: _viewMode == 0 ? 'List View' : 'Grid View',
          ),
        ],
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
                          Icons.shopping_cart_outlined,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'Borrow Menu',
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
                    'Manage your borrow activities',
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
              title: const Text('Pending Borrow Requests'),
              onTap: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, '/borrow/pending-requests');
              },
            ),
            ListTile(
              leading: const Icon(Icons.check_circle_outline),
              title: const Text('Approved Borrow'),
              onTap: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, '/borrow/approved');
              },
            ),
            ListTile(
              leading: const Icon(Icons.shopping_cart_outlined),
              title: const Text('Currently Borrowed'),
              onTap: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, '/borrow/currently-borrowed');
              },
            ),
            ListTile(
              leading: const Icon(Icons.assignment_returned_outlined),
              title: const Text('Returned Items'),
              onTap: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, '/borrow/returned-items');
              },
            ),
            ListTile(
              leading: const Icon(Icons.pending_actions),
              title: const Text('Pending Returns'),
              onTap: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, '/borrow/pending-returns');
              },
            ),
            ListTile(
              leading: const Icon(Icons.upload_outlined),
              title: const Text('Items Currently Lent'),
              onTap: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, '/borrow/currently-lent');
              },
            ),
            ListTile(
              leading: const Icon(Icons.gavel_outlined),
              title: const Text('Disputed Returns'),
              onTap: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, '/borrow/disputed-returns');
              },
            ),
            ListTile(
              leading: const Icon(Icons.inventory_2_outlined),
              title: const Text('My Listing'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const MyListingsScreen(initialTab: 0),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.inventory_2_outlined),
              title: const Text('My Lender'),
              onTap: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, '/my-lenders-detail');
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
                            hintText: 'Search items to borrow...',
                            prefixIcon: const Icon(Icons.search),
                            suffixIcon: _searchController.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear),
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
                              _buildFilterChips(
                                'Category',
                                _allCategories.isNotEmpty ? _allCategories : [],
                                _selectedCategory,
                                (value) =>
                                    setState(() => _selectedCategory = value),
                              ),
                            ],
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),

            // Content
            Expanded(
              child: itemProvider.isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : itemProvider.errorMessage != null
                  ? Center(
                      child: Text(
                        'Error: ${itemProvider.errorMessage}',
                        style: const TextStyle(color: Colors.red),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: () async {
                        await itemProvider.loadAvailableItems();
                        await _preloadPendingRequests();
                      },
                      child: availableItems.isEmpty
                          ? _buildEmptyState()
                          : _viewMode == 0
                          ? _buildGridView(availableItems)
                          : _buildListView(availableItems),
                    ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavBarWidget(
        selectedIndex: _selectedIndex,
        onTap: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        navigationContext: context,
      ),
    );
  }

  List<ItemModel> _getFilteredItems(
    ItemProvider itemProvider, [
    UserProvider? userProvider,
  ]) {
    var items = itemProvider.items.where((item) => item.isAvailable).toList();

    // Filter out items that belong to the current user (don't show own items in borrow screen)
    if (userProvider?.currentUser != null) {
      final currentUserId = userProvider!.currentUser!.uid;
      items = items.where((item) => item.lenderId != currentUserId).toList();
    }

    // Filter by search query
    if (_searchController.text.isNotEmpty) {
      final query = _searchController.text.toLowerCase();
      items = items.where((item) {
        return item.title.toLowerCase().contains(query) ||
            item.description.toLowerCase().contains(query) ||
            item.category.toLowerCase().contains(query);
      }).toList();
    }

    // Filter by category
    if (_selectedCategory.isNotEmpty) {
      items = items
          .where((item) => item.category == _selectedCategory)
          .toList();
    }

    // Filter by barangay
    if (_selectedBarangay != null && _selectedBarangay!.isNotEmpty) {
      items = items.where((item) {
        if (item.location != null && item.location!.isNotEmpty) {
          final itemLocation = item.location!.toLowerCase();
          return itemLocation.contains(_selectedBarangay!.toLowerCase());
        }
        return false;
      }).toList();
    }

    return items;
  }

  Widget _buildFilterChips(
    String label,
    List<String> options,
    String selected,
    Function(String) onChanged,
  ) {
    // Ensure options is not null or empty
    if (options.isEmpty) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      height: 50,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (label.isNotEmpty) ...[
              Text(
                '$label: ',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[700],
                ),
              ),
              const SizedBox(width: 8),
            ],
            ...options.map((option) {
              final isSelected = option == selected;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Text(option),
                  selected: isSelected,
                  onSelected: (selected) {
                    onChanged(selected ? option : '');
                  },
                  backgroundColor: Colors.grey[100],
                  selectedColor: const Color(0xFF00897B),
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : Colors.grey[700],
                    fontWeight: FontWeight.w600,
                  ),
                ),
              );
            }).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'No items available',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Try adjusting your search or filters',
            style: TextStyle(color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  Widget _buildGridView(List<ItemModel> items) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        // Give cards a fixed height so internal content doesn't overflow
        mainAxisExtent: 360,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        return _buildItemCard(items[index]);
      },
    );
  }

  Widget _buildListView(List<ItemModel> items) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      itemBuilder: (context, index) {
        return _buildItemListItem(items[index]);
      },
    );
  }

  Widget _buildItemCard(ItemModel item) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: () {
          _showItemDetails(item);
        },
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image with overlay icons
            Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(16),
                  ),
                  child: Container(
                    height: 160,
                    width: double.infinity,
                    color: Colors.grey[200],
                    child: item.hasImages
                        ? CachedNetworkImage(
                            imageUrl: _normalizeStorageUrl(item.images.first),
                            fit: BoxFit.cover,
                            placeholder: (context, url) => Container(
                              color: Colors.grey[200],
                              child: const Center(
                                child: CircularProgressIndicator(),
                              ),
                            ),
                            errorWidget: (context, url, error) {
                              print('❌ Image cache load Error: $error');
                              print('URL: ${item.images.first}');
                              return _buildPlaceholderImage();
                            },
                          )
                        : _buildPlaceholderImage(),
                  ),
                ),
                // Favorite icon (top-left)
                Positioned(
                  top: 12,
                  left: 12,
                  child: IconButton(
                    icon: const Icon(
                      Icons.favorite_border,
                      color: Colors.white,
                      size: 28,
                    ),
                    onPressed: () {},
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black.withOpacity(0.3),
                      padding: const EdgeInsets.all(8),
                    ),
                  ),
                ),
                // Availability tag (top-right)
                Positioned(
                  top: 12,
                  right: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'available',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            // Content
            Flexible(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Title
                    Text(
                      item.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    // Owner Name
                    InkWell(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                UserPublicProfileScreen(userId: item.lenderId),
                          ),
                        );
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            Icon(
                              Icons.person_outline,
                              size: 14,
                              color: const Color(0xFF00897B),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                item.lenderName,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFF00897B),
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Icon(
                              Icons.arrow_forward_ios,
                              size: 10,
                              color: Colors.grey[400],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    // Location/Barangay - More Prominent
                    Row(
                      children: [
                        Icon(
                          Icons.location_on,
                          size: 14,
                          color: const Color(0xFF00897B),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            _getDisplayLocation(item),
                            style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFF00897B),
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    // Category
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        item.category,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.orange.shade800,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Request Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _requestedItemIds.contains(item.itemId)
                            ? null
                            : () {
                                _showItemDetails(item);
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00897B),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        child: Text(
                          _requestedItemIds.contains(item.itemId)
                              ? 'Requested'
                              : 'Request to Borrow',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
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

  Widget _buildItemListItem(ItemModel item) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: () {
          _showItemDetails(item);
        },
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Image
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: 100,
                  height: 100,
                  color: Colors.grey[200],
                  child: item.hasImages
                      ? CachedNetworkImage(
                          imageUrl: _normalizeStorageUrl(item.images.first),
                          fit: BoxFit.cover,
                          placeholder: (context, url) => Container(
                            color: Colors.grey[200],
                            child: const Center(
                              child: CircularProgressIndicator(),
                            ),
                          ),
                          errorWidget: (context, url, error) {
                            print('❌ Image cache load Error: $error');
                            print('URL: ${item.images.first}');
                            return _buildPlaceholderImage();
                          },
                        )
                      : _buildPlaceholderImage(),
                ),
              ),
              const SizedBox(width: 12),
              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.title,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            'available',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    // Owner Name
                    InkWell(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                UserPublicProfileScreen(userId: item.lenderId),
                          ),
                        );
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            Icon(
                              Icons.person_outline,
                              size: 14,
                              color: const Color(0xFF00897B),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                item.lenderName,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFF00897B),
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Icon(
                              Icons.arrow_forward_ios,
                              size: 10,
                              color: Colors.grey[400],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    // Location/Barangay - More Prominent
                    Row(
                      children: [
                        Icon(
                          Icons.location_on,
                          size: 14,
                          color: const Color(0xFF00897B),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            _getDisplayLocation(item),
                            style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFF00897B),
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    // Category
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        item.category,
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.orange.shade800,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
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

  void _showItemDetails(ItemModel item) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _buildItemDetailsModal(item),
    );
  }

  Future<void> _preloadPendingRequests() async {
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      if (!authProvider.isAuthenticated || authProvider.user == null) return;
      final ids = await _firestoreService.getPendingRequestedItemIdsForBorrower(
        authProvider.user!.uid,
      );
      if (mounted) {
        setState(() {
          _requestedItemIds
            ..clear()
            ..addAll(ids);
        });
      }
    } catch (_) {
      // ignore errors silently for preload
    }
  }

  Future<void> _submitBorrowRequest(ItemModel item) async {
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final userProvider = Provider.of<UserProvider>(context, listen: false);

      if (!authProvider.isAuthenticated || authProvider.user == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please login to request this item'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      if (item.lenderId == authProvider.user!.uid) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("You can't request your own item."),
              backgroundColor: Colors.orange,
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

      // Optional: prevent duplicate pending requests
      final alreadyPending = await _firestoreService.hasPendingBorrowRequest(
        itemId: item.itemId,
        borrowerId: authProvider.user!.uid,
      );
      if (alreadyPending) {
        if (mounted) {
          Navigator.of(context).pop();
          setState(() {
            _requestedItemIds.add(item.itemId);
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('You already requested this item.')),
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

      final requestId = await _firestoreService.createBorrowRequest(
        itemId: item.itemId,
        itemTitle: item.title,
        lenderId: item.lenderId,
        lenderName: item.lenderName,
        borrowerId: authProvider.user!.uid,
        borrowerName: currentUser.fullName,
      );

      // After creating the borrow request, seed a chat so both parties can align
      try {
        final chatProvider = Provider.of<ChatProvider>(context, listen: false);
        final conversationId = await chatProvider.createOrGetConversation(
          userId1: authProvider.user!.uid,
          userId1Name: currentUser.fullName,
          userId2: item.lenderId,
          userId2Name: item.lenderName,
          itemId: item.itemId,
          itemTitle: item.title,
        );

        if (conversationId != null) {
          // Seed default message with optional first image of the item
          final String content = 'I want to borrow this: ${item.title}';
          final String? imageUrl = item.hasImages
              ? _normalizeStorageUrl(item.images.first)
              : null;
          await chatProvider.sendMessage(
            conversationId: conversationId,
            senderId: authProvider.user!.uid,
            senderName: currentUser.fullName,
            content: content,
            imageUrl: imageUrl,
          );
        }
      } catch (_) {
        // best-effort; failure to seed chat shouldn't block the request
      }

      // Close loading and modal
      if (mounted) {
        final rootNav = Navigator.of(context, rootNavigator: true);
        if (rootNav.canPop()) rootNav.pop();
        if (Navigator.of(context).canPop()) Navigator.of(context).pop();

        setState(() {
          _requestedItemIds.add(item.itemId);
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              requestId != null
                  ? 'Request sent to ${item.lenderName}'
                  : 'Request already exists',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        final rootNav = Navigator.of(context, rootNavigator: true);
        if (rootNav.canPop()) rootNav.pop();

        // Extract error message for better user experience
        String errorMessage = 'Error: $e';
        if (e.toString().contains('maximum limit')) {
          errorMessage = e.toString().replaceFirst('Exception: ', '');
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'View Requests',
              textColor: Colors.white,
              onPressed: () {
                Navigator.pushNamed(context, '/pending-requests');
              },
            ),
          ),
        );
      }
    }
  }

  Future<void> _messageOwner(ItemModel item) async {
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final chatProvider = Provider.of<ChatProvider>(context, listen: false);

      // Check if user is authenticated
      if (!authProvider.isAuthenticated || authProvider.user == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please login to message owner'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // Prevent messaging your own listing
      if (item.lenderId == authProvider.user!.uid) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("You can't message yourself about your own item."),
              backgroundColor: Colors.orange,
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
        userId2: item.lenderId,
        userId2Name: item.lenderName,
        itemId: item.itemId,
        itemTitle: item.title,
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
              otherParticipantName: item.lenderName,
              userId: authProvider.user!.uid,
            ),
          ),
        );
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to start conversation'),
              backgroundColor: Colors.red,
            ),
          );
        }
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

  Widget _buildItemDetailsModal(ItemModel item) {
    return DraggableScrollableSheet(
      initialChildSize: 0.8,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Content
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Image
                      if (item.hasImages)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            height: 250,
                            width: double.infinity,
                            color: Colors.grey[200],
                            child: CachedNetworkImage(
                              imageUrl: _normalizeStorageUrl(item.images.first),
                              fit: BoxFit.cover,
                              placeholder: (context, url) => Container(
                                color: Colors.grey[200],
                                child: const Center(
                                  child: CircularProgressIndicator(),
                                ),
                              ),
                              errorWidget: (context, url, error) {
                                print('❌ Image cache load Error: $error');
                                print('URL: ${item.images.first}');
                                return _buildPlaceholderImage();
                              },
                            ),
                          ),
                        ),
                      const SizedBox(height: 20),
                      // Title
                      Text(
                        item.title,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Category
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00897B).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          item.category,
                          style: const TextStyle(
                            color: Color(0xFF00897B),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      // Lender Info
                      InkWell(
                        onTap: () {
                          Navigator.pop(context); // Close modal first
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => UserPublicProfileScreen(
                                userId: item.lenderId,
                              ),
                            ),
                          );
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 8,
                          ),
                          child: Row(
                            children: [
                              const CircleAvatar(
                                backgroundColor: Color(0xFF00897B),
                                child: Icon(Icons.person, color: Colors.white),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Listed by',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey,
                                      ),
                                    ),
                                    Text(
                                      item.lenderName,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF00897B),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(
                                Icons.arrow_forward_ios,
                                size: 14,
                                color: Colors.grey[400],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      // Location/Barangay - More Prominent
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00897B).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0xFF00897B).withOpacity(0.3),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.location_on,
                              color: const Color(0xFF00897B),
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Location',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _getDisplayLocation(item),
                                    style: const TextStyle(
                                      fontSize: 16,
                                      color: Color(0xFF00897B),
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      // Description
                      const Text(
                        'Description',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        item.description,
                        style: TextStyle(
                          fontSize: 15,
                          color: Colors.grey[700],
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 20),
                      // Condition
                      Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.grey[600]),
                          const SizedBox(width: 8),
                          const Text(
                            'Condition: ',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            item.condition,
                            style: TextStyle(color: Colors.grey[700]),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      // Action Buttons
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () {
                                Navigator.pop(context);
                                _messageOwner(item);
                              },
                              icon: const Icon(Icons.message),
                              label: const Text('Message Owner'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFF00897B),
                                side: const BorderSide(
                                  color: Color(0xFF00897B),
                                  width: 2,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: _requestedItemIds.contains(item.itemId)
                                  ? null
                                  : () {
                                      _submitBorrowRequest(item);
                                    },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF00897B),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: Text(
                                _requestedItemIds.contains(item.itemId)
                                    ? 'Requested'
                                    : 'Request',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _normalizeStorageUrl(String url) {
    // Keep original URL; modern buckets use .firebasestorage.app
    return url;
  }

  /// Gets display location (full address)
  String _getDisplayLocation(ItemModel item) {
    return item.location ?? 'Location not specified';
  }
}
