import '../services/firestore_service.dart';

/// Utility class to create sample activity logs for demonstration
class SampleLogsGenerator {
  final FirestoreService _service = FirestoreService();

  /// Generate various sample logs to demonstrate the activity log system
  Future<void> generateSampleLogs() async {
    // User actions
    await _service.createActivityLog(
      category: 'user',
      action: 'user_registered',
      actorId: 'sample_user_1',
      actorName: 'John Doe',
      description: 'New user registered on the platform',
      metadata: {'email': 'john.doe@example.com', 'method': 'email'},
      severity: 'info',
    );

    await _service.createActivityLog(
      category: 'user',
      action: 'user_verified',
      actorId: 'admin_1',
      actorName: 'Admin User',
      targetId: 'sample_user_2',
      targetType: 'user',
      description: 'Verified user account: Jane Smith',
      metadata: {
        'userId': 'sample_user_2',
        'userName': 'Jane Smith',
        'verificationType': 'ID verification',
      },
      severity: 'info',
    );

    await _service.createActivityLog(
      category: 'user',
      action: 'profile_updated',
      actorId: 'sample_user_3',
      actorName: 'Mike Johnson',
      description: 'User updated their profile information',
      metadata: {'fieldsUpdated': 'bio, location'},
      severity: 'info',
    );

    // Transaction events
    await _service.createActivityLog(
      category: 'transaction',
      action: 'borrow_request_created',
      actorId: 'sample_user_4',
      actorName: 'Sarah Wilson',
      targetId: 'item_123',
      targetType: 'item',
      description: 'Created borrow request for "Electric Drill"',
      metadata: {
        'itemId': 'item_123',
        'itemTitle': 'Electric Drill',
        'lenderId': 'owner_1',
        'duration': '3 days',
      },
      severity: 'info',
    );

    await _service.createActivityLog(
      category: 'transaction',
      action: 'borrow_accepted',
      actorId: 'owner_1',
      actorName: 'Tom Brown',
      targetId: 'request_456',
      targetType: 'borrow_request',
      description: 'Accepted borrow request from Sarah Wilson',
      metadata: {
        'requestId': 'request_456',
        'borrower': 'Sarah Wilson',
        'item': 'Electric Drill',
        'returnDate': '2025-12-01',
      },
      severity: 'info',
    );

    await _service.createActivityLog(
      category: 'transaction',
      action: 'rental_payment_received',
      actorId: 'system',
      actorName: 'System',
      targetId: 'payment_789',
      targetType: 'payment',
      description: 'Rental payment received for "Party Tent"',
      metadata: {
        'amount': '₱500.00',
        'renterId': 'renter_1',
        'renterName': 'Alice Green',
        'itemTitle': 'Party Tent',
      },
      severity: 'info',
    );

    await _service.createActivityLog(
      category: 'transaction',
      action: 'trade_offered',
      actorId: 'trader_1',
      actorName: 'Bob Martinez',
      targetId: 'trade_101',
      targetType: 'trade',
      description: 'Offered trade: "Mountain Bike" for "Camping Gear"',
      metadata: {
        'offeredItem': 'Mountain Bike',
        'requestedItem': 'Camping Gear',
        'targetUser': 'Emily Davis',
      },
      severity: 'info',
    );

    // Content actions
    await _service.createActivityLog(
      category: 'content',
      action: 'item_listed',
      actorId: 'seller_1',
      actorName: 'Chris Taylor',
      targetId: 'item_202',
      targetType: 'item',
      description: 'Listed new item for rental: "Professional Camera"',
      metadata: {
        'itemTitle': 'Professional Camera',
        'category': 'Electronics',
        'price': '₱300/day',
      },
      severity: 'info',
    );

    await _service.createActivityLog(
      category: 'content',
      action: 'item_deleted',
      actorId: 'user_5',
      actorName: 'Diana Parker',
      targetId: 'item_303',
      targetType: 'item',
      description: 'Deleted listing: "Old Furniture Set"',
      metadata: {'reason': 'Item sold elsewhere'},
      severity: 'info',
    );

    await _service.createActivityLog(
      category: 'content',
      action: 'giveaway_created',
      actorId: 'donor_1',
      actorName: 'Frank Lee',
      targetId: 'giveaway_404',
      targetType: 'giveaway',
      description: 'Created giveaway: "Children\'s Books (5 books)"',
      metadata: {
        'itemTitle': 'Children\'s Books (5 books)',
        'condition': 'Good',
        'location': 'Oroquieta City',
      },
      severity: 'info',
    );

    // Administrative actions
    await _service.createActivityLog(
      category: 'admin',
      action: 'user_banned',
      actorId: 'admin_2',
      actorName: 'Admin Sarah',
      targetId: 'violator_1',
      targetType: 'user',
      description: 'Banned user for violating community guidelines',
      metadata: {
        'userId': 'violator_1',
        'userName': 'Spam Account',
        'reason': 'Posting spam content repeatedly',
        'duration': 'Permanent',
      },
      severity: 'critical',
    );

    await _service.createActivityLog(
      category: 'admin',
      action: 'report_resolved',
      actorId: 'admin_3',
      actorName: 'Admin Mike',
      targetId: 'report_555',
      targetType: 'report',
      description: 'Resolved user report: False listing claim',
      metadata: {
        'reportId': 'report_555',
        'reportedUser': 'George White',
        'reportType': 'False Listing',
        'resolution': 'Warning issued',
      },
      severity: 'warning',
    );

    await _service.createActivityLog(
      category: 'admin',
      action: 'verification_approved',
      actorId: 'admin_1',
      actorName: 'Admin User',
      targetId: 'user_verification_666',
      targetType: 'verification',
      description: 'Approved ID verification for Helen Kim',
      metadata: {
        'userId': 'user_verification_666',
        'userName': 'Helen Kim',
        'idType': 'Government ID',
      },
      severity: 'info',
    );

    // System events
    await _service.createActivityLog(
      category: 'system',
      action: 'calamity_event_created',
      actorId: 'admin_1',
      actorName: 'Admin User',
      targetId: 'calamity_777',
      targetType: 'calamity_event',
      description: 'Created calamity event: Typhoon Response 2025',
      metadata: {
        'eventTitle': 'Typhoon Response 2025',
        'calamityType': 'Typhoon',
        'targetAmount': '₱100,000',
        'status': 'Active',
      },
      severity: 'critical',
    );

    await _service.createActivityLog(
      category: 'system',
      action: 'bulk_notification_sent',
      actorId: 'system',
      actorName: 'System',
      description: 'Sent overdue reminder notifications to 15 users',
      metadata: {
        'notificationType': 'Overdue Reminder',
        'recipientCount': '15',
      },
      severity: 'info',
    );

    await _service.createActivityLog(
      category: 'system',
      action: 'database_backup',
      actorId: 'system',
      actorName: 'System',
      description: 'Automated database backup completed successfully',
      metadata: {'backupSize': '256 MB', 'duration': '45 seconds'},
      severity: 'info',
    );

    // Some warning level events
    await _service.createActivityLog(
      category: 'system',
      action: 'failed_login_attempt',
      actorId: 'unknown',
      actorName: 'Unknown User',
      description: 'Multiple failed login attempts detected',
      metadata: {
        'attemptCount': '5',
        'ipAddress': '192.168.1.100',
        'targetAccount': 'admin@bridge.com',
      },
      severity: 'warning',
    );

    await _service.createActivityLog(
      category: 'admin',
      action: 'dispute_opened',
      actorId: 'user_dispute_1',
      actorName: 'Irene Scott',
      targetId: 'dispute_888',
      targetType: 'dispute',
      description: 'Opened dispute for damaged item return',
      metadata: {
        'itemTitle': 'Portable Speaker',
        'lender': 'Jack Russell',
        'damageType': 'Physical damage',
        'estimatedCost': '₱1,500',
      },
      severity: 'warning',
    );
  }
}
