import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/chat_provider.dart';
import '../providers/user_provider.dart';
import '../providers/auth_provider.dart';
import '../models/conversation_model.dart';
import '../services/firestore_service.dart';
import 'chat_detail_screen.dart';
import '../reusable_widgets/bottom_nav_bar_widget.dart';
import '../reusable_widgets/offline_banner_widget.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  final TextEditingController _searchController = TextEditingController();
  final int _selectedIndex = 2; // Chat is at index 2 in bottom nav
  final FirestoreService _firestoreService = FirestoreService();
  final Map<String, String?> _profilePhotoCache =
      {}; // Cache for profile photos

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final chatProvider = Provider.of<ChatProvider>(context, listen: false);

      if (authProvider.isAuthenticated && authProvider.user != null) {
        // Setup real-time stream for conversations
        chatProvider.setupConversationsStream(authProvider.user!.uid);

        // Also perform an initial fetch so messages show immediately after
        // reinstall/login before the first stream event arrives
        chatProvider.loadConversations(authProvider.user!.uid);
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chatProvider = Provider.of<ChatProvider>(context);
    final userProvider = Provider.of<UserProvider>(context);
    final authProvider = Provider.of<AuthProvider>(context);

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: const Color(0xFF00897B),
        elevation: 0,
        title: const Text(
          'Chat',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.group_add),
            onPressed: () {
              Navigator.of(context).pushNamed('/chat/create-group');
            },
            tooltip: 'New Group',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              if (authProvider.isAuthenticated && authProvider.user != null) {
                await chatProvider.loadConversations(authProvider.user!.uid);
              }
            },
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Column(
        children: [
          // Offline Banner
          const OfflineBannerWidget(),
          // Search Bar
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search conversations...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          chatProvider.setSearchQuery('');
                          setState(() {});
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
              onChanged: (value) {
                chatProvider.setSearchQuery(value);
                setState(() {});
              },
            ),
          ),

          // Conversations List
          Expanded(
            child: authProvider.isAuthenticated && authProvider.user != null
                ? _buildConversationsList(
                    chatProvider,
                    authProvider.user!.uid,
                    userProvider.currentUser?.fullName ?? '',
                  )
                : const Center(child: CircularProgressIndicator()),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavBarWidget(
        selectedIndex: _selectedIndex,
        onTap: (index) {
          setState(() {});
        },
        navigationContext: context,
      ),
    );
  }

  Widget _buildConversationsList(
    ChatProvider chatProvider,
    String userId,
    String userName,
  ) {
    // Show loading indicator
    if (chatProvider.isLoadingConversations &&
        chatProvider.conversations.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    // Get filtered conversations
    final conversations = chatProvider.getFilteredConversations(userId);

    // Show empty state
    if (conversations.isEmpty) {
      return _buildEmptyState();
    }

    // Show conversations list
    return RefreshIndicator(
      onRefresh: () async {
        await chatProvider.loadConversations(userId);
      },
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: conversations.length,
        itemBuilder: (context, index) {
          final conversation = conversations[index];
          return _buildConversationTile(conversation, userId);
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'No conversations yet',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Start a conversation from an item',
            style: TextStyle(color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  Widget _buildConversationTile(ConversationModel conversation, String userId) {
    final isGroup = conversation.isGroup;
    final displayName = conversation.getDisplayName(userId);
    final unreadCount = conversation.getUnreadCountForUser(userId);
    final hasUnread = conversation.hasUnreadForUser(userId);
    final isYou = conversation.lastMessageSenderId == userId;
    final isMuted = conversation.isMutedByUser(userId);

    // Get other participant ID for individual chats
    final otherParticipantId = !isGroup
        ? conversation.getOtherParticipant(userId)
        : null;

    return InkWell(
      onTap: () {
        // Navigate to chat detail screen
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ChatDetailScreen(
              conversationId: conversation.conversationId,
              otherParticipantName: displayName,
              userId: userId,
            ),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(
            bottom: BorderSide(color: Colors.grey[200]!, width: 1),
          ),
        ),
        child: Row(
          children: [
            // Avatar
            Stack(
              children: [
                ClipOval(
                  child: Container(
                    width: 56,
                    height: 56,
                    color: const Color(0xFF00897B).withValues(alpha: 0.1),
                    child:
                        isGroup &&
                            conversation.groupImageUrl != null &&
                            conversation.groupImageUrl!.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl:
                                '${conversation.groupImageUrl!}?v=${conversation.updatedAt?.millisecondsSinceEpoch ?? conversation.lastMessageTime.millisecondsSinceEpoch}',
                            fit: BoxFit.cover,
                            placeholder: (context, url) => const Center(
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            errorWidget: (context, url, error) => const Icon(
                              Icons.group,
                              color: Color(0xFF00897B),
                              size: 28,
                            ),
                          )
                        : isGroup
                        ? const Icon(
                            Icons.group,
                            color: Color(0xFF00897B),
                            size: 28,
                          )
                        : _buildIndividualChatAvatar(
                            otherParticipantId,
                            displayName,
                          ),
                  ),
                ),
                if (hasUnread)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(
                        color: Color(0xFF00897B),
                        shape: BoxShape.circle,
                        border: Border.fromBorderSide(
                          BorderSide(color: Colors.white, width: 2),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                displayName,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: hasUnread
                                      ? FontWeight.bold
                                      : FontWeight.w600,
                                  color: Colors.black87,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (isGroup) ...[
                              const SizedBox(width: 4),
                              Icon(
                                Icons.group,
                                size: 14,
                                color: Colors.grey[600],
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${conversation.participantCount}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (hasUnread && unreadCount > 0) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF00897B),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '$unreadCount',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                      if (isMuted) ...[
                        const SizedBox(width: 4),
                        Icon(
                          Icons.notifications_off,
                          size: 16,
                          color: Colors.grey[500],
                        ),
                      ],
                      const SizedBox(width: 4),
                      Text(
                        _formatTime(conversation.lastMessageTime),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                          fontWeight: hasUnread
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (isYou) ...[
                        const Icon(
                          Icons.done_all,
                          size: 14,
                          color: Colors.grey,
                        ),
                        const SizedBox(width: 4),
                      ],
                      Expanded(
                        child: Text(
                          conversation.lastMessage.isEmpty
                              ? 'No messages yet'
                              : conversation.lastMessage,
                          style: TextStyle(
                            fontSize: 14,
                            color: hasUnread
                                ? Colors.black87
                                : Colors.grey[600],
                            fontWeight: hasUnread
                                ? FontWeight.w500
                                : FontWeight.normal,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  if (conversation.isItemDiscussion &&
                      conversation.itemTitle != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.shopping_bag,
                          size: 12,
                          color: Colors.grey[500],
                        ),
                        const SizedBox(width: 4),
                        Text(
                          conversation.itemTitle!,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIndividualChatAvatar(
    String? otherParticipantId,
    String displayName,
  ) {
    if (otherParticipantId == null || otherParticipantId.isEmpty) {
      return Center(
        child: Text(
          displayName.isNotEmpty ? displayName[0].toUpperCase() : 'U',
          style: const TextStyle(
            color: Color(0xFF00897B),
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }

    // Check cache first
    if (_profilePhotoCache.containsKey(otherParticipantId)) {
      final cachedUrl = _profilePhotoCache[otherParticipantId];
      if (cachedUrl != null && cachedUrl.isNotEmpty) {
        return CachedNetworkImage(
          imageUrl: cachedUrl,
          fit: BoxFit.cover,
          placeholder: (context, url) => Center(
            child: Text(
              displayName.isNotEmpty ? displayName[0].toUpperCase() : 'U',
              style: const TextStyle(
                color: Color(0xFF00897B),
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          errorWidget: (context, url, error) => Center(
            child: Text(
              displayName.isNotEmpty ? displayName[0].toUpperCase() : 'U',
              style: const TextStyle(
                color: Color(0xFF00897B),
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        );
      } else {
        // Cached as null (no photo)
        return Center(
          child: Text(
            displayName.isNotEmpty ? displayName[0].toUpperCase() : 'U',
            style: const TextStyle(
              color: Color(0xFF00897B),
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        );
      }
    }

    // Use FutureBuilder to fetch profile photo
    return FutureBuilder<Map<String, dynamic>?>(
      key: ValueKey('profile_photo_$otherParticipantId'),
      future: _firestoreService.getUser(otherParticipantId),
      builder: (context, snapshot) {
        String? profilePhotoUrl;

        if (snapshot.hasData && snapshot.data != null) {
          profilePhotoUrl = snapshot.data!['profilePhotoUrl'] as String?;
          // Cache the result
          if (!_profilePhotoCache.containsKey(otherParticipantId)) {
            _profilePhotoCache[otherParticipantId] =
                (profilePhotoUrl != null && profilePhotoUrl.isNotEmpty)
                ? profilePhotoUrl
                : null;
          }
        } else if (snapshot.hasError) {
          // Cache null on error to prevent repeated fetches
          if (!_profilePhotoCache.containsKey(otherParticipantId)) {
            _profilePhotoCache[otherParticipantId] = null;
          }
        }

        // Show profile photo if available
        if (profilePhotoUrl != null && profilePhotoUrl.isNotEmpty) {
          return CachedNetworkImage(
            imageUrl: profilePhotoUrl,
            fit: BoxFit.cover,
            placeholder: (context, url) => Center(
              child: Text(
                displayName.isNotEmpty ? displayName[0].toUpperCase() : 'U',
                style: const TextStyle(
                  color: Color(0xFF00897B),
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            errorWidget: (context, url, error) => Center(
              child: Text(
                displayName.isNotEmpty ? displayName[0].toUpperCase() : 'U',
                style: const TextStyle(
                  color: Color(0xFF00897B),
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          );
        }

        // Show initial while loading or if no photo
        return Center(
          child: Text(
            displayName.isNotEmpty ? displayName[0].toUpperCase() : 'U',
            style: const TextStyle(
              color: Color(0xFF00897B),
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        );
      },
    );
  }

  String _formatTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays == 0) {
      if (difference.inHours == 0) {
        if (difference.inMinutes == 0) {
          return 'Just now';
        }
        return '${difference.inMinutes}m ago';
      }
      return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return '${dateTime.day}/${dateTime.month}';
    }
  }
}
