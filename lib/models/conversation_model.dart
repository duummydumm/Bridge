import 'package:cloud_firestore/cloud_firestore.dart';

class ConversationModel {
  final String conversationId;
  final List<String> participants; // User IDs
  final Map<String, String> participantNames; // userId -> name mapping
  final String lastMessage;
  final DateTime lastMessageTime;
  final String lastMessageSenderId;
  final bool hasUnreadMessages;
  final int unreadCount;
  final Map<String, int> unreadCountByUser; // userId -> unread count
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String? itemId; // Optional: link to item being discussed
  final String? itemTitle; // For display in conversation header

  ConversationModel({
    required this.conversationId,
    required this.participants,
    required this.participantNames,
    required this.lastMessage,
    required this.lastMessageTime,
    required this.lastMessageSenderId,
    required this.hasUnreadMessages,
    required this.unreadCount,
    required this.unreadCountByUser,
    required this.createdAt,
    this.updatedAt,
    this.itemId,
    this.itemTitle,
  });

  factory ConversationModel.fromMap(
    Map<String, dynamic> data,
    String documentId,
  ) {
    // Parse Map to get participant names
    final participantNames = <String, String>{};
    final rawParticipantNames =
        data['participantNames'] as Map<String, dynamic>?;
    if (rawParticipantNames != null) {
      rawParticipantNames.forEach((key, value) {
        participantNames[key] = value.toString();
      });
    }

    // Parse unread count by user
    final unreadCountByUser = <String, int>{};
    final rawUnreadCount = data['unreadCountByUser'] as Map<String, dynamic>?;
    if (rawUnreadCount != null) {
      rawUnreadCount.forEach((key, value) {
        unreadCountByUser[key] = value is int
            ? value
            : int.tryParse(value.toString()) ?? 0;
      });
    }

    return ConversationModel(
      conversationId: documentId,
      participants: List<String>.from(data['participants'] ?? []),
      participantNames: participantNames,
      lastMessage: data['lastMessage'] ?? '',
      lastMessageTime:
          (data['lastMessageTime'] as Timestamp?)?.toDate() ?? DateTime.now(),
      lastMessageSenderId: data['lastMessageSenderId'] ?? '',
      hasUnreadMessages: data['hasUnreadMessages'] ?? false,
      unreadCount: data['unreadCount'] ?? 0,
      unreadCountByUser: unreadCountByUser,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
      itemId: data['itemId'],
      itemTitle: data['itemTitle'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'participants': participants,
      'participantNames': participantNames,
      'lastMessage': lastMessage,
      'lastMessageTime': Timestamp.fromDate(lastMessageTime),
      'lastMessageSenderId': lastMessageSenderId,
      'hasUnreadMessages': hasUnreadMessages,
      'unreadCount': unreadCount,
      'unreadCountByUser': unreadCountByUser,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': updatedAt != null ? Timestamp.fromDate(updatedAt!) : null,
      'itemId': itemId,
      'itemTitle': itemTitle,
    };
  }

  // Get the other participant (not the current user)
  String getOtherParticipant(String currentUserId) {
    return participants.firstWhere(
      (userId) => userId != currentUserId,
      orElse: () => participants.isNotEmpty ? participants.first : '',
    );
  }

  // Get the other participant's name
  String getOtherParticipantName(String currentUserId) {
    final otherId = getOtherParticipant(currentUserId);
    return participantNames[otherId] ?? 'Unknown';
  }

  // Check if conversation has unread messages for current user
  bool hasUnreadForUser(String userId) {
    return (unreadCountByUser[userId] ?? 0) > 0;
  }

  // Get unread count for specific user
  int getUnreadCountForUser(String userId) {
    return unreadCountByUser[userId] ?? 0;
  }

  // Check if conversation involves an item
  bool get isItemDiscussion => itemId != null && itemId!.isNotEmpty;
}
