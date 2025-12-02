import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'dart:async';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../providers/chat_provider.dart';
import '../providers/user_provider.dart';
import '../models/message_model.dart';
import '../models/conversation_model.dart';
import '../services/presence_service.dart';
import '../services/firestore_service.dart';
import '../services/report_block_service.dart';
import '../services/storage_service.dart';
import '../services/chat_service.dart';
import '../reusable_widgets/offline_banner_widget.dart';
import '../providers/connectivity_provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'user_public_profile_screen.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_theme_provider.dart';
import 'chat/conversation_info_screen.dart';

class ChatDetailScreen extends StatefulWidget {
  final String conversationId;
  final String otherParticipantName;
  final String userId;

  const ChatDetailScreen({
    super.key,
    required this.conversationId,
    required this.otherParticipantName,
    required this.userId,
  });

  @override
  State<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<ChatDetailScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final PresenceService _presenceService = PresenceService();
  final FirestoreService _firestoreService = FirestoreService();
  final ReportBlockService _reportBlockService = ReportBlockService();
  final StorageService _storageService = StorageService();
  final ImagePicker _imagePicker = ImagePicker();
  final ChatService _chatService = ChatService();
  StreamSubscription<DateTime?>? _presenceSubscription;
  StreamSubscription<Map<String, bool>>? _typingSubscription;
  DateTime? _otherUserLastSeen;
  String? _otherParticipantId;
  bool _isUserBlocked = false;
  bool _isUploadingImage = false;
  bool _isOtherUserTyping = false;
  bool _isMuted = false;
  Timer? _typingTimer;
  MessageModel? _replyingToMessage;
  bool _isSearchMode = false;
  String _searchQuery = '';
  List<MessageModel> _searchResults = [];
  int _currentSearchIndex = -1;
  ConversationModel? _conversation;
  bool _isGroup = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final chatProvider = Provider.of<ChatProvider>(context, listen: false);

      // Setup real-time stream for messages
      chatProvider.setupMessagesStream(widget.conversationId);

      // Mark messages as read
      chatProvider.markMessagesAsRead(widget.conversationId, widget.userId);

      // Get conversation to find other participant ID
      _loadConversationAndSetupPresence(chatProvider);

      // Check if user is blocked
      _checkIfBlocked();

      // Load mute status
      _loadMuteStatus(chatProvider);
    });
  }

  Future<void> _loadMuteStatus(ChatProvider chatProvider) async {
    try {
      final conversation = await chatProvider.getConversation(
        widget.conversationId,
      );
      if (conversation != null && mounted) {
        setState(() {
          _isMuted = conversation.isMutedByUser(widget.userId);
        });
      }
    } catch (e) {
      debugPrint('Error loading mute status: $e');
    }
  }

  void _setupTypingIndicator(ChatProvider chatProvider) {
    if (_otherParticipantId == null) return;

    _typingSubscription?.cancel();
    _typingSubscription = _chatService
        .getTypingStatusStream(widget.conversationId)
        .listen((typingStatus) {
          if (mounted) {
            setState(() {
              _isOtherUserTyping = typingStatus[_otherParticipantId] ?? false;
            });
          }
        });
  }

  Future<void> _checkIfBlocked() async {
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      if (authProvider.user == null || _otherParticipantId == null) return;

      final isBlocked = await _reportBlockService.isUserBlocked(
        userId: authProvider.user!.uid,
        otherUserId: _otherParticipantId!,
      );

      if (mounted) {
        setState(() {
          _isUserBlocked = isBlocked;
        });
      }
    } catch (e) {
      // Silent fail
    }
  }

  Future<void> _loadConversationAndSetupPresence(
    ChatProvider chatProvider,
  ) async {
    try {
      // Load conversations first if not already loaded
      if (chatProvider.conversations.isEmpty) {
        await chatProvider.loadConversations(widget.userId);
      }

      // Find the conversation to get other participant ID
      ConversationModel? conversation;
      try {
        conversation = chatProvider.conversations.firstWhere(
          (c) => c.conversationId == widget.conversationId,
        );
      } catch (e) {
        // Conversation not found, try to get from Firestore directly
        try {
          final conversationDoc = await FirebaseFirestore.instance
              .collection('conversations')
              .doc(widget.conversationId)
              .get();

          if (conversationDoc.exists && conversationDoc.data() != null) {
            conversation = ConversationModel.fromMap(
              conversationDoc.data()!,
              conversationDoc.id,
            );
          }
        } catch (e2) {
          print('Error fetching conversation from Firestore: $e2');
        }
      }

      if (conversation != null) {
        // Store conversation and check if it's a group
        _conversation = conversation;

        // Get other participant ID
        _otherParticipantId = conversation.getOtherParticipant(widget.userId);

        // Update mute status and group status
        if (mounted) {
          setState(() {
            _isMuted = conversation!.isMutedByUser(widget.userId);
            _isGroup = conversation.isGroup;
          });
        }

        if (_otherParticipantId != null && _otherParticipantId!.isNotEmpty) {
          // Check if blocked
          final authProvider = Provider.of<AuthProvider>(
            context,
            listen: false,
          );
          if (authProvider.user != null) {
            final isBlocked = await _reportBlockService.isUserBlocked(
              userId: authProvider.user!.uid,
              otherUserId: _otherParticipantId!,
            );
            if (mounted) {
              setState(() {
                _isUserBlocked = isBlocked;
              });
            }
          }

          // Listen to other user's presence status
          _presenceSubscription = _firestoreService
              .getUserLastSeenStream(_otherParticipantId!)
              .listen((lastSeen) {
                if (mounted) {
                  setState(() {
                    _otherUserLastSeen = lastSeen;
                  });
                }
              });

          // Setup typing indicator now that we have the participant ID
          _setupTypingIndicator(chatProvider);
        }
      }
    } catch (e) {
      print('Error loading conversation for presence: $e');
    }
  }

  @override
  void dispose() {
    _presenceSubscription?.cancel();
    _typingSubscription?.cancel();
    _typingTimer?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      });
    }
  }

  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty && _replyingToMessage == null) {
      return;
    }

    // Check if user is blocked
    if (_isUserBlocked) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You cannot send messages to a blocked user'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    // Allow sending even if profile hasn't loaded yet; fall back to auth email or a generic name
    String senderName =
        userProvider.currentUser?.fullName.trim().isNotEmpty == true
        ? userProvider.currentUser!.fullName
        : (firebase_auth.FirebaseAuth.instance.currentUser?.email ?? 'User');

    final content = _messageController.text.trim();
    final replyingTo = _replyingToMessage;
    _messageController.clear();
    setState(() {
      _replyingToMessage = null;
    });

    // Stop typing indicator
    await chatProvider.setTypingStatus(
      conversationId: widget.conversationId,
      userId: widget.userId,
      isTyping: false,
    );

    final success = await chatProvider.sendMessage(
      conversationId: widget.conversationId,
      senderId: widget.userId,
      senderName: senderName,
      content: content,
      replyToMessageId: replyingTo?.messageId,
      replyToContent: replyingTo?.content,
      replyToSenderName: replyingTo?.senderName,
    );

    if (success) {
      _scrollToBottom();
    } else {
      // Show error
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to send message'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _onTextChanged(String text) {
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);

    // Cancel existing timer
    _typingTimer?.cancel();

    // Set typing indicator
    if (text.isNotEmpty) {
      chatProvider.setTypingStatus(
        conversationId: widget.conversationId,
        userId: widget.userId,
        isTyping: true,
      );

      // Auto-stop typing after 3 seconds of no typing
      _typingTimer = Timer(const Duration(seconds: 3), () {
        chatProvider.setTypingStatus(
          conversationId: widget.conversationId,
          userId: widget.userId,
          isTyping: false,
        );
      });
    } else {
      chatProvider.setTypingStatus(
        conversationId: widget.conversationId,
        userId: widget.userId,
        isTyping: false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final chatProvider = Provider.of<ChatProvider>(context);
    final chatThemeProvider = Provider.of<ChatThemeProvider>(context);
    final themeData = chatThemeProvider.getThemeData(widget.conversationId);

    return PopScope(
      onPopInvoked: (didPop) async {
        if (didPop) {
          // Mark messages as read before leaving
          final chatProvider = Provider.of<ChatProvider>(
            context,
            listen: false,
          );
          await chatProvider.markMessagesAsRead(
            widget.conversationId,
            widget.userId,
          );
          // Explicitly reload conversations to ensure badge updates
          await chatProvider.loadConversations(widget.userId);
        }
      },
      child: Scaffold(
        backgroundColor: themeData.backgroundColor,
        appBar: AppBar(
          backgroundColor: themeData.primaryColor,
          elevation: 0,
          automaticallyImplyLeading: true,
          title: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: Colors.white.withOpacity(0.2),
                child: Text(
                  widget.otherParticipantName.isNotEmpty
                      ? widget.otherParticipantName[0].toUpperCase()
                      : 'U',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Only make title clickable for 1-on-1 chats, not groups
                    _isGroup
                        ? Text(
                            widget.otherParticipantName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          )
                        : InkWell(
                            onTap: () {
                              if (_otherParticipantId != null &&
                                  _otherParticipantId!.isNotEmpty) {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => UserPublicProfileScreen(
                                      userId: _otherParticipantId!,
                                    ),
                                  ),
                                );
                              }
                            },
                            child: Text(
                              widget.otherParticipantName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                decoration: TextDecoration.underline,
                                decorationColor: Colors.white70,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                    // Only show online status for 1-on-1 chats, not groups
                    if (!_isGroup)
                      StreamBuilder<DateTime?>(
                        stream: _otherParticipantId != null
                            ? _firestoreService.getUserLastSeenStream(
                                _otherParticipantId!,
                              )
                            : Stream.value(null),
                        builder: (context, snapshot) {
                          final lastSeen = snapshot.data ?? _otherUserLastSeen;
                          final isOnline = _presenceService.isUserOnline(
                            lastSeen,
                          );
                          final statusText = _presenceService.getStatusText(
                            lastSeen,
                          );

                          return Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                margin: const EdgeInsets.only(right: 6),
                                decoration: BoxDecoration(
                                  color: isOnline ? Colors.green : Colors.grey,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              Text(
                                statusText,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              icon: Icon(
                _isSearchMode ? Icons.close : Icons.search,
                color: Colors.white,
              ),
              onPressed: () {
                setState(() {
                  _isSearchMode = !_isSearchMode;
                  if (!_isSearchMode) {
                    _searchQuery = '';
                    _searchResults = [];
                    _currentSearchIndex = -1;
                  }
                });
              },
            ),
            IconButton(
              icon: const Icon(Icons.more_vert, color: Colors.white),
              onPressed: () {
                // Show options menu
                _showOptionsMenu();
              },
            ),
          ],
        ),
        body: Column(
          children: [
            // Offline Banner
            const OfflineBannerWidget(),
            // Search Bar (when in search mode)
            if (_isSearchMode) _buildSearchBar(),
            // Messages List
            Expanded(
              child:
                  chatProvider.isLoadingMessages &&
                      chatProvider.messages.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : _buildMessagesList(chatProvider, themeData),
            ),
            // Typing Indicator
            if (_isOtherUserTyping && !_isSearchMode)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Colors.grey[600]!,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${widget.otherParticipantName} is typing...',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 14,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
            // Reply Preview
            if (_replyingToMessage != null && !_isSearchMode)
              _buildReplyPreview(),
            // Message Input Bar
            _buildMessageInputBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildMessagesList(
    ChatProvider chatProvider,
    ChatThemeData themeData,
  ) {
    // Show search results if in search mode
    if (_isSearchMode) {
      if (_searchQuery.isEmpty) {
        return const Center(
          child: Text(
            'Type to search messages...',
            style: TextStyle(color: Colors.grey),
          ),
        );
      }

      if (_searchResults.isEmpty) {
        return const Center(
          child: Text(
            'No messages found',
            style: TextStyle(color: Colors.grey),
          ),
        );
      }

      return ListView.builder(
        controller: _scrollController,
        reverse: false,
        padding: const EdgeInsets.all(16),
        itemCount: _searchResults.length,
        itemBuilder: (context, index) {
          final message = _searchResults[index];
          final isMe = message.senderId == widget.userId;
          final isHighlighted = index == _currentSearchIndex;

          return Container(
            decoration: isHighlighted
                ? BoxDecoration(
                    color: Colors.yellow.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(8),
                  )
                : null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildMessageBubble(message, isMe, themeData),
                const SizedBox(height: 4),
              ],
            ),
          );
        },
      );
    }

    // Normal messages list
    if (chatProvider.messages.isEmpty) {
      return const Center(
        child: Text(
          'No messages yet. Start the conversation!',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    // Auto-scroll to bottom when messages update
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollToBottom();
      }
    });

    return ListView.builder(
      controller: _scrollController,
      reverse: false,
      padding: const EdgeInsets.all(16),
      itemCount: chatProvider.messages.length,
      itemBuilder: (context, index) {
        final message = chatProvider.messages[index];
        final isMe = message.senderId == widget.userId;

        // Check if this is a different day than previous message
        final previousMessage = index > 0
            ? chatProvider.messages[index - 1]
            : null;
        final showDateHeader =
            previousMessage == null ||
            _isDifferentDay(message.timestamp, previousMessage.timestamp);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showDateHeader) ...[
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _formatDate(message.timestamp),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ],
            _buildMessageBubble(message, isMe, themeData),
            const SizedBox(height: 4),
          ],
        );
      },
    );
  }

  Widget _buildMessageBubble(
    MessageModel message,
    bool isMe,
    ChatThemeData themeData,
  ) {
    // Skip deleted messages (for everyone)
    if (message.isDeleted && message.deletedForEveryone) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Center(
          child: Text(
            'This message was deleted',
            style: TextStyle(
              color: Colors.grey[500],
              fontSize: 12,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      );
    }

    return GestureDetector(
      onLongPress: () => _showMessageOptions(message, isMe),
      child: Row(
        mainAxisAlignment: isMe
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[
            CircleAvatar(
              radius: 14,
              backgroundColor: Colors.grey[300],
              child: Text(
                message.senderName.isNotEmpty
                    ? message.senderName[0].toUpperCase()
                    : 'U',
                style: TextStyle(
                  color: Colors.grey[700],
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          // Show sender name in group chats
          if (_isGroup && !isMe)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                message.senderName,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isMe ? Colors.white70 : themeData.primaryColor,
                ),
              ),
            ),
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.7,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: isMe
                  ? themeData.messageBubbleColor
                  : themeData.otherMessageBubbleColor,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(20),
                topRight: const Radius.circular(20),
                bottomLeft: isMe
                    ? const Radius.circular(20)
                    : const Radius.circular(4),
                bottomRight: isMe
                    ? const Radius.circular(4)
                    : const Radius.circular(20),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Reply preview
                if (message.replyToMessageId != null &&
                    message.replyToContent != null) ...[
                  Container(
                    padding: const EdgeInsets.all(8),
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: (isMe ? Colors.white : Colors.grey[200])
                          ?.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(8),
                      border: Border(
                        left: BorderSide(
                          color: isMe ? Colors.white70 : themeData.primaryColor,
                          width: 3,
                        ),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          message.replyToSenderName ?? 'Unknown',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isMe
                                ? Colors.white70
                                : themeData.primaryColor,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          message.replyToContent!,
                          style: TextStyle(
                            fontSize: 12,
                            color: isMe ? Colors.white70 : Colors.grey[700],
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
                if (!isMe)
                  GestureDetector(
                    onTap: () {
                      if (!isMe &&
                          _otherParticipantId != null &&
                          _otherParticipantId!.isNotEmpty) {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => UserPublicProfileScreen(
                              userId: _otherParticipantId!,
                            ),
                          ),
                        );
                      }
                    },
                    child: Text(
                      message.senderName,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: isMe ? Colors.white70 : themeData.primaryColor,
                        decoration: TextDecoration.underline,
                        decorationColor: isMe
                            ? Colors.white70
                            : themeData.primaryColor,
                      ),
                    ),
                  ),
                if (!isMe) const SizedBox(height: 4),
                if (message.imageUrl != null &&
                    message.imageUrl!.isNotEmpty) ...[
                  GestureDetector(
                    onTap: () => _openImageViewer(
                      message.imageUrl!,
                      message.senderName,
                      message.messageId,
                    ),
                    child: Hero(
                      tag: 'image_${message.messageId}_${message.imageUrl!}',
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.6,
                            maxHeight: 220,
                          ),
                          color: Colors.grey[200],
                          child: CachedNetworkImage(
                            imageUrl: message.imageUrl!,
                            fit: BoxFit.cover,
                            placeholder: (context, url) => const SizedBox(
                              height: 160,
                              child: Center(child: CircularProgressIndicator()),
                            ),
                            errorWidget: (context, url, error) => SizedBox(
                              height: 160,
                              child: Center(
                                child: Icon(
                                  Icons.broken_image_outlined,
                                  color: Colors.grey[500],
                                  size: 40,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                Text(
                  message.content,
                  style: TextStyle(
                    fontSize: 15,
                    color: isMe ? Colors.white : Colors.black87,
                    height: 1.4,
                  ),
                  softWrap: true,
                  overflow: TextOverflow.visible,
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _formatTime(message.timestamp),
                      style: TextStyle(
                        fontSize: 11,
                        color: isMe ? Colors.white70 : Colors.grey[600],
                      ),
                    ),
                    if (isMe) ...[
                      const SizedBox(width: 4),
                      Icon(
                        message.isRead ? Icons.done_all : Icons.done,
                        size: 14,
                        color: message.isRead
                            ? Colors.blue[200]
                            : Colors.white70,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          if (isMe) ...[
            const SizedBox(width: 8),
            CircleAvatar(
              radius: 14,
              backgroundColor: themeData.primaryColor.withOpacity(0.1),
              child: Icon(
                Icons.person,
                size: 16,
                color: themeData.primaryColor,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMessageInputBar() {
    return Consumer2<ConnectivityProvider, ChatThemeProvider>(
      builder: (context, connectivityProvider, chatThemeProvider, child) {
        final isOnline = connectivityProvider.isOnline;
        final themeData = chatThemeProvider.getThemeData(widget.conversationId);

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: SafeArea(
            child: Row(
              children: [
                IconButton(
                  icon: _isUploadingImage
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.attach_file),
                  color: Colors.grey[600],
                  onPressed: (isOnline && !_isUploadingImage)
                      ? _showAttachmentOptions
                      : null,
                ),
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    enabled: isOnline,
                    decoration: InputDecoration(
                      hintText: isOnline
                          ? 'Type a message...'
                          : 'Offline - no internet connection',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: isOnline ? Colors.grey[100] : Colors.grey[200],
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                    ),
                    textCapitalization: TextCapitalization.sentences,
                    maxLines: null,
                    onSubmitted: isOnline ? (_) => _sendMessage() : null,
                    onChanged: isOnline ? _onTextChanged : null,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  decoration: BoxDecoration(
                    color: isOnline ? themeData.primaryColor : Colors.grey,
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.send, color: Colors.white),
                    onPressed: isOnline ? _sendMessage : null,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showOptionsMenu() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.palette),
              title: const Text('Chat Theme'),
              onTap: () {
                Navigator.pop(context);
                _showThemeSelector();
              },
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Conversation Info'),
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => ConversationInfoScreen(
                      conversationId: widget.conversationId,
                      userId: widget.userId,
                      otherParticipantName: widget.otherParticipantName,
                    ),
                  ),
                );
              },
            ),
            ListTile(
              leading: Icon(
                _isMuted ? Icons.notifications_off : Icons.notifications,
              ),
              title: Text(
                _isMuted ? 'Unmute Notifications' : 'Mute Notifications',
              ),
              subtitle: Text(
                _isMuted
                    ? 'Tap to receive notifications'
                    : 'You won\'t receive notifications',
              ),
              onTap: () {
                Navigator.pop(context);
                _toggleMute();
              },
            ),
            ListTile(
              leading: Icon(
                _isUserBlocked ? Icons.check_circle : Icons.block,
                color: Colors.red,
              ),
              title: Text(_isUserBlocked ? 'Unblock User' : 'Block User'),
              textColor: Colors.red,
              onTap: () {
                Navigator.pop(context);
                if (_isUserBlocked) {
                  _unblockUser();
                } else {
                  _blockUser();
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.flag_outlined, color: Colors.orange),
              title: const Text('Report User'),
              textColor: Colors.orange,
              onTap: () {
                Navigator.pop(context);
                _reportUser();
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Delete Conversation'),
              textColor: Colors.red,
              onTap: () {
                Navigator.pop(context);
                _deleteConversation();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _blockUser() {
    if (_otherParticipantId == null) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Block User'),
        content: Text(
          'Are you sure you want to block ${widget.otherParticipantName}? You will not be able to send or receive messages from this user.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context); // Close dialog

              final authProvider = Provider.of<AuthProvider>(
                context,
                listen: false,
              );
              if (authProvider.user == null || _otherParticipantId == null)
                return;

              try {
                await _reportBlockService.blockUser(
                  userId: authProvider.user!.uid,
                  blockedUserId: _otherParticipantId!,
                  blockedUserName: widget.otherParticipantName,
                );

                if (mounted) {
                  setState(() {
                    _isUserBlocked = true;
                  });

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        '${widget.otherParticipantName} has been blocked',
                      ),
                      backgroundColor: Colors.green,
                    ),
                  );

                  // Go back to chat list
                  Navigator.pop(context);
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error blocking user: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: const Text('Block', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _unblockUser() {
    if (_otherParticipantId == null) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unblock User'),
        content: Text(
          'Are you sure you want to unblock ${widget.otherParticipantName}? You will be able to send and receive messages again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context); // Close dialog

              final authProvider = Provider.of<AuthProvider>(
                context,
                listen: false,
              );
              if (authProvider.user == null || _otherParticipantId == null)
                return;

              try {
                await _reportBlockService.unblockUser(
                  userId: authProvider.user!.uid,
                  blockedUserId: _otherParticipantId!,
                );

                if (mounted) {
                  setState(() {
                    _isUserBlocked = false;
                  });

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        '${widget.otherParticipantName} has been unblocked',
                      ),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error unblocking user: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: const Text('Unblock', style: TextStyle(color: Colors.green)),
          ),
        ],
      ),
    );
  }

  void _reportUser() {
    if (_otherParticipantId == null) return;

    String selectedReason = 'spam';
    final TextEditingController descriptionController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Report User'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Please select a reason for reporting:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                RadioListTile<String>(
                  title: const Text('Spam'),
                  value: 'spam',
                  groupValue: selectedReason,
                  onChanged: (value) {
                    setDialogState(() {
                      selectedReason = value!;
                    });
                  },
                ),
                RadioListTile<String>(
                  title: const Text('Harassment'),
                  value: 'harassment',
                  groupValue: selectedReason,
                  onChanged: (value) {
                    setDialogState(() {
                      selectedReason = value!;
                    });
                  },
                ),
                RadioListTile<String>(
                  title: const Text('Inappropriate Content'),
                  value: 'inappropriate_content',
                  groupValue: selectedReason,
                  onChanged: (value) {
                    setDialogState(() {
                      selectedReason = value!;
                    });
                  },
                ),
                RadioListTile<String>(
                  title: const Text('Fraud'),
                  value: 'fraud',
                  groupValue: selectedReason,
                  onChanged: (value) {
                    setDialogState(() {
                      selectedReason = value!;
                    });
                  },
                ),
                RadioListTile<String>(
                  title: const Text('Other'),
                  value: 'other',
                  groupValue: selectedReason,
                  onChanged: (value) {
                    setDialogState(() {
                      selectedReason = value!;
                    });
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Additional details (optional)',
                    hintText: 'Please provide more information...',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                // Store parent context before closing dialog
                final parentContext = context;
                Navigator.pop(parentContext);

                final authProvider = Provider.of<AuthProvider>(
                  parentContext,
                  listen: false,
                );
                final userProvider = Provider.of<UserProvider>(
                  parentContext,
                  listen: false,
                );

                if (authProvider.user == null || _otherParticipantId == null)
                  return;

                final reporterName =
                    userProvider.currentUser?.fullName ??
                    authProvider.user!.email ??
                    'Unknown';

                try {
                  await _reportBlockService.reportUser(
                    reporterId: authProvider.user!.uid,
                    reporterName: reporterName,
                    reportedUserId: _otherParticipantId!,
                    reportedUserName: widget.otherParticipantName,
                    reason: selectedReason,
                    description: descriptionController.text.trim().isNotEmpty
                        ? descriptionController.text.trim()
                        : null,
                    contextType: 'chat',
                    contextId: widget.conversationId,
                  );

                  if (mounted) {
                    ScaffoldMessenger.of(parentContext).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'User has been reported successfully. Thank you for keeping the community safe.',
                        ),
                        backgroundColor: Colors.green,
                        duration: Duration(seconds: 3),
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(parentContext).showSnackBar(
                      SnackBar(
                        content: Text('Error reporting user: $e'),
                        backgroundColor: Colors.red,
                        duration: const Duration(seconds: 3),
                      ),
                    );
                  }
                }
              },
              child: const Text(
                'Report',
                style: TextStyle(color: Colors.orange),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _deleteConversation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Conversation'),
        content: const Text(
          'Are you sure you want to delete this conversation? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context); // Close dialog
              final chatProvider = Provider.of<ChatProvider>(
                context,
                listen: false,
              );

              final success = await chatProvider.deleteConversation(
                widget.conversationId,
              );

              if (success && mounted) {
                Navigator.pop(context); // Go back to chat list
              }
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  bool _isDifferentDay(DateTime date1, DateTime date2) {
    return date1.year != date2.year ||
        date1.month != date2.month ||
        date1.day != date2.day;
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      return 'Today';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }

  String _formatTime(DateTime dateTime) {
    return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _showAttachmentOptions() async {
    if (_isUserBlocked) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You cannot send attachments to a blocked user'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose from Gallery'),
              onTap: () {
                Navigator.pop(context);
                _pickAndSendImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Take Photo'),
              onTap: () {
                Navigator.pop(context);
                _pickAndSendImage(ImageSource.camera);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickAndSendImage(ImageSource source) async {
    try {
      final pickedImage = await _imagePicker.pickImage(source: source);
      if (pickedImage == null) return;

      setState(() => _isUploadingImage = true);

      // Upload image to Firebase Storage
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final imageId = 'chat_${widget.conversationId}_$timestamp';
      String imageUrl;

      try {
        // Get userId for organized storage
        final userId = widget.userId;

        if (kIsWeb) {
          // Web platform
          final bytes = await pickedImage.readAsBytes();
          imageUrl = await _storageService.uploadItemImageBytes(
            bytes: bytes,
            itemId: imageId,
            userId: userId,
            listingType: 'chat', // Chat images go to listings/chat/
          );
        } else {
          // Mobile platform
          imageUrl = await _storageService.uploadItemImage(
            file: File(pickedImage.path),
            itemId: imageId,
            userId: userId,
            listingType: 'chat', // Chat images go to listings/chat/
          );
        }
      } catch (e) {
        if (mounted) {
          setState(() => _isUploadingImage = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to upload image: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      if (!mounted) {
        return;
      }

      // Send message with image
      final chatProvider = Provider.of<ChatProvider>(context, listen: false);
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      String senderName =
          userProvider.currentUser?.fullName.trim().isNotEmpty == true
          ? userProvider.currentUser!.fullName
          : (firebase_auth.FirebaseAuth.instance.currentUser?.email ?? 'User');

      final success = await chatProvider.sendMessage(
        conversationId: widget.conversationId,
        senderId: widget.userId,
        senderName: senderName,
        content: _messageController.text.trim().isEmpty
            ? '📷 Image'
            : _messageController.text.trim(),
        imageUrl: imageUrl,
      );

      if (mounted) {
        setState(() => _isUploadingImage = false);
        _messageController.clear();
        if (success) {
          _scrollToBottom();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to send image'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isUploadingImage = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _openImageViewer(String url, String? title, String messageId) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black87,
        pageBuilder: (_, __, ___) {
          return GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Scaffold(
              backgroundColor: Colors.black,
              appBar: AppBar(
                backgroundColor: Colors.transparent,
                elevation: 0,
                iconTheme: const IconThemeData(color: Colors.white),
                title: Text(
                  title ?? '',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
              body: Center(
                child: Hero(
                  tag: 'image_${messageId}_$url',
                  child: InteractiveViewer(
                    minScale: 0.5,
                    maxScale: 4.0,
                    child: CachedNetworkImage(
                      imageUrl: url,
                      fit: BoxFit.contain,
                      placeholder: (context, u) => const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      ),
                      errorWidget: (context, u, error) => Column(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(
                            Icons.broken_image_outlined,
                            color: Colors.white70,
                            size: 48,
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Failed to load image',
                            style: TextStyle(color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      child: Column(
        children: [
          TextField(
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'Search messages...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        setState(() {
                          _searchQuery = '';
                          _searchResults = [];
                          _currentSearchIndex = -1;
                        });
                      },
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              filled: true,
              fillColor: Colors.grey[100],
            ),
            onChanged: (value) async {
              setState(() {
                _searchQuery = value;
              });

              if (value.trim().isNotEmpty) {
                final chatProvider = Provider.of<ChatProvider>(
                  context,
                  listen: false,
                );
                final results = await chatProvider.searchMessages(
                  conversationId: widget.conversationId,
                  query: value.trim(),
                );
                setState(() {
                  _searchResults = results;
                  _currentSearchIndex = results.isNotEmpty ? 0 : -1;
                });
              } else {
                setState(() {
                  _searchResults = [];
                  _currentSearchIndex = -1;
                });
              }
            },
          ),
          if (_searchResults.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${_searchResults.length} result${_searchResults.length == 1 ? '' : 's'}',
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
                if (_searchResults.length > 1)
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_upward, size: 20),
                        onPressed: _currentSearchIndex > 0
                            ? () {
                                setState(() {
                                  _currentSearchIndex--;
                                });
                                _scrollToMessage(
                                  _searchResults[_currentSearchIndex],
                                );
                              }
                            : null,
                      ),
                      Text(
                        _currentSearchIndex >= 0
                            ? '${_currentSearchIndex + 1}/${_searchResults.length}'
                            : '0/${_searchResults.length}',
                        style: TextStyle(color: Colors.grey[600], fontSize: 12),
                      ),
                      IconButton(
                        icon: const Icon(Icons.arrow_downward, size: 20),
                        onPressed:
                            _currentSearchIndex >= 0 &&
                                _currentSearchIndex < _searchResults.length - 1
                            ? () {
                                setState(() {
                                  _currentSearchIndex++;
                                });
                                _scrollToMessage(
                                  _searchResults[_currentSearchIndex],
                                );
                              }
                            : null,
                      ),
                    ],
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildReplyPreview() {
    if (_replyingToMessage == null) return const SizedBox.shrink();

    return Consumer<ChatThemeProvider>(
      builder: (context, chatThemeProvider, _) {
        final themeData = chatThemeProvider.getThemeData(widget.conversationId);

        return Container(
          padding: const EdgeInsets.all(12),
          color: Colors.grey[200],
          child: Row(
            children: [
              Container(
                width: 4,
                height: 40,
                decoration: BoxDecoration(
                  color: themeData.primaryColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Replying to ${_replyingToMessage!.senderName}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: themeData.primaryColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _replyingToMessage!.content,
                      style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                onPressed: () {
                  setState(() {
                    _replyingToMessage = null;
                  });
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _copyMessageToClipboard(MessageModel message) async {
    try {
      String textToCopy = '';

      // If message is a reply, include the reply context
      if (message.replyToContent != null &&
          message.replyToContent!.isNotEmpty) {
        final replyContext = message.replyToSenderName != null
            ? '${message.replyToSenderName}: ${message.replyToContent}'
            : message.replyToContent!;
        textToCopy = 'Replying to: $replyContext\n\n';
      }

      // Add the main message content
      if (message.content.isNotEmpty) {
        textToCopy += message.content;
      }

      // If message has an image, add image URL or indicator
      if (message.imageUrl != null && message.imageUrl!.isNotEmpty) {
        if (textToCopy.isNotEmpty) {
          textToCopy += '\n\n';
        }
        // Include image URL so users can access it
        textToCopy += '📷 Image: ${message.imageUrl}';
      }

      // If message is deleted, don't copy anything
      if (message.isDeleted && message.deletedForEveryone) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Cannot copy deleted message'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 2),
            ),
          );
        }
        return;
      }

      // If there's nothing to copy (empty message with no image)
      if (textToCopy.trim().isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Nothing to copy'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 2),
            ),
          );
        }
        return;
      }

      // Copy to clipboard
      await Clipboard.setData(ClipboardData(text: textToCopy.trim()));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                const Expanded(child: Text('Message copied to clipboard')),
              ],
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to copy: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  void _showMessageOptions(MessageModel message, bool isMe) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.reply),
              title: const Text('Reply'),
              onTap: () {
                Navigator.pop(context);
                setState(() {
                  _replyingToMessage = message;
                });
                // Focus on message input
                FocusScope.of(context).requestFocus(FocusNode());
              },
            ),
            if (isMe)
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text('Delete'),
                textColor: Colors.red,
                onTap: () {
                  Navigator.pop(context);
                  _showDeleteMessageDialog(message);
                },
              ),
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('Copy'),
              onTap: () {
                Navigator.pop(context);
                _copyMessageToClipboard(message);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteMessageDialog(MessageModel message) {
    final isSender = message.senderId == widget.userId;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Message'),
        content: Text(
          isSender
              ? 'Do you want to delete this message for everyone or just for you?'
              : 'Do you want to delete this message?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          if (isSender)
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                await _deleteMessage(message, deleteForEveryone: false);
              },
              child: const Text('Delete for me'),
            ),
          if (isSender)
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                await _deleteMessage(message, deleteForEveryone: true);
              },
              child: const Text(
                'Delete for everyone',
                style: TextStyle(color: Colors.red),
              ),
            ),
          if (!isSender)
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                await _deleteMessage(message, deleteForEveryone: false);
              },
              child: const Text('Delete', style: TextStyle(color: Colors.red)),
            ),
        ],
      ),
    );
  }

  Future<void> _deleteMessage(
    MessageModel message, {
    required bool deleteForEveryone,
  }) async {
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);

    final success = await chatProvider.deleteMessage(
      conversationId: widget.conversationId,
      messageId: message.messageId,
      userId: widget.userId,
      deleteForEveryone: deleteForEveryone,
    );

    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Message deleted'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to delete message'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _scrollToMessage(MessageModel message) {
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    final messages = _isSearchMode ? _searchResults : chatProvider.messages;
    final index = messages.indexWhere((m) => m.messageId == message.messageId);

    if (index != -1 && _scrollController.hasClients) {
      // Use a more accurate scroll calculation
      final itemHeight = 120.0; // Approximate height per message
      final targetOffset = index * itemHeight;

      _scrollController.animateTo(
        targetOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _toggleMute() async {
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    final success = _isMuted
        ? await chatProvider.unmuteConversation(
            conversationId: widget.conversationId,
            userId: widget.userId,
          )
        : await chatProvider.muteConversation(
            conversationId: widget.conversationId,
            userId: widget.userId,
          );

    if (success && mounted) {
      setState(() {
        _isMuted = !_isMuted;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isMuted
                ? 'Conversation muted. You won\'t receive notifications.'
                : 'Conversation unmuted. You will receive notifications.',
          ),
          backgroundColor: Colors.green,
        ),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to update mute status'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showThemeSelector() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => Consumer<ChatThemeProvider>(
        builder: (context, chatThemeProvider, _) {
          return Container(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Choose Chat Theme',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 20),
                Flexible(
                  child: GridView.builder(
                    shrinkWrap: true,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 4,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: 0.9,
                        ),
                    itemCount: ChatTheme.values.length,
                    itemBuilder: (context, index) {
                      final theme = ChatTheme.values[index];
                      final isSelected =
                          chatThemeProvider.getThemeForConversation(
                            widget.conversationId,
                          ) ==
                          theme;
                      final themeColor = ChatThemeProvider.getThemeColor(theme);
                      final themeName = ChatThemeProvider.getThemeName(theme);

                      return InkWell(
                        onTap: () {
                          chatThemeProvider.setThemeForConversation(
                            widget.conversationId,
                            theme,
                          );
                          Navigator.pop(context);
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          decoration: BoxDecoration(
                            color: isSelected
                                ? themeColor.withOpacity(0.1)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected
                                  ? themeColor
                                  : Colors.grey[300]!,
                              width: isSelected ? 2 : 1,
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: themeColor,
                                  shape: BoxShape.circle,
                                ),
                                child: isSelected
                                    ? const Icon(
                                        Icons.check,
                                        color: Colors.white,
                                        size: 20,
                                      )
                                    : null,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                themeName,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  color: isSelected
                                      ? themeColor
                                      : Colors.grey[700],
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          );
        },
      ),
    );
  }
}
