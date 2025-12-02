import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../models/item_model.dart';
import '../models/rental_listing_model.dart';
import '../models/giveaway_listing_model.dart';
import '../services/firestore_service.dart';

class UserListingsScreen extends StatefulWidget {
  const UserListingsScreen({
    super.key,
    required this.userId,
    required this.userName,
  });

  final String userId;
  final String userName;

  @override
  State<UserListingsScreen> createState() => _UserListingsScreenState();
}

class _UserListingsScreenState extends State<UserListingsScreen> {
  final FirestoreService _firestoreService = FirestoreService();

  bool _isLoading = true;
  String? _error;
  List<ItemModel> _items = [];
  List<RentalListingModel> _rentalListings = [];
  List<GiveawayListingModel> _giveawayListings = [];

  /// 'all', 'lend', 'rent', 'trade', 'donate'
  String _selectedTypeFilter = 'all';

  @override
  void initState() {
    super.initState();
    _loadListings();
  }

  Future<void> _loadListings() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Core borrow / trade items
      final itemsData = await _firestoreService.getItemsByLender(widget.userId);

      final items = itemsData
          .map((data) {
            try {
              return ItemModel.fromMap(data, data['id'] ?? '');
            } catch (e) {
              debugPrint('Error parsing item in user listings: $e');
              return null;
            }
          })
          .whereType<ItemModel>()
          .toList();

      // Rental listings (for Rent tab)
      final rentalsData = await _firestoreService.getRentalListingsByOwner(
        widget.userId,
      );
      final rentalListings = rentalsData
          .map((data) {
            try {
              return RentalListingModel.fromMap(
                data,
                data['id']?.toString() ?? '',
              );
            } catch (e) {
              debugPrint('Error parsing rental listing in user listings: $e');
              return null;
            }
          })
          .whereType<RentalListingModel>()
          .toList();

      // Giveaway listings (for Giveaway tab)
      final giveawaysData = await _firestoreService.getGiveawaysByUser(
        widget.userId,
      );
      final giveawayListings = giveawaysData
          .map((data) {
            try {
              return GiveawayListingModel.fromMap(
                data,
                data['id']?.toString() ?? '',
              );
            } catch (e) {
              debugPrint('Error parsing giveaway in user listings: $e');
              return null;
            }
          })
          .whereType<GiveawayListingModel>()
          .toList();

      if (!mounted) return;
      setState(() {
        _items = items;
        _rentalListings = rentalListings;
        _giveawayListings = giveawayListings;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'Failed to load listings: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Listings by ${widget.userName}'),
        backgroundColor: const Color(0xFF00897B),
      ),
      backgroundColor: Colors.grey[50],
      body: RefreshIndicator(onRefresh: _loadListings, child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 80),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  Icon(Icons.error_outline, size: 48, color: Colors.red[300]),
                  const SizedBox(height: 16),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.red[700], fontSize: 14),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    // Choose which dataset to show based on selected type
    if (_selectedTypeFilter == 'rent') {
      if (_rentalListings.isEmpty) {
        return _buildEmptyState(
          icon: Icons.home_outlined,
          title: 'No rental listings',
          subtitle: 'This user has not posted any rental listings.',
        );
      }
      return _buildRentalList();
    } else if (_selectedTypeFilter == 'donate') {
      if (_giveawayListings.isEmpty) {
        return _buildEmptyState(
          icon: Icons.card_giftcard_outlined,
          title: 'No giveaways',
          subtitle: 'This user has not posted any giveaways.',
        );
      }
      return _buildGiveawayList();
    } else {
      final filteredItems = _applyTypeFilter(_items);
      if (filteredItems.isEmpty) {
        return _buildEmptyState(
          icon: Icons.inventory_2_outlined,
          title: 'No listings yet',
          subtitle: 'This user has not posted any items yet.',
        );
      }
      return _buildItemsList(filteredItems);
    }
  }

  List<ItemModel> _applyTypeFilter(List<ItemModel> items) {
    if (_selectedTypeFilter == 'all' ||
        _selectedTypeFilter == 'rent' ||
        _selectedTypeFilter == 'donate') {
      // 'rent' and 'donate' are handled via separate collections
      return items;
    }
    return items
        .where((item) => item.type.toLowerCase() == _selectedTypeFilter)
        .toList();
  }

  Widget _buildItemsList(List<ItemModel> items) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: items.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return _buildTypeFilterRow();
        }
        final item = items[index - 1];
        return _buildItemCard(item);
      },
    );
  }

  Widget _buildRentalList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _rentalListings.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return _buildTypeFilterRow();
        }
        final listing = _rentalListings[index - 1];
        return _buildRentalCard(listing);
      },
    );
  }

  Widget _buildGiveawayList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _giveawayListings.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return _buildTypeFilterRow();
        }
        final giveaway = _giveawayListings[index - 1];
        return _buildGiveawayCard(giveaway);
      },
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        // Keep the type filter row visible even when there are no results
        Padding(
          padding: const EdgeInsets.all(16),
          child: _buildTypeFilterRow(),
        ),
        const SizedBox(height: 40),
        Center(
          child: Column(
            children: [
              Icon(icon, size: 64, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(
                title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                style: TextStyle(fontSize: 14, color: Colors.grey[500]),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTypeFilterRow() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildTypeFilterChip('All', 'all'),
            _buildTypeFilterChip('Borrow', 'lend'),
            _buildTypeFilterChip('Rent', 'rent'),
            _buildTypeFilterChip('Trade', 'trade'),
            _buildTypeFilterChip('Giveaway', 'donate'),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeFilterChip(String label, String value) {
    final bool isSelected = _selectedTypeFilter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (selected) {
          setState(() {
            _selectedTypeFilter = selected ? value : 'all';
          });
        },
        selectedColor: const Color(0xFF00897B),
        labelStyle: TextStyle(
          color: isSelected ? Colors.white : Colors.grey[800],
          fontWeight: FontWeight.w600,
        ),
        backgroundColor: Colors.grey[200],
      ),
    );
  }

  Widget _buildRentalCard(RentalListingModel listing) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: const Icon(Icons.home_outlined, color: Color(0xFF00897B)),
        title: Text(
          'Rental listing (${listing.rentType.name})',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (listing.address != null && listing.address!.isNotEmpty)
              Text(
                listing.address!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            const SizedBox(height: 4),
            Text(
              'Pricing: ${listing.pricingMode.name}',
              style: TextStyle(fontSize: 12, color: Colors.grey[700]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGiveawayCard(GiveawayListingModel giveaway) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: const Icon(
          Icons.card_giftcard_outlined,
          color: Color(0xFFE91E63),
        ),
        title: Text(
          giveaway.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              giveaway.location,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              giveaway.statusDisplay,
              style: TextStyle(fontSize: 12, color: Colors.grey[700]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemCard(ItemModel item) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          // For now, just show a bigger preview; you can later deep-link to
          // your main item details screen if you have one.
          _showItemDetails(item);
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image
            SizedBox(
              height: 180,
              width: double.infinity,
              child: item.hasImages
                  ? CachedNetworkImage(
                      imageUrl: _normalizeStorageUrl(item.images.first),
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Container(
                        color: Colors.grey[200],
                        child: const Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                      errorWidget: (context, url, error) {
                        debugPrint(
                          '❌ Image cache load Error (user listings): $error',
                        );
                        debugPrint('URL: ${item.images.first}');
                        return _buildPlaceholderImage();
                      },
                    )
                  : _buildPlaceholderImage(),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.category_outlined,
                        size: 14,
                        color: Colors.grey[600],
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          item.category,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[600],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _buildStatusChip(item.statusDisplay),
                      const SizedBox(width: 8),
                      _buildTypeChip(item.type),
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

  Widget _buildStatusChip(String statusDisplay) {
    Color color;
    switch (statusDisplay.toLowerCase()) {
      case 'available':
        color = const Color(0xFF66BB6A);
        break;
      case 'reserved':
        color = const Color(0xFFFFA726);
        break;
      case 'unavailable':
      case 'borrowed':
        color = const Color(0xFFEF5350);
        break;
      default:
        color = Colors.grey;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        statusDisplay,
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildTypeChip(String type) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.blueGrey.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        type.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          color: Colors.blueGrey,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildPlaceholderImage() {
    return Container(
      color: Colors.grey[200],
      child: const Center(
        child: Icon(Icons.image_outlined, color: Colors.grey, size: 40),
      ),
    );
  }

  String _normalizeStorageUrl(String url) {
    // Keep original URL; modern buckets use .firebasestorage.app
    return url;
  }

  void _showItemDetails(ItemModel item) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
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
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    controller: scrollController,
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (item.hasImages)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: SizedBox(
                              height: 250,
                              width: double.infinity,
                              child: CachedNetworkImage(
                                imageUrl: _normalizeStorageUrl(
                                  item.images.first,
                                ),
                                fit: BoxFit.cover,
                                placeholder: (context, url) => Container(
                                  color: Colors.grey[200],
                                  child: const Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                ),
                                errorWidget: (context, url, error) {
                                  debugPrint(
                                    '❌ Image cache load Error (detail): $error',
                                  );
                                  debugPrint('URL: ${item.images.first}');
                                  return _buildPlaceholderImage();
                                },
                              ),
                            ),
                          ),
                        const SizedBox(height: 20),
                        Text(
                          item.title,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            _buildStatusChip(item.statusDisplay),
                            const SizedBox(width: 8),
                            _buildTypeChip(item.type),
                          ],
                        ),
                        const SizedBox(height: 16),
                        if (item.description.isNotEmpty) ...[
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
                              fontSize: 14,
                              color: Colors.grey[700],
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        const Text(
                          'Details',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _buildDetailRow('Condition', item.condition),
                        _buildDetailRow('Status', item.statusDisplay),
                        if (item.pricePerDay != null)
                          _buildDetailRow(
                            'Price per Day',
                            '₱${item.pricePerDay!.toStringAsFixed(2)}',
                          ),
                        if (item.location != null && item.location!.isNotEmpty)
                          _buildDetailRow('Location', item.location!),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
