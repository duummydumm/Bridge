import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../reusable_widgets/rental_location_filter.dart';

class RentalApartmentsScreen extends StatefulWidget {
  const RentalApartmentsScreen({super.key});

  @override
  State<RentalApartmentsScreen> createState() => _RentalApartmentsScreenState();
}

class _RentalApartmentsScreenState extends State<RentalApartmentsScreen> {
  String? _selectedBarangay;

  @override
  Widget build(BuildContext context) {
    final listingsQuery = FirebaseFirestore.instance
        .collection('rental_listings')
        .where('isActive', isEqualTo: true)
        .where('rentType', isEqualTo: 'apartment')
        .limit(100);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Apartments for Rent'),
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
                          Icons.home_outlined,
                          size: 64,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No apartments available',
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

                var docs = snapshot.data!.docs;

                // Filter by selected barangay/location
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
                          'No apartments match this location',
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

                // 2-column grid, compact preview cards (image + title + price + location)
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
                    final title = (listing['title'] ?? 'Apartment').toString();
                    final address =
                        (listing['address'] ?? listing['location'] ?? '')
                            .toString();
                    final pricePerMonth = (listing['pricePerMonth'] as num?)
                        ?.toDouble();
                    final imageUrl = (listing['imageUrl'] as String?)?.trim();

                    return _ApartmentCard(
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

class _ApartmentCard extends StatelessWidget {
  const _ApartmentCard({
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
                      Icons.home_outlined,
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
                    Icons.home_outlined,
                    size: 40,
                    color: Colors.grey,
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (pricePerMonth != null)
                    Text(
                      '₱${pricePerMonth!.toStringAsFixed(0)}/mo',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF00A676),
                      ),
                    ),
                  const SizedBox(height: 4),
                  if (address.isNotEmpty)
                    Row(
                      children: [
                        const Icon(
                          Icons.location_on,
                          size: 14,
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
                              fontSize: 12,
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
      ),
    );
  }
}

// Note: full apartment details are shown on RentItemScreen; this screen
// is a compact 2-column overview.
