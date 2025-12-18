import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:flutter/foundation.dart' show debugPrint;
import 'storage_service.dart';

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

    // Create notification for the user
    try {
      await _db.collection('notifications').add({
        'toUserId': uid,
        'type': 'verification_approved',
        'title': 'Account Verified Successfully',
        'message':
            'Congratulations! Your account has been verified. You can now post items, borrow, rent, and use all features of the app.',
        'status': 'unread',
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      // Log error but don't fail verification if notification fails
      debugPrint('Error creating verification notification: $e');
    }

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

  Future<void> deleteUser(String uid, {String? reason}) async {
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

    // Get user info before deletion
    String deletedUserName = 'Unknown User';
    String? userEmail;
    try {
      final userDoc = await _db.collection('users').doc(uid).get();
      if (userDoc.exists) {
        final userData = userDoc.data();
        deletedUserName =
            '${userData?['firstName'] ?? ''} ${userData?['lastName'] ?? ''}'
                .trim();
        if (deletedUserName.isEmpty) {
          deletedUserName = userData?['email'] ?? 'Unknown User';
        }
        userEmail = userData?['email'] as String?;
      }
    } catch (e) {
      // If we can't get user name, use default
    }

    // Check for active transactions before deletion
    final activeBorrowRequests = await _db
        .collection('borrow_requests')
        .where('lenderId', isEqualTo: uid)
        .where('status', whereIn: ['pending', 'accepted', 'active'])
        .limit(1)
        .get();

    final activeRentalRequests = await _db
        .collection('rental_requests')
        .where('ownerId', isEqualTo: uid)
        .where('status', whereIn: ['pending', 'accepted', 'active'])
        .limit(1)
        .get();

    final activeTradeOffers = await _db
        .collection('trade_offers')
        .where('fromUserId', isEqualTo: uid)
        .where('status', whereIn: ['pending', 'accepted'])
        .limit(1)
        .get();

    if (activeBorrowRequests.docs.isNotEmpty ||
        activeRentalRequests.docs.isNotEmpty ||
        activeTradeOffers.docs.isNotEmpty) {
      throw Exception(
        'Cannot delete user with active transactions. Please resolve all active borrow requests, rental requests, or trade offers first.',
      );
    }

    // Delete all associated data before deleting user document
    try {
      // 1. Delete user's items (borrow/lend listings)
      final itemsSnapshot = await _db
          .collection('items')
          .where('lenderId', isEqualTo: uid)
          .get();
      for (final doc in itemsSnapshot.docs) {
        await doc.reference.delete();
      }

      // 2. Delete user's rental listings
      final rentalListingsSnapshot = await _db
          .collection('rental_listings')
          .where('ownerId', isEqualTo: uid)
          .get();
      for (final doc in rentalListingsSnapshot.docs) {
        await doc.reference.delete();
      }

      // 3. Delete user's trade items
      final tradeItemsSnapshot = await _db
          .collection('trade_items')
          .where('offeredBy', isEqualTo: uid)
          .get();
      for (final doc in tradeItemsSnapshot.docs) {
        await doc.reference.delete();
      }

      // 4. Delete user's giveaway listings
      final giveawaysSnapshot = await _db
          .collection('giveaways')
          .where('ownerId', isEqualTo: uid)
          .get();
      for (final doc in giveawaysSnapshot.docs) {
        await doc.reference.delete();
      }

      // 5. Delete borrow requests (as lender or borrower)
      final borrowRequestsSnapshot = await _db
          .collection('borrow_requests')
          .where('lenderId', isEqualTo: uid)
          .get();
      for (final doc in borrowRequestsSnapshot.docs) {
        await doc.reference.delete();
      }
      final borrowerRequestsSnapshot = await _db
          .collection('borrow_requests')
          .where('borrowerId', isEqualTo: uid)
          .get();
      for (final doc in borrowerRequestsSnapshot.docs) {
        await doc.reference.delete();
      }

      // 6. Delete rental requests (as owner or renter)
      final rentalRequestsOwnerSnapshot = await _db
          .collection('rental_requests')
          .where('ownerId', isEqualTo: uid)
          .get();
      for (final doc in rentalRequestsOwnerSnapshot.docs) {
        await doc.reference.delete();
      }
      final rentalRequestsRenterSnapshot = await _db
          .collection('rental_requests')
          .where('renterId', isEqualTo: uid)
          .get();
      for (final doc in rentalRequestsRenterSnapshot.docs) {
        await doc.reference.delete();
      }

      // 7. Delete trade offers (as from or to user)
      final tradeOffersFromSnapshot = await _db
          .collection('trade_offers')
          .where('fromUserId', isEqualTo: uid)
          .get();
      for (final doc in tradeOffersFromSnapshot.docs) {
        await doc.reference.delete();
      }
      final tradeOffersToSnapshot = await _db
          .collection('trade_offers')
          .where('toUserId', isEqualTo: uid)
          .get();
      for (final doc in tradeOffersToSnapshot.docs) {
        await doc.reference.delete();
      }

      // 8. Delete giveaway claims
      final giveawayClaimsSnapshot = await _db
          .collection('giveaway_claims')
          .where('claimedBy', isEqualTo: uid)
          .get();
      for (final doc in giveawayClaimsSnapshot.docs) {
        await doc.reference.delete();
      }

      // 9. Delete notifications (sent to user)
      final notificationsSnapshot = await _db
          .collection('notifications')
          .where('toUserId', isEqualTo: uid)
          .get();
      for (final doc in notificationsSnapshot.docs) {
        await doc.reference.delete();
      }

      // 10. Delete FCM tokens
      try {
        await _db.collection('fcm_tokens').doc(uid).delete();
      } catch (e) {
        // FCM token might not exist, continue
        debugPrint('FCM token deletion skipped: $e');
      }

      // 11. Delete reminders
      final remindersSnapshot = await _db
          .collection('reminders')
          .where('userId', isEqualTo: uid)
          .get();
      for (final doc in remindersSnapshot.docs) {
        await doc.reference.delete();
      }

      // 12. Delete email verifications
      try {
        await _db.collection('email_verifications').doc(uid).delete();
      } catch (e) {
        // Email verification might not exist, continue
        debugPrint('Email verification deletion skipped: $e');
      }

      // 13. Delete user blocks (where user is blocked)
      final userBlocksSnapshot = await _db
          .collection('user_blocks')
          .where('blockedUserId', isEqualTo: uid)
          .get();
      for (final doc in userBlocksSnapshot.docs) {
        await doc.reference.delete();
      }

      // Note: We keep ratings, reports, and conversations for historical/legal purposes
      // but they will show "Deleted User" or similar when the user is referenced
      // If you want to delete these too, uncomment the sections below:

      // 14. Delete ratings (given by user) - UNCOMMENT IF NEEDED
      // final ratingsGivenSnapshot = await _db
      //     .collection('ratings')
      //     .where('ratedBy', isEqualTo: uid)
      //     .get();
      // for (final doc in ratingsGivenSnapshot.docs) {
      //   await doc.reference.delete();
      // }

      // 15. Delete reports (as reporter) - UNCOMMENT IF NEEDED
      // final reportsAsReporterSnapshot = await _db
      //     .collection('reports')
      //     .where('reporterId', isEqualTo: uid)
      //     .get();
      // for (final doc in reportsAsReporterSnapshot.docs) {
      //   await doc.reference.delete();
      // }

      // 16. Delete conversations - UNCOMMENT IF NEEDED
      // This is more complex as conversations have subcollections
      // final conversationsSnapshot = await _db
      //     .collection('conversations')
      //     .where('participants', arrayContains: uid)
      //     .get();
      // for (final doc in conversationsSnapshot.docs) {
      //   // Delete messages subcollection first
      //   final messagesSnapshot = await doc.reference
      //       .collection('messages')
      //       .get();
      //   for (final msgDoc in messagesSnapshot.docs) {
      //     await msgDoc.reference.delete();
      //   }
      //   await doc.reference.delete();
      // }

      // 17. Delete profile photos and ID images from Storage
      try {
        final userDoc = await _db.collection('users').doc(uid).get();
        if (userDoc.exists) {
          final userData = userDoc.data();
          final profilePhotoUrl = userData?['profilePhotoUrl'] as String?;
          final barangayIdUrl = userData?['barangayIdUrl'] as String?;
          final barangayIdUrlBack = userData?['barangayIdUrlBack'] as String?;

          final storageService = StorageService();
          if (profilePhotoUrl != null && profilePhotoUrl.isNotEmpty) {
            try {
              await storageService.deleteImage(profilePhotoUrl);
            } catch (e) {
              debugPrint('Failed to delete profile photo: $e');
            }
          }
          if (barangayIdUrl != null && barangayIdUrl.isNotEmpty) {
            try {
              await storageService.deleteImage(barangayIdUrl);
            } catch (e) {
              debugPrint('Failed to delete ID front image: $e');
            }
          }
          if (barangayIdUrlBack != null && barangayIdUrlBack.isNotEmpty) {
            try {
              await storageService.deleteImage(barangayIdUrlBack);
            } catch (e) {
              debugPrint('Failed to delete ID back image: $e');
            }
          }
        }
      } catch (e) {
        debugPrint('Storage deletion skipped: $e');
      }
    } catch (e) {
      debugPrint('Error deleting associated data: $e');
      // Continue with user deletion even if some data cleanup fails
    }

    // Delete Firebase Auth user (if available)
    try {
      // Note: This requires Firebase Admin SDK on the server side
      // For client-side, we'll just delete the Firestore document
      // The Auth user will remain but won't be able to access the app
      debugPrint(
        'Note: Firebase Auth user deletion requires server-side implementation',
      );
    } catch (e) {
      debugPrint('Warning: Could not delete Firebase Auth user: $e');
      // Continue with Firestore deletion even if Auth deletion fails
    }

    // Finally, delete user document from Firestore
    await _db.collection('users').doc(uid).delete();

    // Create activity log
    try {
      await _db.collection('activity_logs').add({
        'timestamp': FieldValue.serverTimestamp(),
        'category': 'admin',
        'action': 'user_deleted',
        'actorId': adminId,
        'actorName': adminName,
        'targetId': uid,
        'targetType': 'user',
        'description': 'Deleted user account: $deletedUserName',
        'metadata': {
          'userId': uid,
          'userName': deletedUserName,
          'userEmail': userEmail ?? 'N/A',
          'reason': reason ?? 'No reason provided',
          'deletedAt': DateTime.now().toIso8601String(),
        },
        'severity': 'critical',
      });
    } catch (e) {
      // Log error but don't fail the deletion if logging fails
      debugPrint('Error creating activity log for user deletion: $e');
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
    int newViolationCount = 0;
    String? userName;

    await _db.runTransaction((txn) async {
      final snap = await txn.get(userRef);
      final current = (snap.data()?['violationCount'] ?? 0) as int;
      newViolationCount = current + 1;

      // Get user name for notification
      final userData = snap.data();
      final firstName = userData?['firstName'] ?? '';
      final lastName = userData?['lastName'] ?? '';
      userName = '$firstName $lastName'.trim();
      if (userName!.isEmpty) {
        userName = userData?['email'] ?? 'User';
      }

      txn.update(userRef, {
        'violationCount': newViolationCount,
        'lastViolationNote': note ?? '',
        'lastViolationAt': FieldValue.serverTimestamp(),
      });
    });

    // Send notification to the user about the violation with warning system
    try {
      String notificationTitle;
      String notificationMessage;
      String warningLevel = 'info';

      // Warning system based on violation count
      if (newViolationCount == 1) {
        notificationTitle = 'First Violation - Warning';
        notificationMessage =
            '⚠️ You have received your first violation. '
            'Please review our community guidelines to avoid further violations.';
        warningLevel = 'warning';
      } else if (newViolationCount == 2) {
        notificationTitle = 'Second Violation - Serious Warning';
        notificationMessage =
            '⚠️⚠️ You have received a second violation. '
            'Continued violations may result in account suspension. '
            'Please ensure you follow all community guidelines.';
        warningLevel = 'warning';
      } else if (newViolationCount == 3) {
        notificationTitle = 'Third Violation - Final Warning';
        notificationMessage =
            '🚨 You have received a third violation. '
            'Your account is at high risk of suspension. '
            'Any further violations will result in immediate account suspension.';
        warningLevel = 'critical';
      } else if (newViolationCount >= 4) {
        notificationTitle = 'Multiple Violations - Account at Risk';
        notificationMessage =
            '🚨🚨 You have received $newViolationCount violations. '
            'Your account is at severe risk of permanent suspension. '
            'Please contact support if you have questions about these violations.';
        warningLevel = 'critical';
      } else {
        notificationTitle = 'Violation Issued';
        notificationMessage =
            'You have received a violation. '
            'Your account has $newViolationCount total violations.';
        warningLevel = 'warning';
      }

      if (note != null && note.trim().isNotEmpty) {
        notificationMessage += '\n\nAdmin Note: $note';
      }

      await _db.collection('notifications').add({
        'toUserId': userId,
        'type': 'violation_issued',
        'title': notificationTitle,
        'message': notificationMessage,
        'violationCount': newViolationCount,
        'violationNote': note ?? '',
        'warningLevel': warningLevel,
        'status': 'unread',
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Auto-suspend if violation count reaches threshold (e.g., 5 violations)
      if (newViolationCount >= 5) {
        try {
          await suspendUser(
            userId,
            reason: 'Automatic suspension due to $newViolationCount violations',
          );
          // Send additional notification about suspension
          await _db.collection('notifications').add({
            'toUserId': userId,
            'type': 'account_suspended',
            'title': 'Account Suspended',
            'message':
                'Your account has been automatically suspended due to '
                'reaching $newViolationCount violations. '
                'Please contact support if you believe this is an error.',
            'status': 'unread',
            'createdAt': FieldValue.serverTimestamp(),
          });
        } catch (e) {
          debugPrint('Error auto-suspending user after violations: $e');
        }
      }

      // Create activity log
      try {
        final adminUser = fb_auth.FirebaseAuth.instance.currentUser;
        final adminId = adminUser?.uid ?? 'system';
        String adminName = 'Admin';

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

        await _db.collection('activity_logs').add({
          'timestamp': FieldValue.serverTimestamp(),
          'category': 'admin',
          'action': 'violation_filed',
          'actorId': adminId,
          'actorName': adminName,
          'targetId': userId,
          'targetType': 'user',
          'description': 'Filed violation against user: $userName',
          'metadata': {
            'userId': userId,
            'userName': userName,
            'violationCount': newViolationCount,
            'note': note ?? '',
          },
          'severity': 'warning',
        });
      } catch (e) {
        debugPrint('Error creating activity log for violation: $e');
      }
    } catch (e) {
      debugPrint('Error sending violation notification: $e');
      // Don't fail the violation filing if notification fails
    }
  }

  Future<void> resolveReport(
    String reportId, {
    String resolution = 'resolved',
  }) async {
    // Get report data before updating
    final reportDoc = await _db.collection('reports').doc(reportId).get();
    if (!reportDoc.exists) {
      throw Exception('Report not found');
    }

    final reportData = reportDoc.data()!;
    final reporterId = reportData['reporterId'] as String?;
    final reportedUserId = reportData['reportedUserId'] as String?;
    final reportedUserName =
        reportData['reportedUserName'] as String? ?? 'User';
    final reason = reportData['reason'] as String? ?? 'No reason specified';
    final isUserReport = reportedUserId != null;

    // Update report status
    await _db.collection('reports').doc(reportId).update({
      'status': resolution,
      'resolvedAt': FieldValue.serverTimestamp(),
      'resolvedBy': fb_auth.FirebaseAuth.instance.currentUser?.uid ?? 'system',
    });

    // Send notifications to both parties
    try {
      // Get admin name for notifications
      final adminUser = fb_auth.FirebaseAuth.instance.currentUser;
      final adminId = adminUser?.uid ?? 'system';
      String adminName = 'Admin';

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

      // Notification to reporter
      if (reporterId != null) {
        await _db.collection('notifications').add({
          'toUserId': reporterId,
          'type': 'report_resolved',
          'title': 'Report Resolved',
          'message': isUserReport
              ? 'Your report against $reportedUserName has been reviewed and resolved by an administrator.'
              : 'Your report has been reviewed and resolved by an administrator.',
          'reportId': reportId,
          'status': 'unread',
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      // Notification to reported user (if it's a user report)
      if (isUserReport) {
        String messageToReported;
        if (resolution == 'resolved' || resolution == 'dismissed') {
          messageToReported =
              'A report filed against you has been reviewed. '
              'The report has been ${resolution == 'dismissed' ? 'dismissed' : 'resolved'}. '
              'Please continue to follow our community guidelines.';
        } else {
          messageToReported =
              'A report filed against you has been reviewed and marked as: $resolution. '
              'Please review our community guidelines.';
        }

        await _db.collection('notifications').add({
          'toUserId': reportedUserId,
          'type': 'report_resolved',
          'title': 'Report Review Completed',
          'message': messageToReported,
          'reportId': reportId,
          'status': 'unread',
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      // Create activity log
      try {
        await _db.collection('activity_logs').add({
          'timestamp': FieldValue.serverTimestamp(),
          'category': 'admin',
          'action': 'report_resolved',
          'actorId': adminId,
          'actorName': adminName,
          'targetId': reportId,
          'targetType': 'report',
          'description': 'Resolved report: $reportId',
          'metadata': {
            'reportId': reportId,
            'resolution': resolution,
            'reporterId': reporterId,
            'reportedUserId': reportedUserId,
            'reason': reason,
          },
          'severity': 'info',
        });
      } catch (e) {
        debugPrint('Error creating activity log for report resolution: $e');
      }
    } catch (e) {
      debugPrint('Error sending report resolution notifications: $e');
      // Don't fail the report resolution if notification fails
    }
  }

  // Bulk Operations
  Future<BulkOperationResult> bulkApproveUsers(List<String> uids) async {
    final results = BulkOperationResult();
    for (final uid in uids) {
      try {
        await approveUser(uid);
        results.successCount++;
        results.successIds.add(uid);
      } catch (e) {
        results.failureCount++;
        results.failures[uid] = e.toString();
      }
    }
    return results;
  }

  Future<BulkOperationResult> bulkRejectUsers(
    List<String> uids, {
    String? reason,
  }) async {
    final results = BulkOperationResult();
    for (final uid in uids) {
      try {
        await rejectUser(uid, reason: reason);
        results.successCount++;
        results.successIds.add(uid);
      } catch (e) {
        results.failureCount++;
        results.failures[uid] = e.toString();
      }
    }
    return results;
  }

  Future<BulkOperationResult> bulkSuspendUsers(
    List<String> uids, {
    String? reason,
  }) async {
    final results = BulkOperationResult();
    for (final uid in uids) {
      try {
        await suspendUser(uid, reason: reason);
        results.successCount++;
        results.successIds.add(uid);
      } catch (e) {
        results.failureCount++;
        results.failures[uid] = e.toString();
      }
    }
    return results;
  }

  Future<BulkOperationResult> bulkRestoreUsers(List<String> uids) async {
    final results = BulkOperationResult();
    for (final uid in uids) {
      try {
        await restoreUser(uid);
        results.successCount++;
        results.successIds.add(uid);
      } catch (e) {
        results.failureCount++;
        results.failures[uid] = e.toString();
      }
    }
    return results;
  }

  Future<BulkOperationResult> bulkResolveReports(
    List<String> reportIds, {
    String resolution = 'resolved',
  }) async {
    final results = BulkOperationResult();
    for (final reportId in reportIds) {
      try {
        await resolveReport(reportId, resolution: resolution);
        results.successCount++;
        results.successIds.add(reportId);
      } catch (e) {
        results.failureCount++;
        results.failures[reportId] = e.toString();
      }
    }
    return results;
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

// Bulk operation result model
class BulkOperationResult {
  int successCount = 0;
  int failureCount = 0;
  List<String> successIds = [];
  Map<String, String> failures = {};

  bool get hasFailures => failureCount > 0;
  bool get hasSuccess => successCount > 0;
  int get totalCount => successCount + failureCount;
}
