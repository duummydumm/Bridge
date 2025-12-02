import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../providers/chat_provider.dart';
import '../../models/conversation_model.dart';
import '../../services/presence_service.dart';
import '../../services/firestore_service.dart';
import '../user_public_profile_screen.dart';
import 'group_management_screen.dart';

class ConversationInfoScreen extends StatefulWidget {
  final String conversationId;
  final String userId;
  final String otherParticipantName;

  const ConversationInfoScreen({
    super.key,
    required this.conversationId,
    required this.userId,
    required this.otherParticipantName,
  });

  @override
  State<ConversationInfoScreen> createState() => _ConversationInfoScreenState();
}

class _ConversationInfoScreenState extends State<ConversationInfoScreen> {
  ConversationModel? _conversation;
  bool _isLoading = true;
  int _messageCount = 0;
  String? _otherParticipantId;
  DateTime? _otherUserLastSeen;
  final PresenceService _presenceService = PresenceService();
  final FirestoreService _firestoreService = FirestoreService();

  @override
  void initState() {
    super.initState();
    _loadConversationInfo();
  }

  Future<void> _loadConversationInfo() async {
    setState(() => _isLoading = true);

    try {
      final chatProvider = Provider.of<ChatProvider>(context, listen: false);

      // Get conversation details
      _conversation = await chatProvider.getConversation(widget.conversationId);

      if (_conversation != null) {
        _otherParticipantId = _conversation!.getOtherParticipant(widget.userId);

        // Get message count
        final messagesSnapshot = await FirebaseFirestore.instance
            .collection('conversations')
            .doc(widget.conversationId)
            .collection('messages')
            .where('isDeleted', isEqualTo: false)
            .count()
            .get();

        _messageCount = messagesSnapshot.count ?? 0;

        // Load presence if other participant exists
        if (_otherParticipantId != null && _otherParticipantId!.isNotEmpty) {
          _firestoreService.getUserLastSeenStream(_otherParticipantId!).listen((
            lastSeen,
          ) {
            if (mounted) {
              setState(() {
                _otherUserLastSeen = lastSeen;
              });
            }
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading conversation info: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _toggleMute() async {
    if (_conversation == null) return;

    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    final isMuted = _conversation!.isMutedByUser(widget.userId);

    final success = isMuted
        ? await chatProvider.unmuteConversation(
            conversationId: widget.conversationId,
            userId: widget.userId,
          )
        : await chatProvider.muteConversation(
            conversationId: widget.conversationId,
            userId: widget.userId,
          );

    if (success && mounted) {
      // Reload conversation to get updated state
      await _loadConversationInfo();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isMuted
                ? 'Conversation unmuted'
                : 'Conversation muted. You won\'t receive notifications.',
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Conversation Info'),
        backgroundColor: const Color(0xFF00897B),
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _conversation == null
          ? const Center(child: Text('Conversation not found'))
          : _buildContent(),
    );
  }

  Widget _buildContent() {
    final isMuted = _conversation!.isMutedByUser(widget.userId);
    final isOnline = _presenceService.isUserOnline(_otherUserLastSeen);
    final statusText = _presenceService.getStatusText(_otherUserLastSeen);

    return SingleChildScrollView(
      child: Column(
        children: [
          // Profile Section
          Container(
            padding: const EdgeInsets.all(24),
            color: const Color(0xFF00897B),
            child: Column(
              children: [
                CircleAvatar(
                  radius: 50,
                  backgroundColor: Colors.white.withOpacity(0.2),
                  child: Text(
                    widget.otherParticipantName.isNotEmpty
                        ? widget.otherParticipantName[0].toUpperCase()
                        : 'U',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 40,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  widget.otherParticipantName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
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
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Only show View Profile button for 1-on-1 chats, not groups
                if (!_conversation!.isGroup)
                  ElevatedButton.icon(
                    onPressed:
                        _otherParticipantId != null &&
                            _otherParticipantId!.isNotEmpty
                        ? () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => UserPublicProfileScreen(
                                  userId: _otherParticipantId!,
                                ),
                              ),
                            );
                          }
                        : null,
                    icon: const Icon(Icons.person),
                    label: const Text('View Profile'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF00897B),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Info Section
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Mute Toggle
                _buildInfoCard(
                  icon: isMuted ? Icons.notifications_off : Icons.notifications,
                  title: isMuted ? 'Muted' : 'Notifications',
                  subtitle: isMuted
                      ? 'You won\'t receive notifications for this conversation'
                      : 'You will receive notifications for new messages',
                  trailing: Switch(
                    value: !isMuted,
                    onChanged: (_) => _toggleMute(),
                  ),
                ),

                const SizedBox(height: 16),

                // Group Management Button (for groups)
                if (_conversation!.isGroup) ...[
                  _buildInfoCard(
                    icon: Icons.settings,
                    title: 'Group Settings',
                    subtitle: 'Manage members, change name, and more',
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => GroupManagementScreen(
                            conversationId: widget.conversationId,
                            userId: widget.userId,
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                ],

                // Conversation Details
                _buildSectionTitle('Conversation Details'),
                const SizedBox(height: 8),

                _buildInfoRow(
                  icon: Icons.message,
                  label: 'Total Messages',
                  value: _messageCount.toString(),
                ),
                const Divider(),
                _buildInfoRow(
                  icon: Icons.calendar_today,
                  label: 'Created',
                  value: _formatDate(_conversation!.createdAt),
                ),
                const Divider(),
                if (_conversation!.lastMessageTime != _conversation!.createdAt)
                  _buildInfoRow(
                    icon: Icons.access_time,
                    label: 'Last Message',
                    value: _formatDate(_conversation!.lastMessageTime),
                  ),

                // Item Discussion Section
                if (_conversation!.isItemDiscussion &&
                    _conversation!.itemTitle != null) ...[
                  const SizedBox(height: 24),
                  _buildSectionTitle('Item Discussion'),
                  const SizedBox(height: 8),
                  _buildInfoCard(
                    icon: Icons.shopping_bag,
                    title: _conversation!.itemTitle!,
                    subtitle: 'View item details',
                    onTap: _conversation!.itemId != null
                        ? () {
                            // Navigate to item detail - you may need to adjust this
                            // based on your app's navigation structure
                            Navigator.of(context).pop();
                            // TODO: Navigate to item detail screen
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Item detail navigation to be implemented',
                                ),
                              ),
                            );
                          }
                        : null,
                  ),
                ],

                // Participants Section
                const SizedBox(height: 24),
                _buildSectionTitle('Participants'),
                const SizedBox(height: 8),
                ..._conversation!.participants.map((participantId) {
                  final participantName =
                      _conversation!.participantNames[participantId] ??
                      'Unknown';
                  final isCurrentUser = participantId == widget.userId;

                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: isCurrentUser
                          ? const Color(0xFF00897B).withOpacity(0.1)
                          : Colors.grey[300],
                      child: Text(
                        participantName.isNotEmpty
                            ? participantName[0].toUpperCase()
                            : 'U',
                        style: TextStyle(
                          color: isCurrentUser
                              ? const Color(0xFF00897B)
                              : Colors.grey[700],
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    title: Text(
                      participantName,
                      style: TextStyle(
                        fontWeight: isCurrentUser
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                    subtitle: Text(isCurrentUser ? 'You' : 'Other participant'),
                    trailing: isCurrentUser
                        ? const Chip(
                            label: Text('You'),
                            backgroundColor: Color(0xFF00897B),
                            labelStyle: TextStyle(color: Colors.white),
                          )
                        : null,
                  );
                }).toList(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: Color(0xFF00897B),
      ),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Icon(icon, color: Colors.grey[600], size: 20),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 15, color: Colors.grey[700]),
            ),
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, color: const Color(0xFF00897B), size: 24),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      return 'Today';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }
}
