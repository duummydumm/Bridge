import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import '../../../providers/admin_provider.dart';

class AccountManagementTab extends StatefulWidget {
  const AccountManagementTab({super.key});

  @override
  State<AccountManagementTab> createState() => _AccountManagementTabState();
}

class _AccountManagementTabState extends State<AccountManagementTab> {
  final TextEditingController _searchController = TextEditingController();
  String _selectedFilter = 'All Accounts';
  String _sortBy = 'Name';
  final Map<String, UserStats> _userStatsCache = {};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [const Color(0xFF00897B), const Color(0xFF00695C)],
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF00897B).withOpacity(0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.manage_accounts,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Account Management',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Manage user accounts and permissions',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white.withOpacity(0.9),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search by name or email...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: Colors.grey[50],
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 12),
              DropdownButton<String>(
                value: _selectedFilter,
                items: const [
                  DropdownMenuItem(
                    value: 'All Accounts',
                    child: Text('All Accounts'),
                  ),
                  DropdownMenuItem(value: 'Active', child: Text('Active')),
                  DropdownMenuItem(
                    value: 'Suspended',
                    child: Text('Suspended'),
                  ),
                  DropdownMenuItem(value: 'Verified', child: Text('Verified')),
                  DropdownMenuItem(
                    value: 'Unverified',
                    child: Text('Unverified'),
                  ),
                ],
                onChanged: (value) =>
                    setState(() => _selectedFilter = value ?? 'All Accounts'),
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(width: 12),
              DropdownButton<String>(
                value: _sortBy,
                items: const [
                  DropdownMenuItem(value: 'Name', child: Text('Sort: Name')),
                  DropdownMenuItem(
                    value: 'Join Date',
                    child: Text('Sort: Join Date'),
                  ),
                  DropdownMenuItem(
                    value: 'Rating',
                    child: Text('Sort: Rating'),
                  ),
                  DropdownMenuItem(
                    value: 'Activity',
                    child: Text('Sort: Activity'),
                  ),
                ],
                onChanged: (value) => setState(() => _sortBy = value ?? 'Name'),
                style: const TextStyle(fontSize: 14),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    snapshot.data == null) {
                  return const Center(child: CircularProgressIndicator());
                }
                final currentUid =
                    fb_auth.FirebaseAuth.instance.currentUser?.uid;
                var docs = (snapshot.data?.docs ?? []).where((doc) {
                  final data = doc.data();
                  if ((data['isAdmin'] ?? false) == true) return false;
                  if (currentUid != null && doc.id == currentUid) return false;
                  return true;
                }).toList();

                if (_searchController.text.isNotEmpty) {
                  final query = _searchController.text.toLowerCase();
                  docs = docs.where((doc) {
                    final data = doc.data();
                    final name =
                        '${data['firstName'] ?? ''} ${data['lastName'] ?? ''}'
                            .toLowerCase();
                    final email = (data['email'] ?? '').toLowerCase();
                    return name.contains(query) || email.contains(query);
                  }).toList();
                }

                if (_selectedFilter != 'All Accounts') {
                  docs = docs.where((doc) {
                    final data = doc.data();
                    switch (_selectedFilter) {
                      case 'Active':
                        return (data['isSuspended'] ?? false) == false;
                      case 'Suspended':
                        return (data['isSuspended'] ?? false) == true;
                      case 'Verified':
                        return (data['isVerified'] ?? false) == true;
                      case 'Unverified':
                        return (data['isVerified'] ?? false) == false;
                      default:
                        return true;
                    }
                  }).toList();
                }

                docs.sort((a, b) {
                  final aData = a.data();
                  final bData = b.data();
                  switch (_sortBy) {
                    case 'Name':
                      final aName =
                          '${aData['firstName'] ?? ''} ${aData['lastName'] ?? ''}';
                      final bName =
                          '${bData['firstName'] ?? ''} ${bData['lastName'] ?? ''}';
                      return aName.compareTo(bName);
                    case 'Join Date':
                      final aDate = aData['createdAt'] as Timestamp?;
                      final bDate = bData['createdAt'] as Timestamp?;
                      if (aDate == null && bDate == null) return 0;
                      if (aDate == null) return 1;
                      if (bDate == null) return -1;
                      return bDate.toDate().compareTo(aDate.toDate());
                    case 'Rating':
                      final aRating = (aData['reputationScore'] ?? 0.0)
                          .toDouble();
                      final bRating = (bData['reputationScore'] ?? 0.0)
                          .toDouble();
                      return bRating.compareTo(aRating);
                    case 'Activity':
                      final aAct = (aData['activityScore'] ?? 0).toInt();
                      final bAct = (bData['activityScore'] ?? 0).toInt();
                      return bAct.compareTo(aAct);
                    default:
                      return 0;
                  }
                });

                if (docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.person_off_outlined,
                          size: 48,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'No users found',
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  );
                }

                return LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth;
                    int cross = 1;
                    if (width >= 1400)
                      cross = 4;
                    else if (width >= 1100)
                      cross = 3;
                    else if (width >= 800)
                      cross = 2;
                    return GridView.builder(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: cross,
                        mainAxisSpacing: 16,
                        crossAxisSpacing: 16,
                        childAspectRatio: 1.2,
                      ),
                      itemCount: docs.length,
                      itemBuilder: (context, index) {
                        final data = docs[index].data();
                        final uid = docs[index].id;
                        final cached = _userStatsCache[uid];
                        return _UserCard(
                          key: ValueKey(
                            uid,
                          ), // Use key to preserve widget identity
                          userData: data,
                          uid: uid,
                          cachedStats: cached,
                          onStatsLoaded: (stats) {
                            if (!_userStatsCache.containsKey(uid)) {
                              // Use setState only if widget is still mounted
                              if (mounted) {
                                setState(() => _userStatsCache[uid] = stats);
                              }
                            }
                          },
                        );
                      },
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
}

class UserStats {
  final int itemsShared;
  final int itemsBorrowed;
  final double averageRating;

  UserStats({
    required this.itemsShared,
    required this.itemsBorrowed,
    required this.averageRating,
  });
}

class _UserCard extends StatefulWidget {
  final Map<String, dynamic> userData;
  final String uid;
  final UserStats? cachedStats;
  final Function(UserStats) onStatsLoaded;

  const _UserCard({
    super.key,
    required this.userData,
    required this.uid,
    this.cachedStats,
    required this.onStatsLoaded,
  });

  @override
  State<_UserCard> createState() => _UserCardState();
}

class _UserCardState extends State<_UserCard> {
  UserStats? _stats;
  bool _isLoadingStats = true;
  bool _hasLoadedStats = false;

  @override
  void initState() {
    super.initState();
    _initializeStats();
  }

  @override
  void didUpdateWidget(_UserCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only update if the cached stats changed and we don't have stats loaded yet
    if (widget.cachedStats != null &&
        widget.cachedStats != oldWidget.cachedStats &&
        !_hasLoadedStats) {
      _initializeStats();
    }
  }

  void _initializeStats() {
    if (widget.cachedStats != null) {
      _stats = widget.cachedStats;
      _isLoadingStats = false;
      _hasLoadedStats = true;
    } else if (!_hasLoadedStats) {
      // Only load if we haven't loaded before
      Future.microtask(() => _loadStats());
    }
  }

  Future<void> _loadStats() async {
    if (_hasLoadedStats || _stats != null) return;
    try {
      final results = await Future.wait([
        _getItemsSharedCount().timeout(
          const Duration(seconds: 3),
          onTimeout: () => 0,
        ),
        _getItemsBorrowedCount().timeout(
          const Duration(seconds: 3),
          onTimeout: () => 0,
        ),
        _getAverageRating().timeout(
          const Duration(seconds: 3),
          onTimeout: () => 0.0,
        ),
      ]);
      if (mounted && !_hasLoadedStats) {
        setState(() {
          _stats = UserStats(
            itemsShared: results[0] as int,
            itemsBorrowed: results[1] as int,
            averageRating: results[2] as double,
          );
          _isLoadingStats = false;
          _hasLoadedStats = true;
        });
        widget.onStatsLoaded(_stats!);
      }
    } catch (_) {
      if (mounted && !_hasLoadedStats) {
        setState(() {
          _stats = UserStats(
            itemsShared: 0,
            itemsBorrowed: 0,
            averageRating: 0.0,
          );
          _isLoadingStats = false;
          _hasLoadedStats = true;
        });
        widget.onStatsLoaded(_stats!);
      }
    }
  }

  Future<int> _getItemsSharedCount() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('items')
          .where('lenderId', isEqualTo: widget.uid)
          .limit(100)
          .get();
      return snapshot.docs.length;
    } catch (e) {
      return 0;
    }
  }

  Future<int> _getItemsBorrowedCount() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('items')
          .where('currentBorrowerId', isEqualTo: widget.uid)
          .limit(100)
          .get();
      return snapshot.docs.length;
    } catch (e) {
      return 0;
    }
  }

  Future<double> _getAverageRating() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('ratings')
          .where('ratedUserId', isEqualTo: widget.uid)
          .limit(100)
          .get();
      if (snapshot.docs.isEmpty) return 0.0;
      int total = 0;
      for (var doc in snapshot.docs) {
        total += (doc.data()['rating'] as int? ?? 0);
      }
      return total / snapshot.docs.length;
    } catch (e) {
      return 0.0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final firstName = widget.userData['firstName'] ?? '';
    final lastName = widget.userData['lastName'] ?? '';
    final name = '$firstName $lastName'.trim();
    final email = widget.userData['email'] ?? '';
    final profilePhotoUrl = widget.userData['profilePhotoUrl'] as String?;
    final isSuspended = widget.userData['isSuspended'] == true;
    final isVerified = widget.userData['isVerified'] == true;
    final createdAtTs = widget.userData['createdAt'];
    String memberSince = '';
    if (createdAtTs is Timestamp) {
      final d = createdAtTs.toDate();
      memberSince = '${d.month}/${d.day}/${d.year}';
    }

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.white, const Color(0xFFF5F7FA)],
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: InkWell(
          onTap: () {
            showDialog(
              context: context,
              builder: (context) => AccountUserDetailDialog(
                uid: widget.uid,
                userData: widget.userData,
                stats: _stats,
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
                    CircleAvatar(
                      radius: 30,
                      backgroundColor: Colors.grey[300],
                      backgroundImage:
                          profilePhotoUrl != null && profilePhotoUrl.isNotEmpty
                          ? NetworkImage(profilePhotoUrl)
                          : null,
                      child: profilePhotoUrl == null || profilePhotoUrl.isEmpty
                          ? const Icon(Icons.person, size: 30)
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name.isEmpty ? email : name,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            email,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: isSuspended
                            ? Colors.red[50]
                            : (isVerified
                                  ? Colors.green[50]
                                  : Colors.orange[50]),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSuspended
                              ? Colors.red[300]!
                              : (isVerified
                                    ? Colors.green[300]!
                                    : Colors.orange[300]!),
                        ),
                      ),
                      child: Text(
                        isSuspended
                            ? 'Suspended'
                            : (isVerified ? 'Active' : 'Pending'),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: isSuspended
                              ? Colors.red[700]
                              : (isVerified
                                    ? Colors.green[700]
                                    : Colors.orange[700]),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 16),
                _isLoadingStats
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: const [
                          _MetricSkeleton(),
                          _MetricSkeleton(),
                          _MetricSkeleton(),
                        ],
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _MetricItem(
                            icon: Icons.upload,
                            value: '${_stats?.itemsShared ?? 0}',
                            label: 'Shared',
                            color: Colors.blue,
                          ),
                          _MetricItem(
                            icon: Icons.download,
                            value: '${_stats?.itemsBorrowed ?? 0}',
                            label: 'Borrowed',
                            color: Colors.purple,
                          ),
                          _MetricItem(
                            icon: Icons.star,
                            value:
                                _stats?.averageRating.toStringAsFixed(1) ??
                                '0.0',
                            label: 'Rating',
                            color: Colors.amber,
                          ),
                        ],
                      ),
                const Spacer(),
                Row(
                  children: [
                    Icon(
                      Icons.calendar_today,
                      size: 14,
                      color: Colors.grey[600],
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Member since: $memberSince',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (context) => AccountUserDetailDialog(
                              uid: widget.uid,
                              userData: widget.userData,
                              stats: _stats,
                            ),
                          );
                        },
                        icon: const Icon(Icons.visibility, size: 16),
                        label: const Text('View'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: isSuspended
                                ? [
                                    const Color(0xFF2E7D32),
                                    const Color(0xFF1B5E20),
                                  ]
                                : [
                                    const Color(0xFFD32F2F),
                                    const Color(0xFFB71C1C),
                                  ],
                          ),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color:
                                  (isSuspended
                                          ? const Color(0xFF2E7D32)
                                          : const Color(0xFFD32F2F))
                                      .withOpacity(0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                          onPressed: () {
                            final admin = Provider.of<AdminProvider>(
                              context,
                              listen: false,
                            );
                            if (isSuspended) {
                              admin.restoreUser(widget.uid);
                            } else {
                              admin.suspendUser(widget.uid);
                            }
                          },
                          icon: Icon(
                            isSuspended ? Icons.lock_open : Icons.block,
                            size: 16,
                            color: Colors.white,
                          ),
                          label: Text(
                            isSuspended ? 'Restore' : 'Suspend',
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MetricItem extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;
  const _MetricItem({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
      ],
    );
  }
}

class _MetricSkeleton extends StatelessWidget {
  const _MetricSkeleton();
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: Colors.grey[300],
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(height: 4),
        Container(
          width: 30,
          height: 18,
          decoration: BoxDecoration(
            color: Colors.grey[300],
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(height: 2),
        Container(
          width: 40,
          height: 11,
          decoration: BoxDecoration(
            color: Colors.grey[200],
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ],
    );
  }
}

class AccountUserDetailDialog extends StatelessWidget {
  final String uid;
  final Map<String, dynamic> userData;
  final UserStats? stats;
  const AccountUserDetailDialog({
    super.key,
    required this.uid,
    required this.userData,
    this.stats,
  });

  @override
  Widget build(BuildContext context) {
    final firstName = userData['firstName'] ?? '';
    final middleInitial = userData['middleInitial'] ?? '';
    final lastName = userData['lastName'] ?? '';
    final fullName = middleInitial.isNotEmpty
        ? '$firstName $middleInitial. $lastName'
        : '$firstName $lastName';
    final email = userData['email'] ?? '';
    final barangay = userData['barangay'] ?? '';
    final city = userData['city'] ?? '';
    final province = userData['province'] ?? '';
    final address = '$barangay, $city, $province'.trim();
    final profilePhotoUrl = userData['profilePhotoUrl'] as String?;
    final isSuspended = userData['isSuspended'] == true;
    final isVerified = userData['isVerified'] == true;
    final violationCount = userData['violationCount'] ?? 0;
    final reputationScore = (userData['reputationScore'] ?? 0.0).toDouble();
    final createdAtTs = userData['createdAt'];
    String memberSince = '';
    if (createdAtTs is Timestamp) {
      final d = createdAtTs.toDate();
      memberSince = '${d.month}/${d.day}/${d.year}';
    }

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 800, maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    const Color(0xFF00897B),
                    const Color(0xFF00695C),
                    const Color(0xFF004D40),
                  ],
                ),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.person, color: Colors.white, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      fullName.isEmpty ? email : fullName,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 50,
                          backgroundColor: Colors.grey[300],
                          backgroundImage:
                              profilePhotoUrl != null &&
                                  profilePhotoUrl.isNotEmpty
                              ? NetworkImage(profilePhotoUrl)
                              : null,
                          child:
                              profilePhotoUrl == null || profilePhotoUrl.isEmpty
                              ? const Icon(Icons.person, size: 50)
                              : null,
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                fullName.isEmpty ? email : fullName,
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                email,
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey[700],
                                ),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isSuspended
                                          ? Colors.red[50]
                                          : (isVerified
                                                ? Colors.green[50]
                                                : Colors.orange[50]),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: isSuspended
                                            ? Colors.red[300]!
                                            : (isVerified
                                                  ? Colors.green[300]!
                                                  : Colors.orange[300]!),
                                      ),
                                    ),
                                    child: Text(
                                      isSuspended
                                          ? 'Suspended'
                                          : (isVerified
                                                ? 'Verified'
                                                : 'Unverified'),
                                      style: TextStyle(
                                        color: isSuspended
                                            ? Colors.red[700]
                                            : (isVerified
                                                  ? Colors.green[700]
                                                  : Colors.orange[700]),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),
                    if (stats != null) ...[
                      Row(
                        children: [
                          Expanded(
                            child: _DetailStatCard(
                              icon: Icons.upload,
                              label: 'Items Shared',
                              value: '${stats!.itemsShared}',
                              color: Colors.blue,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _DetailStatCard(
                              icon: Icons.download,
                              label: 'Items Borrowed',
                              value: '${stats!.itemsBorrowed}',
                              color: Colors.purple,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _DetailStatCard(
                              icon: Icons.star,
                              label: 'Average Rating',
                              value: stats!.averageRating.toStringAsFixed(1),
                              color: Colors.amber,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 32),
                    ],
                    const Text(
                      'User Information',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _InfoRow(
                      icon: Icons.email_outlined,
                      label: 'Email',
                      value: email,
                    ),
                    const SizedBox(height: 12),
                    _InfoRow(
                      icon: Icons.location_on_outlined,
                      label: 'Address',
                      value: address.isEmpty ? 'Not provided' : address,
                    ),
                    const SizedBox(height: 12),
                    _InfoRow(
                      icon: Icons.calendar_today_outlined,
                      label: 'Member Since',
                      value: memberSince,
                    ),
                    const SizedBox(height: 12),
                    _InfoRow(
                      icon: Icons.star_outline,
                      label: 'Reputation Score',
                      value: reputationScore.toStringAsFixed(1),
                    ),
                    const SizedBox(height: 12),
                    _InfoRow(
                      icon: Icons.warning_outlined,
                      label: 'Violations',
                      value: violationCount.toString(),
                    ),
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                border: Border(top: BorderSide(color: Colors.grey[300]!)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.orange,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                    ),
                    onPressed: () {
                      final admin = Provider.of<AdminProvider>(
                        context,
                        listen: false,
                      );
                      Navigator.of(context).pop();
                      showFileViolationDialog(
                        context,
                        uid,
                        fullName.isEmpty ? email : fullName,
                        admin,
                      );
                    },
                    icon: const Icon(Icons.warning),
                    label: const Text('File Violation'),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: isSuspended ? Colors.green : Colors.red,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                    ),
                    onPressed: () {
                      final admin = Provider.of<AdminProvider>(
                        context,
                        listen: false,
                      );
                      if (isSuspended) {
                        admin.restoreUser(uid);
                      } else {
                        admin.suspendUser(uid);
                      }
                      Navigator.of(context).pop();
                    },
                    icon: Icon(isSuspended ? Icons.lock_open : Icons.block),
                    label: Text(isSuspended ? 'Restore' : 'Suspend'),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          const Color(0xFF00897B),
                          const Color(0xFF00695C),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF00897B).withOpacity(0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close, color: Colors.white),
                      label: const Text(
                        'Close',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailStatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  const _DetailStatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withOpacity(0.15),
            color.withOpacity(0.05),
            Colors.white,
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [color.withOpacity(0.2), color.withOpacity(0.1)],
              ),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 32),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: color,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.grey[700],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });
  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: Colors.grey[600]),
        const SizedBox(width: 12),
        SizedBox(
          width: 120,
          child: Text(
            '$label:',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: Colors.grey[700],
              fontSize: 15,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }
}

void showFileViolationDialog(
  BuildContext context,
  String userId,
  String userName,
  AdminProvider admin,
) {
  final noteController = TextEditingController();

  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('File Violation'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('File a violation against: $userName'),
          const SizedBox(height: 16),
          TextField(
            controller: noteController,
            decoration: const InputDecoration(
              labelText: 'Violation Note (Optional)',
              hintText: 'Enter details about the violation...',
              border: OutlineInputBorder(),
            ),
            maxLines: 3,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () async {
            try {
              await admin.fileViolation(
                userId,
                note: noteController.text.trim().isEmpty
                    ? null
                    : noteController.text.trim(),
              );
              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Violation filed successfully'),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            } catch (e) {
              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Error filing violation: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            }
          },
          child: const Text(
            'File Violation',
            style: TextStyle(color: Colors.orange),
          ),
        ),
      ],
    ),
  );
}
