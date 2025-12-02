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
  final List<String> mutedByUsers; // User IDs who have muted this conversation
  final bool isGroup; // Whether this is a group chat
  final String? groupName; // Name of the group (for group chats)
  final String? groupAdmin; // User ID of the group admin (for group chats)
  final String? groupImageUrl; // Optional group image URL
  final Map<String, dynamic>? groupSettings; // Group settings/permissions

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
    this.mutedByUsers = const [],
    this.isGroup = false,
    this.groupName,
    this.groupAdmin,
    this.groupImageUrl,
    this.groupSettings,
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

    // Parse muted by users
    final mutedByUsers = List<String>.from(data['mutedByUsers'] ?? []);

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
      mutedByUsers: mutedByUsers,
      isGroup: data['isGroup'] ?? false,
      groupName: data['groupName'],
      groupAdmin: data['groupAdmin'],
      groupImageUrl: data['groupImageUrl'],
      groupSettings: data['groupSettings'] != null
          ? Map<String, dynamic>.from(data['groupSettings'])
          : null,
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
      'mutedByUsers': mutedByUsers,
      'isGroup': isGroup,
      'groupName': groupName,
      'groupAdmin': groupAdmin,
      'groupImageUrl': groupImageUrl,
      'groupSettings': groupSettings,
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

  // Check if conversation is muted by a specific user
  bool isMutedByUser(String userId) {
    return mutedByUsers.contains(userId);
  }

  // Get display name for the conversation
  String getDisplayName(String currentUserId) {
    if (isGroup && groupName != null && groupName!.isNotEmpty) {
      return groupName!;
    }
    return getOtherParticipantName(currentUserId);
  }

  // Check if user is group admin
  bool isGroupAdmin(String userId) {
    return isGroup && groupAdmin == userId;
  }

  // Get participant count for display
  int get participantCount => participants.length;
}
