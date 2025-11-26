import 'package:cloud_firestore/cloud_firestore.dart';

enum TradeStatus { open, closed, traded }

class TradeItemModel {
  final String id;
  final String offeredItemName;
  final String offeredCategory;
  final String offeredDescription;
  final List<String> offeredImageUrls; // Changed to support multiple images
  final String? desiredItemName;
  final String? desiredCategory;
  final String? notes;
  final String location;
  final String offeredBy;
  final TradeStatus status;
  final DateTime createdAt;
  final DateTime? updatedAt;

  TradeItemModel({
    required this.id,
    required this.offeredItemName,
    required this.offeredCategory,
    required this.offeredDescription,
    required this.offeredImageUrls,
    this.desiredItemName,
    this.desiredCategory,
    this.notes,
    required this.location,
    required this.offeredBy,
    required this.status,
    required this.createdAt,
    this.updatedAt,
  });

  factory TradeItemModel.fromMap(Map<String, dynamic> data, String id) {
    // Parse status from string
    TradeStatus tradeStatus = TradeStatus.open;
    final statusString = (data['status'] ?? 'Open').toString().toLowerCase();

    switch (statusString) {
      case 'open':
        tradeStatus = TradeStatus.open;
        break;
      case 'closed':
        tradeStatus = TradeStatus.closed;
        break;
      case 'traded':
        tradeStatus = TradeStatus.traded;
        break;
    }

    // Handle both old single image format and new multiple images format
    List<String> imageUrls = [];
    if (data['offeredImageUrls'] != null) {
      // New format: list of URLs
      if (data['offeredImageUrls'] is List) {
        imageUrls = (data['offeredImageUrls'] as List)
            .map((e) => e.toString())
            .where((e) => e.isNotEmpty)
            .toList();
      }
    } else if (data['offeredImageUrl'] != null) {
      // Old format: single URL (for backward compatibility)
      final singleUrl = data['offeredImageUrl'].toString();
      if (singleUrl.isNotEmpty) {
        imageUrls = [singleUrl];
      }
    }

    return TradeItemModel(
      id: id,
      offeredItemName: data['offeredItemName'] ?? '',
      offeredCategory: data['offeredCategory'] ?? '',
      offeredDescription: data['offeredDescription'] ?? '',
      offeredImageUrls: imageUrls,
      desiredItemName: data['desiredItemName'],
      desiredCategory: data['desiredCategory'],
      notes: data['notes'],
      location: data['location'] ?? '',
      offeredBy: data['offeredBy'] ?? '',
      status: tradeStatus,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    String statusString;
    switch (status) {
      case TradeStatus.open:
        statusString = 'Open';
        break;
      case TradeStatus.closed:
        statusString = 'Closed';
        break;
      case TradeStatus.traded:
        statusString = 'Traded';
        break;
    }
    return {
      'offeredItemName': offeredItemName,
      'offeredCategory': offeredCategory,
      'offeredDescription': offeredDescription,
      'offeredImageUrls': offeredImageUrls,
      'desiredItemName': desiredItemName,
      'desiredCategory': desiredCategory,
      'notes': notes,
      'location': location,
      'offeredBy': offeredBy,
      'status': statusString,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': updatedAt != null ? Timestamp.fromDate(updatedAt!) : null,
    };
  }

  String get statusDisplay {
    switch (status) {
      case TradeStatus.open:
        return 'Open';
      case TradeStatus.closed:
        return 'Closed';
      case TradeStatus.traded:
        return 'Traded';
    }
  }

  bool get isOpen => status == TradeStatus.open;
  bool get hasImage => offeredImageUrls.isNotEmpty;

  // Backward compatibility: get first image URL
  String? get offeredImageUrl =>
      offeredImageUrls.isNotEmpty ? offeredImageUrls.first : null;
}
