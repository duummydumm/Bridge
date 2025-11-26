import 'package:cloud_firestore/cloud_firestore.dart';

enum GiveawayStatus { active, claimed, cancelled, completed }

enum ClaimMode { firstCome, approvalRequired }

class GiveawayListingModel {
  final String id;
  final String donorId;
  final String donorName;
  final String title;
  final String description;
  final List<String> images;
  final String category;
  final String? condition; // New, Like New, Good, Fair, Used
  final String location;
  final GiveawayStatus status;
  final ClaimMode claimMode;
  final String? claimedBy; // User ID who claimed it
  final String? claimedByName;
  final DateTime? claimedAt;
  final String? pickupNotes; // Instructions for pickup coordination
  final String? donationTrackingId; // For barangay records
  final int reportCount; // Abuse/spam monitoring
  final bool isReported; // Flagged for admin review
  final DateTime createdAt;
  final DateTime? updatedAt;

  GiveawayListingModel({
    required this.id,
    required this.donorId,
    required this.donorName,
    required this.title,
    required this.description,
    required this.images,
    required this.category,
    this.condition,
    required this.location,
    required this.status,
    required this.claimMode,
    this.claimedBy,
    this.claimedByName,
    this.claimedAt,
    this.pickupNotes,
    this.donationTrackingId,
    this.reportCount = 0,
    this.isReported = false,
    required this.createdAt,
    this.updatedAt,
  });

  factory GiveawayListingModel.fromMap(Map<String, dynamic> data, String id) {
    // Parse status
    GiveawayStatus giveawayStatus = GiveawayStatus.active;
    final statusString = (data['status'] ?? 'active').toString().toLowerCase();
    switch (statusString) {
      case 'active':
        giveawayStatus = GiveawayStatus.active;
        break;
      case 'claimed':
        giveawayStatus = GiveawayStatus.claimed;
        break;
      case 'cancelled':
        giveawayStatus = GiveawayStatus.cancelled;
        break;
      case 'completed':
        giveawayStatus = GiveawayStatus.completed;
        break;
    }

    // Parse claim mode
    ClaimMode claimMode = ClaimMode.firstCome;
    final claimModeString = (data['claimMode'] ?? 'firstCome')
        .toString()
        .toLowerCase();
    switch (claimModeString) {
      case 'approvalrequired':
      case 'approval_required':
        claimMode = ClaimMode.approvalRequired;
        break;
      case 'firstcome':
      case 'first_come':
      default:
        claimMode = ClaimMode.firstCome;
        break;
    }

    // Parse images
    List<String> images = [];
    if (data['images'] != null) {
      if (data['images'] is List) {
        images = List<String>.from(data['images']);
      } else if (data['images'] is String) {
        images = [data['images']];
      }
    }

    return GiveawayListingModel(
      id: id,
      donorId: data['donorId'] ?? '',
      donorName: data['donorName'] ?? '',
      title: data['title'] ?? '',
      description: data['description'] ?? '',
      images: images,
      category: data['category'] ?? '',
      condition: data['condition'],
      location: data['location'] ?? '',
      status: giveawayStatus,
      claimMode: claimMode,
      claimedBy: data['claimedBy'],
      claimedByName: data['claimedByName'],
      claimedAt: (data['claimedAt'] as Timestamp?)?.toDate(),
      pickupNotes: data['pickupNotes'],
      donationTrackingId: data['donationTrackingId'],
      reportCount: (data['reportCount'] ?? 0) is int
          ? (data['reportCount'] ?? 0)
          : int.tryParse('${data['reportCount']}') ?? 0,
      isReported: data['isReported'] ?? false,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'donorId': donorId,
      'donorName': donorName,
      'title': title,
      'description': description,
      'images': images,
      'category': category,
      'condition': condition,
      'location': location,
      'status': status.name,
      'claimMode': claimMode.name,
      'claimedBy': claimedBy,
      'claimedByName': claimedByName,
      'claimedAt': claimedAt != null ? Timestamp.fromDate(claimedAt!) : null,
      'pickupNotes': pickupNotes,
      'donationTrackingId': donationTrackingId,
      'reportCount': reportCount,
      'isReported': isReported,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': updatedAt != null ? Timestamp.fromDate(updatedAt!) : null,
    };
  }

  String get statusDisplay {
    switch (status) {
      case GiveawayStatus.active:
        return 'Available';
      case GiveawayStatus.claimed:
        return 'Claimed';
      case GiveawayStatus.cancelled:
        return 'Cancelled';
      case GiveawayStatus.completed:
        return 'Completed';
    }
  }

  String get claimModeDisplay {
    switch (claimMode) {
      case ClaimMode.firstCome:
        return 'First Come, First Served';
      case ClaimMode.approvalRequired:
        return 'Approval Required';
    }
  }

  bool get isAvailable => status == GiveawayStatus.active;
  bool get isClaimed => status == GiveawayStatus.claimed;
  bool get hasImages => images.isNotEmpty;
}
