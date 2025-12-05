import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../providers/admin_provider.dart';
import '../../../services/export_service.dart';

class ReportsTab extends StatefulWidget {
  const ReportsTab({super.key});

  @override
  State<ReportsTab> createState() => _ReportsTabState();
}

class _ReportsTabState extends State<ReportsTab> {
  String _status = 'open';

  String _getReportTitle(Map<String, dynamic> data) {
    // Check if it's a user report
    if (data['reportedUserId'] != null) {
      final reportedName = data['reportedUserName'] ?? 'Unknown User';
      return 'Report: $reportedName';
    }
    // Check if it's a content report
    if (data['contentType'] != null) {
      final contentType = data['contentType'] as String;
      final contentTitle = data['contentTitle'] ?? 'Unknown Content';
      return 'Report: $contentTitle ($contentType)';
    }
    return 'Report';
  }

  String _getReportSubtitle(Map<String, dynamic> data) {
    final reason = data['reason'] ?? 'No reason provided';
    final contextType = data['contextType'] ?? '';
    if (contextType.isNotEmpty) {
      return 'Reason: ${_formatReason(reason)} • Context: ${_formatContextType(contextType)}';
    }
    return 'Reason: ${_formatReason(reason)}';
  }

  String _formatReason(String reason) {
    return reason
        .split('_')
        .map((word) => word[0].toUpperCase() + word.substring(1))
        .join(' ');
  }

  String _formatContextType(String contextType) {
    return contextType[0].toUpperCase() + contextType.substring(1);
  }

  Future<void> _exportReports(BuildContext context) async {
    try {
      final exportService = ExportService();
      final admin = Provider.of<AdminProvider>(context, listen: false);

      // Get current reports from stream
      final snapshot = await admin.reportsStream(status: _status).first;
      final docs = snapshot.docs;

      final csv = await exportService.exportReportsToCSV(
        reports: docs,
        status: _status,
      );

      // Copy to clipboard
      await Clipboard.setData(ClipboardData(text: csv));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Exported ${docs.length} report(s) to CSV and copied to clipboard!',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error exporting: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Color _getReasonColor(String reason) {
    switch (reason.toLowerCase()) {
      case 'spam':
        return Colors.orange;
      case 'harassment':
        return Colors.red;
      case 'inappropriate_content':
        return Colors.purple;
      case 'fraud':
        return Colors.deepOrange;
      default:
        return Colors.grey;
    }
  }

  void _showReportDetails(
    BuildContext context,
    String reportId,
    Map<String, dynamic> data,
    AdminProvider admin,
  ) {
    final isUserReport = data['reportedUserId'] != null;
    final reportedUserId = data['reportedUserId'] as String?;
    final reportedUserName = data['reportedUserName'] ?? 'Unknown';
    final reporterName = data['reporterName'] ?? 'Unknown';
    final reason = data['reason'] ?? 'No reason';
    final description = data['description'] ?? '';
    final contextType = data['contextType'] ?? '';
    final createdAt = data['createdAt'] as Timestamp?;
    final resolvedAt = data['resolvedAt'] as Timestamp?;
    final evidenceImageUrls =
        (data['evidenceImageUrls'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        [];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.report, color: _getReasonColor(reason)),
            const SizedBox(width: 8),
            const Expanded(child: Text('Report Details')),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isUserReport) ...[
                _DetailRow('Reported User', reportedUserName),
                const SizedBox(height: 8),
              ] else ...[
                _DetailRow('Content Type', data['contentType'] ?? 'Unknown'),
                const SizedBox(height: 8),
                _DetailRow('Content Title', data['contentTitle'] ?? 'Unknown'),
                const SizedBox(height: 8),
                _DetailRow('Content Owner', data['ownerName'] ?? 'Unknown'),
                const SizedBox(height: 8),
              ],
              _DetailRow('Reporter', reporterName),
              const SizedBox(height: 8),
              _DetailRow('Reason', _formatReason(reason)),
              const SizedBox(height: 8),
              if (contextType.isNotEmpty) ...[
                _DetailRow('Context', _formatContextType(contextType)),
                const SizedBox(height: 8),
              ],
              if (description.isNotEmpty) ...[
                const Text(
                  'Description:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(description),
                ),
                const SizedBox(height: 8),
              ],
              if (createdAt != null) ...[
                _DetailRow('Reported At', _formatDate(createdAt.toDate())),
                const SizedBox(height: 8),
              ],
              if (resolvedAt != null) ...[
                _DetailRow('Resolved At', _formatDate(resolvedAt.toDate())),
                const SizedBox(height: 8),
              ],
              if (evidenceImageUrls.isNotEmpty) ...[
                const Text(
                  'Evidence Images:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 150,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: evidenceImageUrls.length,
                    itemBuilder: (context, index) {
                      return Container(
                        width: 150,
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: CachedNetworkImage(
                            imageUrl: evidenceImageUrls[index],
                            fit: BoxFit.cover,
                            placeholder: (context, url) => Container(
                              color: Colors.grey[300],
                              child: const Center(
                                child: CircularProgressIndicator(),
                              ),
                            ),
                            errorWidget: (context, url, error) => Container(
                              color: Colors.grey[300],
                              child: const Icon(
                                Icons.image_not_supported,
                                color: Colors.red,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ],
          ),
        ),
        actions: [
          if (_status == 'open') ...[
            if (isUserReport && reportedUserId != null)
              TextButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  _showFileViolationDialog(
                    context,
                    reportedUserId,
                    reportedUserName,
                    admin,
                  );
                },
                icon: const Icon(Icons.warning, color: Colors.orange),
                label: const Text('File Violation'),
              ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _showResolveDialog(
                  context,
                  reportId,
                  admin,
                  isUserReport,
                  reportedUserId,
                );
              },
              child: const Text('Resolve Report'),
            ),
          ],
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showResolveDialog(
    BuildContext context,
    String reportId,
    AdminProvider admin,
    bool isUserReport,
    String? reportedUserId,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Resolve Report'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('How would you like to resolve this report?'),
            const SizedBox(height: 16),
            if (isUserReport && reportedUserId != null)
              CheckboxListTile(
                title: const Text('File a violation against the reported user'),
                value: false,
                onChanged: (value) {
                  Navigator.pop(context);
                  admin.resolveReport(reportId);
                  _showFileViolationDialog(
                    context,
                    reportedUserId,
                    'User',
                    admin,
                  );
                },
                controlAffinity: ListTileControlAffinity.leading,
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              admin.resolveReport(reportId);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Report resolved successfully'),
                  backgroundColor: Colors.green,
                ),
              );
            },
            child: const Text('Resolve Without Violation'),
          ),
        ],
      ),
    );
  }

  void _showFileViolationDialog(
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

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final admin = Provider.of<AdminProvider>(context, listen: false);
    return Column(
      children: [
        Padding(
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
                        Icons.report_gmailerrorred,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 16),
                    const Expanded(
                      child: Text(
                        'Reports & Violations',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.download, color: Colors.white),
                      onPressed: () => _exportReports(context),
                      tooltip: 'Export reports to CSV',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey[300]!, width: 1),
                ),
                child: Row(
                  children: [
                    const Text(
                      'Status:',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(width: 12),
                    DropdownButton<String>(
                      value: _status,
                      items: const [
                        DropdownMenuItem(value: 'open', child: Text('Open')),
                        DropdownMenuItem(
                          value: 'resolved',
                          child: Text('Resolved'),
                        ),
                      ],
                      onChanged: (v) => setState(() => _status = v ?? 'open'),
                      style: const TextStyle(fontSize: 16),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: admin.reportsStream(status: _status),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(child: Text('Error: ${snapshot.error}'));
              }
              final docs = snapshot.data?.docs ?? [];
              if (docs.isEmpty) {
                return const Center(
                  child: Text(
                    'No reports',
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: docs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final id = docs[index].id;
                  final d = docs[index].data();
                  final title = _getReportTitle(d);
                  final subtitle = _getReportSubtitle(d);
                  final reason = d['reason'] ?? 'other';
                  final isUserReport = d['reportedUserId'] != null;
                  final reportedUserId = d['reportedUserId'] as String?;

                  return Card(
                    elevation: 3,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: InkWell(
                      onTap: () => _showReportDetails(context, id, d, admin),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Colors.white, const Color(0xFFF5F7FA)],
                          ),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.grey[200]!,
                            width: 1,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _getReasonColor(
                                        reason,
                                      ).withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      _formatReason(reason),
                                      style: TextStyle(
                                        color: _getReasonColor(reason),
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                  const Spacer(),
                                  if (_status == 'open')
                                    Icon(
                                      Icons.radio_button_unchecked,
                                      color: Colors.orange,
                                      size: 16,
                                    )
                                  else
                                    Icon(
                                      Icons.check_circle,
                                      color: Colors.green,
                                      size: 16,
                                    ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                title,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                subtitle,
                                style: TextStyle(
                                  color: Colors.grey[700],
                                  fontSize: 14,
                                ),
                              ),
                              if (d['description'] != null &&
                                  (d['description'] as String).isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(
                                  (d['description'] as String).length > 100
                                      ? '${(d['description'] as String).substring(0, 100)}...'
                                      : d['description'] as String,
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 13,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                              if (_status == 'open') ...[
                                const SizedBox(height: 12),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    if (isUserReport && reportedUserId != null)
                                      TextButton.icon(
                                        onPressed: () {
                                          _showFileViolationDialog(
                                            context,
                                            reportedUserId,
                                            d['reportedUserName'] ?? 'User',
                                            admin,
                                          );
                                        },
                                        icon: const Icon(
                                          Icons.warning,
                                          size: 18,
                                          color: Colors.orange,
                                        ),
                                        label: const Text(
                                          'File Violation',
                                          style: TextStyle(
                                            color: Colors.orange,
                                          ),
                                        ),
                                        style: TextButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 8,
                                          ),
                                        ),
                                      ),
                                    const SizedBox(width: 8),
                                    Container(
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [
                                            const Color(0xFF00897B),
                                            const Color(0xFF00695C),
                                          ],
                                        ),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: TextButton(
                                        style: TextButton.styleFrom(
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 8,
                                          ),
                                        ),
                                        onPressed: () {
                                          _showResolveDialog(
                                            context,
                                            id,
                                            admin,
                                            isUserReport,
                                            reportedUserId,
                                          );
                                        },
                                        child: const Text('Resolve'),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
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
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: Text(
            '$label:',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
        ),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 14))),
      ],
    );
  }
}
