import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import '../providers/user_provider.dart';
import '../models/user_model.dart';
import '../models/rating_model.dart';
import '../services/rating_service.dart';
import '../services/firestore_service.dart';
import '../reusable_widgets/bottom_nav_bar_widget.dart';
import 'all_reviews_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => ProfileScreenState();
}

class ProfileScreenState extends State<ProfileScreen> {
  int _selectedIndex = 3; // Profile tab
  final ImagePicker _picker = ImagePicker();
  final RatingService _ratingService = RatingService();
  final FirestoreService _firestoreService = FirestoreService();
  List<RatingModel> _reviews = [];
  double _averageRating = 0.0;
  bool _loadingReviews = false;
  Map<String, dynamic>? _activityStats;
  bool _loadingStats = false;

  Future<void> _onChangeProfilePhoto() async {
    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final picked = await _picker.pickImage(source: ImageSource.gallery);
      if (picked == null) return;
      await userProvider.uploadProfilePhoto(file: picked);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Profile photo updated')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to update photo: $e')));
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _loadReviews();
    _loadActivityStats();
  }

  String _formatDate(DateTime date) {
    const months = [
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
    return '${months[date.month - 1]} ${date.year}';
  }

  Future<void> _loadActivityStats() async {
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final currentUser = userProvider.currentUser;
    if (currentUser == null) return;

    setState(() {
      _loadingStats = true;
    });

    try {
      final stats = await _firestoreService.getUserActivityStats(
        currentUser.uid,
      );
      if (mounted) {
        setState(() {
          _activityStats = stats;
          _loadingStats = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading activity stats: $e');
      if (mounted) {
        setState(() {
          _loadingStats = false;
        });
      }
    }
  }

  Future<void> _loadReviews() async {
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final currentUser = userProvider.currentUser;
    if (currentUser == null) return;

    setState(() {
      _loadingReviews = true;
    });

    try {
      final reviews = await _ratingService.getRatingsForUser(currentUser.uid);
      final avgRating = await _ratingService.getAverageRating(currentUser.uid);

      if (mounted) {
        setState(() {
          _reviews = reviews;
          _averageRating = avgRating;
          _loadingReviews = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingReviews = false;
        });
        // Show error to help debug
        debugPrint('Error loading reviews: $e');
        // Check if it's an index error
        if (e.toString().contains('index') || e.toString().contains('Index')) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'Firestore index required. Run: firebase deploy --only firestore:indexes',
              ),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 5),
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final userProvider = Provider.of<UserProvider>(context);
    final currentUser = userProvider.currentUser;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA), // Soft light background
      body: SafeArea(
        child: Column(
          children: [
            // Scrollable Content
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  await Future.wait([_loadReviews(), _loadActivityStats()]);
                },
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Column(
                    children: [
                      // Profile Header
                      _buildProfileHeader(currentUser),

                      const SizedBox(height: 20),

                      // Removed test barangay ID button
                      // Removed test feedback button
                      const SizedBox(height: 24),

                      // Account Role Section
                      _buildAccountRole(currentUser),

                      const SizedBox(height: 24),

                      // Activity Summary
                      _buildActivitySummary(),

                      const SizedBox(height: 24),

                      // Quick Links
                      _buildQuickLinks(currentUser),

                      const SizedBox(height: 24),

                      // Reputation Progress
                      _buildReputationProgress(),

                      const SizedBox(height: 24),

                      // Reviews & Ratings
                      _buildReviewsSection(),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavBarWidget(
        selectedIndex: _selectedIndex,
        onTap: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        navigationContext: context,
      ),
    );
  }

  Widget _buildProfileHeader(UserModel? user) {
    return Container(
      width: double.infinity,
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
            color: const Color(0xFF00897B).withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
            spreadRadius: 0,
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 16),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // Decorative circles in background
          Positioned(
            top: -30,
            right: -30,
            child: Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.1),
              ),
            ),
          ),
          Positioned(
            bottom: -40,
            left: -40,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),
          ),
          // Content
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Profile Picture with edit
              Stack(
                alignment: Alignment.bottomRight,
                clipBehavior: Clip.none,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 4),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 20,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: CircleAvatar(
                      radius: 60,
                      backgroundColor: Colors.white,
                      child: CircleAvatar(
                        radius: 57,
                        backgroundImage: () {
                          final url = user?.profilePhotoUrl ?? '';
                          if (url.isEmpty) return null;
                          final parsed = Uri.tryParse(url);
                          if (parsed == null || (!parsed.hasScheme)) {
                            return null;
                          }
                          return NetworkImage(url);
                        }(),
                        child: user == null || user.profilePhotoUrl.isEmpty
                            ? const Icon(
                                Icons.person,
                                size: 50,
                                color: Colors.grey,
                              )
                            : null,
                      ),
                    ),
                  ),
                  Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    elevation: 4,
                    child: InkWell(
                      onTap: _onChangeProfilePhoto,
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.1),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.camera_alt,
                          color: Color(0xFF00897B),
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Name
              Text(
                user?.fullName ?? 'User',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 10),

              // Location
              Center(
                child: Container(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.85,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 2),
                        child: Icon(
                          Icons.location_on_outlined,
                          size: 16,
                          color: Colors.white,
                        ),
                      ),
                      // const SizedBox(width: 2),
                      Flexible(
                        child: Text(
                          user?.fullAddress ?? 'Location',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                          textAlign: TextAlign.center,
                          softWrap: true,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Member Since
              if (user?.createdAt != null)
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.calendar_today,
                          size: 14,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Member since ${_formatDate(user!.createdAt)}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 16),

              // Elite Status
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.3),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.star_rounded,
                        color: Colors.amber,
                        size: 22,
                      ),
                      const SizedBox(width: 8),
                      Builder(
                        builder: (context) {
                          final rating = _averageRating;
                          final showBadge = rating > 0;

                          return Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                rating > 0 ? rating.toStringAsFixed(1) : '0.0',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (showBadge) ...[
                                const SizedBox(width: 10),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    gradient: rating >= 4.5
                                        ? const LinearGradient(
                                            colors: [
                                              Colors.amber,
                                              Color(0xFFFFB74D),
                                            ],
                                          )
                                        : null,
                                    color: rating >= 4.5
                                        ? null
                                        : Colors.white.withValues(alpha: 0.3),
                                    borderRadius: BorderRadius.circular(12),
                                    boxShadow: rating >= 4.5
                                        ? [
                                            BoxShadow(
                                              color: Colors.amber.withValues(
                                                alpha: 0.4,
                                              ),
                                              blurRadius: 8,
                                              offset: const Offset(0, 2),
                                            ),
                                          ]
                                        : null,
                                  ),
                                  child: Text(
                                    _getShortBadgeText(rating),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          );
                        },
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

  // Test feedback button removed

  Widget _buildAccountRole(UserModel? user) {
    // Get role display text based on user's actual role
    String roleText = 'Member'; // Default
    if (user != null) {
      switch (user.role) {
        case UserRole.both:
          roleText = 'Borrower & Lender';
          break;
        case UserRole.lender:
          roleText = 'Lender';
          break;
        case UserRole.borrower:
          roleText = 'Borrower';
          break;
      }
    }

    final isVerified = user?.isVerified == true;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00897B).withValues(alpha: 0.1),
            blurRadius: 12,
            offset: const Offset(0, 4),
            spreadRadius: 0,
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFF00897B).withValues(alpha: 0.2),
                  const Color(0xFF26A69A).withValues(alpha: 0.1),
                ],
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: const Color(0xFF00897B).withValues(alpha: 0.3),
                width: 1,
              ),
            ),
            child: const Icon(
              Icons.shield_outlined,
              color: Color(0xFF00897B),
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Account Role',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  roleText,
                  style: const TextStyle(
                    color: Color(0xFF1A1A1A),
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.2,
                  ),
                ),
              ],
            ),
          ),
          // Show verified/pending badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isVerified
                    ? [const Color(0xFF66BB6A), const Color(0xFF4CAF50)]
                    : [const Color(0xFFFFB74D), const Color(0xFFFFA726)],
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color:
                      (isVerified
                              ? const Color(0xFF66BB6A)
                              : const Color(0xFFFFB74D))
                          .withValues(alpha: 0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isVerified ? Icons.verified : Icons.pending_outlined,
                  color: Colors.white,
                  size: 16,
                ),
                const SizedBox(width: 6),
                Text(
                  isVerified ? 'Verified' : 'Pending',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActivitySummary() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00897B).withValues(alpha: 0.1),
            blurRadius: 12,
            offset: const Offset(0, 4),
            spreadRadius: 0,
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
                  Icons.analytics_outlined,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Activity Summary',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                  color: Color(0xFF1A1A1A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (_loadingStats)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(20.0),
                child: CircularProgressIndicator(),
              ),
            )
          else ...[
            Row(
              children: [
                Expanded(
                  child: _buildActivityCard(
                    '${_activityStats?['totalBorrowed'] ?? 0}',
                    'Items Borrowed',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildActivityCard(
                    '${_activityStats?['totalListings'] ?? 0}',
                    'Items Listed',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildActivityCard(
                    '${_activityStats?['tradeItems'] ?? 0}',
                    'Trades Done',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildActivityCard(
                    '${_activityStats?['giveaways'] ?? 0}',
                    'Items Given',
                  ),
                ),
              ],
            ),
            if ((_activityStats?['rentalListings'] ?? 0) > 0 ||
                (_activityStats?['activeListings'] ?? 0) > 0) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildActivityCard(
                      '${_activityStats?['activeListings'] ?? 0}',
                      'Active Listings',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildActivityCard(
                      '${_activityStats?['rentalListings'] ?? 0}',
                      'Rentals',
                    ),
                  ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildQuickLinks(UserModel? user) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00897B).withValues(alpha: 0.1),
            blurRadius: 12,
            offset: const Offset(0, 4),
            spreadRadius: 0,
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF00897B), Color(0xFF26A69A)],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.link_outlined,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Quick Links',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                  color: Color(0xFF1A1A1A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _buildQuickLinkButton(
                icon: Icons.inventory_2_outlined,
                label: 'My Listings',
                route: '/my-listings',
                color: const Color(0xFF00897B),
              ),
              _buildQuickLinkButton(
                icon: Icons.shopping_bag_outlined,
                label: 'Borrow Items',
                route: '/borrow',
                color: const Color(0xFF42A5F5),
              ),
              _buildQuickLinkButton(
                icon: Icons.home_work_outlined,
                label: 'Rent Items',
                route: '/rent',
                color: const Color(0xFF26A69A),
              ),
              _buildQuickLinkButton(
                icon: Icons.swap_horiz_outlined,
                label: 'Trade Items',
                route: '/trade',
                color: const Color(0xFFFFB74D),
              ),
              _buildQuickLinkButton(
                icon: Icons.card_giftcard_outlined,
                label: 'Giveaways',
                route: '/giveaway',
                color: const Color(0xFF66BB6A),
              ),
              _buildQuickLinkButton(
                icon: Icons.chat_bubble_outline,
                label: 'Messages',
                route: '/chat',
                color: const Color(0xFF9C27B0),
              ),
              _buildQuickLinkButton(
                icon: Icons.notifications_outlined,
                label: 'Notifications',
                route: '/notifications',
                color: const Color(0xFFFF5722),
              ),
              _buildQuickLinkButton(
                icon: Icons.share_outlined,
                label: 'Share Profile',
                onTap: () => _shareProfile(user),
                color: const Color(0xFF607D8B),
              ),
              _buildQuickLinkButton(
                icon: Icons.settings,
                label: 'Settings',
                route: '/settings',
                color: const Color(0xFF757575),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickLinkButton({
    required IconData icon,
    required String label,
    String? route,
    VoidCallback? onTap,
    required Color color,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          if (onTap != null) {
            onTap();
          } else if (route != null) {
            Navigator.pushNamed(context, route);
          }
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _shareProfile(UserModel? user) async {
    if (user == null) return;

    try {
      final profileText =
          '''
🌟 ${user.fullName}'s Profile on Bridge App

📍 Location: ${user.fullAddress}
⭐ Rating: ${_averageRating > 0 ? _averageRating.toStringAsFixed(1) : 'New Member'}
👤 Role: ${user.role.name.toUpperCase()}

Check out my profile on Bridge App!
''';

      await Share.share(
        profileText,
        subject: '${user.fullName}\'s Bridge App Profile',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to share profile: $e')));
      }
    }
  }

  Widget _buildActivityCard(String value, String label) {
    // Assign colors based on label
    Color cardColor;
    if (label.contains('Borrowed')) {
      cardColor = const Color(0xFF42A5F5); // Blue
    } else if (label.contains('Listed') || label.contains('Lent')) {
      cardColor = const Color(0xFF66BB6A); // Light Green
    } else if (label.contains('Trades')) {
      cardColor = const Color(0xFF26A69A); // Teal
    } else if (label.contains('Rentals')) {
      cardColor = const Color(0xFFFFB74D); // Orange
    } else if (label.contains('Active')) {
      cardColor = const Color(0xFF00897B); // Dark Teal
    } else {
      cardColor = const Color(0xFF00897B); // Dark Teal
    }

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOut,
      builder: (context, animValue, child) {
        return Transform.scale(
          scale: 0.9 + (animValue * 0.1),
          child: Opacity(opacity: animValue, child: child),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              cardColor.withValues(alpha: 0.15),
              cardColor.withValues(alpha: 0.08),
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cardColor.withValues(alpha: 0.2), width: 1),
          boxShadow: [
            BoxShadow(
              color: cardColor.withValues(alpha: 0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: TextStyle(
                color: cardColor,
                fontSize: 32,
                fontWeight: FontWeight.bold,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                color: Colors.grey[700],
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReputationProgress() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00897B).withValues(alpha: 0.1),
            blurRadius: 12,
            offset: const Offset(0, 4),
            spreadRadius: 0,
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFFB74D), Color(0xFFFFA726)],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.trending_up_outlined,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Reputation Progress',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                  color: Color(0xFF1A1A1A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _getReputationBadgeText(_averageRating),
                style: TextStyle(
                  fontSize: 16,
                  color: Color(0xFF1A1A1A),
                  fontWeight: FontWeight.w600,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  gradient: _averageRating > 0
                      ? const LinearGradient(
                          colors: [Color(0xFFFFB74D), Color(0xFFFFA726)],
                        )
                      : null,
                  color: _averageRating == 0 ? Colors.grey[300] : null,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: _averageRating > 0
                      ? [
                          BoxShadow(
                            color: Colors.amber.withValues(alpha: 0.3),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Text(
                  _averageRating > 0
                      ? '${_averageRating.toStringAsFixed(1)} / 5'
                      : 'No Rating',
                  style: TextStyle(
                    fontSize: 15,
                    color: _averageRating > 0 ? Colors.white : Colors.grey[700],
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: _averageRating / 5),
              duration: const Duration(milliseconds: 1000),
              curve: Curves.easeOut,
              builder: (context, progress, child) {
                return LayoutBuilder(
                  builder: (context, constraints) {
                    final filledWidth = progress * constraints.maxWidth;
                    return Container(
                      height: 14,
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Stack(
                        children: [
                          Container(
                            width: constraints.maxWidth,
                            decoration: BoxDecoration(
                              color: Colors.grey[200],
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          Container(
                            width: filledWidth,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [
                                  Color(0xFFFFB74D), // Amber
                                  Color(0xFFFFA726), // Orange
                                ],
                              ),
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.amber.withValues(alpha: 0.4),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _getReputationBadgeText(double rating) {
    if (rating == 0.0) {
      return 'New Member';
    } else if (rating >= 4.5) {
      return 'Elite Member';
    } else if (rating >= 4.0) {
      return 'Trusted Member';
    } else if (rating >= 3.0) {
      return 'Member';
    } else {
      return 'Building Reputation';
    }
  }

  String _getShortBadgeText(double rating) {
    if (rating == 0.0) {
      return 'New';
    } else if (rating >= 4.5) {
      return 'Elite';
    } else if (rating >= 4.0) {
      return 'Trusted';
    } else if (rating >= 3.0) {
      return 'Member';
    } else {
      return 'New';
    }
  }

  Widget _buildReviewsSection() {
    if (_loadingReviews) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    final currentUser = Provider.of<UserProvider>(context).currentUser;
    final userRating = currentUser?.reputationScore ?? _averageRating;
    final displayRating = userRating > 0 ? userRating : _averageRating;

    // Debug info (remove in production)
    debugPrint(
      'Profile Reviews - User ID: ${currentUser?.uid}, Reviews count: ${_reviews.length}, Avg Rating: $_averageRating',
    );

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00897B).withValues(alpha: 0.1),
            blurRadius: 12,
            offset: const Offset(0, 4),
            spreadRadius: 0,
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Flexible(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFFB74D), Color(0xFFFFA726)],
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.star_outlined,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Text(
                        'Reviews & Ratings',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          letterSpacing: -0.5,
                          color: Color(0xFF1A1A1A),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF00897B).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildStarRating(displayRating),
                    const SizedBox(width: 6),
                    Text(
                      '(${_reviews.length})',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF00897B),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // Add refresh button for debugging
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton(
                icon: const Icon(Icons.refresh, size: 18),
                color: const Color(0xFF00897B),
                onPressed: () {
                  _loadReviews();
                },
                tooltip: 'Refresh reviews',
              ),
            ],
          ),
          if (_reviews.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Column(
                  children: [
                    Text(
                      'No reviews yet',
                      style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Reviews you receive will appear here',
                      style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          else
            ..._reviews
                .take(2)
                .map(
                  (review) => Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: _buildReviewItem(
                      name: review.raterName,
                      time: review.timeAgo,
                      rating: review.rating,
                      comment: review.feedback ?? 'No comment provided',
                      context: review.context,
                    ),
                  ),
                ),
          if (_reviews.length > 2) ...[
            const SizedBox(height: 8),
            Center(
              child: TextButton(
                onPressed: () {
                  if (currentUser != null) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => AllReviewsScreen(
                          userId: currentUser.uid,
                          userName: currentUser.fullName,
                        ),
                      ),
                    ).then((_) {
                      // Reload reviews when returning
                      _loadReviews();
                    });
                  }
                },
                child: const Text(
                  'View All Reviews',
                  style: TextStyle(
                    color: Color(0xFF00897B),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStarRating(double rating) {
    final fullStars = rating.floor();
    final hasHalfStar = (rating - fullStars) >= 0.5;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        if (index < fullStars) {
          return const Icon(Icons.star, color: Colors.amber, size: 18);
        } else if (index == fullStars && hasHalfStar) {
          return const Icon(Icons.star_half, color: Colors.amber, size: 18);
        } else {
          return Icon(Icons.star, color: Colors.grey[300], size: 18);
        }
      }),
    );
  }

  Widget _buildReviewItem({
    required String name,
    required String time,
    required int rating,
    required String comment,
    required RatingContext context,
  }) {
    // Get context label and color
    String contextLabel;
    Color contextColor;
    IconData contextIcon;

    switch (context) {
      case RatingContext.rental:
        contextLabel = 'Rent';
        contextColor = const Color(0xFF26A69A);
        contextIcon = Icons.home_outlined;
        break;
      case RatingContext.trade:
        contextLabel = 'Trade';
        contextColor = const Color(0xFFFFB74D);
        contextIcon = Icons.swap_horiz;
        break;
      case RatingContext.borrow:
        contextLabel = 'Borrow';
        contextColor = const Color(0xFF42A5F5);
        contextIcon = Icons.shopping_bag_outlined;
        break;
      case RatingContext.giveaway:
        contextLabel = 'Giveaway';
        contextColor = const Color(0xFF66BB6A);
        contextIcon = Icons.card_giftcard;
        break;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[200]!, width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF00897B).withValues(alpha: 0.2),
                  const Color(0xFF26A69A).withValues(alpha: 0.1),
                ],
              ),
            ),
            child: CircleAvatar(
              radius: 24,
              backgroundColor: Colors.transparent,
              child: Text(
                name[0].toUpperCase(),
                style: const TextStyle(
                  color: Color(0xFF00897B),
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1A1A1A),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Context label
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: contextColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: contextColor.withValues(alpha: 0.3),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(contextIcon, size: 12, color: contextColor),
                          const SizedBox(width: 4),
                          Text(
                            contextLabel,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: contextColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                // Star rating row - wrapped to prevent overflow
                Row(
                  children: [
                    Flexible(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: List.generate(5, (index) {
                          return Icon(
                            Icons.star,
                            size: 16,
                            color: index < rating
                                ? Colors.amber
                                : Colors.grey[300],
                          );
                        }),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  time,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  comment,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[700],
                    height: 1.4,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
