import 'package:cloud_firestore/cloud_firestore.dart';

enum MessageStatus { sent, delivered, read }

class MessageModel {
  final String messageId;
  final String conversationId;
  final String senderId;
  final String senderName;
  final String content;
  final DateTime timestamp;
  final MessageStatus status;
  final bool isRead;
  final DateTime? readAt;
  final String? imageUrl; // For future image messages
  final String? replyToMessageId; // ID of message being replied to
  final String? replyToContent; // Content of replied message (for display)
  final String? replyToSenderName; // Sender name of replied message
  final bool isDeleted; // Whether message is deleted
  final bool deletedForEveryone; // Whether deleted for everyone or just sender

  MessageModel({
    required this.messageId,
    required this.conversationId,
    required this.senderId,
    required this.senderName,
    required this.content,
    required this.timestamp,
    required this.status,
    required this.isRead,
    this.readAt,
    this.imageUrl,
    this.replyToMessageId,
    this.replyToContent,
    this.replyToSenderName,
    this.isDeleted = false,
    this.deletedForEveryone = false,
  });

  factory MessageModel.fromMap(Map<String, dynamic> data, String documentId) {
    // Parse status from string
    MessageStatus messageStatus = MessageStatus.sent;
    final statusString = (data['status'] ?? 'sent').toString().toLowerCase();

    switch (statusString) {
      case 'sent':
        messageStatus = MessageStatus.sent;
        break;
      case 'delivered':
        messageStatus = MessageStatus.delivered;
        break;
      case 'read':
        messageStatus = MessageStatus.read;
        break;
    }

    return MessageModel(
      messageId: documentId,
      conversationId: data['conversationId'] ?? '',
      senderId: data['senderId'] ?? '',
      senderName: data['senderName'] ?? '',
      content: data['content'] ?? '',
      timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      status: messageStatus,
      isRead: data['isRead'] ?? false,
      readAt: (data['readAt'] as Timestamp?)?.toDate(),
      imageUrl: data['imageUrl'],
      replyToMessageId: data['replyToMessageId'],
      replyToContent: data['replyToContent'],
      replyToSenderName: data['replyToSenderName'],
      isDeleted: data['isDeleted'] ?? false,
      deletedForEveryone: data['deletedForEveryone'] ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'conversationId': conversationId,
      'senderId': senderId,
      'senderName': senderName,
      'content': content,
      'timestamp': Timestamp.fromDate(timestamp),
      'status': status.name.toLowerCase(),
      'isRead': isRead,
      'readAt': readAt != null ? Timestamp.fromDate(readAt!) : null,
      'imageUrl': imageUrl,
      'replyToMessageId': replyToMessageId,
      'replyToContent': replyToContent,
      'replyToSenderName': replyToSenderName,
      'isDeleted': isDeleted,
      'deletedForEveryone': deletedForEveryone,
    };
  }

  String get statusDisplay {
    switch (status) {
      case MessageStatus.sent:
        return 'Sent';
      case MessageStatus.delivered:
        return 'Delivered';
      case MessageStatus.read:
        return 'Read';
    }
  }

  // Check if message was sent by a specific user
  bool isSentBy(String userId) => senderId == userId;

  // Check if message is new (unread and recent)
  bool get isNew =>
      !isRead && DateTime.now().difference(timestamp).inHours < 24;
}
