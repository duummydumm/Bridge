import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:share_plus/share_plus.dart';
import '../providers/auth_provider.dart';
import '../providers/item_provider.dart';
import '../providers/user_provider.dart';
import '../providers/rental_listing_provider.dart';
import '../providers/rental_request_provider.dart';
import '../providers/trade_item_provider.dart';
import '../models/item_model.dart';
import '../models/rental_listing_model.dart';
import '../models/rental_request_model.dart';
import '../models/trade_item_model.dart';
import '../services/firestore_service.dart';
import '../services/local_notifications_service.dart';
import '../services/rating_service.dart';
import '../screens/submit_rating_screen.dart';
import '../models/rating_model.dart';
import 'rental/rental_request_detail_screen.dart';
import 'rental/active_rental_detail_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class MyListingsScreen extends StatefulWidget {
  final int initialTab;
  const MyListingsScreen({super.key, this.initialTab = 0});

  @override
  State<MyListingsScreen> createState() => _MyListingsScreenState();
}

class _MyListingsScreenState extends State<MyListingsScreen>
    with SingleTickerProviderStateMixin {
  // Multi-select state
  bool _selectionMode = false;
  final Set<String> _selectedIds = <String>{};
  Future<List<Map<String, dynamic>>>? _myRentalsFuture;
  late TabController _tabController;

  void _toggleSelection(ItemModel item) {
    setState(() {
      if (_selectedIds.contains(item.itemId)) {
        _selectedIds.remove(item.itemId);
      } else {
        _selectedIds.add(item.itemId);
      }
      _selectionMode = _selectedIds.isNotEmpty;
    });
  }

  void _exitSelection() {
    setState(() {
      _selectedIds.clear();
      _selectionMode = false;
    });
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 4,
      initialIndex: widget.initialTab,
      vsync: this,
    );
    // Subscribe after first frame to avoid notifying during build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final itemProvider = Provider.of<ItemProvider>(context, listen: false);
      final rentalListingProvider = Provider.of<RentalListingProvider>(
        context,
        listen: false,
      );
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final userId = userProvider.currentUser?.uid ?? authProvider.user?.uid;
      if (userId != null) {
        itemProvider.subscribeToMyItems(userId);
        rentalListingProvider.loadMyListings(userId);
        Provider.of<TradeItemProvider>(
          context,
          listen: false,
        ).loadMyTradeItems(userId);
        // Cache rentals future to avoid rebuild-triggered refetches
        setState(() {
          _myRentalsFuture = FirestoreService().getRentalListingsByOwner(
            userId,
          );
        });
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final itemProvider = Provider.of<ItemProvider>(context);
    final rentalListingProvider = Provider.of<RentalListingProvider>(context);
    final tradeItemProvider = Provider.of<TradeItemProvider>(context);
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final userId = userProvider.currentUser?.uid ?? authProvider.user?.uid;

    return Scaffold(
      appBar: AppBar(
        title: _selectionMode
            ? Text('${_selectedIds.length} selected')
            : const Text('My Listings'),
        backgroundColor: const Color(0xFF00897B),
        foregroundColor: Colors.white,
        elevation: 0,
        leading: _selectionMode
            ? IconButton(
                onPressed: _exitSelection,
                icon: const Icon(Icons.close),
              )
            : null,
        actions: _selectionMode
            ? [
                Builder(
                  builder: (ctx) {
                    final tab = _tabController.index;
                    List<Widget> buttons = [];
                    if (tab == 1) {
                      buttons = [
                        IconButton(
                          tooltip: 'Select all',
                          icon: const Icon(Icons.select_all),
                          onPressed: () {
                            final ids = Provider.of<RentalListingProvider>(
                              ctx,
                              listen: false,
                            ).myListings.map((e) => e.id).toList();
                            setState(() {
                              _selectedIds
                                ..clear()
                                ..addAll(ids);
                            });
                          },
                        ),
                        IconButton(
                          tooltip: 'Deactivate',
                          icon: const Icon(Icons.visibility_off_outlined),
                          onPressed: () async {
                            final provider = Provider.of<RentalListingProvider>(
                              ctx,
                              listen: false,
                            );
                            for (final listing in provider.myListings.where(
                              (e) => _selectedIds.contains(e.id),
                            )) {
                              await provider.setListingActive(
                                listing.id,
                                false,
                              );
                            }
                            if (mounted) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                const SnackBar(
                                  content: Text('Deactivated selected'),
                                ),
                              );
                            }
                            _exitSelection();
                          },
                        ),
                        IconButton(
                          tooltip: 'Activate',
                          icon: const Icon(Icons.visibility_outlined),
                          onPressed: () async {
                            final provider = Provider.of<RentalListingProvider>(
                              ctx,
                              listen: false,
                            );
                            for (final listing in provider.myListings.where(
                              (e) => _selectedIds.contains(e.id),
                            )) {
                              await provider.setListingActive(listing.id, true);
                            }
                            if (mounted) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                const SnackBar(
                                  content: Text('Activated selected'),
                                ),
                              );
                            }
                            _exitSelection();
                          },
                        ),
                        IconButton(
                          tooltip: 'Delete',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            final confirmed = await showDialog<bool>(
                              context: ctx,
                              builder: (c) => AlertDialog(
                                title: const Text('Delete listings'),
                                content: const Text(
                                  'This will permanently delete selected listings. Listings with active rental requests cannot be deleted.',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(c, false),
                                    child: const Text('Cancel'),
                                  ),
                                  TextButton(
                                    onPressed: () => Navigator.pop(c, true),
                                    style: TextButton.styleFrom(
                                      foregroundColor: Colors.red,
                                    ),
                                    child: const Text('Delete'),
                                  ),
                                ],
                              ),
                            );
                            if (confirmed != true) return;

                            final provider = Provider.of<RentalListingProvider>(
                              ctx,
                              listen: false,
                            );
                            int deletedCount = 0;
                            int failedCount = 0;
                            for (final listing in provider.myListings.where(
                              (e) => _selectedIds.contains(e.id),
                            )) {
                              final success = await provider.deleteListing(
                                listing.id,
                              );
                              if (success) {
                                deletedCount++;
                              } else {
                                failedCount++;
                              }
                            }
                            if (mounted) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    failedCount > 0
                                        ? 'Deleted $deletedCount, $failedCount failed (may have active rentals)'
                                        : 'Deleted $deletedCount listing${deletedCount != 1 ? 's' : ''}',
                                  ),
                                  backgroundColor: failedCount > 0
                                      ? Colors.orange
                                      : Colors.green,
                                ),
                              );
                            }
                            _exitSelection();
                          },
                        ),
                      ];
                    } else if (tab == 2) {
                      buttons = [
                        IconButton(
                          tooltip: 'Select all',
                          icon: const Icon(Icons.select_all),
                          onPressed: () {
                            final ids = Provider.of<TradeItemProvider>(
                              ctx,
                              listen: false,
                            ).myTradeItems.map((e) => e.id).toList();
                            setState(() {
                              _selectedIds
                                ..clear()
                                ..addAll(ids);
                            });
                          },
                        ),
                        IconButton(
                          tooltip: 'Close',
                          icon: const Icon(Icons.lock_outline),
                          onPressed: () async {
                            final provider = Provider.of<TradeItemProvider>(
                              ctx,
                              listen: false,
                            );
                            for (final t in provider.myTradeItems.where(
                              (e) => _selectedIds.contains(e.id),
                            )) {
                              await provider.setTradeItemActive(t.id, false);
                            }
                            if (mounted) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                const SnackBar(
                                  content: Text('Closed selected'),
                                ),
                              );
                            }
                            _exitSelection();
                          },
                        ),
                        IconButton(
                          tooltip: 'Open',
                          icon: const Icon(Icons.lock_open_outlined),
                          onPressed: () async {
                            final provider = Provider.of<TradeItemProvider>(
                              ctx,
                              listen: false,
                            );
                            for (final t in provider.myTradeItems.where(
                              (e) => _selectedIds.contains(e.id),
                            )) {
                              await provider.setTradeItemActive(t.id, true);
                            }
                            if (mounted) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                const SnackBar(
                                  content: Text('Opened selected'),
                                ),
                              );
                            }
                            _exitSelection();
                          },
                        ),
                        IconButton(
                          tooltip: 'Delete',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            final confirmed = await showDialog<bool>(
                              context: ctx,
                              builder: (c) => AlertDialog(
                                title: const Text('Delete trade items'),
                                content: const Text(
                                  'This will permanently delete selected trade items. Items with active trade offers cannot be deleted.',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(c, false),
                                    child: const Text('Cancel'),
                                  ),
                                  TextButton(
                                    onPressed: () => Navigator.pop(c, true),
                                    style: TextButton.styleFrom(
                                      foregroundColor: Colors.red,
                                    ),
                                    child: const Text('Delete'),
                                  ),
                                ],
                              ),
                            );
                            if (confirmed != true) return;

                            final provider = Provider.of<TradeItemProvider>(
                              ctx,
                              listen: false,
                            );
                            final userProvider = Provider.of<UserProvider>(
                              ctx,
                              listen: false,
                            );
                            final authProvider = Provider.of<AuthProvider>(
                              ctx,
                              listen: false,
                            );
                            final userId =
                                userProvider.currentUser?.uid ??
                                authProvider.user?.uid;
                            if (userId == null) return;

                            int deletedCount = 0;
                            int failedCount = 0;
                            for (final t in provider.myTradeItems.where(
                              (e) => _selectedIds.contains(e.id),
                            )) {
                              // Check for active offers before deleting
                              final hasActive = await FirestoreService()
                                  .hasActiveTradeOffers(t.id);
                              if (hasActive) {
                                failedCount++;
                                continue;
                              }
                              final success = await provider.deleteTradeItem(
                                t.id,
                                userId,
                              );
                              if (success) {
                                deletedCount++;
                              } else {
                                failedCount++;
                              }
                            }
                            if (mounted) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    failedCount > 0
                                        ? 'Deleted $deletedCount, $failedCount failed (may have active offers)'
                                        : 'Deleted $deletedCount trade item${deletedCount != 1 ? 's' : ''}',
                                  ),
                                  backgroundColor: failedCount > 0
                                      ? Colors.orange
                                      : Colors.green,
                                ),
                              );
                            }
                            _exitSelection();
                          },
                        ),
                      ];
                    } else {
                      buttons = [
                        IconButton(
                          tooltip: 'Select all',
                          icon: const Icon(Icons.select_all),
                          onPressed: () {
                            final items = Provider.of<ItemProvider>(
                              ctx,
                              listen: false,
                            ).myItems;
                            final isDonate = tab == 3;
                            final ids = items
                                .where(
                                  (e) =>
                                      (e.type).toLowerCase() ==
                                      (isDonate ? 'donate' : 'lend'),
                                )
                                .map((e) => e.itemId)
                                .toList();
                            setState(() {
                              _selectedIds
                                ..clear()
                                ..addAll(ids);
                            });
                          },
                        ),
                        IconButton(
                          tooltip: 'Hide',
                          icon: const Icon(Icons.visibility_off_outlined),
                          onPressed: () async {
                            final provider = Provider.of<ItemProvider>(
                              ctx,
                              listen: false,
                            );
                            final items = provider.myItems.where(
                              (e) => _selectedIds.contains(e.itemId),
                            );
                            for (final item in items) {
                              if (item.status != ItemStatus.borrowed) {
                                await provider.updateItemStatus(
                                  item.itemId,
                                  ItemStatus.unavailable,
                                );
                              }
                            }
                            if (mounted) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                const SnackBar(
                                  content: Text('Hidden selected'),
                                ),
                              );
                            }
                            _exitSelection();
                          },
                        ),
                        IconButton(
                          tooltip: 'Unhide',
                          icon: const Icon(Icons.visibility_outlined),
                          onPressed: () async {
                            final provider = Provider.of<ItemProvider>(
                              ctx,
                              listen: false,
                            );
                            final items = provider.myItems.where(
                              (e) => _selectedIds.contains(e.itemId),
                            );
                            for (final item in items) {
                              if (item.status != ItemStatus.borrowed) {
                                await provider.updateItemStatus(
                                  item.itemId,
                                  ItemStatus.available,
                                );
                              }
                            }
                            if (mounted) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                const SnackBar(
                                  content: Text('Unhidden selected'),
                                ),
                              );
                            }
                            _exitSelection();
                          },
                        ),
                        IconButton(
                          tooltip: 'Delete',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            final confirmed = await showDialog<bool>(
                              context: ctx,
                              builder: (c) => AlertDialog(
                                title: const Text('Delete items'),
                                content: const Text(
                                  'This will permanently delete selected items.',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(c, false),
                                    child: const Text('Cancel'),
                                  ),
                                  TextButton(
                                    onPressed: () => Navigator.pop(c, true),
                                    child: const Text('Delete'),
                                  ),
                                ],
                              ),
                            );
                            if (confirmed != true) return;
                            final provider = Provider.of<ItemProvider>(
                              ctx,
                              listen: false,
                            );
                            final items = provider.myItems.where(
                              (e) => _selectedIds.contains(e.itemId),
                            );
                            for (final item in items) {
                              await provider.deleteItem(
                                item.itemId,
                                item.lenderId,
                              );
                            }
                            if (mounted) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                const SnackBar(
                                  content: Text('Deleted selected'),
                                ),
                              );
                            }
                            _exitSelection();
                          },
                        ),
                      ];
                    }
                    return Row(children: buttons);
                  },
                ),
              ]
            : null,
        bottom: TabBar(
          controller: _tabController,
          isScrollable: false,
          tabs: const [
            Tab(text: 'Lend'),
            Tab(text: 'Rent'),
            Tab(text: 'Trade'),
            Tab(text: 'Donate'),
          ],
        ),
      ),
      backgroundColor: Colors.grey[50],
      body: RefreshIndicator(
        onRefresh: () async {
          if (userId != null) {
            await itemProvider.loadMyItems(userId);
            await rentalListingProvider.loadMyListings(userId);
            setState(() {
              _myRentalsFuture = FirestoreService().getRentalListingsByOwner(
                userId,
              );
            });
          }
        },
        child: userId == null
            ? _buildEmptyState()
            : StreamBuilder<List<ItemModel>>(
                stream: itemProvider.myItemsStream,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Error: ${snapshot.error}',
                            style: const TextStyle(color: Colors.red),
                          ),
                          const SizedBox(height: 8),
                          ElevatedButton(
                            onPressed: () => itemProvider.loadMyItems(userId),
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    );
                  }

                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final data = snapshot.data!;
                  List<ItemModel> lend = data
                      .where((e) => (e.type).toLowerCase() == 'lend')
                      .toList();
                  // Trade items live in a separate collection; use its provider
                  List<ItemModel> donate = data
                      .where((e) => (e.type).toLowerCase() == 'donate')
                      .toList();

                  Widget buildList(List<ItemModel> list) {
                    if (list.isEmpty) {
                      return ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          const SizedBox(height: 80),
                          Center(
                            child: Text(
                              'No items here yet',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      );
                    }
                    return ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: list.length,
                      itemBuilder: (context, index) =>
                          _buildListTile(context, list[index]),
                    );
                  }

                  Widget buildRentalListings() {
                    final rentalListings = rentalListingProvider.myListings;
                    // Use cached future to access denormalized fields (title, imageUrl)
                    if (_myRentalsFuture == null) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    return FutureBuilder<List<Map<String, dynamic>>>(
                      future: _myRentalsFuture,
                      builder: (context, snapshot) {
                        // Show loading only if we're actually waiting for data
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        // Handle errors
                        if (snapshot.hasError) {
                          return Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  'Error: ${snapshot.error}',
                                  style: const TextStyle(color: Colors.red),
                                ),
                                const SizedBox(height: 8),
                                ElevatedButton(
                                  onPressed: () {
                                    final userId =
                                        userProvider.currentUser?.uid ??
                                        authProvider.user?.uid;
                                    if (userId != null) {
                                      setState(() {
                                        _myRentalsFuture = FirestoreService()
                                            .getRentalListingsByOwner(userId);
                                      });
                                    }
                                  },
                                  child: const Text('Retry'),
                                ),
                              ],
                            ),
                          );
                        }
                        // Show empty state if no data
                        final rawListings = snapshot.data ?? [];
                        if (rawListings.isEmpty) {
                          return ListView(
                            padding: const EdgeInsets.all(16),
                            children: [
                              const SizedBox(height: 80),
                              Center(
                                child: Text(
                                  'No items here yet',
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          );
                        }
                        return ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: rawListings.length,
                          itemBuilder: (context, index) {
                            final rawData = rawListings[index];
                            // Use rawData for isActive to ensure we have the latest value from Firestore
                            final isActiveFromFirestore =
                                rawData['isActive'] as bool? ?? true;
                            final listing = rentalListings.firstWhere(
                              (l) => l.id == rawData['id'],
                              orElse: () => RentalListingModel(
                                id: rawData['id'] ?? '',
                                itemId: rawData['itemId'] ?? '',
                                ownerId: rawData['ownerId'] ?? '',
                                pricingMode: PricingMode.perDay,
                                isActive: isActiveFromFirestore,
                                createdAt: DateTime.now(),
                              ),
                            );
                            // Create a listing with the latest isActive value from Firestore
                            // Copy all fields from the original listing but update isActive
                            final listingWithLatestStatus = RentalListingModel(
                              id: listing.id,
                              itemId: listing.itemId,
                              ownerId: listing.ownerId,
                              pricingMode: listing.pricingMode,
                              pricePerDay: listing.pricePerDay,
                              pricePerWeek: listing.pricePerWeek,
                              pricePerMonth: listing.pricePerMonth,
                              minDays: listing.minDays,
                              maxDays: listing.maxDays,
                              securityDeposit: listing.securityDeposit,
                              cancellationPolicy: listing.cancellationPolicy,
                              termsUrl: listing.termsUrl,
                              isActive: isActiveFromFirestore,
                              allowMultipleRentals:
                                  listing.allowMultipleRentals,
                              quantity: listing.quantity,
                              createdAt: listing.createdAt,
                              updatedAt: listing.updatedAt,
                            );
                            // Extract pricing data from raw data
                            final pricingMode =
                                (rawData['pricingMode'] ?? 'perDay')
                                    .toString()
                                    .toLowerCase();
                            final pricePerDay = (rawData['pricePerDay'] as num?)
                                ?.toDouble();
                            final pricePerWeek =
                                (rawData['pricePerWeek'] as num?)?.toDouble();
                            final pricePerMonth =
                                (rawData['pricePerMonth'] as num?)?.toDouble();

                            return _buildRentalListingTile(
                              context,
                              listingWithLatestStatus,
                              rawData['title'] as String?,
                              rawData['imageUrl'] as String?,
                              pricingMode,
                              pricePerDay,
                              pricePerWeek,
                              pricePerMonth,
                            );
                          },
                        );
                      },
                    );
                  }

                  Widget buildTradeList() {
                    if (tradeItemProvider.isLoading) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final trades = tradeItemProvider.myTradeItems;
                    if (trades.isEmpty) {
                      return ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          const SizedBox(height: 80),
                          Center(
                            child: Text(
                              'No items here yet',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      );
                    }
                    return ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: trades.length,
                      itemBuilder: (context, index) =>
                          _buildTradeListTile(context, trades[index]),
                    );
                  }

                  return TabBarView(
                    controller: _tabController,
                    children: [
                      buildList(lend),
                      buildRentalListings(),
                      buildTradeList(),
                      buildList(donate),
                    ],
                  );
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
          Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 12),
          Text(
            'You haven\'t listed any items yet',
            style: TextStyle(
              color: Colors.grey[600],
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap the + button on Home to list an item',
            style: TextStyle(color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  Widget _buildListTile(BuildContext context, ItemModel item) {
    final isSelected = _selectedIds.contains(item.itemId);
    final statusColor = _statusColor(item.status);
    return Slidable(
      key: ValueKey(item.itemId),
      closeOnScroll: true,
      endActionPane: ActionPane(
        motion: const StretchMotion(),
        extentRatio: 0.30,
        children: [
          SlidableAction(
            onPressed: (_) async {
              final text = '${item.title}\n${item.description}';
              await Share.share(text);
            },
            backgroundColor: const Color(0xFF00897B),
            foregroundColor: Colors.white,
            icon: Icons.share_outlined,
            label: 'Share',
          ),
          SlidableAction(
            onPressed: (_) {
              Navigator.pushNamed(
                context,
                '/list-item',
                arguments: {'itemId': item.itemId, 'listingType': item.type},
              );
            },
            backgroundColor: const Color(0xFF546E7A),
            foregroundColor: Colors.white,
            icon: Icons.edit_outlined,
            label: 'Edit',
            borderRadius: const BorderRadius.only(
              topRight: Radius.circular(12),
              bottomRight: Radius.circular(12),
            ),
          ),
        ],
      ),
      child: Card(
        margin: const EdgeInsets.only(bottom: 12),
        shape: RoundedRectangleBorder(
          side: BorderSide(
            color: isSelected ? const Color(0xFF00897B) : Colors.transparent,
            width: isSelected ? 2 : 0,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: ListTile(
          dense: true,
          visualDensity: const VisualDensity(horizontal: 0, vertical: -3),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 2,
          ),
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: 44,
              height: 44,
              color: Colors.grey[200],
              child: item.hasImages
                  ? CachedNetworkImage(
                      imageUrl: _normalizeStorageUrl(item.images.first),
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Center(
                        child: SizedBox(
                          height: 20,
                          width: 20,
                          child: const CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        ),
                      ),
                      errorWidget: (context, url, error) => Icon(
                        Icons.broken_image_outlined,
                        color: Colors.grey[400],
                      ),
                    )
                  : Icon(Icons.image_outlined, color: Colors.grey[400]),
            ),
          ),
          title: Text(
            item.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Status: ${item.statusDisplay}',
                style: TextStyle(color: Colors.grey[600]),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  Chip(
                    label: Text(item.statusDisplay),
                    backgroundColor: statusColor.withOpacity(0.12),
                    labelStyle: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.w600,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                  if (item.pricePerDay != null)
                    Chip(
                      label: Text(
                        '₱${item.pricePerDay!.toStringAsFixed(0)}/day',
                      ),
                      backgroundColor: const Color(0xFFE0F2F1),
                      labelStyle: const TextStyle(
                        color: Color(0xFF00796B),
                        fontWeight: FontWeight.w600,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
            ],
          ),
          trailing: _selectionMode
              ? Checkbox(
                  value: isSelected,
                  onChanged: (_) => _toggleSelection(item),
                )
              : _buildTrailingActions(item),
          onTap: () {
            if (_selectionMode) {
              _toggleSelection(item);
            }
          },
          onLongPress: () {
            if (!_selectionMode) {
              setState(() {
                _selectionMode = true;
                _selectedIds.add(item.itemId);
              });
            }
          },
        ),
      ),
    );
  }

  Widget _buildTradeListTile(BuildContext context, TradeItemModel trade) {
    final thumbUrl = trade.offeredImageUrl;
    final isSelected = _selectedIds.contains(trade.id);
    return Slidable(
      key: ValueKey('trade_${trade.id}'),
      closeOnScroll: true,
      endActionPane: ActionPane(
        motion: const StretchMotion(),
        extentRatio: 0.30,
        children: [
          SlidableAction(
            onPressed: (_) async {
              final text =
                  '${trade.offeredItemName}\n${trade.offeredDescription}';
              await Share.share(text);
            },
            backgroundColor: const Color(0xFF00897B),
            foregroundColor: Colors.white,
            icon: Icons.share_outlined,
            label: 'Share',
          ),
          // Only show Edit button if item is not traded
          if (trade.status != TradeStatus.traded)
            SlidableAction(
              onPressed: (_) {
                Navigator.pushNamed(
                  context,
                  '/trade/add-item',
                  arguments: {'tradeItemId': trade.id},
                );
              },
              backgroundColor: const Color(0xFF546E7A),
              foregroundColor: Colors.white,
              icon: Icons.edit_outlined,
              label: 'Edit',
              borderRadius: const BorderRadius.only(
                topRight: Radius.circular(12),
                bottomRight: Radius.circular(12),
              ),
            ),
        ],
      ),
      child: Card(
        margin: const EdgeInsets.only(bottom: 12),
        shape: RoundedRectangleBorder(
          side: BorderSide(
            color: isSelected ? const Color(0xFF00897B) : Colors.transparent,
            width: isSelected ? 2 : 0,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: ListTile(
          dense: true,
          visualDensity: const VisualDensity(horizontal: 0, vertical: -3),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 2,
          ),
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: 44,
              height: 44,
              color: Colors.grey[200],
              child: (thumbUrl != null && thumbUrl.isNotEmpty)
                  ? CachedNetworkImage(
                      imageUrl: thumbUrl,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Center(
                        child: SizedBox(
                          height: 20,
                          width: 20,
                          child: const CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        ),
                      ),
                      errorWidget: (context, url, error) => Icon(
                        Icons.broken_image_outlined,
                        color: Colors.grey[400],
                      ),
                    )
                  : Icon(Icons.image_outlined, color: Colors.grey[400]),
            ),
          ),
          title: Text(
            trade.offeredItemName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: Row(
            children: [
              Chip(
                label: Text(
                  trade.status == TradeStatus.open
                      ? 'Open'
                      : trade.status == TradeStatus.closed
                      ? 'Closed'
                      : 'Traded',
                ),
                backgroundColor: Colors.blueGrey.withOpacity(0.12),
                labelStyle: const TextStyle(
                  color: Color(0xFF546E7A),
                  fontWeight: FontWeight.w600,
                ),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 6),
              ),
            ],
          ),
          trailing: _selectionMode
              ? Checkbox(
                  value: isSelected,
                  onChanged: (_) {
                    setState(() {
                      if (isSelected) {
                        _selectedIds.remove(trade.id);
                      } else {
                        _selectedIds.add(trade.id);
                      }
                      _selectionMode = _selectedIds.isNotEmpty;
                    });
                  },
                )
              : const Icon(Icons.chevron_right),
          onTap: () {
            if (_selectionMode) {
              setState(() {
                if (isSelected) {
                  _selectedIds.remove(trade.id);
                } else {
                  _selectedIds.add(trade.id);
                }
                _selectionMode = _selectedIds.isNotEmpty;
              });
              return;
            }
          },
          onLongPress: () {
            if (!_selectionMode) {
              setState(() {
                _selectionMode = true;
                _selectedIds.add(trade.id);
              });
            }
          },
        ),
      ),
    );
  }

  Widget _buildTrailingActions(ItemModel item) {
    if (item.status == ItemStatus.borrowed) {
      return IconButton(
        tooltip: 'Mark returned',
        onPressed: () async {
          try {
            await FirestoreService().markItemReturned(itemId: item.itemId);
            await LocalNotificationsService().cancelReturnReminders(
              item.itemId,
            );
            // Cancel overdue reminders when item is returned
            await LocalNotificationsService().cancelOverdueReminders(
              item.itemId,
            );
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Marked as returned')),
              );
            }
            // After successful return, prompt for rating (Borrow context)
            if (mounted) {
              await _promptForBorrowRating(item);
            }
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Error: $e'),
                  backgroundColor: Colors.red,
                ),
              );
            }
          }
        },
        icon: const Icon(
          Icons.assignment_turned_in_outlined,
          color: Color(0xFF00897B),
        ),
      );
    }
    return const Icon(Icons.chevron_right);
  }

  /// Build trailing actions for rental listings (similar to borrow items)
  Widget _buildRentalTrailingActions(RentalListingModel listing) {
    // Check for active rental requests for this listing
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('rental_requests')
          .where('listingId', isEqualTo: listing.id)
          .where('status', whereIn: ['active', 'returninitiated'])
          .limit(1)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          // No active rental - show normal icon
          return listing.isActive
              ? const Icon(Icons.check_circle, color: Color(0xFF2ECC71))
              : const Icon(Icons.cancel, color: Colors.grey);
        }

        final requestDoc = snapshot.data!.docs.first;
        final requestData = requestDoc.data();
        final status = requestData['status'] as String? ?? '';
        final requestId = requestDoc.id;

        // If return is initiated, show "Verify Return" button
        if (status == 'returninitiated') {
          return IconButton(
            tooltip: 'Verify Return',
            onPressed: () async {
              try {
                final reqProvider = Provider.of<RentalRequestProvider>(
                  context,
                  listen: false,
                );
                final authProvider = Provider.of<AuthProvider>(
                  context,
                  listen: false,
                );
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

                final success = await reqProvider.verifyReturn(
                  requestId,
                  currentUser.uid,
                );

                if (mounted) {
                  if (success) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Return verified! Rental completed.'),
                        backgroundColor: Colors.green,
                      ),
                    );
                    // Prompt for rating after successful return
                    await _promptForRentalRating(requestId);
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
                    SnackBar(
                      content: Text('Error: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            icon: const Icon(Icons.verified, color: Colors.green),
          );
        }

        // If active rental, show indicator
        return const Icon(Icons.shopping_bag, color: Colors.orange);
      },
    );
  }

  Future<void> _promptForRentalRating(String requestId) async {
    try {
      final requestData = await FirestoreService().getRentalRequest(requestId);
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
      final ratingService = RatingService();
      final hasRated = await ratingService.hasRated(
        raterUserId: currentUser.uid,
        ratedUserId: ratedUserId,
        transactionId: requestId,
      );

      if (hasRated) {
        return; // Already rated
      }

      // Get rated user's name if available
      String? ratedUserNameFull;
      try {
        final ratedUserData = await FirestoreService().getUser(ratedUserId);
        if (ratedUserData != null) {
          ratedUserNameFull =
              '${ratedUserData['firstName']} ${ratedUserData['lastName']}';
        }
      } catch (e) {
        // Silent fail
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
      debugPrint('Error prompting for rental rating: $e');
    }
  }

  Future<void> _promptForBorrowRating(ItemModel item) async {
    try {
      // Ensure we have a borrower to rate
      final borrowerId = item.currentBorrowerId;
      if (borrowerId == null || borrowerId.isEmpty) return;

      // Get current user (lender)
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final currentUser = authProvider.user;
      if (currentUser == null) return;

      // Prevent duplicate rating for this item/user combo (use itemId as transactionId)
      final hasRated = await FirestoreService().hasExistingRating(
        raterUserId: currentUser.uid,
        ratedUserId: borrowerId,
        transactionId: item.itemId,
      );
      if (hasRated) return;

      // Try to fetch borrower's display name
      String? borrowerName;
      try {
        final userData = await FirestoreService().getUser(borrowerId);
        if (userData != null) {
          final first = (userData['firstName'] ?? '').toString();
          final last = (userData['lastName'] ?? '').toString();
          final combined = '$first $last'.trim();
          borrowerName = combined.isEmpty ? null : combined;
        }
      } catch (_) {
        // ignore name fetch errors
      }

      if (!mounted) return;
      final shouldRate = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Rate Your Borrow Experience'),
          content: Text(
            'How was your experience lending to ${borrowerName ?? 'this borrower'}?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Maybe Later'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00897B),
              ),
              child: const Text('Rate Now'),
            ),
          ],
        ),
      );

      if (shouldRate == true && mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => SubmitRatingScreen(
              ratedUserId: borrowerId,
              ratedUserName: borrowerName,
              context: RatingContext.borrow,
              transactionId:
                  item.itemId, // scope rating to this item transaction
              role: 'lender',
            ),
          ),
        );
      }
    } catch (_) {
      // Silent fail; do not block user flow
    }
  }

  Color _statusColor(ItemStatus status) {
    switch (status) {
      case ItemStatus.available:
        return const Color(0xFF2E7D32);
      case ItemStatus.borrowed:
        return const Color(0xFFF57C00);
      case ItemStatus.unavailable:
        return const Color(0xFF757575);
      case ItemStatus.pending:
        return const Color(0xFF1565C0);
    }
  }

  Widget _buildRentalListingTile(
    BuildContext context,
    RentalListingModel listing,
    String? title,
    String? imageUrl,
    String pricingMode,
    double? pricePerDay,
    double? pricePerWeek,
    double? pricePerMonth,
  ) {
    final priceText = pricingMode == 'permonth'
        ? '₱${(pricePerMonth ?? 0).toStringAsFixed(0)}/month'
        : pricingMode == 'perweek'
        ? '₱${(pricePerWeek ?? 0).toStringAsFixed(0)}/week'
        : '₱${(pricePerDay ?? 0).toStringAsFixed(0)}/day';

    final isSelected = _selectedIds.contains(listing.id);
    return Slidable(
      key: ValueKey('rental_${listing.id}'),
      closeOnScroll: true,
      endActionPane: ActionPane(
        motion: const StretchMotion(),
        extentRatio: 0.30,
        children: [
          SlidableAction(
            onPressed: (_) async {
              final text = '${title ?? 'Rental Listing'}\n$priceText';
              await Share.share(text);
            },
            backgroundColor: const Color(0xFF00897B),
            foregroundColor: Colors.white,
            icon: Icons.share_outlined,
            label: 'Share',
          ),
          SlidableAction(
            onPressed: (_) async {
              // Check for active rental requests before allowing edit
              final hasActive = await FirestoreService()
                  .hasActiveRentalRequests(listing.id);
              if (hasActive) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Cannot edit listing with active rental requests. Please wait for all rentals to complete.',
                      ),
                      backgroundColor: Colors.orange,
                      duration: Duration(seconds: 4),
                    ),
                  );
                }
                return;
              }
              if (mounted) {
                Navigator.pushNamed(
                  context,
                  '/rental/listing-editor',
                  arguments: {'listingId': listing.id},
                );
              }
            },
            backgroundColor: const Color(0xFF546E7A),
            foregroundColor: Colors.white,
            icon: Icons.edit_outlined,
            label: 'Edit',
            borderRadius: const BorderRadius.only(
              topRight: Radius.circular(12),
              bottomRight: Radius.circular(12),
            ),
          ),
        ],
      ),
      child: Card(
        margin: const EdgeInsets.only(bottom: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: ListTile(
          dense: true,
          visualDensity: const VisualDensity(horizontal: 0, vertical: -3),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 2,
          ),
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: 44,
              height: 35,
              color: Colors.grey[200],
              child: imageUrl != null && imageUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: imageUrl,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Center(
                        child: SizedBox(
                          height: 20,
                          width: 20,
                          child: const CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        ),
                      ),
                      errorWidget: (context, url, error) => Icon(
                        Icons.broken_image_outlined,
                        color: Colors.grey[400],
                      ),
                    )
                  : Icon(Icons.image_outlined, color: Colors.grey[400]),
            ),
          ),
          title: Text(
            title ?? 'Rental Listing',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                priceText,
                style: const TextStyle(
                  color: Color(0xFF00A676),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Chip(
                    label: Text(listing.isActive ? 'Active' : 'Inactive'),
                    backgroundColor:
                        (listing.isActive
                                ? const Color(0xFF2ECC71)
                                : Colors.grey)
                            .withOpacity(0.15),
                    labelStyle: TextStyle(
                      color: listing.isActive
                          ? const Color(0xFF2E7D32)
                          : Colors.grey[700],
                      fontWeight: FontWeight.w600,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ],
          ),
          trailing: _selectionMode
              ? Checkbox(
                  value: isSelected,
                  onChanged: (_) {
                    setState(() {
                      if (isSelected) {
                        _selectedIds.remove(listing.id);
                      } else {
                        _selectedIds.add(listing.id);
                      }
                      _selectionMode = _selectedIds.isNotEmpty;
                    });
                  },
                )
              : _buildRentalTrailingActions(listing),
          onTap: () async {
            if (_selectionMode) {
              setState(() {
                if (isSelected) {
                  _selectedIds.remove(listing.id);
                } else {
                  _selectedIds.add(listing.id);
                }
                _selectionMode = _selectedIds.isNotEmpty;
              });
              return;
            }
            // First check if there's an active rental request for this listing
            final activeRequestId = await FirestoreService()
                .getActiveRentalRequestId(listing.id);
            if (activeRequestId != null) {
              // Navigate to active rental detail screen
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      ActiveRentalDetailScreen(requestId: activeRequestId),
                ),
              );
            } else {
              // Check if there's any rental request history (including completed)
              final recentRequestId = await FirestoreService()
                  .getMostRecentRentalRequestId(listing.id);
              if (recentRequestId != null) {
                // Navigate to most recent rental request detail screen
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        RentalRequestDetailScreen(requestId: recentRequestId),
                  ),
                );
              } else {
                // No rental history - navigate to public view of the listing
                // Users can use the slidable edit action if they want to edit
                Navigator.pushNamed(
                  context,
                  '/rental/rent-item',
                  arguments: {'listingId': listing.id},
                );
              }
            }
          },
          onLongPress: () {
            if (!_selectionMode) {
              setState(() {
                _selectionMode = true;
                _selectedIds.add(listing.id);
              });
            }
          },
        ),
      ),
    );
  }

  String _normalizeStorageUrl(String url) {
    // Keep original URL; modern buckets use .firebasestorage.app
    return url;
  }
}
