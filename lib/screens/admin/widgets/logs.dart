import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../services/firestore_service.dart';
import '../../../models/activity_log_model.dart';
import 'package:intl/intl.dart';

class ActivityLogsTab extends StatefulWidget {
  const ActivityLogsTab({super.key});

  @override
  State<ActivityLogsTab> createState() => _ActivityLogsTabState();
}

class _ActivityLogsTabState extends State<ActivityLogsTab> {
  final FirestoreService _firestoreService = FirestoreService();
  final TextEditingController _searchController = TextEditingController();

  String _selectedCategory = 'all';
  String _selectedSeverity = 'all';
  String _selectedTimeRange = 'all';
  DateTime? _startDate;
  DateTime? _endDate;
  List<Map<String, dynamic>>? _searchResults;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _updateTimeRange(String range) {
    setState(() {
      _selectedTimeRange = range;
      final now = DateTime.now();

      switch (range) {
        case 'today':
          _startDate = DateTime(now.year, now.month, now.day);
          _endDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
          break;
        case 'week':
          _startDate = now.subtract(const Duration(days: 7));
          _endDate = now;
          break;
        case 'month':
          _startDate = now.subtract(const Duration(days: 30));
          _endDate = now;
          break;
        case 'all':
        default:
          _startDate = null;
          _endDate = null;
      }
      _searchResults = null; // Clear search when changing filters
    });
  }

  void _performSearch() async {
    final searchText = _searchController.text.trim();
    if (searchText.isEmpty) {
      setState(() => _searchResults = null);
      return;
    }

    final results = await _firestoreService.searchActivityLogs(
      searchText: searchText,
      limit: 100,
    );
    setState(() => _searchResults = results);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF00897B), Color(0xFF00695C)],
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
                    Icons.article_outlined,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Activity Logs',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Monitor all platform activities and events',
                        style: TextStyle(fontSize: 14, color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Search Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[300]!),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                const Icon(Icons.search, color: Colors.grey),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      hintText: 'Search logs...',
                      border: InputBorder.none,
                      isDense: true,
                    ),
                    onSubmitted: (_) => _performSearch(),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.search, color: Color(0xFF00897B)),
                  onPressed: _performSearch,
                  tooltip: 'Search',
                ),
                if (_searchController.text.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.clear, color: Colors.grey),
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _searchResults = null);
                    },
                    tooltip: 'Clear search',
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Filters
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              // Time Range Filter
              _FilterChip(
                label: 'Today',
                isSelected: _selectedTimeRange == 'today',
                onTap: () => _updateTimeRange('today'),
              ),
              _FilterChip(
                label: 'This Week',
                isSelected: _selectedTimeRange == 'week',
                onTap: () => _updateTimeRange('week'),
              ),
              _FilterChip(
                label: 'This Month',
                isSelected: _selectedTimeRange == 'month',
                onTap: () => _updateTimeRange('month'),
              ),
              _FilterChip(
                label: 'All Time',
                isSelected: _selectedTimeRange == 'all',
                onTap: () => _updateTimeRange('all'),
              ),

              // Category Filter
              const SizedBox(width: 12),
              _buildDropdownFilter(
                label: 'Category',
                value: _selectedCategory,
                items: const [
                  ('all', 'All Categories'),
                  ('user', 'User Actions'),
                  ('transaction', 'Transactions'),
                  ('content', 'Content'),
                  ('admin', 'Admin'),
                  ('system', 'System'),
                ],
                onChanged: (value) {
                  setState(() {
                    _selectedCategory = value ?? 'all';
                    _searchResults = null;
                  });
                },
              ),

              // Severity Filter
              _buildDropdownFilter(
                label: 'Severity',
                value: _selectedSeverity,
                items: const [
                  ('all', 'All Severities'),
                  ('info', 'Info'),
                  ('warning', 'Warning'),
                  ('critical', 'Critical'),
                ],
                onChanged: (value) {
                  setState(() {
                    _selectedSeverity = value ?? 'all';
                    _searchResults = null;
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Logs List
          Expanded(
            child: _searchResults != null
                ? _buildSearchResults()
                : _buildStreamLogs(),
          ),
        ],
      ),
    );
  }

  Widget _buildStreamLogs() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _firestoreService.getActivityLogsStream(
        category: _selectedCategory == 'all' ? null : _selectedCategory,
        severity: _selectedSeverity == 'all' ? null : _selectedSeverity,
        startDate: _startDate,
        endDate: _endDate,
        limit: 100,
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          final error = snapshot.error.toString();
          final isIndexError =
              error.contains('index') ||
              error.contains('requires an index') ||
              error.contains('composite');

          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.red),
                  const SizedBox(height: 16),
                  Text(
                    'Error loading logs',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[800],
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (isIndexError)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.orange[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange[200]!),
                      ),
                      child: Column(
                        children: [
                          Text(
                            'Firestore index required',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.orange[900],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Please deploy the indexes from firestore.indexes.json to Firebase Console.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.orange[800],
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    )
                  else
                    Text(
                      error,
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      textAlign: TextAlign.center,
                    ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () => setState(() {}),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00897B),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.inbox_outlined, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    'No activity logs found',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.grey[700],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _selectedCategory != 'all' ||
                            _selectedSeverity != 'all' ||
                            _selectedTimeRange != 'all'
                        ? 'Try adjusting your filters'
                        : 'Logs will appear here as activities occur on the platform',
                    style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }

        return ListView.separated(
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            try {
              final data = docs[index].data();
              data['id'] = docs[index].id;
              final log = ActivityLogModel.fromMap(data, docs[index].id);
              return _LogCard(log: log);
            } catch (e) {
              debugPrint('Error parsing log at index $index: $e');
              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red[200]!),
                ),
                child: Text(
                  'Error displaying log: $e',
                  style: TextStyle(color: Colors.red[800], fontSize: 12),
                ),
              );
            }
          },
        );
      },
    );
  }

  Widget _buildSearchResults() {
    if (_searchResults!.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 12),
            Text(
              'No results found',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      itemCount: _searchResults!.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final data = _searchResults![index];
        final log = ActivityLogModel.fromMap(data, data['id']);
        return _LogCard(log: log);
      },
    );
  }

  Widget _buildDropdownFilter({
    required String label,
    required String value,
    required List<(String, String)> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: DropdownButton<String>(
        value: value,
        underline: const SizedBox.shrink(),
        isDense: true,
        style: const TextStyle(fontSize: 14, color: Colors.black87),
        items: items.map((item) {
          return DropdownMenuItem(value: item.$1, child: Text(item.$2));
        }).toList(),
        onChanged: onChanged,
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          gradient: isSelected
              ? const LinearGradient(
                  colors: [Color(0xFF00897B), Color(0xFF00695C)],
                )
              : null,
          color: isSelected ? null : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? Colors.transparent : Colors.grey[300]!,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: const Color(0xFF00897B).withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.black87,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

class _LogCard extends StatefulWidget {
  final ActivityLogModel log;

  const _LogCard({required this.log});

  @override
  State<_LogCard> createState() => _LogCardState();
}

class _LogCardState extends State<_LogCard> {
  bool _isExpanded = false;

  Color get _categoryColor {
    switch (widget.log.category) {
      case LogCategory.user:
        return const Color(0xFF1976D2);
      case LogCategory.transaction:
        return const Color(0xFF388E3C);
      case LogCategory.content:
        return const Color(0xFFF57C00);
      case LogCategory.admin:
        return const Color(0xFF7B1FA2);
      case LogCategory.system:
        return const Color(0xFF455A64);
    }
  }

  Color get _severityColor {
    switch (widget.log.severity) {
      case LogSeverity.info:
        return const Color(0xFF1976D2);
      case LogSeverity.warning:
        return const Color(0xFFF57C00);
      case LogSeverity.critical:
        return const Color(0xFFD32F2F);
    }
  }

  IconData get _categoryIcon {
    switch (widget.log.category) {
      case LogCategory.user:
        return Icons.person_outline;
      case LogCategory.transaction:
        return Icons.swap_horiz;
      case LogCategory.content:
        return Icons.inventory_2_outlined;
      case LogCategory.admin:
        return Icons.admin_panel_settings_outlined;
      case LogCategory.system:
        return Icons.settings_outlined;
    }
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inDays < 1) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return DateFormat('MMM d, y • HH:mm').format(timestamp);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.white, Color(0xFFF5F7FA)],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() => _isExpanded = !_isExpanded),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Category Icon
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _categoryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        _categoryIcon,
                        color: _categoryColor,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Content
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              // Category Badge
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: _categoryColor.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: _categoryColor.withOpacity(0.3),
                                  ),
                                ),
                                child: Text(
                                  widget.log.categoryDisplay.toUpperCase(),
                                  style: TextStyle(
                                    color: _categoryColor,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),

                              // Severity Badge
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: _severityColor,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                widget.log.severityDisplay,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.grey[600],
                                  fontWeight: FontWeight.w500,
                                ),
                              ),

                              const Spacer(),

                              // Timestamp
                              Text(
                                _formatTimestamp(widget.log.timestamp),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),

                          // Description
                          Text(
                            widget.log.description,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              height: 1.3,
                            ),
                          ),
                          const SizedBox(height: 4),

                          // Actor
                          Row(
                            children: [
                              Icon(
                                Icons.person_outline,
                                size: 14,
                                color: Colors.grey[600],
                              ),
                              const SizedBox(width: 4),
                              Text(
                                widget.log.actorName,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[700],
                                ),
                              ),
                              if (widget.log.targetType != null) ...[
                                const SizedBox(width: 8),
                                Icon(
                                  Icons.arrow_forward,
                                  size: 12,
                                  color: Colors.grey[500],
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  widget.log.targetType!,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[700],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Expand Icon
                    if (widget.log.metadata.isNotEmpty)
                      Icon(
                        _isExpanded ? Icons.expand_less : Icons.expand_more,
                        color: Colors.grey[600],
                      ),
                  ],
                ),

                // Expanded Section (Metadata)
                if (_isExpanded && widget.log.metadata.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Divider(height: 1),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey[200]!),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              size: 14,
                              color: Colors.grey[700],
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Additional Details',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey[700],
                                letterSpacing: 0.3,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ...widget.log.metadata.entries.map((entry) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  width: 100,
                                  child: Text(
                                    '${entry.key}:',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.grey[700],
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    entry.value.toString(),
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey[800],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
