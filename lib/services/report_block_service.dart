import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class ReportBlockService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Block User Functions
  Future<void> blockUser({
    required String userId,
    required String blockedUserId,
    required String blockedUserName,
  }) async {
    try {
      // Add to user's blocked list
      await _db.collection('users').doc(userId).update({
        'blockedUsers': FieldValue.arrayUnion([blockedUserId]),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Create a block record for admin tracking
      await _db.collection('user_blocks').add({
        'userId': userId,
        'blockedUserId': blockedUserId,
        'blockedUserName': blockedUserName,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Create activity log for user blocking
      try {
        // Get user name for actor
        final userDoc = await _db.collection('users').doc(userId).get();
        String actorName = 'User';
        if (userDoc.exists) {
          final userData = userDoc.data();
          final firstName = userData?['firstName'] ?? '';
          final lastName = userData?['lastName'] ?? '';
          actorName = '$firstName $lastName'.trim();
          if (actorName.isEmpty) {
            actorName = userData?['email'] ?? 'User';
          }
        }

        await _db.collection('activity_logs').add({
          'timestamp': FieldValue.serverTimestamp(),
          'category': 'user',
          'action': 'user_blocked',
          'actorId': userId,
          'actorName': actorName,
          'targetId': blockedUserId,
          'targetType': 'user',
          'description': '$actorName blocked user: $blockedUserName',
          'metadata': {
            'userId': userId,
            'blockedUserId': blockedUserId,
            'blockedUserName': blockedUserName,
          },
          'severity': 'warning',
        });
      } catch (e) {
        debugPrint('Error creating activity log for user block: $e');
        // Don't fail block if logging fails
      }
    } catch (e) {
      throw Exception('Error blocking user: $e');
    }
  }

  Future<void> unblockUser({
    required String userId,
    required String blockedUserId,
  }) async {
    try {
      await _db.collection('users').doc(userId).update({
        'blockedUsers': FieldValue.arrayRemove([blockedUserId]),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Create activity log for user unblocking
      try {
        // Get user names
        final userDoc = await _db.collection('users').doc(userId).get();
        final blockedUserDoc = await _db
            .collection('users')
            .doc(blockedUserId)
            .get();

        String actorName = 'User';
        if (userDoc.exists) {
          final userData = userDoc.data();
          final firstName = userData?['firstName'] ?? '';
          final lastName = userData?['lastName'] ?? '';
          actorName = '$firstName $lastName'.trim();
          if (actorName.isEmpty) {
            actorName = userData?['email'] ?? 'User';
          }
        }

        String blockedUserName = 'User';
        if (blockedUserDoc.exists) {
          final blockedData = blockedUserDoc.data();
          final firstName = blockedData?['firstName'] ?? '';
          final lastName = blockedData?['lastName'] ?? '';
          blockedUserName = '$firstName $lastName'.trim();
          if (blockedUserName.isEmpty) {
            blockedUserName = blockedData?['email'] ?? 'User';
          }
        }

        await _db.collection('activity_logs').add({
          'timestamp': FieldValue.serverTimestamp(),
          'category': 'user',
          'action': 'user_unblocked',
          'actorId': userId,
          'actorName': actorName,
          'targetId': blockedUserId,
          'targetType': 'user',
          'description': '$actorName unblocked user: $blockedUserName',
          'metadata': {
            'userId': userId,
            'unblockedUserId': blockedUserId,
            'unblockedUserName': blockedUserName,
          },
          'severity': 'info',
        });
      } catch (e) {
        debugPrint('Error creating activity log for user unblock: $e');
        // Don't fail unblock if logging fails
      }
    } catch (e) {
      throw Exception('Error unblocking user: $e');
    }
  }

  Future<List<String>> getBlockedUsers(String userId) async {
    try {
      final userDoc = await _db.collection('users').doc(userId).get();
      if (!userDoc.exists) return [];
      final data = userDoc.data();
      final blocked = data?['blockedUsers'] as List<dynamic>?;
      return blocked?.map((e) => e.toString()).toList() ?? [];
    } catch (e) {
      return [];
    }
  }

  Stream<List<String>> getBlockedUsersStream(String userId) {
    return _db.collection('users').doc(userId).snapshots().map((snapshot) {
      if (!snapshot.exists) return <String>[];
      final data = snapshot.data();
      final blocked = data?['blockedUsers'] as List<dynamic>?;
      return blocked?.map((e) => e.toString()).toList() ?? <String>[];
    });
  }

  Future<bool> isUserBlocked({
    required String userId,
    required String otherUserId,
  }) async {
    try {
      final blockedUsers = await getBlockedUsers(userId);
      return blockedUsers.contains(otherUserId);
    } catch (e) {
      return false;
    }
  }

  // Check if either user has blocked the other (bidirectional check)
  Future<bool> areUsersBlocked({
    required String userId1,
    required String userId2,
  }) async {
    try {
      final user1Blocked = await isUserBlocked(
        userId: userId1,
        otherUserId: userId2,
      );
      final user2Blocked = await isUserBlocked(
        userId: userId2,
        otherUserId: userId1,
      );
      return user1Blocked || user2Blocked;
    } catch (e) {
      return false;
    }
  }

  // Report User Functions
  Future<String> reportUser({
    required String reporterId,
    required String reporterName,
    required String reportedUserId,
    required String reportedUserName,
    required String reason,
    String? description,
    String? contextType, // 'chat', 'profile', 'item', 'giveaway', etc.
    String? contextId, // conversationId, itemId, giveawayId, etc.
    List<String>? evidenceImageUrls, // URLs of uploaded evidence images
  }) async {
    try {
      final reportData = {
        'reporterId': reporterId,
        'reporterName': reporterName,
        'reportedUserId': reportedUserId,
        'reportedUserName': reportedUserName,
        'reason':
            reason, // 'spam', 'harassment', 'inappropriate_content', 'fraud', 'other'
        'description': description ?? '',
        'contextType': contextType ?? '',
        'contextId': contextId ?? '',
        'evidenceImageUrls': evidenceImageUrls ?? [],
        'status': 'open',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      final docRef = await _db.collection('reports').add(reportData);

      // Increment report count on the reported user
      await _db.collection('users').doc(reportedUserId).update({
        'reportCount': FieldValue.increment(1),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Create activity log for user reporting
      try {
        await _db.collection('activity_logs').add({
          'timestamp': FieldValue.serverTimestamp(),
          'category': 'user',
          'action': 'user_reported',
          'actorId': reporterId,
          'actorName': reporterName,
          'targetId': reportedUserId,
          'targetType': 'user',
          'description': '$reporterName reported user: $reportedUserName',
          'metadata': {
            'reporterId': reporterId,
            'reportedUserId': reportedUserId,
            'reportedUserName': reportedUserName,
            'reason': reason,
            'contextType': contextType ?? '',
            'contextId': contextId ?? '',
            'reportId': docRef.id,
          },
          'severity': 'warning',
        });
      } catch (e) {
        debugPrint('Error creating activity log for user report: $e');
        // Don't fail report if logging fails
      }

      return docRef.id;
    } catch (e) {
      throw Exception('Error reporting user: $e');
    }
  }

  // Report Giveaway/Item
  Future<String> reportContent({
    required String reporterId,
    required String reporterName,
    required String contentType, // 'giveaway', 'item', 'trade'
    required String contentId,
    required String contentTitle,
    required String ownerId,
    required String ownerName,
    required String reason,
    String? description,
    List<String>? evidenceImageUrls, // URLs of uploaded evidence images
  }) async {
    try {
      final reportData = {
        'reporterId': reporterId,
        'reporterName': reporterName,
        'contentType': contentType,
        'contentId': contentId,
        'contentTitle': contentTitle,
        'ownerId': ownerId,
        'ownerName': ownerName,
        'reason': reason,
        'description': description ?? '',
        'evidenceImageUrls': evidenceImageUrls ?? [],
        'status': 'open',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      final docRef = await _db.collection('reports').add(reportData);

      // Update content-specific report count
      if (contentType == 'giveaway') {
        await _db.collection('giveaways').doc(contentId).update({
          'reportCount': FieldValue.increment(1),
          'isReported': true,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      return docRef.id;
    } catch (e) {
      throw Exception('Error reporting content: $e');
    }
  }

  // Get user's reports (for admins)
  Stream<QuerySnapshot<Map<String, dynamic>>> getReports({
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
}
