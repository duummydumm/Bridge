import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../services/firestore_service.dart';
import '../providers/auth_provider.dart';
import '../models/rating_model.dart';
import 'submit_rating_screen.dart';

class UserRateHistoryScreen extends StatefulWidget {
  const UserRateHistoryScreen({
    super.key,
    required this.userId,
    required this.userName,
  });

  /// The other user whose profile we came from.
  final String userId;
  final String userName;

  @override
  State<UserRateHistoryScreen> createState() => _UserRateHistoryScreenState();
}

class _UserRateHistoryScreenState extends State<UserRateHistoryScreen>
    with SingleTickerProviderStateMixin {
  final FirestoreService _firestoreService = FirestoreService();
  bool _isLoadingBorrow = true;
  bool _isLoadingRent = true;
  bool _isLoadingTrade = true;
  bool _isLoadingGiveaway = true;
  String? _errorBorrow;
  String? _errorRent;
  String? _errorTrade;
  String? _errorGiveaway;

  List<_BorrowHistoryItem> _borrowHistory = [];
  List<_RentHistoryItem> _rentHistory = [];
  List<_TradeHistoryItem> _tradeHistory = [];
  List<_GiveawayHistoryItem> _giveawayHistory = [];

  @override
  void initState() {
    super.initState();
    _loadBorrowHistory();
    _loadRentHistory();
    _loadTradeHistory();
    _loadGiveawayHistory();
  }

  Future<void> _loadBorrowHistory() async {
    setState(() {
      _isLoadingBorrow = true;
      _errorBorrow = null;
    });

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final currentUserId = authProvider.user?.uid;
      if (currentUserId == null) {
        setState(() {
          _isLoadingBorrow = false;
          _borrowHistory = [];
        });
        return;
      }

      // Query borrow requests directly for better control
      final db = FirebaseFirestore.instance;

      // Get all borrow requests where current user is borrower and status indicates completion
      // Statuses: 'returned', 'accepted' (but item is returned), 'return_initiated' (if completed)
      final requestsQuery = await db
          .collection('borrow_requests')
          .where('borrowerId', isEqualTo: currentUserId)
          .where('status', whereIn: ['returned', 'accepted'])
          .get();

      final List<_BorrowHistoryItem> history = [];

      for (final requestDoc in requestsQuery.docs) {
        final requestData = requestDoc.data();
        final requestId = requestDoc.id;
        final status = (requestData['status'] ?? '').toString().toLowerCase();

        // For 'accepted' status, check if item is actually returned
        if (status == 'accepted') {
          final itemId = requestData['itemId'] as String?;
          if (itemId != null) {
            try {
              final itemDoc = await db.collection('items').doc(itemId).get();
              if (itemDoc.exists) {
                final itemData = itemDoc.data();
                final currentStatus = itemData?['status'] as String?;
                final currentBorrowerId =
                    itemData?['currentBorrowerId'] as String?;

                // Item is returned if status is not 'borrowed' OR currentBorrowerId is not this borrower
                final isReturned =
                    currentStatus != 'borrowed' ||
                    (currentStatus == 'borrowed' &&
                        currentBorrowerId != currentUserId);

                if (!isReturned) continue; // Skip if item is still borrowed
              }
            } catch (e) {
              debugPrint(
                'Error checking item status for request $requestId: $e',
              );
              continue; // Skip if we can't verify
            }
          }
        }

        // Get lender info from request
        final lenderId = (requestData['lenderId'] ?? '').toString();
        final lenderName = (requestData['lenderName'] ?? '').toString();

        // Only include items from this profile user
        if (lenderId.isEmpty || lenderId != widget.userId) continue;

        // Get item title
        String title = (requestData['itemTitle'] ?? '').toString();
        if (title.isEmpty) {
          final itemId = requestData['itemId'] as String?;
          if (itemId != null && itemId.isNotEmpty) {
            try {
              final item = await _firestoreService.getItem(itemId);
              title = (item?['title'] ?? item?['name'] ?? 'Item').toString();
            } catch (e) {
              debugPrint('Error fetching item $itemId: $e');
            }
          }
        }
        title = title.isEmpty ? 'Item' : title;

        // Get lender name if not in request
        String finalLenderName = lenderName;
        if (finalLenderName.isEmpty && lenderId.isNotEmpty) {
          try {
            final lender = await _firestoreService.getUser(lenderId);
            if (lender != null) {
              final firstName = lender['firstName'] ?? '';
              final lastName = lender['lastName'] ?? '';
              finalLenderName = '$firstName $lastName'.trim();
            }
          } catch (e) {
            // Continue if user fetch fails
          }
        }
        finalLenderName = finalLenderName.isEmpty
            ? widget.userName
            : finalLenderName;

        final hasRated = await _firestoreService.hasExistingRating(
          raterUserId: currentUserId,
          ratedUserId: lenderId,
          transactionId: requestId,
        );

        history.add(
          _BorrowHistoryItem(
            requestId: requestId,
            itemTitle: title,
            lenderId: lenderId,
            lenderName: finalLenderName,
            isRated: hasRated,
          ),
        );
      }

      if (!mounted) return;
      setState(() {
        _borrowHistory = history;
        _isLoadingBorrow = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingBorrow = false;
        _errorBorrow = 'Error loading borrow history: $e';
      });
    }
  }

  Future<void> _loadRentHistory() async {
    setState(() {
      _isLoadingRent = true;
      _errorRent = null;
    });

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final currentUserId = authProvider.user?.uid;
      if (currentUserId == null) {
        setState(() {
          _isLoadingRent = false;
          _rentHistory = [];
        });
        return;
      }

      // Fetch as owner and as renter, then filter to this profile user
      final asOwnerRequests = await _firestoreService.getRentalRequestsByUser(
        currentUserId,
        asOwner: true,
      );
      final asRenterRequests = await _firestoreService.getRentalRequestsByUser(
        currentUserId,
        asOwner: false,
      );

      final all = <_RentHistoryItem>[];

      for (final req in [...asOwnerRequests, ...asRenterRequests]) {
        final status = (req['status'] ?? 'requested').toString().toLowerCase();

        // Only include history-type rentals
        if (status != 'returned' &&
            status != 'cancelled' &&
            status != 'disputed') {
          continue;
        }

        final ownerId = (req['ownerId'] ?? '').toString();
        final renterId = (req['renterId'] ?? '').toString();

        final otherUserId = currentUserId == ownerId
            ? renterId
            : currentUserId == renterId
            ? ownerId
            : null;

        if (otherUserId != widget.userId) continue;

        final requestId = (req['id'] ?? '').toString();
        if (requestId.isEmpty) continue;

        // Get item title from rental listing
        String itemTitle = (req['itemTitle'] ?? req['title'] ?? '').toString();
        if (itemTitle.isEmpty) {
          final listingId = (req['listingId'] ?? '').toString();
          if (listingId.isNotEmpty) {
            try {
              final listing = await _firestoreService.getRentalListing(
                listingId,
              );
              if (listing != null) {
                itemTitle = (listing['title'] ?? '').toString();
                // Fallback to item title if listing title not available
                if (itemTitle.isEmpty) {
                  final itemId = listing['itemId'] as String?;
                  if (itemId != null && itemId.isNotEmpty) {
                    final item = await _firestoreService.getItem(itemId);
                    itemTitle = (item?['title'] ?? '').toString();
                  }
                }
              }
            } catch (e) {
              // Continue if listing fetch fails
            }
          }
        }
        itemTitle = itemTitle.isEmpty ? 'Rental Item' : itemTitle;

        final isOwner = currentUserId == ownerId;
        // Get other user's name - fetch from user document if not in request
        String otherUserName =
            (isOwner ? (req['renterName'] ?? '') : (req['ownerName'] ?? ''))
                .toString();
        if (otherUserName.isEmpty && otherUserId != null) {
          try {
            final otherUser = await _firestoreService.getUser(otherUserId);
            if (otherUser != null) {
              final firstName = otherUser['firstName'] ?? '';
              final lastName = otherUser['lastName'] ?? '';
              otherUserName = '$firstName $lastName'.trim();
            }
          } catch (e) {
            // Continue if user fetch fails
          }
        }
        otherUserName = otherUserName.isEmpty ? widget.userName : otherUserName;

        final hasRated = await _firestoreService.hasExistingRating(
          raterUserId: currentUserId,
          ratedUserId: widget.userId,
          transactionId: requestId,
        );

        all.add(
          _RentHistoryItem(
            requestId: requestId,
            itemTitle: itemTitle,
            isOwner: isOwner,
            status: status,
            otherUserName: otherUserName,
            isRated: hasRated,
          ),
        );
      }

      if (!mounted) return;
      setState(() {
        _rentHistory = all;
        _isLoadingRent = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingRent = false;
        _errorRent = 'Error loading rental history: $e';
      });
    }
  }

  Future<void> _loadTradeHistory() async {
    setState(() {
      _isLoadingTrade = true;
      _errorTrade = null;
    });

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final currentUserId = authProvider.user?.uid;
      if (currentUserId == null) {
        setState(() {
          _isLoadingTrade = false;
          _tradeHistory = [];
        });
        return;
      }

      final offers = await _firestoreService.getTradeOffersByUser(
        currentUserId,
      );

      final List<_TradeHistoryItem> history = [];

      for (final offer in offers) {
        final status = (offer['status'] ?? 'pending').toString().toLowerCase();
        if (status != 'completed' && status != 'approved') continue;

        final fromUserId = (offer['fromUserId'] ?? '').toString();
        final toUserId = (offer['toUserId'] ?? '').toString();
        final otherUserId = currentUserId == fromUserId
            ? toUserId
            : currentUserId == toUserId
            ? fromUserId
            : null;
        if (otherUserId != widget.userId) continue;

        final offerId = (offer['id'] ?? '').toString();
        if (offerId.isEmpty) continue;

        final otherUserName =
            (currentUserId == fromUserId
                    ? (offer['toUserName'] ?? '')
                    : (offer['fromUserName'] ?? ''))
                .toString();

        // Get item title from trade offer fields
        String itemTitle =
            (offer['originalOfferedItemName'] ??
                    offer['offeredItemName'] ??
                    offer['itemTitle'] ??
                    offer['title'] ??
                    '')
                .toString();

        // If still empty, fetch from trade_item document
        if (itemTitle.isEmpty) {
          final tradeItemId = (offer['tradeItemId'] ?? '').toString();
          if (tradeItemId.isNotEmpty) {
            try {
              final tradeItem = await _firestoreService.getTradeItem(
                tradeItemId,
              );
              if (tradeItem != null) {
                itemTitle = (tradeItem['offeredItemName'] ?? '').toString();
              }
            } catch (e) {
              debugPrint('Error fetching trade item $tradeItemId: $e');
            }
          }
        }
        itemTitle = itemTitle.isEmpty ? 'Trade Item' : itemTitle;

        // Get other user's name if not in offer
        String finalOtherUserName = otherUserName;
        if (finalOtherUserName.isEmpty && otherUserId != null) {
          try {
            final otherUser = await _firestoreService.getUser(otherUserId);
            if (otherUser != null) {
              final firstName = otherUser['firstName'] ?? '';
              final lastName = otherUser['lastName'] ?? '';
              finalOtherUserName = '$firstName $lastName'.trim();
            }
          } catch (e) {
            // Continue if user fetch fails
          }
        }
        finalOtherUserName = finalOtherUserName.isEmpty
            ? widget.userName
            : finalOtherUserName;

        final hasRated = await _firestoreService.hasExistingRating(
          raterUserId: currentUserId,
          ratedUserId: widget.userId,
          transactionId: offerId,
        );

        history.add(
          _TradeHistoryItem(
            offerId: offerId,
            itemTitle: itemTitle,
            otherUserName: finalOtherUserName,
            status: status,
            isRated: hasRated,
          ),
        );
      }

      if (!mounted) return;
      setState(() {
        _tradeHistory = history;
        _isLoadingTrade = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingTrade = false;
        _errorTrade = 'Error loading trade history: $e';
      });
    }
  }

  Future<void> _loadGiveawayHistory() async {
    setState(() {
      _isLoadingGiveaway = true;
      _errorGiveaway = null;
    });

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final currentUserId = authProvider.user?.uid;
      if (currentUserId == null) {
        setState(() {
          _isLoadingGiveaway = false;
          _giveawayHistory = [];
        });
        return;
      }

      final asClaimant = await _firestoreService.getClaimRequestsByClaimant(
        currentUserId,
      );
      final asDonor = await _firestoreService.getClaimRequestsByDonor(
        currentUserId,
      );

      final List<_GiveawayHistoryItem> history = [];

      for (final claim in [...asClaimant, ...asDonor]) {
        final status = (claim['status'] ?? 'pending').toString().toLowerCase();
        if (status != 'approved' && status != 'completed') continue;

        final donorId = (claim['donorId'] ?? '').toString();
        final claimantId = (claim['claimantId'] ?? '').toString();
        final otherUserId = currentUserId == donorId
            ? claimantId
            : currentUserId == claimantId
            ? donorId
            : null;
        if (otherUserId != widget.userId) continue;

        final claimId = (claim['id'] ?? '').toString();
        if (claimId.isEmpty) continue;

        // Get item title from giveaway document
        String title = (claim['itemTitle'] ?? claim['title'] ?? '').toString();
        if (title.isEmpty) {
          final giveawayId = (claim['giveawayId'] ?? '').toString();
          if (giveawayId.isNotEmpty) {
            try {
              final giveaway = await _firestoreService.getGiveaway(giveawayId);
              if (giveaway != null) {
                title = (giveaway['title'] ?? '').toString();
              }
            } catch (e) {
              debugPrint('Error fetching giveaway $giveawayId: $e');
            }
          }
        }
        title = title.isEmpty ? 'Giveaway Item' : title;

        // Get other user's name
        String otherUserName =
            (currentUserId == donorId
                    ? (claim['claimantName'] ?? '')
                    : (claim['donorName'] ?? ''))
                .toString();
        if (otherUserName.isEmpty && otherUserId != null) {
          try {
            final otherUser = await _firestoreService.getUser(otherUserId);
            if (otherUser != null) {
              final firstName = otherUser['firstName'] ?? '';
              final lastName = otherUser['lastName'] ?? '';
              otherUserName = '$firstName $lastName'.trim();
            }
          } catch (e) {
            // Continue if user fetch fails
          }
        }
        otherUserName = otherUserName.isEmpty ? widget.userName : otherUserName;

        final hasRated = await _firestoreService.hasExistingRating(
          raterUserId: currentUserId,
          ratedUserId: widget.userId,
          transactionId: claimId,
        );

        history.add(
          _GiveawayHistoryItem(
            claimId: claimId,
            itemTitle: title,
            otherUserName: otherUserName,
            status: status,
            isRated: hasRated,
          ),
        );
      }

      if (!mounted) return;
      setState(() {
        _giveawayHistory = history;
        _isLoadingGiveaway = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingGiveaway = false;
        _errorGiveaway = 'Error loading giveaway history: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text('Your history with ${widget.userName}'),
          backgroundColor: const Color(0xFF00897B),
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Borrow'),
              Tab(text: 'Rent'),
              Tab(text: 'Trade'),
              Tab(text: 'Giveaway'),
            ],
          ),
        ),
        backgroundColor: Colors.grey[50],
        body: TabBarView(
          children: [
            _buildBorrowTab(),
            _buildRentTab(),
            _buildTradeTab(),
            _buildGiveawayTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildBorrowTab() {
    if (_isLoadingBorrow) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorBorrow != null) {
      return _buildErrorState(_errorBorrow!, onRetry: _loadBorrowHistory);
    }
    if (_borrowHistory.isEmpty) {
      return _buildEmptyState(
        icon: Icons.shopping_bag_outlined,
        message: 'No completed borrow transactions with this user yet.',
      );
    }
    return RefreshIndicator(
      onRefresh: _loadBorrowHistory,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _borrowHistory.length,
        itemBuilder: (context, index) {
          final item = _borrowHistory[index];
          return _buildBorrowCard(item);
        },
      ),
    );
  }

  Widget _buildRentTab() {
    if (_isLoadingRent) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorRent != null) {
      return _buildErrorState(_errorRent!, onRetry: _loadRentHistory);
    }
    if (_rentHistory.isEmpty) {
      return _buildEmptyState(
        icon: Icons.home_outlined,
        message: 'No completed rentals with this user yet.',
      );
    }
    return RefreshIndicator(
      onRefresh: _loadRentHistory,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _rentHistory.length,
        itemBuilder: (context, index) {
          final item = _rentHistory[index];
          return _buildRentCard(item);
        },
      ),
    );
  }

  Widget _buildTradeTab() {
    if (_isLoadingTrade) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorTrade != null) {
      return _buildErrorState(_errorTrade!, onRetry: _loadTradeHistory);
    }
    if (_tradeHistory.isEmpty) {
      return _buildEmptyState(
        icon: Icons.swap_horiz_outlined,
        message: 'No completed trades with this user yet.',
      );
    }
    return RefreshIndicator(
      onRefresh: _loadTradeHistory,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _tradeHistory.length,
        itemBuilder: (context, index) {
          final item = _tradeHistory[index];
          return _buildTradeCard(item);
        },
      ),
    );
  }

  Widget _buildGiveawayTab() {
    if (_isLoadingGiveaway) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorGiveaway != null) {
      return _buildErrorState(_errorGiveaway!, onRetry: _loadGiveawayHistory);
    }
    if (_giveawayHistory.isEmpty) {
      return _buildEmptyState(
        icon: Icons.card_giftcard_outlined,
        message: 'No giveaways with this user yet.',
      );
    }
    return RefreshIndicator(
      onRefresh: _loadGiveawayHistory,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _giveawayHistory.length,
        itemBuilder: (context, index) {
          final item = _giveawayHistory[index];
          return _buildGiveawayCard(item);
        },
      ),
    );
  }

  Widget _buildBorrowCard(_BorrowHistoryItem item) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: const Icon(
          Icons.shopping_bag_outlined,
          color: Color(0xFF00897B),
        ),
        title: Text(
          item.itemTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          'Lender: ${item.lenderName}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: item.isRated
            ? const Chip(
                label: Text('Rated', style: TextStyle(fontSize: 11)),
                backgroundColor: Color(0xFFE0F2F1),
              )
            : TextButton(
                onPressed: () => _rateBorrowTransaction(item),
                child: const Text('Rate'),
              ),
      ),
    );
  }

  Widget _buildRentCard(_RentHistoryItem item) {
    // Show the other user's role (opposite of current user's role)
    final roleLabel = item.isOwner ? 'Renter' : 'Owner';
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: const Icon(Icons.home_outlined, color: Color(0xFF00897B)),
        title: Text(
          item.itemTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '$roleLabel: ${item.otherUserName}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: item.isRated
            ? const Chip(
                label: Text('Rated', style: TextStyle(fontSize: 11)),
                backgroundColor: Color(0xFFE0F2F1),
              )
            : TextButton(
                onPressed: () => _rateRentalTransaction(item),
                child: const Text('Rate'),
              ),
      ),
    );
  }

  Widget _buildTradeCard(_TradeHistoryItem item) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: const Icon(
          Icons.swap_horiz_outlined,
          color: Color(0xFF00897B),
        ),
        title: Text(
          item.itemTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          'Trade with ${item.otherUserName}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: item.isRated
            ? const Chip(
                label: Text('Rated', style: TextStyle(fontSize: 11)),
                backgroundColor: Color(0xFFE0F2F1),
              )
            : TextButton(
                onPressed: () => _rateTradeTransaction(item),
                child: const Text('Rate'),
              ),
      ),
    );
  }

  Widget _buildGiveawayCard(_GiveawayHistoryItem item) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: const Icon(
          Icons.card_giftcard_outlined,
          color: Color(0xFF00897B),
        ),
        title: Text(
          item.itemTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          'Giveaway with ${item.otherUserName}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: item.isRated
            ? const Chip(
                label: Text('Rated', style: TextStyle(fontSize: 11)),
                backgroundColor: Color(0xFFE0F2F1),
              )
            : TextButton(
                onPressed: () => _rateGiveawayTransaction(item),
                child: const Text('Rate'),
              ),
      ),
    );
  }

  Future<void> _rateBorrowTransaction(_BorrowHistoryItem item) async {
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final currentUserId = authProvider.user?.uid;
      if (currentUserId == null) return;

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => SubmitRatingScreen(
            ratedUserId: item.lenderId,
            ratedUserName: item.lenderName,
            context: RatingContext.borrow,
            transactionId: item.requestId,
            role: 'borrower',
          ),
        ),
      );

      await _loadBorrowHistory();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error launching rating: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _rateRentalTransaction(_RentHistoryItem item) async {
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final currentUserId = authProvider.user?.uid;
      if (currentUserId == null) return;

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => SubmitRatingScreen(
            ratedUserId: widget.userId,
            ratedUserName: widget.userName,
            context: RatingContext.rental,
            transactionId: item.requestId,
            role: item.isOwner ? 'owner' : 'renter',
          ),
        ),
      );

      await _loadRentHistory();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error launching rating: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _rateTradeTransaction(_TradeHistoryItem item) async {
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final currentUserId = authProvider.user?.uid;
      if (currentUserId == null) return;

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => SubmitRatingScreen(
            ratedUserId: widget.userId,
            ratedUserName: widget.userName,
            context: RatingContext.trade,
            transactionId: item.offerId,
            role: 'trader',
          ),
        ),
      );

      await _loadTradeHistory();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error launching rating: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _rateGiveawayTransaction(_GiveawayHistoryItem item) async {
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final currentUserId = authProvider.user?.uid;
      if (currentUserId == null) return;

      // Determine role based on whether current user is donor or claimant
      final role = 'donation';

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => SubmitRatingScreen(
            ratedUserId: widget.userId,
            ratedUserName: widget.userName,
            context: RatingContext.giveaway,
            transactionId: item.claimId,
            role: role,
          ),
        ),
      );

      await _loadGiveawayHistory();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error launching rating: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildEmptyState({required IconData icon, required String message}) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 80),
        Center(
          child: Column(
            children: [
              Icon(icon, size: 56, color: Colors.grey[400]),
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildErrorState(String error, {required VoidCallback onRetry}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red[300]),
            const SizedBox(height: 12),
            Text(
              error,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.red[700]),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: onRetry,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00897B),
                foregroundColor: Colors.white,
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _BorrowHistoryItem {
  final String requestId;
  final String itemTitle;
  final String lenderId;
  final String lenderName;
  final bool isRated;

  _BorrowHistoryItem({
    required this.requestId,
    required this.itemTitle,
    required this.lenderId,
    required this.lenderName,
    required this.isRated,
  });
}

class _RentHistoryItem {
  final String requestId;
  final String itemTitle;
  final bool isOwner;
  final String status;
  final String otherUserName;
  final bool isRated;

  _RentHistoryItem({
    required this.requestId,
    required this.itemTitle,
    required this.isOwner,
    required this.status,
    required this.otherUserName,
    required this.isRated,
  });
}

class _TradeHistoryItem {
  final String offerId;
  final String itemTitle;
  final String otherUserName;
  final String status;
  final bool isRated;

  _TradeHistoryItem({
    required this.offerId,
    required this.itemTitle,
    required this.otherUserName,
    required this.status,
    required this.isRated,
  });
}

class _GiveawayHistoryItem {
  final String claimId;
  final String itemTitle;
  final String otherUserName;
  final String status;
  final bool isRated;

  _GiveawayHistoryItem({
    required this.claimId,
    required this.itemTitle,
    required this.otherUserName,
    required this.status,
    required this.isRated,
  });
}
