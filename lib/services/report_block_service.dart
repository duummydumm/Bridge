import 'package:cloud_firestore/cloud_firestore.dart';

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
