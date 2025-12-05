import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/user_provider.dart';
import '../../reusable_widgets/rental_location_filter.dart';

class RentalItemsScreen extends StatefulWidget {
  const RentalItemsScreen({super.key});

  @override
  State<RentalItemsScreen> createState() => _RentalItemsScreenState();
}

class _RentalItemsScreenState extends State<RentalItemsScreen> {
  String? _selectedBarangay;

  @override
  Widget build(BuildContext context) {
    final currentUserId = Provider.of<UserProvider>(context).currentUser?.uid;

    final listingsQuery = FirebaseFirestore.instance
        .collection('rental_listings')
        .where('isActive', isEqualTo: true)
        .where('rentType', isEqualTo: 'item')
        .limit(100);

    // Query to get user's existing rental requests (only approved/active)
    final existingRequestsQuery = currentUserId != null
        ? FirebaseFirestore.instance
              .collection('rental_requests')
              .where('renterId', isEqualTo: currentUserId)
              .where('status', whereIn: ['ownerapproved', 'active'])
              .snapshots()
        : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('All Items to Rent'),
        backgroundColor: const Color(0xFF00897B),
        foregroundColor: Colors.white,
      ),
      backgroundColor: Colors.grey[50],
      body: Column(
        children: [
          RentalLocationFilter(
            onChanged: (barangay) {
              setState(() {
                _selectedBarangay = barangay;
              });
            },
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: listingsQuery.snapshots(),
              builder: (context, snapshot) {
                // Wrap with another stream to know which listings the user
                // already has active/approved rental requests for.
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
                              'No rental items available',
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

                    // Filter out listings where user already has an approved/active
                    // rental request (i.e., currently renting).
                    if (currentUserId != null &&
                        requestedListingIds.isNotEmpty) {
                      docs = docs.where((doc) {
                        final listingId = doc.id;
                        return !requestedListingIds.contains(listingId);
                      }).toList();
                    }

                    // Filter by selected barangay (location/address contains name)
                    if (_selectedBarangay != null &&
                        _selectedBarangay!.isNotEmpty) {
                      final selectedLower = _selectedBarangay!.toLowerCase();
                      docs = docs.where((doc) {
                        final listing = doc.data();
                        final location = (listing['location'] ?? '')
                            .toString()
                            .toLowerCase();
                        final address = (listing['address'] ?? '')
                            .toString()
                            .toLowerCase();
                        return location.contains(selectedLower) ||
                            address.contains(selectedLower);
                      }).toList();
                    }

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
                              'No rental items match this location',
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

                    return GridView.builder(
                      padding: const EdgeInsets.all(12),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
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
                        final pricePerDay = (listing['pricePerDay'] as num?)
                            ?.toDouble();
                        final pricePerWeek = (listing['pricePerWeek'] as num?)
                            ?.toDouble();
                        final pricePerMonth = (listing['pricePerMonth'] as num?)
                            ?.toDouble();
                        final pricingMode = (listing['pricingMode'] ?? 'perDay')
                            .toString();
                        final isActive = (listing['isActive'] ?? true) == true;

                        final itemRef = FirebaseFirestore.instance
                            .collection('items')
                            .doc(itemId);

                        return FutureBuilder<
                          DocumentSnapshot<Map<String, dynamic>>
                        >(
                          future: itemRef.get(),
                          builder: (context, itemSnap) {
                            final isLoading =
                                itemSnap.connectionState ==
                                ConnectionState.waiting;
                            final itemData = itemSnap.data?.data();
                            final denormTitle = (listing['title'] as String?)
                                ?.trim();
                            final denormCategory =
                                (listing['category'] as String?)?.trim();
                            final denormImage = (listing['imageUrl'] as String?)
                                ?.trim();
                            final denormLocation =
                                (listing['location'] as String?)?.trim();

                            final title = denormTitle?.isNotEmpty == true
                                ? denormTitle!
                                : (itemData != null
                                      ? (itemData['title'] ?? 'Item')
                                      : 'Item');
                            final category = denormCategory?.isNotEmpty == true
                                ? denormCategory!
                                : (itemData != null
                                      ? (itemData['category'] ?? 'Category')
                                      : 'Category');

                            String? imageUrl;
                            if (denormImage != null && denormImage.isNotEmpty) {
                              imageUrl = denormImage;
                            } else if (itemData != null) {
                              final List images =
                                  (itemData['images'] as List? ?? const []);
                              imageUrl = images.isNotEmpty
                                  ? images.first.toString()
                                  : null;
                            }

                            final location = denormLocation?.isNotEmpty == true
                                ? denormLocation!
                                : (itemData != null
                                      ? (itemData['location'] ?? '')
                                      : '');

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
                                      color: Colors.black.withValues(
                                        alpha: 0.06,
                                      ),
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
                                            borderRadius:
                                                const BorderRadius.only(
                                                  topLeft: Radius.circular(16),
                                                  topRight: Radius.circular(16),
                                                ),
                                            color: Colors.grey[200],
                                          ),
                                          child:
                                              imageUrl != null &&
                                                  imageUrl.isNotEmpty
                                              ? ClipRRect(
                                                  borderRadius:
                                                      const BorderRadius.only(
                                                        topLeft:
                                                            Radius.circular(16),
                                                        topRight:
                                                            Radius.circular(16),
                                                      ),
                                                  child: CachedNetworkImage(
                                                    imageUrl: imageUrl,
                                                    fit: BoxFit.cover,
                                                    width: double.infinity,
                                                    height: 180,
                                                    placeholder:
                                                        (
                                                          context,
                                                          url,
                                                        ) => Container(
                                                          color:
                                                              Colors.grey[200],
                                                          child: const Center(
                                                            child:
                                                                CircularProgressIndicator(
                                                                  strokeWidth:
                                                                      2,
                                                                ),
                                                          ),
                                                        ),
                                                    errorWidget:
                                                        (
                                                          context,
                                                          url,
                                                          error,
                                                        ) => Container(
                                                          color:
                                                              Colors.grey[200],
                                                          child: const Center(
                                                            child: Icon(
                                                              Icons
                                                                  .image_not_supported_outlined,
                                                              size: 48,
                                                              color:
                                                                  Colors.grey,
                                                            ),
                                                          ),
                                                        ),
                                                  ),
                                                )
                                              : const Center(
                                                  child: Icon(
                                                    Icons
                                                        .image_not_supported_outlined,
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
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                            ),
                                            child: Text(
                                              isActive
                                                  ? 'available'
                                                  : 'inactive',
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
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    title,
                                                    maxLines: 2,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                      fontSize: 15,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      height: 1.3,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
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
                                            Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.center,
                                              children: [
                                                Flexible(
                                                  child: Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 8,
                                                          vertical: 4,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      color: const Color(
                                                        0xFFE8F5E9,
                                                      ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            8,
                                                          ),
                                                    ),
                                                    child: Text(
                                                      category,
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: const TextStyle(
                                                        color: Color(
                                                          0xFF1B5E20,
                                                        ),
                                                        fontSize: 10,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                                if (location.isNotEmpty) ...[
                                                  const SizedBox(width: 8),
                                                  Flexible(
                                                    child: Row(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: [
                                                        const Icon(
                                                          Icons
                                                              .location_on_outlined,
                                                          size: 13,
                                                          color: Colors.teal,
                                                        ),
                                                        const SizedBox(
                                                          width: 4,
                                                        ),
                                                        Flexible(
                                                          child: Text(
                                                            location,
                                                            maxLines: 1,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                            style: TextStyle(
                                                              color: Colors
                                                                  .grey[700],
                                                              fontSize: 11,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w500,
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
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
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
