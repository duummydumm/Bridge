import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io';
import '../../providers/chat_provider.dart';
import '../../models/conversation_model.dart';
import '../../services/firestore_service.dart';
import '../../services/storage_service.dart';
import '../user_public_profile_screen.dart';

class GroupManagementScreen extends StatefulWidget {
  final String conversationId;
  final String userId;

  const GroupManagementScreen({
    super.key,
    required this.conversationId,
    required this.userId,
  });

  @override
  State<GroupManagementScreen> createState() => _GroupManagementScreenState();
}

class _GroupManagementScreenState extends State<GroupManagementScreen> {
  ConversationModel? _conversation;
  bool _isLoading = true;
  bool _isUpdating = false;
  final TextEditingController _groupNameController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _allUsers = [];
  List<Map<String, dynamic>> _filteredUsers = [];
  bool _showAddMember = false;
  final ImagePicker _imagePicker = ImagePicker();
  final StorageService _storageService = StorageService();
  bool _isUploadingImage = false;

  @override
  void initState() {
    super.initState();
    _loadConversation();
    _searchController.addListener(_filterUsers);
  }

  @override
  void dispose() {
    _groupNameController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadConversation() async {
    setState(() => _isLoading = true);
    try {
      final chatProvider = Provider.of<ChatProvider>(context, listen: false);
      _conversation = await chatProvider.getConversation(widget.conversationId);

      if (_conversation != null) {
        _groupNameController.text = _conversation!.groupName ?? '';
      }

      await _loadAvailableUsers();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading group: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadAvailableUsers() async {
    try {
      final firestoreService = FirestoreService();
      final allUsers = await firestoreService.getAllUsers();
      final currentUserId = widget.userId;

      // Filter out users already in the group
      final participantIds = _conversation?.participants ?? [];
      _allUsers = allUsers
          .where(
            (user) =>
                user['id'] != currentUserId &&
                !participantIds.contains(user['id']),
          )
          .toList();

      _filteredUsers = List.from(_allUsers);
    } catch (e) {
      debugPrint('Error loading users: $e');
    }
  }

  void _filterUsers() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredUsers = List.from(_allUsers);
      } else {
        _filteredUsers = _allUsers.where((user) {
          final name =
              '${user['firstName'] ?? ''} ${user['middleInitial'] ?? ''} ${user['lastName'] ?? ''}'
                  .toLowerCase()
                  .trim();
          final email = (user['email'] ?? '').toString().toLowerCase();
          return name.contains(query) || email.contains(query);
        }).toList();
      }
    });
  }

  Future<void> _updateGroupName() async {
    if (_groupNameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Group name cannot be empty'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (_groupNameController.text.trim() == _conversation?.groupName) {
      return; // No change
    }

    setState(() => _isUpdating = true);
    try {
      final chatProvider = Provider.of<ChatProvider>(context, listen: false);
      final success = await chatProvider.updateGroupName(
        conversationId: widget.conversationId,
        newName: _groupNameController.text.trim(),
        adminId: widget.userId,
      );

      if (success && mounted) {
        await _loadConversation();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Group name updated'),
            backgroundColor: Colors.green,
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to update group name'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUpdating = false);
      }
    }
  }

  Future<void> _addMember(String userId, String userName) async {
    setState(() => _isUpdating = true);
    try {
      final chatProvider = Provider.of<ChatProvider>(context, listen: false);
      final success = await chatProvider.addParticipantToGroup(
        conversationId: widget.conversationId,
        userId: userId,
        userName: userName,
        adminId: widget.userId,
      );

      if (success && mounted) {
        await _loadConversation();
        await _loadAvailableUsers();
        setState(() => _showAddMember = false);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$userName added to group'),
            backgroundColor: Colors.green,
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to add member'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUpdating = false);
      }
    }
  }

  Future<void> _removeMember(String userId, String userName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Member'),
        content: Text(
          'Are you sure you want to remove $userName from the group?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isUpdating = true);
    try {
      if (!mounted) return;
      final chatProvider = Provider.of<ChatProvider>(context, listen: false);
      final success = await chatProvider.removeParticipantFromGroup(
        conversationId: widget.conversationId,
        userId: userId,
        adminId: widget.userId,
      );

      if (success && mounted) {
        await _loadConversation();
        await _loadAvailableUsers();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$userName removed from group'),
            backgroundColor: Colors.green,
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to remove member'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUpdating = false);
      }
    }
  }

  Future<void> _leaveGroup() async {
    final isAdmin = _conversation?.isGroupAdmin(widget.userId) ?? false;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isAdmin ? 'Leave Group as Admin' : 'Leave Group'),
        content: Text(
          isAdmin
              ? 'You are the group admin. If you leave, admin rights will be automatically transferred to another member. Are you sure you want to leave?'
              : 'Are you sure you want to leave this group? You will no longer receive messages from this group.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Leave'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isUpdating = true);
    try {
      if (!mounted) return;
      final chatProvider = Provider.of<ChatProvider>(context, listen: false);
      final success = await chatProvider.removeParticipantFromGroup(
        conversationId: widget.conversationId,
        userId: widget.userId,
        adminId: widget.userId, // User can leave themselves
      );

      if (success && mounted) {
        Navigator.of(context).pop(); // Go back to chat list
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You left the group'),
            backgroundColor: Colors.green,
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to leave group'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUpdating = false);
      }
    }
  }

  Future<void> _transferAdmin(String newAdminId, String newAdminName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Transfer Admin'),
        content: Text(
          'Are you sure you want to transfer admin rights to $newAdminName? You will no longer be the group admin.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.orange),
            child: const Text('Transfer'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isUpdating = true);
    try {
      if (!mounted) return;
      final chatProvider = Provider.of<ChatProvider>(context, listen: false);
      final success = await chatProvider.transferGroupAdmin(
        conversationId: widget.conversationId,
        newAdminId: newAdminId,
        currentAdminId: widget.userId,
      );

      if (success && mounted) {
        await _loadConversation();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Admin rights transferred to $newAdminName'),
            backgroundColor: Colors.green,
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to transfer admin'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUpdating = false);
      }
    }
  }

  Future<void> _pickAndUploadGroupImage() async {
    try {
      final pickedImage = await _imagePicker.pickImage(
        source: ImageSource.gallery,
      );
      if (pickedImage == null) return;

      setState(() => _isUploadingImage = true);

      // Upload image to Firebase Storage
      String imageUrl;

      if (kIsWeb) {
        final bytes = await pickedImage.readAsBytes();
        imageUrl = await _storageService.uploadGroupImageBytes(
          bytes: bytes,
          groupId: widget.conversationId,
          userId: widget.userId,
        );
      } else {
        imageUrl = await _storageService.uploadGroupImage(
          file: File(pickedImage.path),
          groupId: widget.conversationId,
          userId: widget.userId,
        );
      }

      // Update group image
      if (!mounted) return;
      final chatProvider = Provider.of<ChatProvider>(context, listen: false);
      final success = await chatProvider.updateGroupImage(
        conversationId: widget.conversationId,
        imageUrl: imageUrl,
        adminId: widget.userId,
      );

      if (success && mounted) {
        await _loadConversation();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Group image updated'),
            backgroundColor: Colors.green,
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to update group image'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error uploading image: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUploadingImage = false);
      }
    }
  }

  Future<void> _updateSetting(String key, bool value) async {
    if (_conversation == null) return;

    setState(() => _isUpdating = true);
    try {
      final currentSettings = Map<String, dynamic>.from(
        _conversation!.groupSettings ?? {},
      );
      currentSettings[key] = value;

      final chatProvider = Provider.of<ChatProvider>(context, listen: false);
      final success = await chatProvider.updateGroupSettings(
        conversationId: widget.conversationId,
        settings: currentSettings,
        adminId: widget.userId,
      );

      if (success && mounted) {
        await _loadConversation();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Setting updated'),
            backgroundColor: Colors.green,
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to update setting'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUpdating = false);
      }
    }
  }

  Widget _buildSettingsSwitch({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      title: Text(title),
      subtitle: Text(subtitle),
      value: value,
      onChanged: _isUpdating ? null : onChanged,
      activeColor: const Color(0xFF00897B),
    );
  }

  String _getUserName(Map<String, dynamic> user) {
    final firstName = user['firstName'] ?? '';
    final middleInitial = user['middleInitial'] ?? '';
    final lastName = user['lastName'] ?? '';
    return '$firstName ${middleInitial.isNotEmpty ? "$middleInitial " : ""}$lastName'
        .trim();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Group Settings'),
          backgroundColor: const Color(0xFF00897B),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_conversation == null || !_conversation!.isGroup) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Group Settings'),
          backgroundColor: const Color(0xFF00897B),
        ),
        body: const Center(child: Text('Group not found')),
      );
    }

    final isAdmin = _conversation!.isGroupAdmin(widget.userId);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Group Settings'),
        backgroundColor: const Color(0xFF00897B),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Group Image Section
            Container(
              padding: const EdgeInsets.all(24),
              color: const Color(0xFF00897B),
              child: Column(
                children: [
                  Stack(
                    children: [
                      ClipOval(
                        child: Container(
                          width: 120,
                          height: 120,
                          color: Colors.white.withValues(alpha: 0.2),
                          child:
                              _conversation!.groupImageUrl != null &&
                                  _conversation!.groupImageUrl!.isNotEmpty
                              ? CachedNetworkImage(
                                  imageUrl:
                                      '${_conversation!.groupImageUrl!}?v=${_conversation!.updatedAt?.millisecondsSinceEpoch ?? DateTime.now().millisecondsSinceEpoch}',
                                  fit: BoxFit.cover,
                                  placeholder: (context, url) => const Center(
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  ),
                                  errorWidget: (context, url, error) =>
                                      const Icon(
                                        Icons.group,
                                        size: 60,
                                        color: Colors.white,
                                      ),
                                )
                              : const Icon(
                                  Icons.group,
                                  size: 60,
                                  color: Colors.white,
                                ),
                        ),
                      ),
                      if (isAdmin && !_isUploadingImage)
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: CircleAvatar(
                            radius: 20,
                            backgroundColor: const Color(0xFF00897B),
                            child: IconButton(
                              icon: const Icon(Icons.camera_alt, size: 20),
                              color: Colors.white,
                              onPressed: _pickAndUploadGroupImage,
                            ),
                          ),
                        ),
                      if (_isUploadingImage)
                        Positioned.fill(
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.5),
                              shape: BoxShape.circle,
                            ),
                            child: const Center(
                              child: CircularProgressIndicator(
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (isAdmin)
                    TextButton.icon(
                      onPressed: _pickAndUploadGroupImage,
                      icon: const Icon(Icons.camera_alt),
                      label: const Text('Change Group Photo'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                      ),
                    ),
                ],
              ),
            ),

            // Group Name Section
            Container(
              padding: const EdgeInsets.all(16),
              color: Colors.white,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Group Name',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _groupNameController,
                          enabled: isAdmin && !_isUpdating,
                          decoration: InputDecoration(
                            hintText: 'Enter group name',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            filled: true,
                            fillColor: isAdmin
                                ? Colors.grey[50]
                                : Colors.grey[100],
                          ),
                        ),
                      ),
                      if (isAdmin) ...[
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.check),
                          color: const Color(0xFF00897B),
                          onPressed: _isUpdating ? null : _updateGroupName,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 8),

            // Members Section
            Container(
              padding: const EdgeInsets.all(16),
              color: Colors.white,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Members (${_conversation!.participantCount})',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (isAdmin)
                        TextButton.icon(
                          onPressed: () {
                            setState(() => _showAddMember = !_showAddMember);
                          },
                          icon: const Icon(Icons.person_add),
                          label: const Text('Add'),
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFF00897B),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Add Member Section
                  if (_showAddMember && isAdmin) ...[
                    TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Search users...',
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: Colors.grey[50],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 200),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey[300]!),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: _filteredUsers.isEmpty
                          ? const Padding(
                              padding: EdgeInsets.all(16),
                              child: Center(child: Text('No users found')),
                            )
                          : ListView.builder(
                              shrinkWrap: true,
                              itemCount: _filteredUsers.length,
                              itemBuilder: (context, index) {
                                final user = _filteredUsers[index];
                                final userId = user['id'] as String;
                                final userName = _getUserName(user);

                                return ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: const Color(
                                      0xFF00897B,
                                    ).withValues(alpha: 0.1),
                                    child: Text(
                                      userName.isNotEmpty
                                          ? userName[0].toUpperCase()
                                          : 'U',
                                      style: const TextStyle(
                                        color: Color(0xFF00897B),
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  title: Text(userName),
                                  subtitle: Text(user['email'] ?? ''),
                                  trailing: IconButton(
                                    icon: const Icon(Icons.add),
                                    color: const Color(0xFF00897B),
                                    onPressed: () =>
                                        _addMember(userId, userName),
                                  ),
                                );
                              },
                            ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Members List
                  ..._conversation!.participants.map((participantId) {
                    final participantName =
                        _conversation!.participantNames[participantId] ??
                        'Unknown';
                    final isCurrentUser = participantId == widget.userId;
                    final isParticipantAdmin =
                        _conversation!.groupAdmin == participantId;

                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: const Color(
                          0xFF00897B,
                        ).withValues(alpha: 0.1),
                        child: Text(
                          participantName.isNotEmpty
                              ? participantName[0].toUpperCase()
                              : 'U',
                          style: const TextStyle(
                            color: Color(0xFF00897B),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              participantName,
                              style: TextStyle(
                                fontWeight: isCurrentUser
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                          ),
                          if (isParticipantAdmin)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.orange[100],
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Text(
                                'Admin',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.orange,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                        ],
                      ),
                      subtitle: Text(isCurrentUser ? 'You' : 'Member'),
                      trailing: isCurrentUser
                          ? null
                          : (isAdmin
                                ? PopupMenuButton(
                                    icon: const Icon(Icons.more_vert),
                                    itemBuilder: (context) => [
                                      PopupMenuItem(
                                        child: const ListTile(
                                          leading: Icon(Icons.person_remove),
                                          title: Text('Remove'),
                                        ),
                                        onTap: () => _removeMember(
                                          participantId,
                                          participantName,
                                        ),
                                      ),
                                      if (!isParticipantAdmin)
                                        PopupMenuItem(
                                          child: const ListTile(
                                            leading: Icon(
                                              Icons.admin_panel_settings,
                                            ),
                                            title: Text('Make Admin'),
                                          ),
                                          onTap: () => _transferAdmin(
                                            participantId,
                                            participantName,
                                          ),
                                        ),
                                    ],
                                  )
                                : null),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                UserPublicProfileScreen(userId: participantId),
                          ),
                        );
                      },
                    );
                  }).toList(),
                ],
              ),
            ),

            const SizedBox(height: 8),

            // Group Settings Section (Admin only)
            if (isAdmin) ...[
              Container(
                padding: const EdgeInsets.all(16),
                color: Colors.white,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Group Settings',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildSettingsSwitch(
                      title: 'Only admins can add members',
                      subtitle: 'Prevent members from adding others',
                      value:
                          _conversation!
                              .groupSettings?['onlyAdminCanAddMembers'] ??
                          false,
                      onChanged: (value) =>
                          _updateSetting('onlyAdminCanAddMembers', value),
                    ),
                    const Divider(),
                    _buildSettingsSwitch(
                      title: 'Only admins can change name',
                      subtitle: 'Prevent members from changing group name',
                      value:
                          _conversation!
                              .groupSettings?['onlyAdminCanChangeName'] ??
                          true,
                      onChanged: (value) =>
                          _updateSetting('onlyAdminCanChangeName', value),
                    ),
                    const Divider(),
                    _buildSettingsSwitch(
                      title: 'Only admins can change image',
                      subtitle: 'Prevent members from changing group photo',
                      value:
                          _conversation!
                              .groupSettings?['onlyAdminCanChangeImage'] ??
                          true,
                      onChanged: (value) =>
                          _updateSetting('onlyAdminCanChangeImage', value),
                    ),
                    const Divider(),
                    _buildSettingsSwitch(
                      title: 'Allow members to invite',
                      subtitle: 'Let members invite others to the group',
                      value:
                          _conversation!
                              .groupSettings?['allowMembersToInvite'] ??
                          true,
                      onChanged: (value) =>
                          _updateSetting('allowMembersToInvite', value),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],

            // Leave Group Section
            Container(
              padding: const EdgeInsets.all(16),
              color: Colors.white,
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _isUpdating ? null : _leaveGroup,
                  icon: const Icon(Icons.exit_to_app, color: Colors.red),
                  label: const Text(
                    'Leave Group',
                    style: TextStyle(color: Colors.red),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.red),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
            ),

            if (_isUpdating)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              ),
          ],
        ),
      ),
    );
  }
}
