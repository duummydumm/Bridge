import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/user_provider.dart';
import '../../reusable_widgets/rental_location_filter.dart';

class RentalBoardingHousesScreen extends StatefulWidget {
  const RentalBoardingHousesScreen({super.key});

  @override
  State<RentalBoardingHousesScreen> createState() =>
      _RentalBoardingHousesScreenState();
}

class _RentalBoardingHousesScreenState
    extends State<RentalBoardingHousesScreen> {
  String? _selectedBarangay;

  @override
  Widget build(BuildContext context) {
    final currentUserId = Provider.of<UserProvider>(
      context,
      listen: false,
    ).currentUser?.uid;
    final listingsQuery = FirebaseFirestore.instance
        .collection('rental_listings')
        .where('isActive', isEqualTo: true)
        .where('rentType', whereIn: ['boardinghouse', 'boarding_house'])
        .limit(100);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Boarding Houses'),
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
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.hotel_outlined,
                          size: 64,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No boarding houses available',
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

                // Optionally filter out listings owned by the current user
                var docs = snapshot.data!.docs;
                if (currentUserId != null) {
                  docs = docs.where((doc) {
                    final data = doc.data();
                    final ownerId = (data['ownerId'] ?? '').toString();
                    return ownerId != currentUserId;
                  }).toList();
                }

                // Filter by selected barangay/location
                if (_selectedBarangay != null &&
                    _selectedBarangay!.isNotEmpty) {
                  final selectedLower = _selectedBarangay!.toLowerCase();
                  docs = docs.where((doc) {
                    final data = doc.data();
                    final location = (data['location'] ?? '')
                        .toString()
                        .toLowerCase();
                    final address = (data['address'] ?? '')
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
                          'No boarding houses to rent in this location',
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

                // 2-column grid with compact preview cards
                return GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisExtent: 260,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final listing = docs[index].data();
                    final listingId = docs[index].id;
                    final title = (listing['title'] ?? 'Boarding House')
                        .toString();
                    final address =
                        (listing['address'] ?? listing['location'] ?? '')
                            .toString();
                    final pricePerMonth = (listing['pricePerMonth'] as num?)
                        ?.toDouble();
                    final imageUrl = (listing['imageUrl'] as String?)?.trim();

                    return _BoardingHouseCard(
                      listingId: listingId,
                      title: title,
                      address: address,
                      pricePerMonth: pricePerMonth,
                      imageUrl: imageUrl,
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

class _BoardingHouseCard extends StatelessWidget {
  const _BoardingHouseCard({
    required this.listingId,
    required this.title,
    required this.address,
    this.pricePerMonth,
    this.imageUrl,
  });

  final String listingId;
  final String title;
  final String address;
  final double? pricePerMonth;
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
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
          mainAxisSize: MainAxisSize.min,
          children: [
            if (imageUrl != null && imageUrl!.isNotEmpty)
              ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(12),
                ),
                child: CachedNetworkImage(
                  imageUrl: imageUrl!,
                  height: 140,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Container(
                    height: 140,
                    color: Colors.grey[200],
                    child: const Center(child: CircularProgressIndicator()),
                  ),
                  errorWidget: (context, url, error) => Container(
                    height: 140,
                    color: Colors.grey[200],
                    child: const Icon(
                      Icons.hotel_outlined,
                      size: 40,
                      color: Colors.grey,
                    ),
                  ),
                ),
              )
            else
              Container(
                height: 140,
                color: Colors.grey[200],
                child: const Center(
                  child: Icon(
                    Icons.hotel_outlined,
                    size: 40,
                    color: Colors.grey,
                  ),
                ),
              ),
            Flexible(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 3),
                    if (pricePerMonth != null)
                      Text(
                        '₱${pricePerMonth!.toStringAsFixed(0)}/mo',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF00A676),
                        ),
                      ),
                    const SizedBox(height: 3),
                    if (address.isNotEmpty)
                      Row(
                        children: [
                          const Icon(
                            Icons.location_on,
                            size: 13,
                            color: Colors.teal,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              address,
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
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
