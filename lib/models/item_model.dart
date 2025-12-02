import 'package:cloud_firestore/cloud_firestore.dart';

enum ItemStatus { available, borrowed, unavailable, pending }

class ItemModel {
  final String itemId;
  final String lenderId; // The user who is lending the item
  final String lenderName;
  final String title;
  final String description;
  final List<String> images; // URLs to item images
  final String category;
  final String type; // lend, rent, trade, donate
  final String condition; // New, Like New, Good, Fair
  final ItemStatus status;
  final double? pricePerDay; // Optional pricing
  final String? location; // Item location
  final DateTime createdAt;
  final DateTime? lastUpdated;

  // Optional: Rental / borrow details
  final String? currentBorrowerId;
  final DateTime? borrowedDate;
  final DateTime? returnDate;
  final int
  borrowCount; // How many times this item has been borrowed (all time)

  ItemModel({
    required this.itemId,
    required this.lenderId,
    required this.lenderName,
    required this.title,
    required this.description,
    required this.images,
    required this.category,
    required this.type,
    required this.condition,
    required this.status,
    this.pricePerDay,
    this.location,
    required this.createdAt,
    this.lastUpdated,
    this.currentBorrowerId,
    this.borrowedDate,
    this.returnDate,
    this.borrowCount = 0,
  });

  factory ItemModel.fromMap(Map<String, dynamic> data, String documentId) {
    // Parse status from string
    ItemStatus itemStatus = ItemStatus.available;
    final statusString = (data['status'] ?? 'available')
        .toString()
        .toLowerCase();

    switch (statusString) {
      case 'available':
        itemStatus = ItemStatus.available;
        break;
      case 'borrowed':
        itemStatus = ItemStatus.borrowed;
        break;
      case 'unavailable':
        itemStatus = ItemStatus.unavailable;
        break;
      case 'pending':
        itemStatus = ItemStatus.pending;
        break;
    }

    return ItemModel(
      itemId: documentId,
      lenderId: data['lenderId'] ?? '',
      lenderName: data['lenderName'] ?? '',
      title: data['title'] ?? '',
      description: data['description'] ?? '',
      images: List<String>.from(data['images'] ?? []),
      category: data['category'] ?? 'Other',
      type: (data['type'] ?? 'lend').toString(),
      condition: data['condition'] ?? 'Good',
      status: itemStatus,
      pricePerDay: data['pricePerDay']?.toDouble(),
      location: data['location'],
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      lastUpdated: (data['lastUpdated'] as Timestamp?)?.toDate(),
      currentBorrowerId: data['currentBorrowerId'],
      borrowedDate: (data['borrowedDate'] as Timestamp?)?.toDate(),
      returnDate: (data['returnDate'] as Timestamp?)?.toDate(),
      borrowCount: (data['borrowCount'] is int)
          ? data['borrowCount'] as int
          : int.tryParse((data['borrowCount'] ?? '0').toString()) ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'lenderId': lenderId,
      'lenderName': lenderName,
      'title': title,
      'description': description,
      'images': images,
      'category': category,
      'type': type,
      'condition': condition,
      'status': status.name.toLowerCase(),
      'pricePerDay': pricePerDay,
      'location': location,
      'createdAt': Timestamp.fromDate(createdAt),
      'lastUpdated': lastUpdated != null
          ? Timestamp.fromDate(lastUpdated!)
          : null,
      'currentBorrowerId': currentBorrowerId,
      'borrowedDate': borrowedDate != null
          ? Timestamp.fromDate(borrowedDate!)
          : null,
      'returnDate': returnDate != null ? Timestamp.fromDate(returnDate!) : null,
      'borrowCount': borrowCount,
    };
  }

  String get statusDisplay {
    switch (status) {
      case ItemStatus.available:
        return 'Available';
      case ItemStatus.borrowed:
        return 'Borrowed';
      case ItemStatus.unavailable:
        return 'Unavailable';
      case ItemStatus.pending:
        return 'Pending';
    }
  }

  bool get isAvailable => status == ItemStatus.available;
  bool get isBorrowed => status == ItemStatus.borrowed;
  bool get hasImages => images.isNotEmpty;
}
