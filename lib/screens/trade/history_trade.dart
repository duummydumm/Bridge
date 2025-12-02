import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../providers/auth_provider.dart';
import '../../providers/user_provider.dart';
import '../../providers/chat_provider.dart';
import '../../services/firestore_service.dart';
import '../../reusable_widgets/bottom_nav_bar_widget.dart';
import '../chat_detail_screen.dart';
import 'trade_offer_detail_screen.dart';

class TradeHistoryScreen extends StatefulWidget {
  final String? initialFilter; // 'all', 'incoming', or 'outgoing'

  const TradeHistoryScreen({super.key, this.initialFilter});

  @override
  State<TradeHistoryScreen> createState() => _TradeHistoryScreenState();
}

class _TradeHistoryScreenState extends State<TradeHistoryScreen>
    with SingleTickerProviderStateMixin {
  final FirestoreService _firestoreService = FirestoreService();
  bool _isLoading = true;
  List<Map<String, dynamic>> _allOffers = [];
  late TabController _tabController;
  String _searchQuery = '';
  late String _userFilter; // all, incoming, outgoing
  DateTimeRange? _dateRange;

  // BRIDGE Trade theme color
  static const Color _primaryColor = Color(0xFF2A7A9E);

  @override
  void initState() {
    super.initState();
    _userFilter = widget.initialFilter ?? 'all';
    _tabController = TabController(length: 3, vsync: this);
    _loadOffers();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadOffers() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final userId = authProvider.user?.uid;

      if (userId == null) {
        setState(() {
          _isLoading = false;
        });
        return;
      }

      // Get all trade offers for user (both incoming and outgoing)
      final allOffers = await _firestoreService.getTradeOffersByUser(userId);

      // Sort by date (newest first)
      allOffers.sort((a, b) {
        final aDate = (a['createdAt'] as Timestamp?)?.toDate() ?? DateTime(0);
        final bDate = (b['createdAt'] as Timestamp?)?.toDate() ?? DateTime(0);
        return bDate.compareTo(aDate);
      });

      setState(() {
        _allOffers = allOffers;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading trade history: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  List<Map<String, dynamic>> _getOffersByStatus(String status) {
    return _allOffers.where((offer) => offer['status'] == status).toList();
  }

  String _formatDate(DateTime date) {
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.day.toString().padLeft(2, '0')}, ${date.year}';
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return Colors.orange;
      case 'approved':
        return Colors.green;
      case 'declined':
        return Colors.red;
      case 'completed':
        return Colors.blue;
      case 'cancelled':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: _primaryColor,
        elevation: 0,
        title: Text(
          widget.initialFilter == 'outgoing'
              ? 'Your Trade Offers'
              : 'Trade History',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: 'All'),
            Tab(text: 'Completed'),
            Tab(text: 'Declined'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildFilters(),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildOffersList(_allOffers, 'All Trades'),
                      _buildOffersList(
                        _getOffersByStatus('completed'),
                        'Completed Trades',
                      ),
                      _buildOffersList(
                        _getOffersByStatus('declined'),
                        'Declined Trades',
                      ),
                    ],
                  ),
                ),
              ],
            ),
      bottomNavigationBar: BottomNavBarWidget(
        selectedIndex: null,
        onTap: (_) {},
        navigationContext: context,
      ),
    );
  }

  Widget _buildOffersList(
    List<Map<String, dynamic>> offers,
    String emptyTitle,
  ) {
    final filtered = _applyFilters(offers);

    if (filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No $emptyTitle.toLowerCase()',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Your trade history will appear here',
              style: TextStyle(color: Colors.grey[500]),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadOffers,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: filtered.length,
        itemBuilder: (context, index) {
          final offer = filtered[index];
          return _buildOfferCard(offer);
        },
      ),
    );
  }

  Widget _buildFilters() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            decoration: InputDecoration(
              hintText: 'Search by user or item...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        setState(() {
                          _searchQuery = '';
                        });
                      },
                    )
                  : null,
              filled: true,
              fillColor: Colors.grey[100],
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: (value) {
              setState(() {
                _searchQuery = value.trim().toLowerCase();
              });
            },
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              // Incoming / Outgoing filter
              Expanded(
                child: Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('All roles'),
                      selected: _userFilter == 'all',
                      onSelected: (_) {
                        setState(() {
                          _userFilter = 'all';
                        });
                      },
                    ),
                    ChoiceChip(
                      label: const Text('Incoming'),
                      selected: _userFilter == 'incoming',
                      onSelected: (_) {
                        setState(() {
                          _userFilter = 'incoming';
                        });
                      },
                    ),
                    ChoiceChip(
                      label: const Text('Outgoing'),
                      selected: _userFilter == 'outgoing',
                      onSelected: (_) {
                        setState(() {
                          _userFilter = 'outgoing';
                        });
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Date range filter
              OutlinedButton.icon(
                onPressed: () async {
                  final now = DateTime.now();
                  final firstDate = DateTime(now.year - 1);
                  final picked = await showDateRangePicker(
                    context: context,
                    firstDate: firstDate,
                    lastDate: now,
                    initialDateRange: _dateRange,
                  );
                  if (picked != null) {
                    setState(() {
                      _dateRange = picked;
                    });
                  }
                },
                icon: const Icon(Icons.date_range, size: 18),
                label: Text(
                  _dateRange == null
                      ? 'Any date'
                      : '${_formatDate(_dateRange!.start)} - ${_formatDate(_dateRange!.end)}',
                  overflow: TextOverflow.ellipsis,
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _applyFilters(List<Map<String, dynamic>> offers) {
    if (offers.isEmpty) return offers;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final currentUserId = authProvider.user?.uid ?? '';

    return offers.where((offer) {
      // Role filter (incoming/outgoing)
      if (_userFilter != 'all') {
        final isIncoming = offer['toUserId'] == currentUserId;
        if (_userFilter == 'incoming' && !isIncoming) return false;
        if (_userFilter == 'outgoing' && isIncoming) return false;
      }

      // Date range filter
      if (_dateRange != null) {
        final createdAt =
            (offer['createdAt'] as Timestamp?)?.toDate() ?? DateTime(0);
        if (createdAt.isBefore(_dateRange!.start) ||
            createdAt.isAfter(_dateRange!.end.add(const Duration(days: 1)))) {
          return false;
        }
      }

      // Search filter (user name or item title)
      if (_searchQuery.isNotEmpty) {
        final isIncoming = offer['toUserId'] == currentUserId;
        final otherUserName =
            (isIncoming
                    ? (offer['fromUserName'] ?? '')
                    : (offer['toUserName'] ?? ''))
                .toString()
                .toLowerCase();
        final offeredName = (offer['offeredItemName'] ?? '')
            .toString()
            .toLowerCase();
        final originalName = (offer['originalOfferedItemName'] ?? '')
            .toString()
            .toLowerCase();

        final haystack = '$otherUserName $offeredName $originalName';
        if (!haystack.contains(_searchQuery)) {
          return false;
        }
      }

      return true;
    }).toList();
  }

  Widget _buildOfferCard(Map<String, dynamic> offer) {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final currentUserId = authProvider.user?.uid ?? '';
    final createdAt =
        (offer['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
    final status = offer['status'] as String? ?? 'unknown';
    final statusColor = _getStatusColor(status);

    // Determine if this is an incoming or outgoing offer
    final isIncoming = offer['toUserId'] == currentUserId;
    final otherUserName = isIncoming
        ? (offer['fromUserName'] ?? 'Unknown')
        : (offer['toUserName'] ?? 'Unknown');

    Future<void> startChat() async {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final chatProvider = Provider.of<ChatProvider>(context, listen: false);

      if (authProvider.user == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please log in to message the other user'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final currentUserName =
          userProvider.currentUser?.fullName.isNotEmpty == true
          ? userProvider.currentUser!.fullName
          : (authProvider.user!.email ?? 'You');

      final String otherUserId = isIncoming
          ? (offer['fromUserId'] ?? '')
          : (offer['toUserId'] ?? '');
      final String otherName = (otherUserName as String).isNotEmpty
          ? otherUserName
          : 'User';

      if (otherUserId.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not determine the other user for this trade'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );

      try {
        final conversationId = await chatProvider.createOrGetConversation(
          userId1: currentUserId,
          userId1Name: currentUserName,
          userId2: otherUserId,
          userId2Name: otherName,
          itemId: offer['tradeItemId'] as String?,
          itemTitle:
              (offer['originalOfferedItemName'] ?? offer['offeredItemName'])
                  as String?,
        );

        if (!context.mounted) return;
        Navigator.of(context, rootNavigator: true).pop();

        if (conversationId == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to start conversation'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }

        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ChatDetailScreen(
              conversationId: conversationId,
              otherParticipantName: otherName,
              userId: currentUserId,
            ),
          ),
        );
      } catch (e) {
        if (!context.mounted) return;
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error starting chat: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => TradeOfferDetailScreen(
                offerId: offer['id'] as String,
                canAcceptDecline: false,
              ),
            ),
          );
        },
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      status == 'approved' || status == 'completed'
                          ? Icons.check_circle
                          : status == 'declined'
                          ? Icons.cancel
                          : Icons.pending,
                      color: statusColor,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Trade with: $otherUserName',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _formatDate(createdAt),
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[700],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      status.toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Trade visualization
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isIncoming ? 'They Offer' : 'You Offer',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 4),
                        if (offer['offeredItemImageUrl'] != null)
                          Container(
                            height: 60,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              color: Colors.grey[200],
                              image: DecorationImage(
                                image: NetworkImage(
                                  offer['offeredItemImageUrl'],
                                ),
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                        const SizedBox(height: 4),
                        Text(
                          offer['offeredItemName'] ?? 'Unknown',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Icon(Icons.swap_horiz, color: statusColor, size: 24),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          isIncoming ? 'You Offer' : 'They Offer',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 4),
                        if (offer['originalOfferedItemImageUrl'] != null)
                          Container(
                            height: 60,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              color: Colors.grey[200],
                              image: DecorationImage(
                                image: NetworkImage(
                                  offer['originalOfferedItemImageUrl'],
                                ),
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                        const SizedBox(height: 4),
                        Text(
                          offer['originalOfferedItemName'] ?? 'Unknown',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.end,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: startChat,
                  icon: const Icon(Icons.message, size: 18),
                  label: const Text('Message User'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _primaryColor,
                    side: const BorderSide(color: _primaryColor),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
