import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;

class ExportService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Export users to CSV format
  Future<String> exportUsersToCSV({
    List<QueryDocumentSnapshot<Map<String, dynamic>>>? users,
  }) async {
    List<Map<String, dynamic>> userList;

    if (users != null) {
      userList = users.map((doc) => doc.data()).toList();
    } else {
      // Fetch all users if not provided
      final snapshot = await _db.collection('users').get();
      userList = snapshot.docs.map((doc) => doc.data()).toList();
    }

    final csv = StringBuffer();
    // CSV Header
    csv.writeln(
      'Email,First Name,Last Name,Verified,Suspended,Violations,Reputation Score,Joined Date,Barangay,City,Province',
    );

    // CSV Rows
    for (final user in userList) {
      final email = _escapeCSV(user['email']?.toString() ?? '');
      final firstName = _escapeCSV(user['firstName']?.toString() ?? '');
      final lastName = _escapeCSV(user['lastName']?.toString() ?? '');
      final isVerified = user['isVerified'] == true ? 'Yes' : 'No';
      final isSuspended = user['isSuspended'] == true ? 'Yes' : 'No';
      final violations = user['violationCount']?.toString() ?? '0';
      final reputation = user['reputationScore']?.toString() ?? '0.0';
      final createdAt = user['createdAt'] is Timestamp
          ? (user['createdAt'] as Timestamp).toDate().toString()
          : '';
      final barangay = _escapeCSV(user['barangay']?.toString() ?? '');
      final city = _escapeCSV(user['city']?.toString() ?? '');
      final province = _escapeCSV(user['province']?.toString() ?? '');

      csv.writeln(
        '$email,$firstName,$lastName,$isVerified,$isSuspended,$violations,$reputation,$createdAt,$barangay,$city,$province',
      );
    }

    return csv.toString();
  }

  /// Export reports to CSV format
  Future<String> exportReportsToCSV({
    List<QueryDocumentSnapshot<Map<String, dynamic>>>? reports,
    String? status,
  }) async {
    List<Map<String, dynamic>> reportList;

    if (reports != null) {
      reportList = reports.map((doc) => doc.data()).toList();
    } else {
      // Fetch reports based on status
      Query<Map<String, dynamic>> query = _db.collection('reports');
      if (status != null) {
        query = query.where('status', isEqualTo: status);
      }
      final snapshot = await query.get();
      reportList = snapshot.docs.map((doc) => doc.data()).toList();
    }

    final csv = StringBuffer();
    // CSV Header
    csv.writeln(
      'Report ID,Status,Reason,Reporter ID,Reported User ID,Reported User Name,Content Type,Content Title,Created Date,Resolved Date,Resolved By',
    );

    // CSV Rows
    for (final report in reportList) {
      final reportId = _escapeCSV(report['reportId']?.toString() ?? '');
      final status = _escapeCSV(report['status']?.toString() ?? '');
      final reason = _escapeCSV(report['reason']?.toString() ?? '');
      final reporterId = _escapeCSV(report['reporterId']?.toString() ?? '');
      final reportedUserId = _escapeCSV(
        report['reportedUserId']?.toString() ?? '',
      );
      final reportedUserName = _escapeCSV(
        report['reportedUserName']?.toString() ?? '',
      );
      final contentType = _escapeCSV(report['contentType']?.toString() ?? '');
      final contentTitle = _escapeCSV(report['contentTitle']?.toString() ?? '');
      final createdAt = report['createdAt'] is Timestamp
          ? (report['createdAt'] as Timestamp).toDate().toString()
          : '';
      final resolvedAt = report['resolvedAt'] is Timestamp
          ? (report['resolvedAt'] as Timestamp).toDate().toString()
          : '';
      final resolvedBy = _escapeCSV(report['resolvedBy']?.toString() ?? '');

      csv.writeln(
        '$reportId,$status,$reason,$reporterId,$reportedUserId,$reportedUserName,$contentType,$contentTitle,$createdAt,$resolvedAt,$resolvedBy',
      );
    }

    return csv.toString();
  }

  /// Export activity logs to CSV format
  Future<String> exportActivityLogsToCSV({
    List<Map<String, dynamic>>? logs,
  }) async {
    List<Map<String, dynamic>> logList;

    if (logs != null) {
      logList = logs;
    } else {
      // Fetch recent logs
      final snapshot = await _db
          .collection('activity_logs')
          .orderBy('timestamp', descending: true)
          .limit(1000)
          .get();
      logList = snapshot.docs.map((doc) => doc.data()).toList();
    }

    final csv = StringBuffer();
    // CSV Header
    csv.writeln(
      'Timestamp,Category,Action,Actor ID,Actor Name,Target ID,Target Type,Description,Severity',
    );

    // CSV Rows
    for (final log in logList) {
      final timestamp = log['timestamp'] is Timestamp
          ? (log['timestamp'] as Timestamp).toDate().toString()
          : '';
      final category = _escapeCSV(log['category']?.toString() ?? '');
      final action = _escapeCSV(log['action']?.toString() ?? '');
      final actorId = _escapeCSV(log['actorId']?.toString() ?? '');
      final actorName = _escapeCSV(log['actorName']?.toString() ?? '');
      final targetId = _escapeCSV(log['targetId']?.toString() ?? '');
      final targetType = _escapeCSV(log['targetType']?.toString() ?? '');
      final description = _escapeCSV(log['description']?.toString() ?? '');
      final severity = _escapeCSV(log['severity']?.toString() ?? '');

      csv.writeln(
        '$timestamp,$category,$action,$actorId,$actorName,$targetId,$targetType,$description,$severity',
      );
    }

    return csv.toString();
  }

  /// Save CSV to file (for mobile/desktop) or download (for web)
  Future<String> saveCSVToFile(String csvContent, String filename) async {
    if (kIsWeb) {
      // For web, return the content as base64 for download
      // The UI will handle the download using html package or similar
      return csvContent;
    } else {
      // For mobile/desktop, save to file
      // Note: This requires path_provider package
      // For now, return the content and let the UI handle saving
      debugPrint('CSV content ready: ${csvContent.length} characters');
      return csvContent;
    }
  }

  String _escapeCSV(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }

  /// Get quick stats for dashboard
  Future<Map<String, int>> getQuickStats() async {
    final stats = <String, int>{};

    // Unverified users
    final unverifiedSnapshot = await _db
        .collection('users')
        .where('isVerified', isEqualTo: false)
        .get();
    stats['unverifiedUsers'] = unverifiedSnapshot.docs.length;

    // Suspended users
    final suspendedSnapshot = await _db
        .collection('users')
        .where('isSuspended', isEqualTo: true)
        .get();
    stats['suspendedUsers'] = suspendedSnapshot.docs.length;

    // Open reports
    final openReportsSnapshot = await _db
        .collection('reports')
        .where('status', isEqualTo: 'open')
        .get();
    stats['openReports'] = openReportsSnapshot.docs.length;

    // Total users
    final totalUsersSnapshot = await _db.collection('users').count().get();
    stats['totalUsers'] = totalUsersSnapshot.count ?? 0;

    // Active items
    final activeItemsSnapshot = await _db.collection('items').get();
    stats['activeItems'] = activeItemsSnapshot.docs.length;

    // Pending borrow requests
    final borrowRequestsSnapshot = await _db
        .collection('borrow_requests')
        .where('status', isEqualTo: 'pending')
        .get();
    stats['pendingBorrowRequests'] = borrowRequestsSnapshot.docs.length;

    // Pending rental requests
    final rentalRequestsSnapshot = await _db
        .collection('rental_requests')
        .where('status', isEqualTo: 'pending')
        .get();
    stats['pendingRentalRequests'] = rentalRequestsSnapshot.docs.length;

    return stats;
  }
}
