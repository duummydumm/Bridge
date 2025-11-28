import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:flutter/foundation.dart' show debugPrint;

class AdminService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Users awaiting verification
  Stream<QuerySnapshot<Map<String, dynamic>>> streamUnverifiedUsers({
    int limit = 50,
  }) {
    return _db
        .collection('users')
        .where('isVerified', isEqualTo: false)
        .limit(limit)
        .snapshots();
  }

  Future<void> approveUser(String uid) async {
    // Get admin user info
    final adminUser = fb_auth.FirebaseAuth.instance.currentUser;
    final adminId = adminUser?.uid ?? 'system';
    String adminName = 'Admin';

    try {
      if (adminUser != null) {
        final adminDoc = await _db.collection('users').doc(adminId).get();
        if (adminDoc.exists) {
          final adminData = adminDoc.data();
          adminName =
              '${adminData?['firstName'] ?? ''} ${adminData?['lastName'] ?? ''}'
                  .trim();
          if (adminName.isEmpty) {
            adminName = adminData?['email'] ?? 'Admin';
          }
        }
      }
    } catch (e) {
      // If we can't get admin name, use default
    }

    // Get verified user info
    String verifiedUserName = 'Unknown User';
    String? idType;
    try {
      final userDoc = await _db.collection('users').doc(uid).get();
      if (userDoc.exists) {
        final userData = userDoc.data();
        verifiedUserName =
            '${userData?['firstName'] ?? ''} ${userData?['lastName'] ?? ''}'
                .trim();
        if (verifiedUserName.isEmpty) {
          verifiedUserName = userData?['email'] ?? 'Unknown User';
        }
        idType = userData?['barangayIdType']?.toString();
      }
    } catch (e) {
      // If we can't get user name, use default
    }

    // Update user verification status
    await _db.collection('users').doc(uid).update({
      'isVerified': true,
      'verificationStatus': 'approved',
      'verifiedAt': FieldValue.serverTimestamp(),
    });

    // Create activity log
    try {
      await _db.collection('activity_logs').add({
        'timestamp': FieldValue.serverTimestamp(),
        'category': 'admin',
        'action': 'user_verified',
        'actorId': adminId,
        'actorName': adminName,
        'targetId': uid,
        'targetType': 'user',
        'description': 'Verified user account: $verifiedUserName',
        'metadata': {
          'userId': uid,
          'userName': verifiedUserName,
          'verificationType': idType ?? 'ID verification',
        },
        'severity': 'info',
      });
    } catch (e) {
      // Log error but don't fail verification if logging fails
      debugPrint('Error creating activity log for user verification: $e');
    }
  }

  Future<void> rejectUser(String uid, {String? reason}) async {
    try {
      final rejectionReason = reason?.trim();
      final hasReason = rejectionReason != null && rejectionReason.isNotEmpty;

      print(
        'AdminService: Rejecting user $uid with reason: ${hasReason ? rejectionReason : "(no reason provided)"}',
      );

      // Update user verification status
      await _db.collection('users').doc(uid).update({
        'isVerified': false,
        'verificationStatus': 'rejected',
        'rejectionReason': hasReason ? rejectionReason : '',
        'rejectedAt': FieldValue.serverTimestamp(),
        'verifiedAt': null,
      });
      print('AdminService: User document updated successfully');

      // Create notification for the user
      final notificationMessage = hasReason
          ? rejectionReason
          : 'Your account verification was rejected. Please review your submitted information and try again.';

      await _db.collection('notifications').add({
        'toUserId': uid,
        'type': 'verification_rejected',
        'title': 'Account Verification Rejected',
        'message': notificationMessage,
        'rejectionReason': hasReason ? rejectionReason : '',
        'status': 'unread',
        'createdAt': FieldValue.serverTimestamp(),
      });
      print('AdminService: Notification created successfully');
    } catch (e) {
      print('AdminService: Error rejecting user: $e');
      rethrow;
    }
  }

  // Suspend / Restore accounts
  Future<void> suspendUser(String uid, {String? reason}) async {
    // Get admin user info
    final adminUser = fb_auth.FirebaseAuth.instance.currentUser;
    final adminId = adminUser?.uid ?? 'system';
    String adminName = 'Admin';

    try {
      if (adminUser != null) {
        final adminDoc = await _db.collection('users').doc(adminId).get();
        if (adminDoc.exists) {
          final adminData = adminDoc.data();
          adminName =
              '${adminData?['firstName'] ?? ''} ${adminData?['lastName'] ?? ''}'
                  .trim();
          if (adminName.isEmpty) {
            adminName = adminData?['email'] ?? 'Admin';
          }
        }
      }
    } catch (e) {
      // If we can't get admin name, use default
    }

    // Get suspended user info
    String suspendedUserName = 'Unknown User';
    try {
      final userDoc = await _db.collection('users').doc(uid).get();
      if (userDoc.exists) {
        final userData = userDoc.data();
        suspendedUserName =
            '${userData?['firstName'] ?? ''} ${userData?['lastName'] ?? ''}'
                .trim();
        if (suspendedUserName.isEmpty) {
          suspendedUserName = userData?['email'] ?? 'Unknown User';
        }
      }
    } catch (e) {
      // If we can't get user name, use default
    }

    // Update user suspension status
    await _db.collection('users').doc(uid).update({
      'isSuspended': true,
      'suspendedAt': FieldValue.serverTimestamp(),
      'suspensionReason': reason ?? '',
    });

    // Create activity log
    try {
      await _db.collection('activity_logs').add({
        'timestamp': FieldValue.serverTimestamp(),
        'category': 'admin',
        'action': 'user_suspended',
        'actorId': adminId,
        'actorName': adminName,
        'targetId': uid,
        'targetType': 'user',
        'description': 'Suspended user account: $suspendedUserName',
        'metadata': {
          'userId': uid,
          'userName': suspendedUserName,
          'reason': reason ?? 'No reason provided',
          'suspendedAt': DateTime.now().toIso8601String(),
        },
        'severity': 'critical',
      });
    } catch (e) {
      // Log error but don't fail the suspension if logging fails
      debugPrint('Error creating activity log for user suspension: $e');
    }
  }

  Future<void> restoreUser(String uid) async {
    // Get admin user info
    final adminUser = fb_auth.FirebaseAuth.instance.currentUser;
    final adminId = adminUser?.uid ?? 'system';
    String adminName = 'Admin';

    try {
      if (adminUser != null) {
        final adminDoc = await _db.collection('users').doc(adminId).get();
        if (adminDoc.exists) {
          final adminData = adminDoc.data();
          adminName =
              '${adminData?['firstName'] ?? ''} ${adminData?['lastName'] ?? ''}'
                  .trim();
          if (adminName.isEmpty) {
            adminName = adminData?['email'] ?? 'Admin';
          }
        }
      }
    } catch (e) {
      // If we can't get admin name, use default
    }

    // Get restored user info
    String restoredUserName = 'Unknown User';
    try {
      final userDoc = await _db.collection('users').doc(uid).get();
      if (userDoc.exists) {
        final userData = userDoc.data();
        restoredUserName =
            '${userData?['firstName'] ?? ''} ${userData?['lastName'] ?? ''}'
                .trim();
        if (restoredUserName.isEmpty) {
          restoredUserName = userData?['email'] ?? 'Unknown User';
        }
      }
    } catch (e) {
      // If we can't get user name, use default
    }

    // Update user suspension status
    await _db.collection('users').doc(uid).update({
      'isSuspended': false,
      'suspendedAt': null,
      'suspensionReason': '',
    });

    // Create activity log
    try {
      await _db.collection('activity_logs').add({
        'timestamp': FieldValue.serverTimestamp(),
        'category': 'admin',
        'action': 'user_restored',
        'actorId': adminId,
        'actorName': adminName,
        'targetId': uid,
        'targetType': 'user',
        'description': 'Restored user account: $restoredUserName',
        'metadata': {
          'userId': uid,
          'userName': restoredUserName,
          'restoredAt': DateTime.now().toIso8601String(),
        },
        'severity': 'info',
      });
    } catch (e) {
      // Log error but don't fail the restoration if logging fails
      debugPrint('Error creating activity log for user restoration: $e');
    }
  }

  // Monitor activities
  Stream<QuerySnapshot<Map<String, dynamic>>> streamBorrowRequests({
    int limit = 100,
  }) {
    return _db
        .collection('borrow_requests')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> streamRentalRequests({
    int limit = 100,
  }) {
    return _db
        .collection('rental_requests')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> streamTradeOffers({
    int limit = 100,
  }) {
    return _db
        .collection('trade_offers')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> streamGiveawayClaims({
    int limit = 100,
  }) {
    return _db
        .collection('giveaway_claims')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> streamItems({int limit = 100}) {
    return _db
        .collection('items')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots();
  }

  // Reports & violations
  Stream<QuerySnapshot<Map<String, dynamic>>> streamReports({
    String status = 'open',
    int limit = 100,
  }) {
    return _db
        .collection('reports')
        .where('status', isEqualTo: status)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots();
  }

  Future<void> fileViolation({required String userId, String? note}) async {
    final userRef = _db.collection('users').doc(userId);
    await _db.runTransaction((txn) async {
      final snap = await txn.get(userRef);
      final current = (snap.data()?['violationCount'] ?? 0) as int;
      txn.update(userRef, {
        'violationCount': current + 1,
        'lastViolationNote': note ?? '',
        'lastViolationAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> resolveReport(
    String reportId, {
    String resolution = 'resolved',
  }) async {
    await _db.collection('reports').doc(reportId).update({
      'status': resolution,
      'resolvedAt': FieldValue.serverTimestamp(),
    });
  }

  // Analytics
  Future<Map<String, dynamic>> getAnalyticsSummary() async {
    final results = <String, dynamic>{};

    // Active users in last 7 days
    final sevenDaysAgo = DateTime.now().subtract(const Duration(days: 7));
    final activeUsersSnap = await _db
        .collection('users')
        .where(
          'lastSeen',
          isGreaterThanOrEqualTo: Timestamp.fromDate(sevenDaysAgo),
        )
        .get();
    results['activeUsers7d'] = activeUsersSnap.docs.length;

    // Popular categories (top 5)
    final itemsSnap = await _db.collection('items').get();
    final Map<String, int> categoryCounts = {};
    for (final doc in itemsSnap.docs) {
      final cat = (doc.data()['category'] ?? 'Other') as String;
      categoryCounts[cat] = (categoryCounts[cat] ?? 0) + 1;
    }
    final popular = categoryCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    results['popularCategories'] = popular
        .take(5)
        .map((e) => {'category': e.key, 'count': e.value})
        .toList();

    // Issues open
    final openReportsSnap = await _db
        .collection('reports')
        .where('status', isEqualTo: 'open')
        .get();
    results['openIssues'] = openReportsSnap.docs.length;

    return results;
  }
}
