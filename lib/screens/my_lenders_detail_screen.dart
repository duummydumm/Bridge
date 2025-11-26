import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/firestore_service.dart';
import '../reusable_widgets/bottom_nav_bar_widget.dart';
import 'user_public_profile_screen.dart';

class MyLendersDetailScreen extends StatefulWidget {
  const MyLendersDetailScreen({super.key});

  @override
  State<MyLendersDetailScreen> createState() => _MyLendersDetailScreenState();
}

class _MyLendersDetailScreenState extends State<MyLendersDetailScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  List<Map<String, dynamic>> _lenders = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadLenders();
  }

  Future<void> _loadLenders() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final userId = authProvider.user?.uid;

      if (userId == null) {
        setState(() {
          _errorMessage = 'User not authenticated';
          _isLoading = false;
        });
        return;
      }

      // Get all borrowed items to extract unique lender IDs
      final borrowedItems = await _firestoreService.getBorrowedItemsByBorrower(
        userId,
      );
      final lenderIds = <String>{};

      for (final item in borrowedItems) {
        final lenderId = (item['lenderId'] ?? '').toString();
        if (lenderId.isNotEmpty) {
          lenderIds.add(lenderId);
        }
      }

      // Fetch lender details
      final lenders = <Map<String, dynamic>>[];
      for (final lenderId in lenderIds) {
        try {
          final userData = await _firestoreService.getUser(lenderId);
          if (userData != null) {
            lenders.add(userData);
          }
        } catch (e) {
          // Skip if user not found
        }
      }

      setState(() {
        _lenders = lenders;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error loading lenders: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  String _getLenderName(Map<String, dynamic> lender) {
    final firstName = (lender['firstName'] ?? '').toString();
    final middleInitial = (lender['middleInitial'] ?? '').toString();
    final lastName = (lender['lastName'] ?? '').toString();

    if (firstName.isEmpty && lastName.isEmpty) {
      return 'Unknown User';
    }

    if (middleInitial.isNotEmpty) {
      return '$firstName $middleInitial. $lastName';
    }
    return '$firstName $lastName';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: const Color(0xFF00897B),
        elevation: 0,
        title: const Text(
          'My Lenders',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadLenders,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadLenders,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _errorMessage != null
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 64,
                      color: Colors.grey[400],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _errorMessage!,
                      style: TextStyle(color: Colors.grey[700], fontSize: 16),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _loadLenders,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              )
            : _lenders.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.people_outline,
                      size: 64,
                      color: Colors.grey[400],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No lenders yet',
                      style: TextStyle(
                        color: Colors.grey[700],
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Lenders you borrow from will appear here',
                      style: TextStyle(color: Colors.grey[600], fontSize: 14),
                    ),
                  ],
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _lenders.length,
                itemBuilder: (context, index) {
                  final lender = _lenders[index];
                  final lenderId = (lender['id'] ?? lender['uid'] ?? '')
                      .toString();
                  final lenderName = _getLenderName(lender);
                  final reputationScore = (lender['reputationScore'] ?? 0.0)
                      .toDouble();
                  final profilePhotoUrl = (lender['profilePhotoUrl'] ?? '')
                      .toString();

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: InkWell(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                UserPublicProfileScreen(userId: lenderId),
                          ),
                        );
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 28,
                              backgroundColor: const Color(
                                0xFF00897B,
                              ).withOpacity(0.1),
                              backgroundImage: profilePhotoUrl.isNotEmpty
                                  ? NetworkImage(profilePhotoUrl)
                                  : null,
                              child: profilePhotoUrl.isEmpty
                                  ? Text(
                                      lenderName.isNotEmpty
                                          ? lenderName[0].toUpperCase()
                                          : '?',
                                      style: const TextStyle(
                                        color: Color(0xFF00897B),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 20,
                                      ),
                                    )
                                  : null,
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    lenderName,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF1A1A1A),
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.star_rounded,
                                        size: 16,
                                        color: Colors.amber,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        reputationScore > 0
                                            ? reputationScore.toStringAsFixed(1)
                                            : 'New',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Colors.grey[700],
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            Icon(Icons.chevron_right, color: Colors.grey[400]),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
      ),
      bottomNavigationBar: BottomNavBarWidget(
        selectedIndex: 0,
        onTap: (_) {},
        navigationContext: context,
      ),
    );
  }
}
