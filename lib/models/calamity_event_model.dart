import 'package:cloud_firestore/cloud_firestore.dart';

enum CalamityEventStatus { active, closed, expired }

class CalamityEventModel {
  final String eventId;
  final String title;
  final String description;
  final String bannerUrl;
  final String calamityType;
  final List<String> neededItems;
  final String dropoffLocation;
  final DateTime deadline;
  final String createdBy; // "admin"
  final CalamityEventStatus status;
  final DateTime createdAt;
  final DateTime? updatedAt;

  CalamityEventModel({
    required this.eventId,
    required this.title,
    required this.description,
    required this.bannerUrl,
    required this.calamityType,
    required this.neededItems,
    required this.dropoffLocation,
    required this.deadline,
    required this.createdBy,
    required this.status,
    required this.createdAt,
    this.updatedAt,
  });

  factory CalamityEventModel.fromMap(Map<String, dynamic> data, String id) {
    // Parse status
    CalamityEventStatus eventStatus = CalamityEventStatus.active;
    final statusString = (data['status'] ?? 'active').toString().toLowerCase();
    switch (statusString) {
      case 'active':
        eventStatus = CalamityEventStatus.active;
        break;
      case 'closed':
        eventStatus = CalamityEventStatus.closed;
        break;
      case 'expired':
        eventStatus = CalamityEventStatus.expired;
        break;
    }

    // Parse neededItems
    List<String> neededItems = [];
    if (data['neededItems'] != null) {
      if (data['neededItems'] is List) {
        neededItems = List<String>.from(data['neededItems']);
      }
    }

    return CalamityEventModel(
      eventId: id,
      title: data['title'] ?? '',
      description: data['description'] ?? '',
      bannerUrl: data['bannerUrl'] ?? '',
      calamityType: data['calamityType'] ?? '',
      neededItems: neededItems,
      dropoffLocation: data['dropoffLocation'] ?? '',
      deadline: (data['deadline'] as Timestamp?)?.toDate() ?? DateTime.now(),
      createdBy: data['createdBy'] ?? 'admin',
      status: eventStatus,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'description': description,
      'bannerUrl': bannerUrl,
      'calamityType': calamityType,
      'neededItems': neededItems,
      'dropoffLocation': dropoffLocation,
      'deadline': Timestamp.fromDate(deadline),
      'createdBy': createdBy,
      'status': status.name,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': updatedAt != null ? Timestamp.fromDate(updatedAt!) : null,
    };
  }

  String get statusDisplay {
    switch (status) {
      case CalamityEventStatus.active:
        return 'Active';
      case CalamityEventStatus.closed:
        return 'Closed';
      case CalamityEventStatus.expired:
        return 'Expired';
    }
  }

  bool get isActive => status == CalamityEventStatus.active;
  bool get isExpired => deadline.isBefore(DateTime.now());
  bool get canAcceptDonations => isActive && !isExpired;
}
