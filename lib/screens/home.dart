import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/firestore_service.dart';
import '../providers/user_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/item_provider.dart';
import '../models/user_model.dart';
import '../reusable_widgets/bottom_nav_bar_widget.dart';
import '../reusable_widgets/offline_banner_widget.dart';
import '../reusable_widgets/share&exchange.dart';
import '../services/presence_service.dart';
import '../services/local_notifications_service.dart';
import '../apptutorial/home_tutorial.dart'
    show HomeTutorial, createTutorialKeys;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'dart:ui';
import 'package:shared_preferences/shared_preferences.dart';
import 'rental/active_rental_detail_screen.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => HomePageState();
}

class HomePageState extends State<HomePage> {
  int _selectedIndex = 0;
  final PresenceService _presenceService = PresenceService();
  int _pendingRequests = 0;
  int _itemsBorrowed = 0;
  int _dueSoon = 0;
  int _myLendersCount = 0;
  // Rental stats (as renter)
  int _pendingRentalRequests = 0;
  int _activeRentals = 0;
  // Rental stats (as owner)
  int _pendingRentalRequestsToReview = 0;
  int _activeRentalsAsOwner = 0;
  bool _isFabOpen = false;
  bool _isLoadingAllActivity = false;
  List<Map<String, dynamic>> _allActivities = [];
  String _selectedActivityFilter = 'all';
  bool _dueBannerDismissed = false;
  // Minimal info for due-soon banner
  final List<_DueItem> _dueSoonItems = <_DueItem>[];
  DateTime? _hideDueBannerUntil;
  bool _statsLoading = false;
  bool _showTutorial = false;

  // Tutorial target keys
  final List<GlobalKey> _tutorialKeys = createTutorialKeys();

  // Helper to get the effective role (toggle value for "both" users, actual role otherwise)
  // Effective role is always both in the unified approach

  @override
  void initState() {
    super.initState();
    // Load items when screen loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final chatProvider = Provider.of<ChatProvider>(context, listen: false);
      final currentUser = userProvider.currentUser;
      if (currentUser != null) {
        final itemProvider = Provider.of<ItemProvider>(context, listen: false);
        itemProvider.loadMyItems(currentUser.uid);
        itemProvider.loadBorrowerActivity(currentUser.uid);
        if (!kIsWeb) {
          _rescheduleBorrowerReminders(currentUser.uid, currentUser.fullName);
          // Check and schedule overdue notifications
          _checkAndScheduleOverdueNotifications(
            currentUser.uid,
            currentUser.fullName,
          );
          // Check for missed notifications (fallback for devices that block AlarmManager)
          _checkMissedNotifications(currentUser.uid, currentUser.fullName);
        }
        setState(() {
          _statsLoading = true;
        });
        _loadBorrowerStats(currentUser.uid);
        _loadRentalStats(currentUser.uid);
        // Load all activities (borrow, rent, trade, donate)
        _loadAllActivities(currentUser.uid);
        // Check for overdue items and create Firestore notifications
        _checkOverdueItems();
      }
      if (authProvider.isAuthenticated && authProvider.user != null) {
        chatProvider.setupConversationsStream(authProvider.user!.uid);
        // Start presence tracking for online status
        _presenceService.startPresenceTracking(authProvider.user!.uid);
        // Persist current user for background worker to access
        if (!kIsWeb) {
          _persistCurrentUserForBackground(currentUser);
        }
      }
    });
    _loadDueBannerPreference();
    _checkTutorialStatus();
  }

  Future<void> _checkTutorialStatus() async {
    final hasBeenShown = await HomeTutorial.hasBeenShown();
    if (!hasBeenShown && mounted) {
      // Delay to ensure UI is fully rendered
      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) {
        setState(() {
          _showTutorial = true;
        });
      }
    }
  }

  Future<void> _loadDueBannerPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final int? ms = prefs.getInt('hide_due_banner_until');
      if (ms != null) {
        final dt = DateTime.fromMillisecondsSinceEpoch(ms);
        if (mounted) {
          setState(() {
            _hideDueBannerUntil = dt;
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _rescheduleBorrowerReminders(
    String userId,
    String borrowerName,
  ) async {
    try {
      await LocalNotificationsService().initialize();
      final service = FirestoreService();
      final items = await service.getBorrowedItemsByBorrower(userId);
      for (final data in items) {
        final String itemId = data['id'] as String;
        final String itemTitle = (data['title'] ?? '') as String;
        final Timestamp? ts = data['returnDate'] as Timestamp?;
        if (ts == null) continue;
        final DateTime dueLocal = ts.toDate().toLocal();
        if (dueLocal.isAfter(DateTime.now())) {
          await LocalNotificationsService().scheduleReturnReminders(
            itemId: itemId,
            itemTitle: itemTitle,
            returnDateLocal: dueLocal,
            borrowerName: borrowerName,
          );
        }
      }
    } catch (_) {
      // No-op: best-effort scheduling
    }
  }

  Future<void> _checkAndScheduleOverdueNotifications(
    String userId,
    String userName,
  ) async {
    try {
      await LocalNotificationsService().checkAndScheduleOverdueNotifications(
        userId: userId,
        userName: userName,
      );
      // Also check rental overdue notifications
      await LocalNotificationsService()
          .checkAndScheduleRentalOverdueNotifications(
            userId: userId,
            userName: userName,
          );
    } catch (_) {
      // Best-effort; don't fail if notification scheduling fails
    }
  }

  Future<void> _checkOverdueItems() async {
    try {
      final service = FirestoreService();
      await service.checkAndNotifyOverdueItems();
    } catch (_) {
      // Best-effort; don't fail if overdue check fails
    }
  }

  Future<void> _checkMissedNotifications(String userId, String userName) async {
    try {
      await LocalNotificationsService().checkAndShowMissedNotifications(
        userId: userId,
        userName: userName,
      );
    } catch (_) {
      // Best-effort; don't fail if missed notification check fails
    }
  }

  Future<void> _persistCurrentUserForBackground(UserModel? user) async {
    try {
      if (user == null) return;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('current_user_uid', user.uid);
      await prefs.setString('current_user_name', user.fullName);
    } catch (_) {}
  }

  Future<void> _loadAllActivities(String userId) async {
    setState(() {
      _isLoadingAllActivity = true;
    });

    try {
      final service = FirestoreService();
      final allActivities = <Map<String, dynamic>>[];

      // 1. Borrow activities
      final pendingBorrow = await service.getPendingBorrowRequestsForBorrower(
        userId,
      );
      for (final req in pendingBorrow) {
        allActivities.add({
          'type': 'borrow',
          'subtype': 'pending',
          'title': (req['itemTitle'] ?? 'Item').toString(),
          'subtitle': 'Borrow request pending',
          'icon': Icons.shopping_cart_outlined,
          'iconColor': Colors.orange,
          'status': 'pending',
          'createdAt': req['createdAt'],
          'itemId': req['itemId'],
          'requestId': req['id'],
        });
      }

      final borrowed = await service.getBorrowedItemsByBorrower(userId);
      for (final item in borrowed) {
        allActivities.add({
          'type': 'borrow',
          'subtype': 'active',
          'title': (item['title'] ?? 'Item').toString(),
          'subtitle': 'Currently borrowed',
          'icon': Icons.check_circle_outline,
          'iconColor': Colors.green,
          'status': 'approved',
          'createdAt': item['borrowedAt'] ?? item['createdAt'],
          'itemId': item['id'],
        });
      }

      // 2. Rent activities
      final pendingRent = await service.getPendingRentalRequestsForRenter(
        userId,
      );
      for (final req in pendingRent) {
        allActivities.add({
          'type': 'rent',
          'subtype': 'pending',
          'title': (req['itemTitle'] ?? 'Rental Item').toString(),
          'subtitle': 'Rental request pending',
          'icon': Icons.attach_money,
          'iconColor': Colors.blue,
          'status': 'pending',
          'createdAt': req['createdAt'],
          'requestId': req['id'],
          'listingId': req['listingId'],
        });
      }

      final rentRequests = await service.getRentalRequestsByUser(
        userId,
        asOwner: false,
      );
      for (final req in rentRequests) {
        final status = (req['status'] ?? 'requested').toString().toLowerCase();
        // Active rentals include: ownerapproved, active, returninitiated
        if (status == 'ownerapproved' ||
            status == 'active' ||
            status == 'returninitiated') {
          allActivities.add({
            'type': 'rent',
            'subtype': 'active',
            'title': (req['itemTitle'] ?? 'Rental Item').toString(),
            'subtitle': 'Rental active',
            'icon': Icons.check_circle_outline,
            'iconColor': Colors.green,
            'status': status,
            'createdAt': req['createdAt'],
            'requestId': req['id'],
            'listingId': req['listingId'],
          });
        }
      }

      // 3. Trade activities
      final tradeOffers = await service.getPendingTradeOffersForUser(userId);
      for (final offer in tradeOffers) {
        allActivities.add({
          'type': 'trade',
          'subtype': 'pending',
          'title': (offer['originalOfferedItemName'] ?? 'Trade Item')
              .toString(),
          'subtitle': 'Trade offer pending',
          'icon': Icons.swap_horiz,
          'iconColor': Colors.purple,
          'status': 'pending',
          'createdAt': offer['createdAt'],
          'offerId': offer['id'],
          'tradeItemId': offer['tradeItemId'],
        });
      }

      final allTradeOffers = await service.getTradeOffersByUser(userId);
      for (final offer in allTradeOffers) {
        final status = (offer['status'] ?? 'pending').toString();
        if (status == 'approved' || status == 'completed') {
          allActivities.add({
            'type': 'trade',
            'subtype': 'completed',
            'title': (offer['originalOfferedItemName'] ?? 'Trade Item')
                .toString(),
            'subtitle': 'Trade completed',
            'icon': Icons.check_circle_outline,
            'iconColor': Colors.green,
            'status': status,
            'createdAt': offer['createdAt'],
            'offerId': offer['id'],
            'tradeItemId': offer['tradeItemId'],
          });
        }
      }

      // 4. Donate/Giveaway activities
      final claimRequests = await service.getClaimRequestsByClaimant(userId);
      for (final claim in claimRequests) {
        final status = (claim['status'] ?? 'pending').toString();
        // Fetch giveaway title if available
        String giveawayTitle = 'Giveaway Item';
        final giveawayId = (claim['giveawayId'] ?? '').toString();
        if (giveawayId.isNotEmpty) {
          try {
            final giveaway = await service.getGiveaway(giveawayId);
            if (giveaway != null) {
              giveawayTitle = (giveaway['title'] ?? 'Giveaway Item').toString();
            }
          } catch (_) {
            // Use default if fetch fails
          }
        }
        allActivities.add({
          'type': 'donate',
          'subtype': status == 'approved' ? 'claimed' : 'pending',
          'title': giveawayTitle,
          'subtitle': status == 'approved'
              ? 'Giveaway claimed'
              : 'Claim request pending',
          'icon': status == 'approved' ? Icons.card_giftcard : Icons.pending,
          'iconColor': status == 'approved' ? Colors.green : Colors.orange,
          'status': status,
          'createdAt': claim['createdAt'],
          'claimId': claim['id'],
          'giveawayId': giveawayId,
        });
      }

      // Sort by date (most recent first)
      allActivities.sort((a, b) {
        final aDate = _parseActivityDate(a['createdAt']);
        final bDate = _parseActivityDate(b['createdAt']);
        if (aDate == null && bDate == null) return 0;
        if (aDate == null) return 1;
        if (bDate == null) return -1;
        return bDate.compareTo(aDate); // Descending order
      });

      if (mounted) {
        setState(() {
          _allActivities = allActivities;
          _isLoadingAllActivity = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingAllActivity = false;
        });
      }
    }
  }

  DateTime? _parseActivityDate(dynamic dateValue) {
    if (dateValue == null) return null;
    if (dateValue is DateTime) return dateValue;
    if (dateValue is Timestamp) return dateValue.toDate();
    if (dateValue is int) {
      return DateTime.fromMillisecondsSinceEpoch(dateValue);
    }
    return null;
  }

  Future<void> _loadBorrowerStats(String userId) async {
    try {
      final service = FirestoreService();
      // Pending requests for borrower
      final pendingItemIds = await service
          .getPendingRequestedItemIdsForBorrower(userId);
      // Borrowed items list
      final borrowedItems = await service.getBorrowedItemsByBorrower(userId);
      final now = DateTime.now();
      // Due soon: due within next 3 days or overdue
      int dueSoonCount = 0;
      _dueSoonItems.clear();

      // Calculate unique lenders count
      final lenderIds = <String>{};

      for (final data in borrowedItems) {
        // Count unique lenders
        final lenderId = (data['lenderId'] ?? '').toString();
        if (lenderId.isNotEmpty) {
          lenderIds.add(lenderId);
        }

        // Check if due soon
        final ts = data['returnDate'];
        if (ts == null) continue;
        DateTime due;
        try {
          if (ts is DateTime) {
            due = ts;
          } else if (ts is int) {
            due = DateTime.fromMillisecondsSinceEpoch(ts);
          } else {
            // Firestore Timestamp
            // ignore: avoid_dynamic_calls
            due = (ts as dynamic).toDate();
          }
        } catch (_) {
          continue;
        }
        if (due.isBefore(now.add(const Duration(days: 3)))) {
          dueSoonCount++;
          _dueSoonItems.add(
            _DueItem(
              id: (data['id'] ?? '').toString(),
              title: (data['title'] ?? 'Item').toString(),
              dueLocal: due.toLocal(),
            ),
          );
        }
      }
      _dueSoonItems.sort((a, b) => a.dueLocal.compareTo(b.dueLocal));

      if (mounted) {
        setState(() {
          _pendingRequests = pendingItemIds.length;
          _itemsBorrowed = borrowedItems.length;
          _dueSoon = dueSoonCount;
          _myLendersCount = lenderIds.length;
        });
      }
    } catch (_) {
      // Leave defaults on error
    }
  }

  Future<void> _loadRentalStats(String userId) async {
    try {
      final service = FirestoreService();

      // Load rental stats as renter
      final pendingRentals = await service.getPendingRentalRequestsForRenter(
        userId,
      );
      final allRentalsAsRenter = await service.getRentalRequestsByUser(
        userId,
        asOwner: false,
      );
      final activeRentalsAsRenter = allRentalsAsRenter.where((req) {
        final status = (req['status'] ?? 'requested').toString();
        return status == 'approved' ||
            status == 'active' ||
            status == 'ownerapproved' ||
            status == 'renterpaid';
      }).length;

      // Load rental stats as owner
      final allRentalsAsOwner = await service.getRentalRequestsByUser(
        userId,
        asOwner: true,
      );
      final pendingRentalsToReview = allRentalsAsOwner.where((req) {
        final status = (req['status'] ?? 'requested').toString();
        return status == 'requested';
      }).length;
      final activeRentalsAsOwner = allRentalsAsOwner.where((req) {
        final status = (req['status'] ?? 'requested').toString();
        return status == 'approved' ||
            status == 'active' ||
            status == 'ownerapproved' ||
            status == 'renterpaid';
      }).length;

      if (mounted) {
        setState(() {
          _pendingRentalRequests = pendingRentals.length;
          _activeRentals = activeRentalsAsRenter;
          _pendingRentalRequestsToReview = pendingRentalsToReview;
          _activeRentalsAsOwner = activeRentalsAsOwner;
          _statsLoading = false;
        });
      }
    } catch (_) {
      // Leave defaults on error
      if (mounted) {
        setState(() {
          _statsLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    // Stop presence tracking when leaving home screen
    _presenceService.stopPresenceTracking();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final itemProvider = Provider.of<ItemProvider>(context);
    // No role toggling needed; everyone is both

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA), // Soft light background
      body: Stack(
        children: [
          SafeArea(
            child: CustomScrollView(
              slivers: [
                // Offline Banner
                const SliverToBoxAdapter(child: OfflineBannerWidget()),
                // Top Header Bar - Converted to SliverAppBar
                SliverAppBar(
                  floating: true,
                  pinned: false,
                  snap: true,
                  elevation: 0,
                  backgroundColor: const Color(0xFFF5F7FA),
                  automaticallyImplyLeading: false,
                  flexibleSpace: Container(
                    key:
                        _tutorialKeys[0], // Home screen key - on Container for RenderBox
                    child: _buildHeader(itemProvider),
                  ),
                  toolbarHeight: 64,
                ),

                // Inline Due Soon Banner
                if (_dueSoon > 0 &&
                    !_dueBannerDismissed &&
                    !_isDueBannerTemporarilyHidden())
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: _buildDueSoonBanner(),
                    ),
                  ),

                // Welcome Banner
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 16),
                        Container(
                          key: _tutorialKeys[2], // Welcome banner key
                          child: _buildWelcomeBanner(UserRole.both),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),

                // Dashboard Cards (with skeleton + fade-in)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Container(
                      key: _tutorialKeys[3], // Stats cards key
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        switchInCurve: Curves.easeOut,
                        switchOutCurve: Curves.easeOut,
                        child: _statsLoading
                            ? _buildStatsSkeleton()
                            : _buildStatsCards(UserRole.both),
                      ),
                    ),
                  ),
                ),

                const SliverToBoxAdapter(child: SizedBox(height: 24)),

                // Recent Activity
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Container(
                      key: _tutorialKeys[4], // Recent activity key
                      child: _buildRecentActivity(UserRole.both, itemProvider),
                    ),
                  ),
                ),

                const SliverToBoxAdapter(child: SizedBox(height: 80)),
              ],
            ),
          ),
          if (_isFabOpen) ...[
            // Backdrop blur + tap-away barrier
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() {
                    _isFabOpen = false;
                  });
                },
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 6.0, sigmaY: 6.0),
                  child: Container(color: Colors.black.withOpacity(0.20)),
                ),
              ),
            ),
            // Actions positioned to the left of the FAB
            Positioned(
              right: 148,
              bottom:
                  MediaQuery.of(context).padding.bottom +
                  120, // Dynamic spacing above nav bar (nav bar ~80px + padding)
              child: _FabActions(
                onSelect: (type) {
                  HapticFeedback.mediumImpact();
                  setState(() {
                    _isFabOpen = false;
                  });

                  // Check verification status
                  final userProvider = Provider.of<UserProvider>(
                    context,
                    listen: false,
                  );
                  final isVerified =
                      userProvider.currentUser?.isVerified ?? false;

                  if (!isVerified) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text(
                          'Your account is pending admin verification. You can browse items but cannot post or transact yet.',
                        ),
                        backgroundColor: Colors.orange.shade700,
                        duration: const Duration(seconds: 4),
                      ),
                    );
                    return;
                  }

                  if (type == 'rent') {
                    // Go to Rental Listing Editor (create a rent listing)
                    Navigator.pushNamed(context, '/rental/listing-editor');
                  } else if (type == 'lend') {
                    Navigator.pushNamed(
                      context,
                      '/list-item',
                      arguments: {'listingType': type},
                    );
                  } else if (type == 'trade') {
                    // Go to Add Trade Item Screen
                    Navigator.pushNamed(context, '/trade/add-item');
                  } else if (type == 'donate') {
                    // Go to Add Giveaway Screen
                    Navigator.pushNamed(context, '/giveaway/add');
                  } else {
                    Navigator.pushNamed(
                      context,
                      '/list-item',
                      arguments: {'listingType': type},
                    );
                  }
                },
              ),
            ),
          ],
          // Tutorial overlay
          if (_showTutorial) _buildTutorialOverlay(),
        ],
      ),
      floatingActionButton: Container(
        key: _tutorialKeys[5], // FAB key
        child: FloatingActionButton.extended(
          onPressed: () {
            HapticFeedback.selectionClick();
            setState(() {
              _isFabOpen = !_isFabOpen;
            });
          },
          backgroundColor: const Color(0xFF00897B),
          foregroundColor: Colors.white,
          icon: AnimatedCrossFade(
            duration: const Duration(milliseconds: 180),
            firstChild: const Icon(Icons.add),
            secondChild: const Icon(Icons.close),
            crossFadeState: _isFabOpen
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstCurve: Curves.easeOut,
            secondCurve: Curves.easeOut,
            sizeCurve: Curves.easeOut,
          ),
          label: Text(_isFabOpen ? 'Actions' : 'Create'),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      extendBody: true,
      extendBodyBehindAppBar: false,
      bottomNavigationBar: Container(
        key: _tutorialKeys[6], // Bottom nav key
        child: BottomNavBarWidget(
          selectedIndex: _selectedIndex,
          onTap: (index) {
            setState(() {
              _selectedIndex = index;
            });
          },
          navigationContext: context,
        ),
      ),
    );
  }

  Widget _buildHeader(ItemProvider itemProvider) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          // App Logo/Title with Gradient
          ShaderMask(
            shaderCallback: (bounds) => const LinearGradient(
              colors: [
                Color(0xFF00897B), // Teal
                Color(0xFF26A69A), // Light Teal
                Color(0xFF4DD0E1), // Cyan
              ],
            ).createShader(bounds),
            child: const Text(
              'BRIDGE',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 24,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const Spacer(),

          // Search removed from Home (search lives on Borrow screen)

          // Header actions container for tutorial
          Container(
            key: _tutorialKeys[1], // Header actions key
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Notifications Icon with Badge
                _buildNotificationsIcon(),

                // My Listings button
                Semantics(
                  label: 'My Listings',
                  button: true,
                  child: IconButton(
                    icon: const Icon(Icons.inventory_2_outlined, size: 28),
                    tooltip: 'My Listings',
                    constraints: const BoxConstraints(
                      minWidth: 48, // Increased for better accessibility
                      minHeight: 48,
                    ),
                    padding: const EdgeInsets.all(10),
                    onPressed: () {
                      Navigator.pushNamed(context, '/my-listings');
                    },
                  ),
                ),
                // Settings Icon
                Semantics(
                  label: 'Settings',
                  button: true,
                  child: IconButton(
                    icon: const Icon(Icons.settings_outlined, size: 28),
                    onPressed: () {
                      Navigator.pushNamed(context, '/settings');
                    },
                    tooltip: 'Settings',
                    constraints: const BoxConstraints(
                      minWidth: 48, // Increased for better accessibility
                      minHeight: 48,
                    ),
                    padding: const EdgeInsets.all(10),
                  ),
                ),
              ],
            ),
          ),
          // List Item button moved to Floating Action Button
        ],
      ),
    );
  }

  Widget _buildTutorialOverlay() {
    if (!_showTutorial) return const SizedBox.shrink();

    return HomeTutorial(
      targetKeys: _tutorialKeys,
      onComplete: () {
        setState(() {
          _showTutorial = false;
        });
      },
      onSkip: () {
        setState(() {
          _showTutorial = false;
        });
      },
    );
  }

  bool _isDueBannerTemporarilyHidden() {
    final until = _hideDueBannerUntil;
    if (until == null) return false;
    return DateTime.now().isBefore(until);
  }

  Widget _buildDueSoonBanner() {
    final items = _dueSoonItems.take(3).toList();
    return Dismissible(
      key: const ValueKey('due-soon-banner'),
      direction: DismissDirection.endToStart,
      onDismissed: (_) async {
        try {
          final until = DateTime.now().add(const Duration(hours: 24));
          final prefs = await SharedPreferences.getInstance();
          await prefs.setInt(
            'hide_due_banner_until',
            until.millisecondsSinceEpoch,
          );
          if (mounted) {
            setState(() {
              _dueBannerDismissed = true;
              _hideDueBannerUntil = until;
            });
          }
        } catch (_) {
          if (mounted) {
            setState(() {
              _dueBannerDismissed = true;
            });
          }
        }
      },
      background: Container(
        margin: const EdgeInsets.only(top: 8, bottom: 16),
        decoration: BoxDecoration(
          color: Colors.red.withOpacity(0.9),
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: const Icon(Icons.close, color: Colors.white),
      ),
      child: Semantics(
        container: true,
        liveRegion: true,
        label: _dueSoon == 1
            ? 'Due soon banner. 1 item is due soon.'
            : 'Due soon banner. $_dueSoon items are due soon.',
        child: Container(
          margin: const EdgeInsets.only(top: 8, bottom: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF8E1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFFFECB3)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.access_time, color: Colors.orange),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _dueSoon == 1
                              ? '1 item is due soon'
                              : '$_dueSoon items are due soon',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.black,
                          ),
                        ),
                        const SizedBox(height: 6),
                        for (final it in items)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    it.title,
                                    style: TextStyle(
                                      color: Colors.grey[800],
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    _formatDue(it.dueLocal),
                                    style: TextStyle(
                                      color: Colors.grey[700],
                                      fontSize: 13,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (_dueSoonItems.length > items.length)
                          Text(
                            '+${_dueSoonItems.length - items.length} more',
                            style: TextStyle(
                              color: Colors.grey[700],
                              fontSize: 13,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Flexible(
                    child: TextButton.icon(
                      onPressed: () async {
                        if (_dueSoonItems.isEmpty) return;
                        final earliest = _dueSoonItems.first;
                        try {
                          await LocalNotificationsService().scheduleNudge(
                            itemId: earliest.id,
                            itemTitle: earliest.title,
                          );
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'We will remind you again later.',
                                ),
                              ),
                            );
                          }
                        } catch (_) {}
                      },
                      icon: const Icon(Icons.snooze),
                      label: const Text('Remind me later'),
                    ),
                  ),
                  Flexible(
                    child: TextButton.icon(
                      onPressed: () {
                        Navigator.pushNamed(context, '/upcoming-reminders');
                      },
                      icon: const Icon(Icons.calendar_today),
                      label: const Text('View Calendar'),
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      try {
                        final until = DateTime.now().add(
                          const Duration(hours: 24),
                        );
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setInt(
                          'hide_due_banner_until',
                          until.millisecondsSinceEpoch,
                        );
                        if (mounted) {
                          setState(() {
                            _dueBannerDismissed = true;
                            _hideDueBannerUntil = until;
                          });
                        }
                      } catch (_) {
                        if (mounted) {
                          setState(() {
                            _dueBannerDismissed = true;
                          });
                        }
                      }
                    },
                    child: const Text('Dismiss'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDue(DateTime due) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dueDay = DateTime(due.year, due.month, due.day);
    if (dueDay == today) {
      final hh = due.hour.toString().padLeft(2, '0');
      final mm = due.minute.toString().padLeft(2, '0');
      return 'today $hh:$mm';
    }
    if (dueDay == today.add(const Duration(days: 1))) {
      final hh = due.hour.toString().padLeft(2, '0');
      final mm = due.minute.toString().padLeft(2, '0');
      return 'tomorrow $hh:$mm';
    }
    return '${due.month}/${due.day}';
  }

  // Role toggle removed in unified-role approach
  Widget _buildNotificationsIcon() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final String? uid = authProvider.user?.uid;
    if (uid == null) {
      return IconButton(
        icon: const Icon(Icons.notifications_outlined, size: 28),
        onPressed: () {},
      );
    }

    final query = FirebaseFirestore.instance
        .collection('notifications')
        .where('toUserId', isEqualTo: uid)
        .where('status', isEqualTo: 'unread')
        .limit(20);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        final count = snapshot.hasData ? snapshot.data!.docs.length : 0;
        return Semantics(
          label: count > 0
              ? 'Notifications, $count unread'
              : 'Notifications, none unread',
          button: true,
          child: InkWell(
            onTap: () {
              Navigator.pushNamed(context, '/notifications');
            },
            borderRadius: BorderRadius.circular(24),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                IconButton(
                  icon: const Icon(Icons.notifications_outlined, size: 28),
                  onPressed: () {
                    Navigator.pushNamed(context, '/notifications');
                  },
                  tooltip: 'Notifications',
                  constraints: const BoxConstraints(
                    minWidth: 48,
                    minHeight: 48,
                  ),
                  padding: const EdgeInsets.all(10),
                ),
                if (count > 0)
                  Positioned(
                    right: 6,
                    top: 6,
                    child: IgnorePointer(
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Colors.orange,
                          shape: BoxShape.circle,
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 20,
                          minHeight: 20,
                        ),
                        child: Text(
                          count > 9 ? '9+' : '$count',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildWelcomeBanner(UserRole role) {
    // Get current user's reputation score
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final currentUser = userProvider.currentUser;
    final reputationScore = currentUser?.reputationScore ?? 0.0;
    final reputationScoreText = reputationScore > 0
        ? reputationScore.toStringAsFixed(1)
        : '0.0';

    // Role-specific messages
    final String greeting;
    final String subtitle;
    final String motivationalText =
        'Share more, waste less, connect with neighbors';

    if (role == UserRole.lender) {
      greeting = 'Welcome back, Lender!';
      subtitle = 'Your items are helping your\ncommunity every day';
    } else {
      greeting = 'Welcome back!';
      subtitle =
          'Ready to borrow, rent, trade or donate from your\ncommunity today?';
    }

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF00897B), // Teal
            Color(0xFF26A69A), // Light Teal
            Color(0xFF4DD0E1), // Cyan
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00897B).withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
            spreadRadius: 0,
          ),
        ],
      ),
      child: Stack(
        children: [
          // Decorative circles in background
          Positioned(
            top: -20,
            right: -20,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.1),
              ),
            ),
          ),
          Positioned(
            bottom: -30,
            left: -30,
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.08),
              ),
            ),
          ),
          // Content
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final isNarrow = constraints.maxWidth < 420;
                  if (isNarrow) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            // Community icon illustration
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.people_outline,
                                color: Colors.white,
                                size: 28,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    greeting,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 28,
                                      fontWeight: FontWeight.bold,
                                      height: 1.2,
                                      letterSpacing: -0.5,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    subtitle,
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.95),
                                      fontSize: 15,
                                      height: 1.4,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        // Motivational subtext
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.eco_outlined,
                                color: Colors.white,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  motivationalText,
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.95),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    height: 1.3,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: () {
                            showExchangeOptions(context);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: const Color(0xFF00897B),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 16, // Increased for better touch target
                            ),
                            minimumSize: const Size(
                              120,
                              48,
                            ), // Minimum touch target
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 2,
                          ),
                          icon: const Icon(Icons.search_outlined, size: 20),
                          label: const Text(
                            'Browse Items',
                            style: TextStyle(
                              fontSize: 16, // Increased for readability
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    );
                  }
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                // Community icon illustration
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(
                                    Icons.people_outline,
                                    color: Colors.white,
                                    size: 28,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        greeting,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 28,
                                          fontWeight: FontWeight.bold,
                                          height: 1.2,
                                          letterSpacing: -0.5,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        subtitle,
                                        style: TextStyle(
                                          color: Colors.white.withOpacity(0.95),
                                          fontSize: 15,
                                          height: 1.4,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            // Motivational subtext
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.eco_outlined,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      motivationalText,
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.95),
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                        height: 1.3,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        onPressed: () {
                          showExchangeOptions(context);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: const Color(0xFF00897B),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 16, // Increased for better touch target
                          ),
                          minimumSize: const Size(
                            120,
                            48,
                          ), // Minimum touch target
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 2,
                        ),
                        icon: const Icon(Icons.search_outlined, size: 20),
                        label: const Text(
                          'Browse Items',
                          style: TextStyle(
                            fontSize: 16, // Increased for readability
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 20),
              Align(
                alignment: Alignment.centerRight,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.star_rounded,
                        color: Colors.amber,
                        size: 20,
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        'Your Reputation',
                        style: TextStyle(
                          color: Colors.grey,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        reputationScoreText,
                        style: const TextStyle(
                          color: Color(0xFF00897B),
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatsCards(UserRole role) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Compact at-a-glance stats row
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildMiniStat(
                icon: Icons.shopping_bag_outlined,
                label: 'Borrowed',
                value: _itemsBorrowed,
              ),
              _buildMiniStat(
                icon: Icons.home_work_outlined,
                label: 'Rentals',
                value: _activeRentals,
              ),
              _buildMiniStat(
                icon: Icons.hourglass_bottom_outlined,
                label: 'Pending',
                value: _pendingRequests + _pendingRentalRequests,
              ),
            ],
          ),
        ),

        // Row 1: Borrow Dashboard and Rental Dashboard
        Row(
          children: [
            Expanded(
              child: _buildDashboardCard(
                icon: Icons.shopping_cart_outlined,
                iconColor: const Color(0xFF42A5F5), // Blue
                title: 'Borrow Dashboard',
                subtitle: 'Browse Items to Borrow',
                onTap: () {
                  Navigator.pushNamed(context, '/borrow');
                },
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildDashboardCard(
                icon: Icons.home_outlined,
                iconColor: const Color(0xFF26A69A), // Teal
                title: 'Rental Dashboard',
                subtitle: 'View Rentals & Spaces',
                onTap: () {
                  Navigator.pushNamed(context, '/rent');
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        // Row 2: Trade Dashboard and Donate Dashboard
        Row(
          children: [
            Expanded(
              child: _buildDashboardCard(
                icon: Icons.swap_horiz,
                iconColor: const Color(0xFF9C27B0), // Purple
                title: 'Trade Dashboard',
                subtitle: 'View Trade Activity',
                onTap: () {
                  Navigator.pushNamed(context, '/trade');
                },
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildDashboardCard(
                icon: Icons.favorite_outlined,
                iconColor: const Color(0xFFEF5350), // Red/Pink
                title: 'Donate Dashboard',
                subtitle: 'View Donations',
                onTap: () {
                  Navigator.pushNamed(context, '/giveaway');
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        // Row 3: Pending Requests and Due Soon
        Row(
          children: [
            Expanded(
              child: _buildDashboardCard(
                icon: Icons.pending_outlined,
                iconColor: const Color(0xFFFF9800), // Orange
                title: 'Pending Requests',
                subtitle: 'View Your Requests',
                onTap: () {
                  Navigator.pushNamed(context, '/pending-requests');
                },
              ),
            ),
            const SizedBox(width: 16),
            Expanded(child: _buildDueSoonCard()),
          ],
        ),
      ],
    );
  }

  Widget _buildMiniStat({
    required IconData icon,
    required String label,
    required int value,
  }) {
    return Row(
      children: [
        Icon(icon, size: 20, color: const Color(0xFF00897B)),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$value',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1A1A1A),
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildShimmerContainer({
    double height = 16,
    double width = double.infinity,
    BorderRadius? radius,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 800),
      curve: Curves.easeInOut,
      height: height,
      width: width,
      decoration: BoxDecoration(
        color: Colors.grey[300],
        borderRadius: radius ?? BorderRadius.circular(12),
      ),
    );
  }

  Widget _buildStatsSkeleton() {
    Widget _skeletonCard() => Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: SizedBox(
        height: 160,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildShimmerContainer(
                  height: 44,
                  width: 44,
                  radius: BorderRadius.circular(12),
                ),
                _buildShimmerContainer(
                  height: 24,
                  width: 24,
                  radius: BorderRadius.circular(8),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _buildShimmerContainer(
              height: 18,
              width: 120,
              radius: BorderRadius.circular(8),
            ),
            const SizedBox(height: 8),
            _buildShimmerContainer(
              height: 14,
              width: 100,
              radius: BorderRadius.circular(8),
            ),
          ],
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // First row: Borrow and Rental Dashboard
        Row(
          children: [
            Expanded(child: _skeletonCard()),
            const SizedBox(width: 16),
            Expanded(child: _skeletonCard()),
          ],
        ),
        const SizedBox(height: 16),
        // Second row: Trade and Donate Dashboard
        Row(
          children: [
            Expanded(child: _skeletonCard()),
            const SizedBox(width: 16),
            Expanded(child: _skeletonCard()),
          ],
        ),
        const SizedBox(height: 16),
        // Third row: Pending Requests and Due Soon
        Row(
          children: [
            Expanded(child: _skeletonCard()),
            const SizedBox(width: 16),
            Expanded(child: _skeletonCard()),
          ],
        ),
      ],
    );
  }

  Widget _buildDashboardCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
  }) {
    return _DashboardCardWithAnimation(
      icon: icon,
      iconColor: iconColor,
      title: title,
      subtitle: subtitle,
      onTap: onTap,
    );
  }

  Widget _buildActivityFilterChip(String value, String label) {
    final bool isSelected = _selectedActivityFilter == value;
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: isSelected ? Colors.white : Colors.grey[800],
        ),
      ),
      selected: isSelected,
      onSelected: (selected) {
        if (!selected) return;
        setState(() {
          _selectedActivityFilter = value;
        });
      },
      selectedColor: const Color(0xFF00897B),
      backgroundColor: const Color(0xFFF1F4F6),
      pressElevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: isSelected
              ? const Color(0xFF00897B)
              : Colors.grey.withOpacity(0.2),
        ),
      ),
    );
  }

  Widget _buildDueSoonCard() {
    return _DashboardCardWithAnimation(
      icon: Icons.access_time_outlined,
      iconColor: const Color(0xFFFFB74D), // Amber
      title: 'Due Soon',
      subtitle: _dueSoon == 0
          ? 'No items due soon'
          : '$_dueSoon ${_dueSoon == 1 ? 'item' : 'items'} due soon',
      onTap: () {
        Navigator.pushNamed(context, '/due-soon-items-detail');
      },
    );
  }

  Widget _buildRecentActivity(UserRole role, ItemProvider itemProvider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF26A69A), Color(0xFF00897B)],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.history_outlined,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  role == UserRole.lender
                      ? 'Your Lending Activity'
                      : 'Your Activity',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.5,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
              ),
              if (role != UserRole.lender && _allActivities.isNotEmpty)
                TextButton.icon(
                  onPressed: () {
                    // Navigate to the dedicated All Activity screen
                    Navigator.pushNamed(context, '/activity/all');
                  },
                  icon: const Icon(Icons.arrow_forward, size: 16),
                  label: const Text('View All'),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF00897B),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Filter chips for activity types (borrow, rent, trade, donate)
        if (role != UserRole.lender && _allActivities.isNotEmpty)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Row(
              children: [
                _buildActivityFilterChip('all', 'All'),
                const SizedBox(width: 8),
                _buildActivityFilterChip('borrow', 'Borrow'),
                const SizedBox(width: 8),
                _buildActivityFilterChip('rent', 'Rent'),
                const SizedBox(width: 8),
                _buildActivityFilterChip('trade', 'Trade'),
                const SizedBox(width: 8),
                _buildActivityFilterChip('donate', 'Donate'),
              ],
            ),
          ),
        const SizedBox(height: 8),
        // Show different activities based on role
        if (role == UserRole.lender) ...[
          // Show user's listed items
          if (itemProvider.myItems.isEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.inventory_2_outlined,
                    size: 48,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No items listed yet',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[700],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tap the + button to list your first item',
                    style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          else
            ...itemProvider.myItems
                .take(3)
                .map(
                  (item) => Column(
                    children: [
                      _buildActivityItem(
                        icon: item.isAvailable
                            ? Icons.check_circle_outline
                            : Icons.info_outline,
                        iconColor: item.isAvailable
                            ? Colors.green
                            : Colors.orange,
                        title: item.title,
                        subtitle: 'Status: ${item.statusDisplay}',
                        status: item.statusDisplay.toLowerCase(),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
        ] else ...[
          Builder(
            builder: (context) {
              if (_isLoadingAllActivity) {
                return _buildActivitySkeleton();
              }

              if (_allActivities.isEmpty) {
                return Container(
                  padding: const EdgeInsets.all(24),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.06),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Icon(
                        Icons.inbox_outlined,
                        size: 48,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'No recent activity',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[700],
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Your borrow, rent, trade, and donate activities will appear here',
                        style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                );
              }

              // Apply simple type filter based on currently selected chip
              final filteredActivities = _selectedActivityFilter == 'all'
                  ? _allActivities
                  : _allActivities
                        .where(
                          (a) =>
                              (a['type'] as String?) == _selectedActivityFilter,
                        )
                        .toList();

              // If specific filter has no results, show a friendly empty state
              if (filteredActivities.isEmpty &&
                  _selectedActivityFilter != 'all') {
                String label;
                if (_selectedActivityFilter == 'trade') {
                  label = 'No trade activity yet';
                } else if (_selectedActivityFilter == 'borrow') {
                  label = 'No borrow activity yet';
                } else if (_selectedActivityFilter == 'rent') {
                  label = 'No rental activity yet';
                } else {
                  label = 'No activity yet for this category';
                }

                return Container(
                  padding: const EdgeInsets.all(24),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.06),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Icon(
                        Icons.inbox_outlined,
                        size: 48,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[700],
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                );
              }

              final widgets = <Widget>[];
              for (final activity in filteredActivities.take(5)) {
                final icon = activity['icon'] as IconData?;
                final iconColor = activity['iconColor'] as Color?;
                final title = (activity['title'] ?? '').toString();
                final subtitle = (activity['subtitle'] ?? '').toString();
                final status = (activity['status'] ?? '').toString();

                widgets.add(
                  _buildActivityItem(
                    icon: icon ?? Icons.info_outline,
                    iconColor: iconColor ?? Colors.grey,
                    title: title,
                    subtitle: subtitle,
                    status: status.isEmpty ? 'status' : status,
                    onTap: () {
                      _handleActivityTap(activity);
                    },
                  ),
                );
                widgets.add(const SizedBox(height: 12));
              }
              if (widgets.isNotEmpty) widgets.removeLast();
              return AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeOut,
                child: Column(
                  key: ValueKey('activity-content-${widgets.length}'),
                  children: widgets,
                ),
              );
            },
          ),
        ],
      ],
    );
  }

  Widget _buildActivitySkeleton() {
    Widget tile() => Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          _buildShimmerContainer(
            height: 44,
            width: 44,
            radius: BorderRadius.circular(12),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildShimmerContainer(
                  height: 16,
                  width: 180,
                  radius: BorderRadius.circular(8),
                ),
                const SizedBox(height: 8),
                _buildShimmerContainer(
                  height: 12,
                  width: 120,
                  radius: BorderRadius.circular(8),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return Column(children: [tile(), tile(), tile()]);
  }

  void _handleActivityTap(Map<String, dynamic> activity) {
    final type = activity['type'] as String;
    HapticFeedback.selectionClick();

    if (type == 'borrow') {
      if (activity['subtype'] == 'pending') {
        Navigator.pushNamed(context, '/pending-requests');
      } else {
        Navigator.pushNamed(context, '/borrowed-items-detail');
      }
    } else if (type == 'rent') {
      if (activity['subtype'] == 'pending') {
        Navigator.pushNamed(context, '/pending-requests');
      } else {
        // Active rental - navigate to active rental detail
        final requestId = activity['requestId'] as String?;
        if (requestId != null && requestId.isNotEmpty) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) =>
                  ActiveRentalDetailScreen(requestId: requestId),
            ),
          );
        } else {
          Navigator.pushNamed(context, '/pending-requests');
        }
      }
    } else if (type == 'trade') {
      Navigator.pushNamed(context, '/trade');
    } else if (type == 'donate') {
      Navigator.pushNamed(context, '/giveaway');
    }
  }

  Widget _buildActivityItem({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required String status,
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap:
            onTap ??
            () {
              HapticFeedback.selectionClick();
            },
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: iconColor.withOpacity(0.1),
                blurRadius: 10,
                offset: const Offset(0, 3),
                spreadRadius: 0,
              ),
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      iconColor.withOpacity(0.2),
                      iconColor.withOpacity(0.1),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: iconColor.withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: Icon(icon, color: iconColor, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 17, // Increased for readability
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                        letterSpacing: -0.2,
                        color: Color(0xFF1A1A1A), // Improved contrast
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 14, // Increased for readability
                        color: Colors.grey[700], // Improved contrast
                        height: 1.2,
                        fontWeight: FontWeight.w500,
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
                  gradient: LinearGradient(
                    colors: [iconColor, iconColor.withOpacity(0.8)],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: iconColor.withOpacity(0.3),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Text(
                  status,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
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

class _StatCardWithAnimation extends StatefulWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String value;
  final VoidCallback? onTap;

  const _StatCardWithAnimation({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.value,
    this.onTap,
  });

  @override
  State<_StatCardWithAnimation> createState() => _StatCardWithAnimationState();
}

class _StatCardWithAnimationState extends State<_StatCardWithAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _scaleController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails details) {
    _scaleController.forward();
  }

  void _handleTapUp(TapUpDetails details) {
    _scaleController.reverse();
    HapticFeedback.selectionClick();
    widget.onTap?.call();
  }

  void _handleTapCancel() {
    _scaleController.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOut,
      builder: (context, fadeValue, child) {
        return Transform.scale(
          scale: 0.9 + (fadeValue * 0.1),
          child: Opacity(opacity: fadeValue, child: child),
        );
      },
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(scale: _scaleAnimation.value, child: child);
        },
        child: GestureDetector(
          onTapDown: _handleTapDown,
          onTapUp: _handleTapUp,
          onTapCancel: _handleTapCancel,
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white,
                    widget.iconColor.withOpacity(0.05),
                    Colors.white,
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: widget.iconColor.withOpacity(0.12),
                    blurRadius: 20,
                    offset: const Offset(0, 6),
                    spreadRadius: 0,
                  ),
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 12,
                    offset: const Offset(0, 3),
                    spreadRadius: 0,
                  ),
                  BoxShadow(
                    color: Colors.black.withOpacity(0.02),
                    blurRadius: 6,
                    offset: const Offset(0, 1),
                    spreadRadius: 0,
                  ),
                ],
              ),
              child: SizedBox(
                height: 160, // Fixed height for all cards
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                widget.iconColor.withOpacity(0.25),
                                widget.iconColor.withOpacity(0.15),
                                widget.iconColor.withOpacity(0.08),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: widget.iconColor.withOpacity(0.3),
                              width: 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: widget.iconColor.withOpacity(0.15),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Icon(
                            widget.icon,
                            color: widget.iconColor,
                            size: 28,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                widget.iconColor.withOpacity(0.15),
                                widget.iconColor.withOpacity(0.08),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.trending_up_outlined,
                            color: widget.iconColor,
                            size: 16,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Text(
                      widget.title,
                      style: TextStyle(
                        color: Colors.grey[800], // Improved contrast
                        fontSize: 15, // Increased for readability
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                        letterSpacing: -0.2,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    FittedBox(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        widget.value,
                        style: TextStyle(
                          color: widget.iconColor,
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          height: 1.0,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DashboardCardWithAnimation extends StatefulWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  const _DashboardCardWithAnimation({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  @override
  State<_DashboardCardWithAnimation> createState() =>
      _DashboardCardWithAnimationState();
}

class _DashboardCardWithAnimationState
    extends State<_DashboardCardWithAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _scaleController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails details) {
    _scaleController.forward();
  }

  void _handleTapUp(TapUpDetails details) {
    _scaleController.reverse();
    HapticFeedback.selectionClick();
    widget.onTap?.call();
  }

  void _handleTapCancel() {
    _scaleController.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOut,
      builder: (context, fadeValue, child) {
        return Transform.scale(
          scale: 0.9 + (fadeValue * 0.1),
          child: Opacity(opacity: fadeValue, child: child),
        );
      },
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(scale: _scaleAnimation.value, child: child);
        },
        child: GestureDetector(
          onTapDown: widget.onTap != null ? _handleTapDown : null,
          onTapUp: widget.onTap != null ? _handleTapUp : null,
          onTapCancel: widget.onTap != null ? _handleTapCancel : null,
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white,
                    widget.iconColor.withOpacity(0.05),
                    Colors.white,
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: widget.iconColor.withOpacity(0.12),
                    blurRadius: 20,
                    offset: const Offset(0, 6),
                    spreadRadius: 0,
                  ),
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 12,
                    offset: const Offset(0, 3),
                    spreadRadius: 0,
                  ),
                  BoxShadow(
                    color: Colors.black.withOpacity(0.02),
                    blurRadius: 6,
                    offset: const Offset(0, 1),
                    spreadRadius: 0,
                  ),
                ],
              ),
              child: SizedBox(
                height: 160, // Fixed height for all cards
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                widget.iconColor.withOpacity(0.25),
                                widget.iconColor.withOpacity(0.15),
                                widget.iconColor.withOpacity(0.08),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: widget.iconColor.withOpacity(0.3),
                              width: 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: widget.iconColor.withOpacity(0.15),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Icon(
                            widget.icon,
                            color: widget.iconColor,
                            size: 28,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                widget.iconColor.withOpacity(0.15),
                                widget.iconColor.withOpacity(0.08),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.arrow_forward_outlined,
                            color: widget.iconColor,
                            size: 16,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Text(
                      widget.title,
                      style: TextStyle(
                        color: Colors.grey[800],
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        height: 1.3,
                        letterSpacing: -0.2,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.subtitle,
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        height: 1.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FabActions extends StatelessWidget {
  final void Function(String type) onSelect;
  const _FabActions({required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final isVerified = userProvider.currentUser?.isVerified ?? false;
    final currentUser = userProvider.currentUser;
    final canLend =
        currentUser?.canLend ?? true; // Default to true if user is null

    final List<_FabActionData> actions = [];

    // Only add Lend action if user can lend
    if (canLend) {
      actions.add(
        _FabActionData(
          'Lend',
          Icons.volunteer_activism,
          const Color(0xFF26A69A),
          'lend',
        ),
      );
    }

    // Add other actions (Rent, Trade, Donate) for all users
    actions.addAll([
      _FabActionData(
        'Rent',
        Icons.attach_money,
        const Color(0xFF66BB6A),
        'rent',
      ),
      _FabActionData(
        'Trade',
        Icons.swap_horiz,
        const Color(0xFF42A5F5),
        'trade',
      ),
      _FabActionData(
        'Donate',
        Icons.card_giftcard,
        const Color(0xFFEF5350),
        'donate',
      ),
    ]);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (int i = 0; i < actions.length; i++)
          _MiniAction(
            label: actions[i].label,
            icon: actions[i].icon,
            color: actions[i].color,
            delayMs: 40 * i,
            onTap: () => onSelect(actions[i].type),
            isEnabled: isVerified,
          ),
      ],
    );
  }
}

class _MiniAction extends StatefulWidget {
  final String label;
  final IconData icon;
  final Color color;
  final int delayMs;
  final VoidCallback onTap;
  final bool isEnabled;
  const _MiniAction({
    required this.label,
    required this.icon,
    required this.color,
    required this.delayMs,
    required this.onTap,
    this.isEnabled = true,
  });

  @override
  State<_MiniAction> createState() => _MiniActionState();
}

class _MiniActionState extends State<_MiniAction>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _offset;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _opacity = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _offset = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    Future.delayed(Duration(milliseconds: widget.delayMs), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(
        position: _offset,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Semantics(
            label: widget.label,
            button: true,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: widget.isEnabled ? widget.onTap : null,
              child: Opacity(
                opacity: widget.isEnabled ? 1.0 : 0.5,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 10,
                        spreadRadius: 1,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: widget.color.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(widget.icon, color: widget.color),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        widget.label,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 8),
                      widget.isEnabled
                          ? const Icon(Icons.chevron_right, color: Colors.grey)
                          : const Icon(
                              Icons.lock_outline,
                              color: Colors.grey,
                              size: 18,
                            ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FabActionData {
  final String label;
  final IconData icon;
  final Color color;
  final String type;
  _FabActionData(this.label, this.icon, this.color, this.type);
}

class _DueItem {
  final String id;
  final String title;
  final DateTime dueLocal;
  const _DueItem({
    required this.id,
    required this.title,
    required this.dueLocal,
  });
}
