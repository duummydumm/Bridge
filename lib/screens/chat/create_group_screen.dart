import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import '../../providers/chat_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/user_provider.dart';
import '../../services/firestore_service.dart';
import '../chat_detail_screen.dart';

class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final TextEditingController _groupNameController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _selectedUserIds = <String>{};
  final Map<String, String> _selectedUserNames = <String, String>{};
  List<Map<String, dynamic>> _allUsers = [];
  List<Map<String, dynamic>> _filteredUsers = [];
  bool _isLoading = false;
  bool _isCreating = false;

  @override
  void initState() {
    super.initState();
    _loadUsers();
    _searchController.addListener(_filterUsers);
  }

  @override
  void dispose() {
    _groupNameController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadUsers() async {
    setState(() => _isLoading = true);
    try {
      final firestoreService = FirestoreService();
      final allUsers = await firestoreService.getAllUsers();
      final currentUserId =
          firebase_auth.FirebaseAuth.instance.currentUser?.uid;

      // Filter out current user and get user data
      _allUsers = allUsers
          .where((user) => user['id'] != currentUserId)
          .toList();

      _filteredUsers = List.from(_allUsers);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading users: $e'),
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

  void _toggleUserSelection(String userId, String userName) {
    setState(() {
      if (_selectedUserIds.contains(userId)) {
        _selectedUserIds.remove(userId);
        _selectedUserNames.remove(userId);
      } else {
        _selectedUserIds.add(userId);
        _selectedUserNames[userId] = userName;
      }
    });
  }

  Future<void> _createGroup() async {
    if (_groupNameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a group name'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (_selectedUserIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select at least one participant'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isCreating = true);

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final chatProvider = Provider.of<ChatProvider>(context, listen: false);

      if (authProvider.user == null) {
        throw Exception('User not authenticated');
      }

      final adminId = authProvider.user!.uid;
      final adminName =
          userProvider.currentUser?.fullName ??
          authProvider.user!.email ??
          'User';

      final conversationId = await chatProvider.createGroupConversation(
        adminId: adminId,
        adminName: adminName,
        participantIds: _selectedUserIds.toList(),
        participantNames: _selectedUserNames,
        groupName: _groupNameController.text.trim(),
      );

      if (conversationId != null && mounted) {
        // Navigate to the new group chat
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => ChatDetailScreen(
              conversationId: conversationId,
              otherParticipantName: _groupNameController.text.trim(),
              userId: adminId,
            ),
          ),
        );
      } else {
        throw Exception('Failed to create group');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isCreating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error creating group: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('New Group'),
        backgroundColor: const Color(0xFF00897B),
        elevation: 0,
      ),
      body: Column(
        children: [
          // Group name input
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: TextField(
              controller: _groupNameController,
              decoration: InputDecoration(
                hintText: 'Group name',
                prefixIcon: const Icon(Icons.group),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: Colors.grey[50],
              ),
            ),
          ),

          // Selected participants count
          if (_selectedUserIds.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: const Color(0xFF00897B).withOpacity(0.1),
              child: Row(
                children: [
                  Icon(Icons.people, color: const Color(0xFF00897B), size: 20),
                  const SizedBox(width: 8),
                  Text(
                    '${_selectedUserIds.length} participant${_selectedUserIds.length == 1 ? '' : 's'} selected',
                    style: TextStyle(
                      color: const Color(0xFF00897B),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),

          // Search bar
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: TextField(
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
          ),

          // Users list
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredUsers.isEmpty
                ? Center(
                    child: Text(
                      _searchController.text.isEmpty
                          ? 'No users found'
                          : 'No users match your search',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _filteredUsers.length,
                    itemBuilder: (context, index) {
                      final user = _filteredUsers[index];
                      final userId = user['id'] as String;
                      final userName = _getUserName(user);
                      final isSelected = _selectedUserIds.contains(userId);

                      return CheckboxListTile(
                        value: isSelected,
                        onChanged: (_) =>
                            _toggleUserSelection(userId, userName),
                        title: Text(userName),
                        subtitle: Text(user['email'] ?? ''),
                        secondary: CircleAvatar(
                          backgroundColor: const Color(
                            0xFF00897B,
                          ).withOpacity(0.1),
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
                        activeColor: const Color(0xFF00897B),
                      );
                    },
                  ),
          ),

          // Create button
          Container(
            padding: const EdgeInsets.all(16),
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
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isCreating ? null : _createGroup,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00897B),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isCreating
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        )
                      : const Text(
                          'Create Group',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
