import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../providers/auth_provider.dart';
import '../../services/firestore_service.dart';
import '../../reusable_widgets/bottom_nav_bar_widget.dart';

class BorrowedItemsDetailScreen extends StatefulWidget {
  const BorrowedItemsDetailScreen({super.key});

  @override
  State<BorrowedItemsDetailScreen> createState() =>
      _BorrowedItemsDetailScreenState();
}

class _BorrowedItemsDetailScreenState extends State<BorrowedItemsDetailScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  List<Map<String, dynamic>> _borrowedItems = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadBorrowedItems();
  }

  Future<void> _loadBorrowedItems() async {
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

      final items = await _firestoreService.getBorrowedItemsByBorrower(userId);
      setState(() {
        _borrowedItems = items;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error loading borrowed items: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  DateTime? _parseDate(dynamic dateValue) {
    if (dateValue == null) return null;
    if (dateValue is DateTime) return dateValue;
    if (dateValue is Timestamp) return dateValue.toDate();
    if (dateValue is int) {
      return DateTime.fromMillisecondsSinceEpoch(dateValue);
    }
    return null;
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'No date set';
    final now = DateTime.now();
    final difference = date.difference(now);

    if (difference.inDays < 0) {
      return 'Overdue by ${difference.inDays.abs()} days';
    } else if (difference.inDays == 0) {
      return 'Due today';
    } else if (difference.inDays == 1) {
      return 'Due tomorrow';
    } else {
      return 'Due in ${difference.inDays} days';
    }
  }

  Color _getStatusColor(DateTime? returnDate) {
    if (returnDate == null) return Colors.grey;
    final now = DateTime.now();
    final difference = returnDate.difference(now);

    if (difference.inDays < 0) {
      return Colors.red;
    } else if (difference.inDays <= 3) {
      return Colors.orange;
    } else {
      return Colors.green;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: const Color(0xFF00897B),
        elevation: 0,
        title: const Text(
          'Items Borrowed',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadBorrowedItems,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadBorrowedItems,
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
                      onPressed: _loadBorrowedItems,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              )
            : _borrowedItems.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.inbox_outlined,
                      size: 64,
                      color: Colors.grey[400],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No borrowed items',
                      style: TextStyle(
                        color: Colors.grey[700],
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Items you borrow will appear here',
                      style: TextStyle(color: Colors.grey[600], fontSize: 14),
                    ),
                  ],
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _borrowedItems.length,
                itemBuilder: (context, index) {
                  final item = _borrowedItems[index];
                  final title = (item['title'] ?? 'Untitled Item').toString();
                  final returnDate = _parseDate(item['returnDate']);
                  final statusColor = _getStatusColor(returnDate);

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: InkWell(
                      onTap: () {
                        // Navigate to borrow screen to view item details
                        Navigator.pushNamed(context, '/borrow');
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                color: statusColor.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                Icons.inventory_2_outlined,
                                color: statusColor,
                                size: 28,
                              ),
                            ),
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
                                      color: Color(0xFF1A1A1A),
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.calendar_today,
                                        size: 16,
                                        color: Colors.grey[600],
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        _formatDate(returnDate),
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: statusColor,
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
