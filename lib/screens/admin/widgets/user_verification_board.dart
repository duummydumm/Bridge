import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../providers/admin_provider.dart';
import 'user_verification_detail_dialog.dart';

class UserVerificationBoard extends StatefulWidget {
  const UserVerificationBoard({super.key});

  @override
  State<UserVerificationBoard> createState() => _UserVerificationBoardState();
}

class _UserVerificationBoardState extends State<UserVerificationBoard> {
  final Set<String> _selectedUserIds = {};
  bool _isSelectionMode = false;

  void _showRejectDialog(
    BuildContext context,
    AdminProvider admin,
    String uid,
    Map<String, dynamic> userData,
  ) {
    final verificationStatus = userData['verificationStatus'] as String?;
    final isVerified = userData['isVerified'] as bool? ?? false;
    final isAlreadyRejected = verificationStatus == 'rejected';
    final canReject = !isVerified && verificationStatus != 'rejected';

    if (isAlreadyRejected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'This user is already rejected. They need to update their information first.',
          ),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    if (!canReject) {
      return;
    }

    // Show simple rejection reason dialog
    final TextEditingController reasonController = TextEditingController();
    bool isLoading = false;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.red),
              SizedBox(width: 8),
              Text('Reject User Verification'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Please provide a reason for rejecting this user\'s verification:',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildQuickReasonChip(
                      context,
                      'Please upload the correct information',
                      reasonController,
                      setDialogState,
                    ),
                    _buildQuickReasonChip(
                      context,
                      'ID must match the valid ID you uploaded',
                      reasonController,
                      setDialogState,
                    ),
                    _buildQuickReasonChip(
                      context,
                      'Personal information mismatch',
                      reasonController,
                      setDialogState,
                    ),
                    _buildQuickReasonChip(
                      context,
                      'Invalid or expired ID',
                      reasonController,
                      setDialogState,
                    ),
                    _buildQuickReasonChip(
                      context,
                      'ID image is unclear or unreadable',
                      reasonController,
                      setDialogState,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: reasonController,
                  decoration: const InputDecoration(
                    hintText: 'Or enter custom rejection reason...',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.all(12),
                  ),
                  maxLines: 4,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isLoading
                  ? null
                  : () {
                      reasonController.dispose();
                      Navigator.of(context).pop();
                    },
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFE53935),
              ),
              onPressed: isLoading
                  ? null
                  : () async {
                      setDialogState(() => isLoading = true);
                      try {
                        final reason = reasonController.text.trim();
                        await admin.rejectUser(
                          uid,
                          reason: reason.isEmpty ? null : reason,
                        );
                        reasonController.dispose();
                        if (context.mounted) {
                          Navigator.of(context).pop();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                reason.isEmpty
                                    ? 'User rejected successfully (no reason provided)'
                                    : 'User rejected successfully',
                              ),
                              backgroundColor: const Color(0xFFE53935),
                              duration: const Duration(seconds: 3),
                            ),
                          );
                        }
                      } catch (e) {
                        setDialogState(() => isLoading = false);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Error: ${e.toString()}'),
                              backgroundColor: Colors.red,
                              duration: const Duration(seconds: 5),
                            ),
                          );
                        }
                      }
                    },
              child: isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text('Confirm Reject'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickReasonChip(
    BuildContext context,
    String label,
    TextEditingController controller,
    StateSetter setState,
  ) {
    return InkWell(
      onTap: () {
        String fullReason;
        switch (label) {
          case 'Please upload the correct information':
            fullReason =
                'Please upload the correct information. The details you provided do not match the requirements.';
            break;
          case 'ID must match the valid ID you uploaded':
            fullReason =
                'The ID you uploaded must match the valid ID information. Please ensure the ID document matches your personal details.';
            break;
          case 'Personal information mismatch':
            fullReason =
                'The personal information you provided does not match your ID document. Please ensure all details are consistent.';
            break;
          case 'Invalid or expired ID':
            fullReason =
                'The ID you uploaded appears to be invalid or expired. Please upload a valid, current government-issued ID.';
            break;
          case 'ID image is unclear or unreadable':
            fullReason =
                'The ID image you uploaded is unclear or unreadable. Please upload a clear, high-quality photo of your valid ID.';
            break;
          default:
            fullReason = label;
        }
        setState(() {
          controller.text = fullReason;
        });
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.red[50],
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.red[300]!, width: 1),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.red[900],
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  void _toggleSelectionMode() {
    setState(() {
      _isSelectionMode = !_isSelectionMode;
      if (!_isSelectionMode) {
        _selectedUserIds.clear();
      }
    });
  }

  void _toggleUserSelection(String uid) {
    setState(() {
      if (_selectedUserIds.contains(uid)) {
        _selectedUserIds.remove(uid);
      } else {
        _selectedUserIds.add(uid);
      }
    });
  }

  Future<void> _handleBulkApprove() async {
    if (_selectedUserIds.isEmpty) return;

    final admin = Provider.of<AdminProvider>(context, listen: false);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Bulk Approve Users'),
        content: Text(
          'Are you sure you want to approve ${_selectedUserIds.length} user(s)?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Approve'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final result = await admin.bulkApproveUsers(_selectedUserIds.toList());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Approved ${result.successCount} user(s)${result.hasFailures ? '. ${result.failureCount} failed.' : ''}',
            ),
            backgroundColor: result.hasFailures ? Colors.orange : Colors.green,
          ),
        );
        setState(() {
          _selectedUserIds.clear();
          _isSelectionMode = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _handleBulkReject() async {
    if (_selectedUserIds.isEmpty) return;

    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Bulk Reject Users'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Reject ${_selectedUserIds.length} user(s)?'),
            const SizedBox(height: 16),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                hintText: 'Rejection reason (optional)',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reject'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final admin = Provider.of<AdminProvider>(context, listen: false);
    try {
      final reason = reasonController.text.trim().isEmpty
          ? null
          : reasonController.text.trim();
      final result = await admin.bulkRejectUsers(
        _selectedUserIds.toList(),
        reason: reason,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Rejected ${result.successCount} user(s)${result.hasFailures ? '. ${result.failureCount} failed.' : ''}',
            ),
            backgroundColor: result.hasFailures ? Colors.orange : Colors.red,
          ),
        );
        setState(() {
          _selectedUserIds.clear();
          _isSelectionMode = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final admin = Provider.of<AdminProvider>(context, listen: false);
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
                    Icons.verified_user,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                const Expanded(
                  child: Text(
                    'User Verification',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(
                    _isSelectionMode ? Icons.close : Icons.checklist,
                    color: Colors.white,
                  ),
                  onPressed: _toggleSelectionMode,
                  tooltip: _isSelectionMode
                      ? 'Exit selection mode'
                      : 'Enable bulk selection',
                ),
              ],
            ),
          ),
          if (_isSelectionMode && _selectedUserIds.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue[200]!),
              ),
              child: Row(
                children: [
                  Text(
                    '${_selectedUserIds.length} selected',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: _handleBulkApprove,
                    icon: const Icon(Icons.check),
                    label: const Text('Approve All'),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.green[700],
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: _handleBulkReject,
                    icon: const Icon(Icons.close),
                    label: const Text('Reject All'),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.red[700],
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: admin.unverifiedUsersStream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snapshot.data?.docs ?? [];
                if (docs.isEmpty) {
                  return const Center(
                    child: Text('No users awaiting verification'),
                  );
                }
                return LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth;
                    int cross = 1;
                    if (width >= 1200)
                      cross = 3;
                    else if (width >= 900)
                      cross = 2;
                    return GridView.builder(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: cross,
                        mainAxisSpacing: 16,
                        crossAxisSpacing: 16,
                        childAspectRatio: 1.8,
                      ),
                      itemCount: docs.length,
                      itemBuilder: (context, index) {
                        final data = docs[index].data();
                        final uid = docs[index].id;
                        final name =
                            '${data['firstName'] ?? ''} ${data['lastName'] ?? ''}'
                                .trim();
                        final email = data['email'] ?? '';
                        final idType = data['barangayIdType'] ?? '';
                        final createdAtTs = data['createdAt'];
                        String joined = '';
                        if (createdAtTs is Timestamp) {
                          final d = createdAtTs.toDate();
                          joined = '${d.month}/${d.day}/${d.year}';
                        }
                        final isSelected = _selectedUserIds.contains(uid);
                        return Card(
                          elevation: 4,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: isSelected
                                    ? [Colors.blue[50]!, Colors.blue[100]!]
                                    : [Colors.white, const Color(0xFFF5F7FA)],
                              ),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: isSelected
                                    ? Colors.blue[300]!
                                    : Colors.grey[200]!,
                                width: isSelected ? 2 : 1,
                              ),
                            ),
                            child: InkWell(
                              onTap: _isSelectionMode
                                  ? () => _toggleUserSelection(uid)
                                  : () {
                                      showDialog(
                                        context: context,
                                        builder: (context) =>
                                            UserVerificationDetailDialog(
                                              uid: uid,
                                              userData: data,
                                              admin: admin,
                                            ),
                                      );
                                    },
                              borderRadius: BorderRadius.circular(16),
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        if (_isSelectionMode)
                                          Checkbox(
                                            value: isSelected,
                                            onChanged: (_) =>
                                                _toggleUserSelection(uid),
                                          ),
                                        CircleAvatar(
                                          radius: 24,
                                          backgroundColor: Colors.grey[300],
                                          backgroundImage:
                                              (data['profilePhotoUrl']
                                                          as String?)
                                                      ?.isNotEmpty ==
                                                  true
                                              ? NetworkImage(
                                                  data['profilePhotoUrl']
                                                      as String,
                                                )
                                              : null,
                                          child:
                                              ((data['profilePhotoUrl']
                                                          as String?)
                                                      ?.isEmpty ??
                                                  true)
                                              ? const Icon(
                                                  Icons.person,
                                                  size: 24,
                                                  color: Colors.white,
                                                )
                                              : null,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                name.isEmpty ? email : name,
                                                style: const TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                              Text(
                                                email,
                                                style: TextStyle(
                                                  color: Colors.grey[700],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const _StatusPill(
                                          text: 'Pending',
                                          color: Colors.orange,
                                        ),
                                      ],
                                    ),
                                    // Removed barangay ID image preview from card to keep list clean
                                    const SizedBox(height: 10),
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.calendar_today_outlined,
                                          size: 14,
                                          color: Colors.grey[600],
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          'Joined: $joined',
                                          style: TextStyle(
                                            color: Colors.grey[800],
                                            fontSize: 13,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.credit_card_outlined,
                                          size: 14,
                                          color: Colors.grey[600],
                                        ),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            'ID: ${idType.isEmpty ? 'Not provided' : idType}',
                                            style: TextStyle(
                                              color: Colors.grey[800],
                                              fontSize: 13,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 20),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Container(
                                            decoration: BoxDecoration(
                                              gradient: LinearGradient(
                                                colors: [
                                                  const Color(0xFF2E7D32),
                                                  const Color(0xFF1B5E20),
                                                ],
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: const Color(
                                                    0xFF2E7D32,
                                                  ).withOpacity(0.3),
                                                  blurRadius: 8,
                                                  offset: const Offset(0, 4),
                                                ),
                                              ],
                                            ),
                                            child: FilledButton.icon(
                                              style: FilledButton.styleFrom(
                                                backgroundColor:
                                                    Colors.transparent,
                                                shadowColor: Colors.transparent,
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      vertical: 12,
                                                    ),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                ),
                                              ),
                                              onPressed: () =>
                                                  admin.approveUser(uid),
                                              icon: const Icon(
                                                Icons.check,
                                                size: 18,
                                                color: Colors.white,
                                              ),
                                              label: const Text(
                                                'Approve',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: OutlinedButton.icon(
                                            style: OutlinedButton.styleFrom(
                                              foregroundColor: const Color(
                                                0xFFD32F2F,
                                              ),
                                              side: const BorderSide(
                                                color: Color(0xFFD32F2F),
                                                width: 1.5,
                                              ),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    vertical: 12,
                                                  ),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                            ),
                                            onPressed: () => _showRejectDialog(
                                              context,
                                              admin,
                                              uid,
                                              data,
                                            ),
                                            icon: const Icon(
                                              Icons.close,
                                              size: 18,
                                            ),
                                            label: const Text('Reject'),
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

class _StatusPill extends StatelessWidget {
  final String text;
  final Color color;
  const _StatusPill({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}
