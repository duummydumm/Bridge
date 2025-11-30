import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/user_model.dart';
import '../models/rating_model.dart';
import '../models/item_model.dart';
import '../services/firestore_service.dart';
import '../services/report_block_service.dart';
import '../services/rating_service.dart';
import '../providers/auth_provider.dart';
import '../providers/user_provider.dart';
import 'all_reviews_screen.dart';
import 'borrow/borrow_items_screen.dart';

class UserPublicProfileScreen extends StatefulWidget {
  final String userId;

  const UserPublicProfileScreen({super.key, required this.userId});

  @override
  State<UserPublicProfileScreen> createState() =>
      _UserPublicProfileScreenState();
}

class _UserPublicProfileScreenState extends State<UserPublicProfileScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  final ReportBlockService _reportBlockService = ReportBlockService();
  final RatingService _ratingService = RatingService();
  UserModel? _user;
  bool _isLoading = true;
  String? _error;
  bool _isBlocked = false;
  List<RatingModel> _reviews = [];
  double _averageRating = 0.0;
  bool _loadingReviews = false;
  Map<String, dynamic>? _activityStats;
  Map<String, dynamic>? _responseStats;
  bool _loadingStats = false;
  List<ItemModel> _activeListings = [];
  bool _loadingListings = false;

  @override
  void initState() {
    super.initState();
    _loadUser();
    _checkIfBlocked();
    _loadReviews();
    _loadStatistics();
    _loadActiveListings();
  }

  Future<void> _loadReviews() async {
    setState(() {
      _loadingReviews = true;
    });

    try {
      final reviews = await _ratingService.getRatingsForUser(widget.userId);
      final avgRating = await _ratingService.getAverageRating(widget.userId);

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
        // Surface helpful debug info (likely missing Firestore index)
        debugPrint('Error loading public reviews: $e');
        if (e.toString().contains('index') || e.toString().contains('Index')) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'Firestore index required for reviews. Run: firebase deploy --only firestore:indexes',
              ),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 5),
            ),
          );
        }
      }
    }
  }

  Future<void> _loadStatistics() async {
    setState(() {
      _loadingStats = true;
    });

    try {
      final activityStats = await _firestoreService.getUserActivityStats(
        widget.userId,
      );
      final responseStats = await _firestoreService.getUserResponseStats(
        widget.userId,
      );

      if (mounted) {
        setState(() {
          _activityStats = activityStats;
          _responseStats = responseStats;
          _loadingStats = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingStats = false;
        });
        debugPrint('Error loading statistics: $e');
      }
    }
  }

  Future<void> _loadActiveListings() async {
    setState(() {
      _loadingListings = true;
    });

    try {
      final itemsData = await _firestoreService.getItemsByLender(widget.userId);
      final activeItems = itemsData
          .where(
            (item) =>
                (item['status'] ?? '').toString().toLowerCase() == 'available',
          )
          .take(6)
          .map((data) {
            try {
              return ItemModel.fromMap(data, data['id'] ?? '');
            } catch (e) {
              debugPrint('Error parsing item: $e');
              return null;
            }
          })
          .whereType<ItemModel>()
          .toList();

      if (mounted) {
        debugPrint('Loaded ${activeItems.length} active listings');
        for (var item in activeItems) {
          debugPrint(
            'Item: ${item.title}, Images: ${item.images.length}, hasImages: ${item.hasImages}',
          );
          if (item.images.isNotEmpty) {
            debugPrint('First image URL: ${item.images.first}');
          }
        }
        setState(() {
          _activeListings = activeItems;
          _loadingListings = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingListings = false;
        });
        debugPrint('Error loading active listings: $e');
      }
    }
  }

  Future<void> _checkIfBlocked() async {
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      if (authProvider.user == null) return;

      final isBlocked = await _reportBlockService.isUserBlocked(
        userId: authProvider.user!.uid,
        otherUserId: widget.userId,
      );

      if (mounted) {
        setState(() {
          _isBlocked = isBlocked;
        });
      }
    } catch (e) {
      // Silent fail
    }
  }

  Future<void> _loadUser() async {
    try {
      final data = await _firestoreService.getUser(widget.userId);
      if (!mounted) return;
      if (data == null) {
        setState(() {
          _error = 'User not found';
          _isLoading = false;
        });
        return;
      }
      setState(() {
        _user = UserModel.fromMap(data, data['id'] ?? widget.userId);
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load user: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Profile'),
        backgroundColor: const Color(0xFF00897B),
        elevation: 0,
        actions: [
          Builder(
            builder: (context) => PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: Colors.white),
              onSelected: (value) {
                if (value == 'report') {
                  _reportUser();
                } else if (value == 'block') {
                  _blockUser();
                } else if (value == 'unblock') {
                  _unblockUser();
                }
              },
              itemBuilder: (context) {
                final authProvider = Provider.of<AuthProvider>(
                  context,
                  listen: false,
                );
                final isOwnProfile = authProvider.user?.uid == widget.userId;

                if (isOwnProfile) return [];

                return [
                  if (_isBlocked)
                    const PopupMenuItem(
                      value: 'unblock',
                      child: Row(
                        children: [
                          Icon(Icons.check_circle, color: Colors.green),
                          SizedBox(width: 8),
                          Text('Unblock User'),
                        ],
                      ),
                    )
                  else
                    const PopupMenuItem(
                      value: 'block',
                      child: Row(
                        children: [
                          Icon(Icons.block, color: Colors.red),
                          SizedBox(width: 8),
                          Text('Block User'),
                        ],
                      ),
                    ),
                  const PopupMenuItem(
                    value: 'report',
                    child: Row(
                      children: [
                        Icon(Icons.flag_outlined, color: Colors.orange),
                        SizedBox(width: 8),
                        Text('Report User'),
                      ],
                    ),
                  ),
                ];
              },
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            )
          : _user == null
          ? const Center(child: Text('No data'))
          : _buildProfileContent(_user!),
    );
  }

  Widget _buildProfileContent(UserModel user) {
    return RefreshIndicator(
      onRefresh: () async {
        await _loadReviews();
        await _loadUser();
        await _loadStatistics();
        await _loadActiveListings();
      },
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 6,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 48,
                    backgroundColor: const Color(0xFF00897B).withOpacity(0.1),
                    backgroundImage: user.profilePhotoUrl.isNotEmpty
                        ? NetworkImage(user.profilePhotoUrl)
                        : null,
                    child: user.profilePhotoUrl.isEmpty
                        ? const Icon(
                            Icons.person,
                            size: 48,
                            color: Color(0xFF00897B),
                          )
                        : null,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    user.fullName,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.location_on,
                        size: 16,
                        color: Colors.grey,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          user.fullAddress,
                          style: const TextStyle(color: Colors.grey),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: user.isVerified
                          ? const Color(0xFF00897B)
                          : Colors.orange,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      user.isVerified ? 'Verified' : 'Pending',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _buildRating(
                    _averageRating > 0 ? _averageRating : user.reputationScore,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Active Listings Preview
            if (!_loadingListings && _activeListings.isNotEmpty)
              _buildListingsPreview(),

            const SizedBox(height: 16),

            // Activity & Statistics Section
            if (_loadingStats)
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 6,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(40),
                child: const Center(child: CircularProgressIndicator()),
              )
            else if (_activityStats != null)
              _buildActivityStatsSection(),

            const SizedBox(height: 16),

            // Reviews Section
            if (!_loadingReviews) _buildReviewsSection(),

            const SizedBox(height: 16),

            // About
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 6,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'About',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  _row('Email', user.email),
                  const Divider(height: 20),
                  _row('Role', _roleText(user.role)),
                  const Divider(height: 20),
                  _row('Member since', _formatDate(user.createdAt)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(label, style: TextStyle(color: Colors.grey[700])),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  String _roleText(UserRole role) {
    switch (role) {
      case UserRole.borrower:
        return 'Borrower';
      case UserRole.lender:
        return 'Lender';
      case UserRole.both:
        return 'Borrower & Lender';
    }
  }

  void _blockUser() {
    if (_user == null) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Block User'),
        content: Text(
          'Are you sure you want to block ${_user!.fullName}? You will not be able to send or receive messages from this user.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);

              final authProvider = Provider.of<AuthProvider>(
                context,
                listen: false,
              );
              if (authProvider.user == null) return;

              try {
                await _reportBlockService.blockUser(
                  userId: authProvider.user!.uid,
                  blockedUserId: widget.userId,
                  blockedUserName: _user!.fullName,
                );

                if (mounted) {
                  setState(() {
                    _isBlocked = true;
                  });

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('${_user!.fullName} has been blocked'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error blocking user: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: const Text('Block', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _unblockUser() {
    if (_user == null) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unblock User'),
        content: Text(
          'Are you sure you want to unblock ${_user!.fullName}? You will be able to send and receive messages again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);

              final authProvider = Provider.of<AuthProvider>(
                context,
                listen: false,
              );
              if (authProvider.user == null) return;

              try {
                await _reportBlockService.unblockUser(
                  userId: authProvider.user!.uid,
                  blockedUserId: widget.userId,
                );

                if (mounted) {
                  setState(() {
                    _isBlocked = false;
                  });

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('${_user!.fullName} has been unblocked'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error unblocking user: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: const Text('Unblock', style: TextStyle(color: Colors.green)),
          ),
        ],
      ),
    );
  }

  void _reportUser() {
    if (_user == null) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final userProvider = Provider.of<UserProvider>(context, listen: false);

    if (authProvider.user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please log in to report a user'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    String selectedReason = 'spam';
    final TextEditingController descriptionController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Report User'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Please select a reason for reporting:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                RadioListTile<String>(
                  title: const Text('Spam'),
                  value: 'spam',
                  groupValue: selectedReason,
                  onChanged: (value) {
                    setDialogState(() {
                      selectedReason = value!;
                    });
                  },
                ),
                RadioListTile<String>(
                  title: const Text('Harassment'),
                  value: 'harassment',
                  groupValue: selectedReason,
                  onChanged: (value) {
                    setDialogState(() {
                      selectedReason = value!;
                    });
                  },
                ),
                RadioListTile<String>(
                  title: const Text('Inappropriate Content'),
                  value: 'inappropriate_content',
                  groupValue: selectedReason,
                  onChanged: (value) {
                    setDialogState(() {
                      selectedReason = value!;
                    });
                  },
                ),
                RadioListTile<String>(
                  title: const Text('Fraud'),
                  value: 'fraud',
                  groupValue: selectedReason,
                  onChanged: (value) {
                    setDialogState(() {
                      selectedReason = value!;
                    });
                  },
                ),
                RadioListTile<String>(
                  title: const Text('Other'),
                  value: 'other',
                  groupValue: selectedReason,
                  onChanged: (value) {
                    setDialogState(() {
                      selectedReason = value!;
                    });
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Additional details (optional)',
                    hintText: 'Please provide more information...',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                // Store parent context before closing dialog
                final parentContext = context;
                Navigator.pop(parentContext);

                final reporterName =
                    userProvider.currentUser?.fullName ??
                    authProvider.user!.email ??
                    'Unknown';

                try {
                  await _reportBlockService.reportUser(
                    reporterId: authProvider.user!.uid,
                    reporterName: reporterName,
                    reportedUserId: widget.userId,
                    reportedUserName: _user!.fullName,
                    reason: selectedReason,
                    description: descriptionController.text.trim().isNotEmpty
                        ? descriptionController.text.trim()
                        : null,
                    contextType: 'profile',
                  );

                  if (mounted) {
                    ScaffoldMessenger.of(parentContext).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'User has been reported successfully. Thank you for keeping the community safe.',
                        ),
                        backgroundColor: Colors.green,
                        duration: Duration(seconds: 3),
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(parentContext).showSnackBar(
                      SnackBar(
                        content: Text('Error reporting user: $e'),
                        backgroundColor: Colors.red,
                        duration: const Duration(seconds: 3),
                      ),
                    );
                  }
                }
              },
              child: const Text(
                'Report',
                style: TextStyle(color: Colors.orange),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  Widget _buildRating(double score) {
    final double clamped = score.clamp(0.0, 5.0);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          children: List.generate(5, (index) {
            final starIndex = index + 1;
            if (clamped >= starIndex) {
              return const Icon(Icons.star, color: Colors.amber, size: 18);
            } else if (clamped > starIndex - 1 && clamped < starIndex) {
              return const Icon(Icons.star_half, color: Colors.amber, size: 18);
            } else {
              return Icon(Icons.star, color: Colors.grey[300], size: 18);
            }
          }),
        ),
        const SizedBox(width: 6),
        Text(
          '${clamped.toStringAsFixed(1)} / 5',
          style: const TextStyle(
            color: Colors.black54,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildActivityStatsSection() {
    final stats = _activityStats!;
    final responseStats = _responseStats ?? {};

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Activity & Statistics',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          // First row: Listings and Borrowed
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  icon: Icons.inventory_2_outlined,
                  iconColor: const Color(0xFF42A5F5),
                  title: 'Active Listings',
                  value: '${stats['activeListings'] ?? 0}',
                  subtitle: '${stats['totalListings'] ?? 0} total',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  icon: Icons.shopping_bag_outlined,
                  iconColor: const Color(0xFF66BB6A),
                  title: 'Currently Borrowed',
                  value: '${stats['currentlyBorrowed'] ?? 0}',
                  subtitle: '${stats['totalBorrowed'] ?? 0} total',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Second row: Trades and Rentals
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  icon: Icons.swap_horiz_outlined,
                  iconColor: const Color(0xFFFF9800),
                  title: 'Trade Items',
                  value: '${stats['tradeItems'] ?? 0}',
                  subtitle: 'Items for trade',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  icon: Icons.home_outlined,
                  iconColor: const Color(0xFF9C27B0),
                  title: 'Rental Listings',
                  value: '${stats['rentalListings'] ?? 0}',
                  subtitle: 'Available to rent',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Third row: Giveaways and Response Rate
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  icon: Icons.card_giftcard_outlined,
                  iconColor: const Color(0xFFE91E63),
                  title: 'Giveaways',
                  value: '${stats['giveaways'] ?? 0}',
                  subtitle: 'Items given away',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  icon: Icons.reply_outlined,
                  iconColor: const Color(0xFF26A69A),
                  title: 'Response Rate',
                  value: responseStats['responseRate'] != null
                      ? '${(responseStats['responseRate'] as double).toStringAsFixed(0)}%'
                      : 'N/A',
                  subtitle: _formatResponseTime(
                    responseStats['averageResponseTime'],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String value,
    String? subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: iconColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: iconColor.withOpacity(0.2), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor, size: 20),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[700],
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: iconColor,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(fontSize: 10, color: Colors.grey[600]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }

  String _formatResponseTime(dynamic avgResponseTimeMinutes) {
    if (avgResponseTimeMinutes == null || avgResponseTimeMinutes == 0) {
      return 'No data';
    }
    final minutes = avgResponseTimeMinutes as double;
    if (minutes < 60) {
      return '~${minutes.toStringAsFixed(0)}m avg';
    } else if (minutes < 1440) {
      final hours = (minutes / 60).toStringAsFixed(1);
      return '~${hours}h avg';
    } else {
      final days = (minutes / 1440).toStringAsFixed(1);
      return '~${days}d avg';
    }
  }

  Widget _buildListingsPreview() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Active Listings',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              TextButton(
                onPressed: () {
                  // Navigate to borrow items screen filtered by this user
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const BorrowItemsScreen(),
                    ),
                  );
                },
                child: const Text(
                  'View All',
                  style: TextStyle(color: Color(0xFF00897B), fontSize: 14),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 200,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _activeListings.length,
              itemBuilder: (context, index) {
                return _buildListingCard(_activeListings[index]);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildListingCard(ItemModel item) {
    return Container(
      width: 160,
      margin: const EdgeInsets.only(right: 12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: InkWell(
        onTap: () => _showItemDetails(item),
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(12),
              ),
              child: Container(
                height: 120,
                width: double.infinity,
                color: Colors.grey[200],
                child: item.hasImages
                    ? CachedNetworkImage(
                        imageUrl: _normalizeStorageUrl(item.images.first),
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(
                          color: Colors.grey[200],
                          child: const Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                        errorWidget: (context, url, error) {
                          debugPrint('❌ Image cache load Error: $error');
                          debugPrint('URL: ${item.images.first}');
                          return _buildPlaceholderImage();
                        },
                      )
                    : _buildPlaceholderImage(),
              ),
            ),
            // Content
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.category_outlined,
                        size: 12,
                        color: Colors.grey[600],
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          item.category,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[600],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholderImage() {
    return Container(
      color: Colors.grey[200],
      child: const Center(
        child: Icon(Icons.image_outlined, color: Colors.grey, size: 40),
      ),
    );
  }

  String _normalizeStorageUrl(String url) {
    // Keep original URL; modern buckets use .firebasestorage.app
    return url;
  }

  void _showItemDetails(ItemModel item) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) {
          return Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              children: [
                // Handle bar
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // Content
                Expanded(
                  child: SingleChildScrollView(
                    controller: scrollController,
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Image
                        if (item.hasImages)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              height: 250,
                              width: double.infinity,
                              color: Colors.grey[200],
                              child: CachedNetworkImage(
                                imageUrl: _normalizeStorageUrl(
                                  item.images.first,
                                ),
                                fit: BoxFit.cover,
                                placeholder: (context, url) => Container(
                                  color: Colors.grey[200],
                                  child: const Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                ),
                                errorWidget: (context, url, error) {
                                  debugPrint(
                                    '❌ Image cache load Error: $error',
                                  );
                                  debugPrint('URL: ${item.images.first}');
                                  return _buildPlaceholderImage();
                                },
                              ),
                            ),
                          ),
                        const SizedBox(height: 20),
                        // Title
                        Text(
                          item.title,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Category and Type
                        Wrap(
                          spacing: 8,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF00897B).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                item.category,
                                style: const TextStyle(
                                  color: Color(0xFF00897B),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.orange.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                item.type.toUpperCase(),
                                style: const TextStyle(
                                  color: Colors.orange,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        // Description
                        if (item.description.isNotEmpty) ...[
                          const Text(
                            'Description',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            item.description,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[700],
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 20),
                        ],
                        // Details
                        const Text(
                          'Details',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _buildDetailRow('Condition', item.condition),
                        _buildDetailRow('Status', item.statusDisplay),
                        if (item.pricePerDay != null)
                          _buildDetailRow(
                            'Price per Day',
                            '₱${item.pricePerDay!.toStringAsFixed(2)}',
                          ),
                        if (item.location != null && item.location!.isNotEmpty)
                          _buildDetailRow('Location', item.location!),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewsSection() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Reviews & Ratings',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 18),
                    color: const Color(0xFF00897B),
                    tooltip: 'Refresh reviews',
                    onPressed: _loadReviews,
                  ),
                  TextButton(
                    onPressed: () {
                      if (_user != null) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => AllReviewsScreen(
                              userId: widget.userId,
                              userName: _user!.fullName,
                            ),
                          ),
                        );
                      }
                    },
                    child: const Text(
                      'View All',
                      style: TextStyle(color: Color(0xFF00897B), fontSize: 14),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_reviews.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Text(
                  'No reviews yet',
                  style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                ),
              ),
            )
          else
            ..._reviews
                .take(3)
                .map(
                  (review) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          radius: 18,
                          backgroundColor: Colors.grey[300],
                          child: Text(
                            review.raterName.isNotEmpty
                                ? review.raterName[0].toUpperCase()
                                : '?',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
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
                                      review.raterName,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  Row(
                                    children: List.generate(5, (index) {
                                      return Icon(
                                        Icons.star,
                                        size: 12,
                                        color: index < review.rating
                                            ? Colors.amber
                                            : Colors.grey[300],
                                      );
                                    }),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                review.timeAgo,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                              if (review.feedback != null &&
                                  review.feedback!.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  review.feedback!,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[700],
                                    height: 1.4,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
        ],
      ),
    );
  }
}
