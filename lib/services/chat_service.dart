import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/conversation_model.dart';
import '../models/message_model.dart';

class ChatService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Create or get existing conversation between two users
  Future<String> createOrGetConversation({
    required String userId1,
    required String userId1Name,
    required String userId2,
    required String userId2Name,
    String? itemId,
    String? itemTitle,
  }) async {
    try {
      // Create sorted list of participants for consistent conversation IDs
      final participants = [userId1, userId2]..sort();

      // Check if conversation already exists
      final existingQuery = await _db
          .collection('conversations')
          .where('participants', arrayContains: userId1)
          .get();

      for (var doc in existingQuery.docs) {
        final data = doc.data();
        final convParticipants = List<String>.from(data['participants'] ?? []);
        convParticipants.sort();

        if (convParticipants.length == 2 &&
            convParticipants[0] == participants[0] &&
            convParticipants[1] == participants[1]) {
          return doc.id;
        }
      }

      // Create new conversation
      final conversationData = {
        'participants': participants,
        'participantNames': {userId1: userId1Name, userId2: userId2Name},
        'lastMessage': '',
        'lastMessageTime': FieldValue.serverTimestamp(),
        'lastMessageSenderId': '',
        'hasUnreadMessages': false,
        'unreadCount': 0,
        'unreadCountByUser': {userId1: 0, userId2: 0},
        'mutedByUsers': [],
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        if (itemId != null) 'itemId': itemId,
        if (itemTitle != null) 'itemTitle': itemTitle,
      };

      final docRef = await _db
          .collection('conversations')
          .add(conversationData);
      return docRef.id;
    } catch (e) {
      throw Exception('Error creating conversation: $e');
    }
  }

  // Send a message
  Future<String> sendMessage({
    required String conversationId,
    required String senderId,
    required String senderName,
    required String content,
    String? imageUrl,
    String? replyToMessageId,
    String? replyToContent,
    String? replyToSenderName,
  }) async {
    try {
      final messageData = {
        'conversationId': conversationId,
        'senderId': senderId,
        'senderName': senderName,
        'content': content,
        'timestamp': FieldValue.serverTimestamp(),
        'status': 'sent',
        'isRead': false,
        'imageUrl': imageUrl,
        if (replyToMessageId != null) 'replyToMessageId': replyToMessageId,
        if (replyToContent != null) 'replyToContent': replyToContent,
        if (replyToSenderName != null) 'replyToSenderName': replyToSenderName,
        'isDeleted': false,
        'deletedForEveryone': false,
      };

      final messageRef = await _db
          .collection('conversations')
          .doc(conversationId)
          .collection('messages')
          .add(messageData);
      final messageId = messageRef.id;

      // Update conversation with last message info
      await _db.collection('conversations').doc(conversationId).update({
        'lastMessage': content,
        'lastMessageTime': FieldValue.serverTimestamp(),
        'lastMessageSenderId': senderId,
        'lastMessageId': messageId,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Increment unread count for all participants except sender
      final conversationDoc = await _db
          .collection('conversations')
          .doc(conversationId)
          .get();

      if (conversationDoc.exists) {
        final data = conversationDoc.data()!;
        final participants = List<String>.from(data['participants'] ?? []);
        final unreadCountByUser = Map<String, dynamic>.from(
          data['unreadCountByUser'] ?? {},
        );

        for (var participantId in participants) {
          if (participantId != senderId) {
            final currentCount = unreadCountByUser[participantId] ?? 0;
            unreadCountByUser[participantId] = currentCount + 1;
          }
        }

        final totalUnread = unreadCountByUser.values.fold<int>(
          0,
          (total, value) => total + ((value is int ? value : 0)),
        );

        await _db.collection('conversations').doc(conversationId).update({
          'hasUnreadMessages': true,
          'unreadCountByUser': unreadCountByUser,
          'unreadCount': totalUnread,
        });

        // Create notifications for recipients (one-to-one and group chats)
        try {
          final isGroup = data['isGroup'] == true;
          final groupName = data['groupName'] as String?;
          final participantNames = Map<String, dynamic>.from(
            data['participantNames'] ?? {},
          );
          final mutedByUsers = List<String>.from(
            data['mutedByUsers'] ?? const [],
          );

          for (final participantId in participants) {
            if (participantId == senderId) continue;
            if (mutedByUsers.contains(participantId)) continue;

            // Best-effort: create a notification document that Cloud Functions
            // will use to send FCM push notifications.
            await _db.collection('notifications').add({
              'toUserId': participantId,
              'type': 'chat_message',
              'conversationId': conversationId,
              'messageId': messageId,
              'senderId': senderId,
              'senderName': senderName,
              'content': content,
              'isGroup': isGroup,
              if (isGroup) 'groupName': groupName,
              'participantNameMap': participantNames,
              'status': 'unread',
              'createdAt': FieldValue.serverTimestamp(),
            });
          }
        } catch (e) {
          // Best-effort: chat should still work even if notification write fails
          throw Exception('Error creating chat notifications: $e');
        }
      }

      return messageId;
    } catch (e) {
      throw Exception('Error sending message: $e');
    }
  }

  // Get all conversations for a user
  Future<List<ConversationModel>> getUserConversations(String userId) async {
    try {
      final snapshot = await _db
          .collection('conversations')
          .where('participants', arrayContains: userId)
          // Dropping orderBy to avoid composite index requirement; sort client-side
          .get();

      final conversations = snapshot.docs
          .map((doc) => ConversationModel.fromMap(doc.data(), doc.id))
          .toList();

      conversations.sort(
        (a, b) => b.lastMessageTime.compareTo(a.lastMessageTime),
      );

      return conversations;
    } catch (e) {
      throw Exception('Error getting conversations: $e');
    }
  }

  // Stream conversations for real-time updates
  Stream<List<ConversationModel>> getUserConversationsStream(String userId) {
    try {
      return _db
          .collection('conversations')
          .where('participants', arrayContains: userId)
          // Dropping orderBy to avoid composite index requirement; sort client-side
          .snapshots()
          .map((snapshot) {
            final list = snapshot.docs
                .map((doc) => ConversationModel.fromMap(doc.data(), doc.id))
                .toList();
            list.sort((a, b) => b.lastMessageTime.compareTo(a.lastMessageTime));
            return list;
          });
    } catch (e) {
      throw Exception('Error streaming conversations: $e');
    }
  }

  // Get all messages for a conversation
  Future<List<MessageModel>> getConversationMessages(
    String conversationId,
  ) async {
    try {
      final snapshot = await _db
          .collection('conversations')
          .doc(conversationId)
          .collection('messages')
          .orderBy('timestamp', descending: false)
          .get();

      return snapshot.docs
          .map((doc) => MessageModel.fromMap(doc.data(), doc.id))
          .toList();
    } catch (e) {
      throw Exception('Error getting messages: $e');
    }
  }

  // Stream messages for real-time updates
  Stream<List<MessageModel>> getConversationMessagesStream(
    String conversationId,
  ) {
    try {
      return _db
          .collection('conversations')
          .doc(conversationId)
          .collection('messages')
          .orderBy('timestamp', descending: false)
          .snapshots()
          .map(
            (snapshot) => snapshot.docs
                .map((doc) => MessageModel.fromMap(doc.data(), doc.id))
                .toList(),
          );
    } catch (e) {
      throw Exception('Error streaming messages: $e');
    }
  }

  // Mark messages as read
  Future<void> markMessagesAsRead(String conversationId, String userId) async {
    try {
      // Update unread count for this user
      final conversationDoc = await _db
          .collection('conversations')
          .doc(conversationId)
          .get();

      if (conversationDoc.exists) {
        final data = conversationDoc.data()!;
        final unreadCountByUser = Map<String, dynamic>.from(
          data['unreadCountByUser'] ?? {},
        );
        unreadCountByUser[userId] = 0;

        // Check if any user still has unread messages
        final hasUnread = unreadCountByUser.values.any((value) => value > 0);

        final totalUnread = unreadCountByUser.values.fold<int>(
          0,
          (total, value) => total + ((value is int ? value : 0)),
        );

        await _db.collection('conversations').doc(conversationId).update({
          'hasUnreadMessages': hasUnread,
          'unreadCount': totalUnread,
          'unreadCountByUser': unreadCountByUser,
        });
      }

      // Update message status to 'read'
      final messagesSnapshot = await _db
          .collection('conversations')
          .doc(conversationId)
          .collection('messages')
          .where('senderId', isNotEqualTo: userId)
          .where('isRead', isEqualTo: false)
          .get();

      final batch = _db.batch();
      for (var doc in messagesSnapshot.docs) {
        batch.update(doc.reference, {
          'isRead': true,
          'readAt': FieldValue.serverTimestamp(),
          'status': 'read',
        });
      }

      await batch.commit();
    } catch (e) {
      throw Exception('Error marking messages as read: $e');
    }
  }

  // Delete a conversation
  Future<void> deleteConversation(String conversationId) async {
    try {
      // Delete all messages in the conversation
      final messagesSnapshot = await _db
          .collection('conversations')
          .doc(conversationId)
          .collection('messages')
          .get();

      final batch = _db.batch();
      for (var doc in messagesSnapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();

      // Delete the conversation
      await _db.collection('conversations').doc(conversationId).delete();
    } catch (e) {
      throw Exception('Error deleting conversation: $e');
    }
  }

  // Search conversations
  Future<List<ConversationModel>> searchConversations(
    String userId,
    String query,
  ) async {
    try {
      final conversations = await getUserConversations(userId);
      final lowerQuery = query.toLowerCase();

      return conversations.where((conversation) {
        final otherParticipantName = conversation.participantNames.values
            .join(' ')
            .toLowerCase();
        final lastMessage = conversation.lastMessage.toLowerCase();
        final itemTitle = conversation.itemTitle?.toLowerCase() ?? '';

        return otherParticipantName.contains(lowerQuery) ||
            lastMessage.contains(lowerQuery) ||
            itemTitle.contains(lowerQuery);
      }).toList();
    } catch (e) {
      throw Exception('Error searching conversations: $e');
    }
  }

  // Typing indicators
  Future<void> setTypingStatus({
    required String conversationId,
    required String userId,
    required bool isTyping,
  }) async {
    try {
      await _db.collection('conversations').doc(conversationId).update({
        'typingUsers': isTyping
            ? FieldValue.arrayUnion([userId])
            : FieldValue.arrayRemove([userId]),
      });
    } catch (e) {
      throw Exception('Error setting typing status: $e');
    }
  }

  // Stream typing status
  Stream<Map<String, bool>> getTypingStatusStream(String conversationId) {
    try {
      return _db
          .collection('conversations')
          .doc(conversationId)
          .snapshots()
          .map((snapshot) {
            final data = snapshot.data();
            final typingUsers = List<String>.from(data?['typingUsers'] ?? []);
            final participants = List<String>.from(data?['participants'] ?? []);

            final typingStatus = <String, bool>{};
            for (var participantId in participants) {
              typingStatus[participantId] = typingUsers.contains(participantId);
            }
            return typingStatus;
          });
    } catch (e) {
      throw Exception('Error streaming typing status: $e');
    }
  }

  // Delete a message
  Future<void> deleteMessage({
    required String conversationId,
    required String messageId,
    required String userId,
    required bool deleteForEveryone,
  }) async {
    try {
      final messageRef = _db
          .collection('conversations')
          .doc(conversationId)
          .collection('messages')
          .doc(messageId);

      final messageDoc = await messageRef.get();
      if (!messageDoc.exists) {
        throw Exception('Message not found');
      }

      final messageData = messageDoc.data()!;
      final senderId = messageData['senderId'] as String;

      // Only sender can delete for everyone
      if (deleteForEveryone && senderId != userId) {
        throw Exception('Only the sender can delete for everyone');
      }

      if (deleteForEveryone) {
        // Delete for everyone - mark as deleted
        await messageRef.update({
          'isDeleted': true,
          'deletedForEveryone': true,
          'content': 'This message was deleted',
        });
      } else {
        // Delete for me only - mark as deleted for this user
        // Store deleted messages per user in a subcollection or array
        await messageRef.update({
          'deletedForUsers': FieldValue.arrayUnion([userId]),
        });
      }

      // Update last message if this was the last message
      final conversationDoc = await _db
          .collection('conversations')
          .doc(conversationId)
          .get();

      if (conversationDoc.exists) {
        final lastMessageId = conversationDoc.data()?['lastMessageId'];
        if (lastMessageId == messageId) {
          // Find the most recent non-deleted message
          final messagesSnapshot = await _db
              .collection('conversations')
              .doc(conversationId)
              .collection('messages')
              .orderBy('timestamp', descending: true)
              .limit(1)
              .get();

          if (messagesSnapshot.docs.isNotEmpty) {
            final lastMsg = messagesSnapshot.docs.first.data();
            await _db.collection('conversations').doc(conversationId).update({
              'lastMessage': lastMsg['content'] ?? '',
              'lastMessageTime': lastMsg['timestamp'],
              'lastMessageSenderId': lastMsg['senderId'] ?? '',
            });
          }
        }
      }
    } catch (e) {
      throw Exception('Error deleting message: $e');
    }
  }

  // Search messages within a conversation
  Future<List<MessageModel>> searchMessagesInConversation({
    required String conversationId,
    required String query,
  }) async {
    try {
      final snapshot = await _db
          .collection('conversations')
          .doc(conversationId)
          .collection('messages')
          .orderBy('timestamp', descending: false)
          .get();

      final lowerQuery = query.toLowerCase();
      return snapshot.docs
          .map((doc) => MessageModel.fromMap(doc.data(), doc.id))
          .where((message) {
            // Filter out deleted messages
            if (message.isDeleted && message.deletedForEveryone) {
              return false;
            }
            // Search in content
            return message.content.toLowerCase().contains(lowerQuery);
          })
          .toList();
    } catch (e) {
      throw Exception('Error searching messages: $e');
    }
  }

  // Mute a conversation for a user
  Future<void> muteConversation({
    required String conversationId,
    required String userId,
  }) async {
    try {
      await _db.collection('conversations').doc(conversationId).update({
        'mutedByUsers': FieldValue.arrayUnion([userId]),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw Exception('Error muting conversation: $e');
    }
  }

  // Unmute a conversation for a user
  Future<void> unmuteConversation({
    required String conversationId,
    required String userId,
  }) async {
    try {
      await _db.collection('conversations').doc(conversationId).update({
        'mutedByUsers': FieldValue.arrayRemove([userId]),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw Exception('Error unmuting conversation: $e');
    }
  }

  // Get conversation details
  Future<ConversationModel?> getConversation(String conversationId) async {
    try {
      final doc = await _db
          .collection('conversations')
          .doc(conversationId)
          .get();

      if (!doc.exists || doc.data() == null) {
        return null;
      }

      return ConversationModel.fromMap(doc.data()!, doc.id);
    } catch (e) {
      throw Exception('Error getting conversation: $e');
    }
  }

  // Create a group conversation
  Future<String> createGroupConversation({
    required String adminId,
    required String adminName,
    required List<String> participantIds,
    required Map<String, String> participantNames,
    required String groupName,
    String? groupImageUrl,
  }) async {
    try {
      // Ensure admin is in participants
      final allParticipants = <String>{...participantIds, adminId};
      final allParticipantNames = Map<String, String>.from(participantNames);
      allParticipantNames[adminId] = adminName;

      // Initialize unread counts for all participants
      final unreadCountByUser = <String, int>{};
      for (var participantId in allParticipants) {
        unreadCountByUser[participantId] = 0;
      }

      final conversationData = {
        'participants': allParticipants.toList(),
        'participantNames': allParticipantNames,
        'lastMessage': '',
        'lastMessageTime': FieldValue.serverTimestamp(),
        'lastMessageSenderId': '',
        'hasUnreadMessages': false,
        'unreadCount': 0,
        'unreadCountByUser': unreadCountByUser,
        'mutedByUsers': [],
        'isGroup': true,
        'groupName': groupName,
        'groupAdmin': adminId,
        'groupImageUrl': groupImageUrl,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      final docRef = await _db
          .collection('conversations')
          .add(conversationData);
      return docRef.id;
    } catch (e) {
      throw Exception('Error creating group conversation: $e');
    }
  }

  // Add participant to group
  Future<void> addParticipantToGroup({
    required String conversationId,
    required String userId,
    required String userName,
    required String adminId,
  }) async {
    try {
      final conversationDoc = await _db
          .collection('conversations')
          .doc(conversationId)
          .get();

      if (!conversationDoc.exists) {
        throw Exception('Conversation not found');
      }

      final data = conversationDoc.data()!;
      if (data['isGroup'] != true) {
        throw Exception('Not a group conversation');
      }

      if (data['groupAdmin'] != adminId) {
        throw Exception('Only group admin can add participants');
      }

      final participants = List<String>.from(data['participants'] ?? []);
      if (participants.contains(userId)) {
        throw Exception('User is already in the group');
      }

      final participantNames = Map<String, dynamic>.from(
        data['participantNames'] ?? {},
      );
      participantNames[userId] = userName;

      final unreadCountByUser = Map<String, dynamic>.from(
        data['unreadCountByUser'] ?? {},
      );
      unreadCountByUser[userId] = 0;

      await _db.collection('conversations').doc(conversationId).update({
        'participants': FieldValue.arrayUnion([userId]),
        'participantNames': participantNames,
        'unreadCountByUser': unreadCountByUser,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw Exception('Error adding participant: $e');
    }
  }

  // Remove participant from group
  Future<void> removeParticipantFromGroup({
    required String conversationId,
    required String userId,
    required String adminId,
  }) async {
    try {
      final conversationDoc = await _db
          .collection('conversations')
          .doc(conversationId)
          .get();

      if (!conversationDoc.exists) {
        throw Exception('Conversation not found');
      }

      final data = conversationDoc.data()!;
      if (data['isGroup'] != true) {
        throw Exception('Not a group conversation');
      }

      // Admin can remove anyone, users can leave themselves
      final isAdmin = data['groupAdmin'] == adminId;
      final isLeavingSelf = userId == adminId;

      if (!isAdmin && !isLeavingSelf) {
        throw Exception('Only group admin can remove participants');
      }

      // Can't remove the admin (unless they're leaving themselves)
      if (data['groupAdmin'] == userId && !isLeavingSelf) {
        throw Exception('Cannot remove group admin. Transfer admin first.');
      }

      final participantNames = Map<String, dynamic>.from(
        data['participantNames'] ?? {},
      );
      participantNames.remove(userId);

      final unreadCountByUser = Map<String, dynamic>.from(
        data['unreadCountByUser'] ?? {},
      );
      unreadCountByUser.remove(userId);

      final participants = List<String>.from(data['participants'] ?? []);
      participants.remove(userId);

      // If admin is leaving and there are other participants, transfer admin
      if (data['groupAdmin'] == userId && isLeavingSelf) {
        if (participants.isEmpty) {
          // Delete group if no participants left
          await _db.collection('conversations').doc(conversationId).delete();
          return;
        }

        // Transfer admin to first remaining participant
        final newAdminId = participants.first;
        await _db.collection('conversations').doc(conversationId).update({
          'participants': participants,
          'participantNames': participantNames,
          'unreadCountByUser': unreadCountByUser,
          'groupAdmin': newAdminId,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else if (participants.isEmpty) {
        // Delete group if no participants left (shouldn't happen for non-admin)
        await _db.collection('conversations').doc(conversationId).delete();
      } else {
        // Regular member leaving or admin removing someone
        await _db.collection('conversations').doc(conversationId).update({
          'participants': participants,
          'participantNames': participantNames,
          'unreadCountByUser': unreadCountByUser,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      throw Exception('Error removing participant: $e');
    }
  }

  // Update group name
  Future<void> updateGroupName({
    required String conversationId,
    required String newName,
    required String adminId,
  }) async {
    try {
      final conversationDoc = await _db
          .collection('conversations')
          .doc(conversationId)
          .get();

      if (!conversationDoc.exists) {
        throw Exception('Conversation not found');
      }

      final data = conversationDoc.data()!;
      if (data['isGroup'] != true) {
        throw Exception('Not a group conversation');
      }

      if (data['groupAdmin'] != adminId) {
        throw Exception('Only group admin can update group name');
      }

      await _db.collection('conversations').doc(conversationId).update({
        'groupName': newName,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw Exception('Error updating group name: $e');
    }
  }

  // Update group image
  Future<void> updateGroupImage({
    required String conversationId,
    required String? imageUrl,
    required String adminId,
  }) async {
    try {
      final conversationDoc = await _db
          .collection('conversations')
          .doc(conversationId)
          .get();

      if (!conversationDoc.exists) {
        throw Exception('Conversation not found');
      }

      final data = conversationDoc.data()!;
      if (data['isGroup'] != true) {
        throw Exception('Not a group conversation');
      }

      if (data['groupAdmin'] != adminId) {
        throw Exception('Only group admin can update group image');
      }

      await _db.collection('conversations').doc(conversationId).update({
        'groupImageUrl': imageUrl,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw Exception('Error updating group image: $e');
    }
  }

  // Transfer group admin
  Future<void> transferGroupAdmin({
    required String conversationId,
    required String newAdminId,
    required String currentAdminId,
  }) async {
    try {
      final conversationDoc = await _db
          .collection('conversations')
          .doc(conversationId)
          .get();

      if (!conversationDoc.exists) {
        throw Exception('Conversation not found');
      }

      final data = conversationDoc.data()!;
      if (data['isGroup'] != true) {
        throw Exception('Not a group conversation');
      }

      if (data['groupAdmin'] != currentAdminId) {
        throw Exception('Only current admin can transfer admin');
      }

      final participants = List<String>.from(data['participants'] ?? []);
      if (!participants.contains(newAdminId)) {
        throw Exception('New admin must be a participant');
      }

      await _db.collection('conversations').doc(conversationId).update({
        'groupAdmin': newAdminId,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw Exception('Error transferring admin: $e');
    }
  }

  // Update group settings
  Future<void> updateGroupSettings({
    required String conversationId,
    required Map<String, dynamic> settings,
    required String adminId,
  }) async {
    try {
      final conversationDoc = await _db
          .collection('conversations')
          .doc(conversationId)
          .get();

      if (!conversationDoc.exists) {
        throw Exception('Conversation not found');
      }

      final data = conversationDoc.data()!;
      if (data['isGroup'] != true) {
        throw Exception('Not a group conversation');
      }

      if (data['groupAdmin'] != adminId) {
        throw Exception('Only group admin can update settings');
      }

      await _db.collection('conversations').doc(conversationId).update({
        'groupSettings': settings,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw Exception('Error updating group settings: $e');
    }
  }
}
