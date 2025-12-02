import 'package:flutter/material.dart';
import 'dart:async';
import '../services/chat_service.dart';
import '../models/conversation_model.dart';
import '../models/message_model.dart';

class ChatProvider extends ChangeNotifier {
  final ChatService _chatService = ChatService();

  // State variables
  List<ConversationModel> _conversations = [];
  List<MessageModel> _messages = [];
  String? _currentConversationId;
  bool _isLoadingConversations = false;
  bool _isLoadingMessages = false;
  String? _errorMessage;
  String _searchQuery = '';
  StreamSubscription<List<ConversationModel>>? _conversationsSubscription;
  StreamSubscription<List<MessageModel>>? _messagesSubscription;

  // Getters
  List<ConversationModel> get conversations => _conversations;
  List<MessageModel> get messages => _messages;
  String? get currentConversationId => _currentConversationId;
  bool get isLoadingConversations => _isLoadingConversations;
  bool get isLoadingMessages => _isLoadingMessages;
  String? get errorMessage => _errorMessage;

  // Get filtered conversations based on search query
  List<ConversationModel> getFilteredConversations(String userId) {
    if (_searchQuery.isEmpty) {
      return _conversations;
    }

    final lowerQuery = _searchQuery.toLowerCase();
    return _conversations.where((conversation) {
      final otherParticipantName = conversation.participantNames.values
          .join(' ')
          .toLowerCase();
      final lastMessage = conversation.lastMessage.toLowerCase();
      final itemTitle = conversation.itemTitle?.toLowerCase() ?? '';

      return otherParticipantName.contains(lowerQuery) ||
          lastMessage.contains(lowerQuery) ||
          itemTitle.contains(lowerQuery);
    }).toList();
  }

  // Load all conversations for user
  Future<void> loadConversations(String userId) async {
    try {
      _setLoadingConversations(true);
      _clearError();

      final conversations = await _chatService.getUserConversations(userId);
      _conversations = conversations;

      _setLoadingConversations(false);
      notifyListeners();
    } catch (e) {
      _setError(e.toString());
      _setLoadingConversations(false);
      notifyListeners();
    }
  }

  // Stream conversations for real-time updates
  void setupConversationsStream(String userId) {
    // Cancel any existing subscription to avoid duplicate listeners
    _conversationsSubscription?.cancel();
    _conversationsSubscription = _chatService
        .getUserConversationsStream(userId)
        .listen(
          (conversations) {
            _conversations = conversations;
            notifyListeners();
          },
          onError: (error) {
            _setError(error.toString());
            notifyListeners();
          },
        );
  }

  // Set current conversation and load messages
  Future<void> loadMessages(String conversationId) async {
    try {
      _currentConversationId = conversationId;
      _setLoadingMessages(true);
      _clearError();

      final messages = await _chatService.getConversationMessages(
        conversationId,
      );
      _messages = messages;

      _setLoadingMessages(false);
      notifyListeners();
    } catch (e) {
      _setError(e.toString());
      _setLoadingMessages(false);
      notifyListeners();
    }
  }

  // Stream messages for real-time updates
  void setupMessagesStream(String conversationId) {
    _currentConversationId = conversationId;
    _messagesSubscription?.cancel();
    _messagesSubscription = _chatService
        .getConversationMessagesStream(conversationId)
        .listen(
          (messages) {
            _messages = messages;
            notifyListeners();
          },
          onError: (error) {
            _setError(error.toString());
            notifyListeners();
          },
        );
  }

  // Send a message
  Future<bool> sendMessage({
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
      await _chatService.sendMessage(
        conversationId: conversationId,
        senderId: senderId,
        senderName: senderName,
        content: content,
        imageUrl: imageUrl,
        replyToMessageId: replyToMessageId,
        replyToContent: replyToContent,
        replyToSenderName: replyToSenderName,
      );

      // The stream will automatically update the messages
      return true;
    } catch (e) {
      _setError(e.toString());
      notifyListeners();
      return false;
    }
  }

  // Delete a message
  Future<bool> deleteMessage({
    required String conversationId,
    required String messageId,
    required String userId,
    required bool deleteForEveryone,
  }) async {
    try {
      await _chatService.deleteMessage(
        conversationId: conversationId,
        messageId: messageId,
        userId: userId,
        deleteForEveryone: deleteForEveryone,
      );

      // Remove from local list if deleted for everyone
      if (deleteForEveryone) {
        _messages.removeWhere((m) => m.messageId == messageId);
        notifyListeners();
      }

      return true;
    } catch (e) {
      _setError(e.toString());
      notifyListeners();
      return false;
    }
  }

  // Set typing status
  Future<void> setTypingStatus({
    required String conversationId,
    required String userId,
    required bool isTyping,
  }) async {
    try {
      await _chatService.setTypingStatus(
        conversationId: conversationId,
        userId: userId,
        isTyping: isTyping,
      );
    } catch (e) {
      // Silent fail for typing indicators
      print('Error setting typing status: $e');
    }
  }

  // Search messages in conversation
  Future<List<MessageModel>> searchMessages({
    required String conversationId,
    required String query,
  }) async {
    try {
      return await _chatService.searchMessagesInConversation(
        conversationId: conversationId,
        query: query,
      );
    } catch (e) {
      _setError(e.toString());
      notifyListeners();
      return [];
    }
  }

  // Create or get existing conversation
  Future<String?> createOrGetConversation({
    required String userId1,
    required String userId1Name,
    required String userId2,
    required String userId2Name,
    String? itemId,
    String? itemTitle,
  }) async {
    try {
      final conversationId = await _chatService.createOrGetConversation(
        userId1: userId1,
        userId1Name: userId1Name,
        userId2: userId2,
        userId2Name: userId2Name,
        itemId: itemId,
        itemTitle: itemTitle,
      );

      // Refresh conversations list
      await loadConversations(userId1);

      return conversationId;
    } catch (e) {
      _setError(e.toString());
      notifyListeners();
      return null;
    }
  }

  // Mark messages as read
  Future<void> markMessagesAsRead(String conversationId, String userId) async {
    try {
      await _chatService.markMessagesAsRead(conversationId, userId);

      // Immediately update local state for instant UI feedback
      final conversationIndex = _conversations.indexWhere(
        (c) => c.conversationId == conversationId,
      );
      if (conversationIndex != -1) {
        final conversation = _conversations[conversationIndex];
        // Create updated conversation with unread count reset
        final updatedUnreadCountByUser = Map<String, int>.from(
          conversation.unreadCountByUser,
        );
        updatedUnreadCountByUser[userId] = 0;

        final updatedConversation = ConversationModel(
          conversationId: conversation.conversationId,
          participants: conversation.participants,
          participantNames: conversation.participantNames,
          lastMessage: conversation.lastMessage,
          lastMessageTime: conversation.lastMessageTime,
          lastMessageSenderId: conversation.lastMessageSenderId,
          hasUnreadMessages: updatedUnreadCountByUser.values.any(
            (count) => count > 0,
          ),
          unreadCount: updatedUnreadCountByUser.values.fold(
            0,
            (sum, count) => sum + count,
          ),
          unreadCountByUser: updatedUnreadCountByUser,
          createdAt: conversation.createdAt,
          updatedAt: conversation.updatedAt,
          itemId: conversation.itemId,
          itemTitle: conversation.itemTitle,
        );

        _conversations[conversationIndex] = updatedConversation;
        notifyListeners(); // Immediate UI update
      }

      // Then reload from Firestore to ensure consistency
      await loadConversations(userId);
    } catch (e) {
      _setError(e.toString());
      notifyListeners();
    }
  }

  // Delete a conversation
  Future<bool> deleteConversation(String conversationId) async {
    try {
      await _chatService.deleteConversation(conversationId);

      // Remove from local list
      _conversations.removeWhere((c) => c.conversationId == conversationId);
      notifyListeners();

      return true;
    } catch (e) {
      _setError(e.toString());
      notifyListeners();
      return false;
    }
  }

  // Set search query
  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  // Helper methods
  void _setLoadingConversations(bool loading) {
    _isLoadingConversations = loading;
  }

  void _setLoadingMessages(bool loading) {
    _isLoadingMessages = loading;
  }

  void _setError(String error) {
    _errorMessage = error;
  }

  void _clearError() {
    _errorMessage = null;
  }

  void clearError() {
    _clearError();
    notifyListeners();
  }

  void clearMessages() {
    _messages = [];
    _currentConversationId = null;
    notifyListeners();
  }

  void clearConversations() {
    _conversations = [];
    notifyListeners();
  }

  // Get unread count for all conversations
  int getTotalUnreadCount(String userId) {
    return _conversations.fold(0, (sum, conversation) {
      return sum + conversation.getUnreadCountForUser(userId);
    });
  }

  // Mute a conversation
  Future<bool> muteConversation({
    required String conversationId,
    required String userId,
  }) async {
    try {
      await _chatService.muteConversation(
        conversationId: conversationId,
        userId: userId,
      );

      // Update local state
      final conversationIndex = _conversations.indexWhere(
        (c) => c.conversationId == conversationId,
      );
      if (conversationIndex != -1) {
        final conversation = _conversations[conversationIndex];
        final updatedMutedByUsers = List<String>.from(
          conversation.mutedByUsers,
        );
        if (!updatedMutedByUsers.contains(userId)) {
          updatedMutedByUsers.add(userId);
        }

        // Create updated conversation
        final updatedConversation = ConversationModel(
          conversationId: conversation.conversationId,
          participants: conversation.participants,
          participantNames: conversation.participantNames,
          lastMessage: conversation.lastMessage,
          lastMessageTime: conversation.lastMessageTime,
          lastMessageSenderId: conversation.lastMessageSenderId,
          hasUnreadMessages: conversation.hasUnreadMessages,
          unreadCount: conversation.unreadCount,
          unreadCountByUser: conversation.unreadCountByUser,
          createdAt: conversation.createdAt,
          updatedAt: conversation.updatedAt,
          itemId: conversation.itemId,
          itemTitle: conversation.itemTitle,
          mutedByUsers: updatedMutedByUsers,
        );

        _conversations[conversationIndex] = updatedConversation;
        notifyListeners();
      }

      return true;
    } catch (e) {
      _setError(e.toString());
      notifyListeners();
      return false;
    }
  }

  // Unmute a conversation
  Future<bool> unmuteConversation({
    required String conversationId,
    required String userId,
  }) async {
    try {
      await _chatService.unmuteConversation(
        conversationId: conversationId,
        userId: userId,
      );

      // Update local state
      final conversationIndex = _conversations.indexWhere(
        (c) => c.conversationId == conversationId,
      );
      if (conversationIndex != -1) {
        final conversation = _conversations[conversationIndex];
        final updatedMutedByUsers = List<String>.from(conversation.mutedByUsers)
          ..remove(userId);

        // Create updated conversation
        final updatedConversation = ConversationModel(
          conversationId: conversation.conversationId,
          participants: conversation.participants,
          participantNames: conversation.participantNames,
          lastMessage: conversation.lastMessage,
          lastMessageTime: conversation.lastMessageTime,
          lastMessageSenderId: conversation.lastMessageSenderId,
          hasUnreadMessages: conversation.hasUnreadMessages,
          unreadCount: conversation.unreadCount,
          unreadCountByUser: conversation.unreadCountByUser,
          createdAt: conversation.createdAt,
          updatedAt: conversation.updatedAt,
          itemId: conversation.itemId,
          itemTitle: conversation.itemTitle,
          mutedByUsers: updatedMutedByUsers,
        );

        _conversations[conversationIndex] = updatedConversation;
        notifyListeners();
      }

      return true;
    } catch (e) {
      _setError(e.toString());
      notifyListeners();
      return false;
    }
  }

  // Get conversation by ID
  Future<ConversationModel?> getConversation(String conversationId) async {
    try {
      return await _chatService.getConversation(conversationId);
    } catch (e) {
      _setError(e.toString());
      notifyListeners();
      return null;
    }
  }

  // Create a group conversation
  Future<String?> createGroupConversation({
    required String adminId,
    required String adminName,
    required List<String> participantIds,
    required Map<String, String> participantNames,
    required String groupName,
    String? groupImageUrl,
  }) async {
    try {
      final conversationId = await _chatService.createGroupConversation(
        adminId: adminId,
        adminName: adminName,
        participantIds: participantIds,
        participantNames: participantNames,
        groupName: groupName,
        groupImageUrl: groupImageUrl,
      );

      // Refresh conversations list
      await loadConversations(adminId);

      return conversationId;
    } catch (e) {
      _setError(e.toString());
      notifyListeners();
      return null;
    }
  }

  // Add participant to group
  Future<bool> addParticipantToGroup({
    required String conversationId,
    required String userId,
    required String userName,
    required String adminId,
  }) async {
    try {
      await _chatService.addParticipantToGroup(
        conversationId: conversationId,
        userId: userId,
        userName: userName,
        adminId: adminId,
      );

      // Refresh conversations
      await loadConversations(adminId);

      return true;
    } catch (e) {
      _setError(e.toString());
      notifyListeners();
      return false;
    }
  }

  // Remove participant from group
  Future<bool> removeParticipantFromGroup({
    required String conversationId,
    required String userId,
    required String adminId,
  }) async {
    try {
      await _chatService.removeParticipantFromGroup(
        conversationId: conversationId,
        userId: userId,
        adminId: adminId,
      );

      // Refresh conversations
      await loadConversations(adminId);

      return true;
    } catch (e) {
      _setError(e.toString());
      notifyListeners();
      return false;
    }
  }

  // Update group name
  Future<bool> updateGroupName({
    required String conversationId,
    required String newName,
    required String adminId,
  }) async {
    try {
      await _chatService.updateGroupName(
        conversationId: conversationId,
        newName: newName,
        adminId: adminId,
      );

      // Refresh conversations
      await loadConversations(adminId);

      return true;
    } catch (e) {
      _setError(e.toString());
      notifyListeners();
      return false;
    }
  }

  // Update group image
  Future<bool> updateGroupImage({
    required String conversationId,
    required String? imageUrl,
    required String adminId,
  }) async {
    try {
      await _chatService.updateGroupImage(
        conversationId: conversationId,
        imageUrl: imageUrl,
        adminId: adminId,
      );

      // Refresh conversations
      await loadConversations(adminId);

      return true;
    } catch (e) {
      _setError(e.toString());
      notifyListeners();
      return false;
    }
  }

  // Transfer group admin
  Future<bool> transferGroupAdmin({
    required String conversationId,
    required String newAdminId,
    required String currentAdminId,
  }) async {
    try {
      await _chatService.transferGroupAdmin(
        conversationId: conversationId,
        newAdminId: newAdminId,
        currentAdminId: currentAdminId,
      );

      // Refresh conversations
      await loadConversations(currentAdminId);

      return true;
    } catch (e) {
      _setError(e.toString());
      notifyListeners();
      return false;
    }
  }

  // Update group settings
  Future<bool> updateGroupSettings({
    required String conversationId,
    required Map<String, dynamic> settings,
    required String adminId,
  }) async {
    try {
      await _chatService.updateGroupSettings(
        conversationId: conversationId,
        settings: settings,
        adminId: adminId,
      );

      // Refresh conversations
      await loadConversations(adminId);

      return true;
    } catch (e) {
      _setError(e.toString());
      notifyListeners();
      return false;
    }
  }

  @override
  void dispose() {
    _conversationsSubscription?.cancel();
    _messagesSubscription?.cancel();
    super.dispose();
  }
}
