import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class FeedbackTab extends StatefulWidget {
  const FeedbackTab({super.key});

  @override
  State<FeedbackTab> createState() => _FeedbackTabState();
}

class _FeedbackTabState extends State<FeedbackTab> {
  String _statusFilter = 'all'; // all, pending, reviewed, resolved
  String _categoryFilter = 'all'; // all, general, bug, feature, etc.

  Stream<QuerySnapshot> _getFeedbackStream() {
    // If both filters are active, we need to fetch all and filter in memory
    // to avoid requiring a composite index
    final bothFiltersActive =
        _statusFilter != 'all' && _categoryFilter != 'all';

    if (bothFiltersActive) {
      // Fetch all feedback ordered by createdAt, filtering will be done in memory
      return FirebaseFirestore.instance
          .collection('feedback')
          .orderBy('createdAt', descending: true)
          .snapshots();
    }

    // If only one filter is active, use it with orderBy (works with simple index)
    Query query = FirebaseFirestore.instance
        .collection('feedback')
        .orderBy('createdAt', descending: true);

    if (_statusFilter != 'all') {
      query = query.where('status', isEqualTo: _statusFilter);
    } else if (_categoryFilter != 'all') {
      query = query.where('category', isEqualTo: _categoryFilter);
    }

    return query.snapshots();
  }

  Future<void> _updateFeedbackStatus(
    String feedbackId,
    String newStatus,
  ) async {
    try {
      await FirebaseFirestore.instance
          .collection('feedback')
          .doc(feedbackId)
          .update({
            'status': newStatus,
            'updatedAt': FieldValue.serverTimestamp(),
          });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Feedback marked as $newStatus'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating feedback: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _deleteFeedback(String feedbackId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Feedback'),
        content: const Text('Are you sure you want to delete this feedback?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await FirebaseFirestore.instance
            .collection('feedback')
            .doc(feedbackId)
            .delete();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Feedback deleted'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error deleting feedback: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  void _showFeedbackDetail(Map<String, dynamic> feedback, String feedbackId) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 600, maxHeight: 700),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF00897B),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(12),
                    topRight: Radius.circular(12),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.feedback, color: Colors.white),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        feedback['subject'] ?? 'Feedback',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              // Content
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Category and Status
                      Row(
                        children: [
                          _buildChip(
                            _getCategoryLabel(
                              feedback['category'] ?? 'general',
                            ),
                            _getCategoryColor(
                              feedback['category'] ?? 'general',
                            ),
                          ),
                          const SizedBox(width: 8),
                          _buildChip(
                            feedback['status'] ?? 'pending',
                            _getStatusColor(feedback['status'] ?? 'pending'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // User Info
                      _buildInfoRow('User', feedback['userName'] ?? 'Unknown'),
                      if (feedback['userEmail'] != null)
                        _buildInfoRow('Email', feedback['userEmail']),
                      _buildInfoRow(
                        'Submitted',
                        _formatTimestamp(feedback['createdAt']),
                      ),
                      const Divider(height: 32),
                      // Message
                      const Text(
                        'Message',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        feedback['message'] ?? 'No message',
                        style: const TextStyle(fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ),
              // Actions
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(12),
                    bottomRight: Radius.circular(12),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (feedback['status'] != 'reviewed')
                      TextButton.icon(
                        onPressed: () {
                          _updateFeedbackStatus(feedbackId, 'reviewed');
                          Navigator.pop(context);
                        },
                        icon: const Icon(Icons.check),
                        label: const Text('Mark as Reviewed'),
                      ),
                    if (feedback['status'] != 'resolved')
                      TextButton.icon(
                        onPressed: () {
                          _updateFeedbackStatus(feedbackId, 'resolved');
                          Navigator.pop(context);
                        },
                        icon: const Icon(Icons.done_all),
                        label: const Text('Mark as Resolved'),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.green,
                        ),
                      ),
                    TextButton.icon(
                      onPressed: () {
                        _deleteFeedback(feedbackId);
                        Navigator.pop(context);
                      },
                      icon: const Icon(Icons.delete),
                      label: const Text('Delete'),
                      style: TextButton.styleFrom(foregroundColor: Colors.red),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.grey,
              ),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  Widget _buildChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  String _getCategoryLabel(String category) {
    switch (category) {
      case 'general':
        return 'General';
      case 'bug':
        return 'Bug Report';
      case 'feature':
        return 'Feature Request';
      case 'improvement':
        return 'Improvement';
      case 'ui':
        return 'UI/UX';
      case 'other':
        return 'Other';
      default:
        return category;
    }
  }

  Color _getCategoryColor(String category) {
    switch (category) {
      case 'bug':
        return Colors.red;
      case 'feature':
        return Colors.blue;
      case 'improvement':
        return Colors.green;
      case 'ui':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'pending':
        return Colors.orange;
      case 'reviewed':
        return Colors.blue;
      case 'resolved':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  String _formatTimestamp(dynamic timestamp) {
    if (timestamp == null) return 'Unknown';
    if (timestamp is Timestamp) {
      return DateFormat('MMM dd, yyyy • hh:mm a').format(timestamp.toDate());
    }
    return 'Unknown';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: Column(
        children: [
          // Header with filters
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    const Icon(Icons.feedback, color: Color(0xFF00897B)),
                    const SizedBox(width: 12),
                    const Text(
                      'User Feedback',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    // Status Filter
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _statusFilter,
                        decoration: InputDecoration(
                          labelText: 'Status',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'all', child: Text('All')),
                          DropdownMenuItem(
                            value: 'pending',
                            child: Text('Pending'),
                          ),
                          DropdownMenuItem(
                            value: 'reviewed',
                            child: Text('Reviewed'),
                          ),
                          DropdownMenuItem(
                            value: 'resolved',
                            child: Text('Resolved'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setState(() => _statusFilter = value);
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Category Filter
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _categoryFilter,
                        decoration: InputDecoration(
                          labelText: 'Category',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'all', child: Text('All')),
                          DropdownMenuItem(
                            value: 'general',
                            child: Text('General'),
                          ),
                          DropdownMenuItem(
                            value: 'bug',
                            child: Text('Bug Report'),
                          ),
                          DropdownMenuItem(
                            value: 'feature',
                            child: Text('Feature Request'),
                          ),
                          DropdownMenuItem(
                            value: 'improvement',
                            child: Text('Improvement'),
                          ),
                          DropdownMenuItem(value: 'ui', child: Text('UI/UX')),
                          DropdownMenuItem(
                            value: 'other',
                            child: Text('Other'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setState(() => _categoryFilter = value);
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Feedback List
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _getFeedbackStream(),
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
                          const Icon(
                            Icons.error_outline,
                            size: 48,
                            color: Colors.red,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Error loading feedback',
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
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
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

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.feedback_outlined,
                          size: 64,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No feedback found',
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  );
                }

                // Filter in memory if both filters are active
                var docs = snapshot.data!.docs;
                final bothFiltersActive =
                    _statusFilter != 'all' && _categoryFilter != 'all';

                if (bothFiltersActive) {
                  docs = docs.where((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    final statusMatch =
                        _statusFilter == 'all' ||
                        (data['status'] ?? 'pending') == _statusFilter;
                    final categoryMatch =
                        _categoryFilter == 'all' ||
                        (data['category'] ?? 'general') == _categoryFilter;
                    return statusMatch && categoryMatch;
                  }).toList();
                }

                if (docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.feedback_outlined,
                          size: 64,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No feedback found',
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Try adjusting your filters',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[500],
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final feedback = doc.data() as Map<String, dynamic>;
                    final feedbackId = doc.id;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      elevation: 2,
                      child: InkWell(
                        onTap: () => _showFeedbackDetail(feedback, feedbackId),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      feedback['subject'] ?? 'No Subject',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  _buildChip(
                                    _getCategoryLabel(
                                      feedback['category'] ?? 'general',
                                    ),
                                    _getCategoryColor(
                                      feedback['category'] ?? 'general',
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  _buildChip(
                                    feedback['status'] ?? 'pending',
                                    _getStatusColor(
                                      feedback['status'] ?? 'pending',
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                feedback['message'] ?? '',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.grey[700],
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Icon(
                                    Icons.person,
                                    size: 16,
                                    color: Colors.grey[600],
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    feedback['userName'] ?? 'Unknown User',
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Icon(
                                    Icons.access_time,
                                    size: 16,
                                    color: Colors.grey[600],
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    _formatTimestamp(feedback['createdAt']),
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
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
}
