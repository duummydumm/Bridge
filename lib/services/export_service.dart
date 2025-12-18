import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'dart:convert';
import 'dart:typed_data';
import 'package:excel/excel.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:universal_html/html.dart' as html show Blob, Url, AnchorElement;

/// Export format enum
enum ExportFormat { csv, json, excel, pdf }

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

  /// Export users with format selection
  Future<String> exportUsers({
    List<QueryDocumentSnapshot<Map<String, dynamic>>>? users,
    required ExportFormat format,
  }) async {
    switch (format) {
      case ExportFormat.csv:
        return await exportUsersToCSV(users: users);
      case ExportFormat.json:
        return await exportUsersToJSON(users: users);
      case ExportFormat.excel:
        return await exportUsersToExcel(users: users);
      case ExportFormat.pdf:
        return await exportUsersToPDF(users: users);
    }
  }

  /// Export users to JSON format
  Future<String> exportUsersToJSON({
    List<QueryDocumentSnapshot<Map<String, dynamic>>>? users,
  }) async {
    List<Map<String, dynamic>> userList;

    if (users != null) {
      userList = users.map((doc) {
        final data = doc.data();
        // Convert Timestamp to ISO string for JSON
        if (data['createdAt'] is Timestamp) {
          data['createdAt'] = (data['createdAt'] as Timestamp)
              .toDate()
              .toIso8601String();
        }
        if (data['updatedAt'] is Timestamp) {
          data['updatedAt'] = (data['updatedAt'] as Timestamp)
              .toDate()
              .toIso8601String();
        }
        return data;
      }).toList();
    } else {
      final snapshot = await _db.collection('users').get();
      userList = snapshot.docs.map((doc) {
        final data = doc.data();
        if (data['createdAt'] is Timestamp) {
          data['createdAt'] = (data['createdAt'] as Timestamp)
              .toDate()
              .toIso8601String();
        }
        if (data['updatedAt'] is Timestamp) {
          data['updatedAt'] = (data['updatedAt'] as Timestamp)
              .toDate()
              .toIso8601String();
        }
        return data;
      }).toList();
    }

    final exportData = {
      'exportDate': DateTime.now().toIso8601String(),
      'totalRecords': userList.length,
      'data': userList,
    };

    return const JsonEncoder.withIndent('  ').convert(exportData);
  }

  /// Export reports with format selection
  Future<String> exportReports({
    List<QueryDocumentSnapshot<Map<String, dynamic>>>? reports,
    String? status,
    required ExportFormat format,
  }) async {
    switch (format) {
      case ExportFormat.csv:
        return await exportReportsToCSV(reports: reports, status: status);
      case ExportFormat.json:
        return await exportReportsToJSON(reports: reports, status: status);
      case ExportFormat.excel:
        return await exportReportsToExcel(reports: reports, status: status);
      case ExportFormat.pdf:
        return await exportReportsToPDF(reports: reports, status: status);
    }
  }

  /// Export reports to JSON format
  Future<String> exportReportsToJSON({
    List<QueryDocumentSnapshot<Map<String, dynamic>>>? reports,
    String? status,
  }) async {
    List<Map<String, dynamic>> reportList;

    if (reports != null) {
      reportList = reports.map((doc) {
        final data = doc.data();
        if (data['createdAt'] is Timestamp) {
          data['createdAt'] = (data['createdAt'] as Timestamp)
              .toDate()
              .toIso8601String();
        }
        if (data['resolvedAt'] is Timestamp) {
          data['resolvedAt'] = (data['resolvedAt'] as Timestamp)
              .toDate()
              .toIso8601String();
        }
        return data;
      }).toList();
    } else {
      Query<Map<String, dynamic>> query = _db.collection('reports');
      if (status != null) {
        query = query.where('status', isEqualTo: status);
      }
      final snapshot = await query.get();
      reportList = snapshot.docs.map((doc) {
        final data = doc.data();
        if (data['createdAt'] is Timestamp) {
          data['createdAt'] = (data['createdAt'] as Timestamp)
              .toDate()
              .toIso8601String();
        }
        if (data['resolvedAt'] is Timestamp) {
          data['resolvedAt'] = (data['resolvedAt'] as Timestamp)
              .toDate()
              .toIso8601String();
        }
        return data;
      }).toList();
    }

    final exportData = {
      'exportDate': DateTime.now().toIso8601String(),
      'status': status ?? 'all',
      'totalRecords': reportList.length,
      'data': reportList,
    };

    return const JsonEncoder.withIndent('  ').convert(exportData);
  }

  /// Export activity logs with format selection
  Future<String> exportActivityLogs({
    List<Map<String, dynamic>>? logs,
    required ExportFormat format,
  }) async {
    switch (format) {
      case ExportFormat.csv:
        return await exportActivityLogsToCSV(logs: logs);
      case ExportFormat.json:
        return await exportActivityLogsToJSON(logs: logs);
      case ExportFormat.excel:
        return await exportActivityLogsToExcel(logs: logs);
      case ExportFormat.pdf:
        return await exportActivityLogsToPDF(logs: logs);
    }
  }

  /// Export activity logs to JSON format
  Future<String> exportActivityLogsToJSON({
    List<Map<String, dynamic>>? logs,
  }) async {
    List<Map<String, dynamic>> logList;

    if (logs != null) {
      logList = logs.map((log) {
        final data = Map<String, dynamic>.from(log);
        if (data['timestamp'] is Timestamp) {
          data['timestamp'] = (data['timestamp'] as Timestamp)
              .toDate()
              .toIso8601String();
        }
        return data;
      }).toList();
    } else {
      final snapshot = await _db
          .collection('activity_logs')
          .orderBy('timestamp', descending: true)
          .limit(1000)
          .get();
      logList = snapshot.docs.map((doc) {
        final data = doc.data();
        if (data['timestamp'] is Timestamp) {
          data['timestamp'] = (data['timestamp'] as Timestamp)
              .toDate()
              .toIso8601String();
        }
        return data;
      }).toList();
    }

    final exportData = {
      'exportDate': DateTime.now().toIso8601String(),
      'totalRecords': logList.length,
      'data': logList,
    };

    return const JsonEncoder.withIndent('  ').convert(exportData);
  }

  /// Export users to Excel format
  Future<String> exportUsersToExcel({
    List<QueryDocumentSnapshot<Map<String, dynamic>>>? users,
  }) async {
    List<Map<String, dynamic>> userList;

    if (users != null) {
      userList = users.map((doc) => doc.data()).toList();
    } else {
      final snapshot = await _db.collection('users').get();
      userList = snapshot.docs.map((doc) => doc.data()).toList();
    }

    final excel = Excel.createExcel();
    excel.delete('Sheet1'); // Delete default sheet
    final sheet = excel['Users'];

    // Headers
    final headers = [
      'Email',
      'First Name',
      'Last Name',
      'Verified',
      'Suspended',
      'Violations',
      'Reputation Score',
      'Joined Date',
      'Barangay',
      'City',
      'Province',
    ];

    // Write headers
    for (int i = 0; i < headers.length; i++) {
      final cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0),
      );
      cell.value = headers[i];
      cell.cellStyle = CellStyle(bold: true, backgroundColorHex: '#E8F5E9');
    }

    // Write data
    for (int row = 0; row < userList.length; row++) {
      final user = userList[row];
      final values = [
        user['email']?.toString() ?? '',
        user['firstName']?.toString() ?? '',
        user['lastName']?.toString() ?? '',
        user['isVerified'] == true ? 'Yes' : 'No',
        user['isSuspended'] == true ? 'Yes' : 'No',
        user['violationCount']?.toString() ?? '0',
        user['reputationScore']?.toString() ?? '0.0',
        user['createdAt'] is Timestamp
            ? (user['createdAt'] as Timestamp).toDate().toString()
            : '',
        user['barangay']?.toString() ?? '',
        user['city']?.toString() ?? '',
        user['province']?.toString() ?? '',
      ];

      for (int col = 0; col < values.length; col++) {
        final cell = sheet.cell(
          CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row + 1),
        );
        cell.value = values[col];
      }
    }

    // Convert to bytes
    final excelBytes = excel.encode();
    if (excelBytes != null) {
      final bytes = Uint8List.fromList(excelBytes);
      // Trigger download/share (file is generated and downloaded/shared)
      await downloadOrShareFile(
        bytes: bytes,
        filename: 'users_export.xlsx',
        mimeType:
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
      // Return empty string - file is downloaded, not copied to clipboard
      return '';
    }
    return '';
  }

  /// Export reports to Excel format
  Future<String> exportReportsToExcel({
    List<QueryDocumentSnapshot<Map<String, dynamic>>>? reports,
    String? status,
  }) async {
    List<Map<String, dynamic>> reportList;

    if (reports != null) {
      reportList = reports.map((doc) => doc.data()).toList();
    } else {
      Query<Map<String, dynamic>> query = _db.collection('reports');
      if (status != null) {
        query = query.where('status', isEqualTo: status);
      }
      final snapshot = await query.get();
      reportList = snapshot.docs.map((doc) => doc.data()).toList();
    }

    final excel = Excel.createExcel();
    excel.delete('Sheet1');
    final sheet = excel['Reports'];

    // Headers
    final headers = [
      'Report ID',
      'Status',
      'Reason',
      'Reporter ID',
      'Reported User ID',
      'Reported User Name',
      'Content Type',
      'Content Title',
      'Created Date',
      'Resolved Date',
      'Resolved By',
    ];

    // Write headers
    for (int i = 0; i < headers.length; i++) {
      final cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0),
      );
      cell.value = headers[i];
      cell.cellStyle = CellStyle(bold: true, backgroundColorHex: '#FFEBEE');
    }

    // Write data
    for (int row = 0; row < reportList.length; row++) {
      final report = reportList[row];
      final values = [
        report['reportId']?.toString() ?? '',
        report['status']?.toString() ?? '',
        report['reason']?.toString() ?? '',
        report['reporterId']?.toString() ?? '',
        report['reportedUserId']?.toString() ?? '',
        report['reportedUserName']?.toString() ?? '',
        report['contentType']?.toString() ?? '',
        report['contentTitle']?.toString() ?? '',
        report['createdAt'] is Timestamp
            ? (report['createdAt'] as Timestamp).toDate().toString()
            : '',
        report['resolvedAt'] is Timestamp
            ? (report['resolvedAt'] as Timestamp).toDate().toString()
            : '',
        report['resolvedBy']?.toString() ?? '',
      ];

      for (int col = 0; col < values.length; col++) {
        final cell = sheet.cell(
          CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row + 1),
        );
        cell.value = values[col];
      }
    }

    final excelBytes = excel.encode();
    if (excelBytes != null) {
      final bytes = Uint8List.fromList(excelBytes);
      await downloadOrShareFile(
        bytes: bytes,
        filename: 'reports_export.xlsx',
        mimeType:
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
      // File is downloaded/shared, return empty string
      return '';
    }
    return '';
  }

  /// Export activity logs to Excel format
  Future<String> exportActivityLogsToExcel({
    List<Map<String, dynamic>>? logs,
  }) async {
    List<Map<String, dynamic>> logList;

    if (logs != null) {
      logList = logs;
    } else {
      final snapshot = await _db
          .collection('activity_logs')
          .orderBy('timestamp', descending: true)
          .limit(1000)
          .get();
      logList = snapshot.docs.map((doc) => doc.data()).toList();
    }

    final excel = Excel.createExcel();
    excel.delete('Sheet1');
    final sheet = excel['Activity Logs'];

    // Headers
    final headers = [
      'Timestamp',
      'Category',
      'Action',
      'Actor ID',
      'Actor Name',
      'Target ID',
      'Target Type',
      'Description',
      'Severity',
    ];

    // Write headers
    for (int i = 0; i < headers.length; i++) {
      final cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0),
      );
      cell.value = headers[i];
      cell.cellStyle = CellStyle(bold: true, backgroundColorHex: '#E3F2FD');
    }

    // Write data
    for (int row = 0; row < logList.length; row++) {
      final log = logList[row];
      final values = [
        log['timestamp'] is Timestamp
            ? (log['timestamp'] as Timestamp).toDate().toString()
            : '',
        log['category']?.toString() ?? '',
        log['action']?.toString() ?? '',
        log['actorId']?.toString() ?? '',
        log['actorName']?.toString() ?? '',
        log['targetId']?.toString() ?? '',
        log['targetType']?.toString() ?? '',
        log['description']?.toString() ?? '',
        log['severity']?.toString() ?? '',
      ];

      for (int col = 0; col < values.length; col++) {
        final cell = sheet.cell(
          CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row + 1),
        );
        cell.value = values[col];
      }
    }

    final excelBytes = excel.encode();
    if (excelBytes != null) {
      final bytes = Uint8List.fromList(excelBytes);
      await downloadOrShareFile(
        bytes: bytes,
        filename: 'activity_logs_export.xlsx',
        mimeType:
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
      // File is downloaded/shared, return empty string
      return '';
    }
    return '';
  }

  /// Export users to PDF format
  Future<String> exportUsersToPDF({
    List<QueryDocumentSnapshot<Map<String, dynamic>>>? users,
  }) async {
    List<Map<String, dynamic>> userList;

    if (users != null) {
      userList = users.map((doc) => doc.data()).toList();
    } else {
      final snapshot = await _db.collection('users').get();
      userList = snapshot.docs.map((doc) => doc.data()).toList();
    }

    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (pw.Context context) {
          return [
            pw.Header(
              level: 0,
              child: pw.Text(
                'Users Export Report',
                style: pw.TextStyle(
                  fontSize: 24,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.SizedBox(height: 20),
            pw.Text(
              'Generated: ${DateTime.now().toString()}',
              style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
            ),
            pw.SizedBox(height: 20),
            pw.TableHelper.fromTextArray(
              headers: [
                'Email',
                'Name',
                'Verified',
                'Suspended',
                'Violations',
                'Reputation',
              ],
              data: userList.map((user) {
                return [
                  user['email']?.toString() ?? '',
                  '${user['firstName'] ?? ''} ${user['lastName'] ?? ''}'.trim(),
                  user['isVerified'] == true ? 'Yes' : 'No',
                  user['isSuspended'] == true ? 'Yes' : 'No',
                  user['violationCount']?.toString() ?? '0',
                  user['reputationScore']?.toString() ?? '0.0',
                ];
              }).toList(),
              headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
              ),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.teal700,
              ),
              cellAlignment: pw.Alignment.centerLeft,
              cellPadding: const pw.EdgeInsets.all(5),
            ),
            pw.SizedBox(height: 20),
            pw.Text(
              'Total Users: ${userList.length}',
              style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
            ),
          ];
        },
      ),
    );

    // Convert PDF to bytes
    final pdfBytes = await pdf.save();
    // Trigger download/share (file is generated and downloaded/shared)
    await downloadOrShareFile(
      bytes: pdfBytes,
      filename: 'users_export.pdf',
      mimeType: 'application/pdf',
    );
    // File is downloaded/shared, return empty string
    return '';
  }

  /// Export reports to PDF format
  Future<String> exportReportsToPDF({
    List<QueryDocumentSnapshot<Map<String, dynamic>>>? reports,
    String? status,
  }) async {
    List<Map<String, dynamic>> reportList;

    if (reports != null) {
      reportList = reports.map((doc) => doc.data()).toList();
    } else {
      Query<Map<String, dynamic>> query = _db.collection('reports');
      if (status != null) {
        query = query.where('status', isEqualTo: status);
      }
      final snapshot = await query.get();
      reportList = snapshot.docs.map((doc) => doc.data()).toList();
    }

    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (pw.Context context) {
          return [
            pw.Header(
              level: 0,
              child: pw.Text(
                'Reports Export',
                style: pw.TextStyle(
                  fontSize: 24,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.SizedBox(height: 10),
            pw.Text(
              'Status: ${status ?? 'All'} | Generated: ${DateTime.now().toString()}',
              style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
            ),
            pw.SizedBox(height: 20),
            pw.TableHelper.fromTextArray(
              headers: [
                'Status',
                'Reason',
                'Reported User',
                'Content Type',
                'Created Date',
              ],
              data: reportList.map((report) {
                return [
                  report['status']?.toString() ?? '',
                  report['reason']?.toString() ?? '',
                  report['reportedUserName']?.toString() ?? 'N/A',
                  report['contentType']?.toString() ?? 'N/A',
                  report['createdAt'] is Timestamp
                      ? (report['createdAt'] as Timestamp).toDate().toString()
                      : '',
                ];
              }).toList(),
              headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
              ),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.red700),
              cellAlignment: pw.Alignment.centerLeft,
              cellPadding: const pw.EdgeInsets.all(5),
            ),
            pw.SizedBox(height: 20),
            pw.Text(
              'Total Reports: ${reportList.length}',
              style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
            ),
          ];
        },
      ),
    );

    final pdfBytes = await pdf.save();
    await downloadOrShareFile(
      bytes: pdfBytes,
      filename: 'reports_export.pdf',
      mimeType: 'application/pdf',
    );
    // File is downloaded/shared, return empty string
    return '';
  }

  /// Export activity logs to PDF format
  Future<String> exportActivityLogsToPDF({
    List<Map<String, dynamic>>? logs,
  }) async {
    List<Map<String, dynamic>> logList;

    if (logs != null) {
      logList = logs;
    } else {
      final snapshot = await _db
          .collection('activity_logs')
          .orderBy('timestamp', descending: true)
          .limit(1000)
          .get();
      logList = snapshot.docs.map((doc) => doc.data()).toList();
    }

    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (pw.Context context) {
          return [
            pw.Header(
              level: 0,
              child: pw.Text(
                'Activity Logs Export',
                style: pw.TextStyle(
                  fontSize: 24,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.SizedBox(height: 10),
            pw.Text(
              'Generated: ${DateTime.now().toString()}',
              style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
            ),
            pw.SizedBox(height: 20),
            pw.TableHelper.fromTextArray(
              headers: [
                'Timestamp',
                'Category',
                'Action',
                'Actor',
                'Target',
                'Severity',
              ],
              data: logList.map((log) {
                return [
                  log['timestamp'] is Timestamp
                      ? (log['timestamp'] as Timestamp).toDate().toString()
                      : '',
                  log['category']?.toString() ?? '',
                  log['action']?.toString() ?? '',
                  log['actorName']?.toString() ?? 'N/A',
                  log['targetType']?.toString() ?? 'N/A',
                  log['severity']?.toString() ?? '',
                ];
              }).toList(),
              headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
              ),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.blue700,
              ),
              cellAlignment: pw.Alignment.centerLeft,
              cellPadding: const pw.EdgeInsets.all(5),
            ),
            pw.SizedBox(height: 20),
            pw.Text(
              'Total Logs: ${logList.length}',
              style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
            ),
          ];
        },
      ),
    );

    final pdfBytes = await pdf.save();
    await downloadOrShareFile(
      bytes: pdfBytes,
      filename: 'activity_logs_export.pdf',
      mimeType: 'application/pdf',
    );
    // File is downloaded/shared, return empty string
    return '';
  }

  /// Download or share file (web/mobile)
  Future<void> downloadOrShareFile({
    required Uint8List bytes,
    required String filename,
    required String mimeType,
  }) async {
    try {
      if (kIsWeb) {
        // For web, create a blob URL and trigger download
        final blob = html.Blob([bytes], mimeType);
        final url = html.Url.createObjectUrlFromBlob(blob);
        html.AnchorElement(href: url)
          ..setAttribute('download', filename)
          ..click();
        html.Url.revokeObjectUrl(url);
        debugPrint('File download triggered: $filename');
      } else {
        // For mobile, save to temp directory and share
        final tempDir = await getTemporaryDirectory();
        final file = File('${tempDir.path}/$filename');
        await file.writeAsBytes(bytes);
        await Share.shareXFiles([XFile(file.path)], text: 'Exported $filename');
      }
    } catch (e) {
      debugPrint('Error downloading/sharing file: $e');
      // Fallback: continue even if download fails
    }
  }

  /// Get file extension for format
  String getFileExtension(ExportFormat format) {
    switch (format) {
      case ExportFormat.csv:
        return 'csv';
      case ExportFormat.json:
        return 'json';
      case ExportFormat.excel:
        return 'xlsx';
      case ExportFormat.pdf:
        return 'pdf';
    }
  }

  /// Get MIME type for format
  String getMimeType(ExportFormat format) {
    switch (format) {
      case ExportFormat.csv:
        return 'text/csv';
      case ExportFormat.json:
        return 'application/json';
      case ExportFormat.excel:
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case ExportFormat.pdf:
        return 'application/pdf';
    }
  }

  String _escapeCSV(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }

  /// Export notifications
  Future<String> exportNotifications({
    required ExportFormat format,
    List<QueryDocumentSnapshot<Map<String, dynamic>>>? notifications,
  }) async {
    switch (format) {
      case ExportFormat.csv:
        return await exportNotificationsToCSV(notifications: notifications);
      case ExportFormat.json:
        return await exportNotificationsToJSON(notifications: notifications);
      case ExportFormat.excel:
        await exportNotificationsToExcel(notifications: notifications);
        return '';
      case ExportFormat.pdf:
        await exportNotificationsToPDF(notifications: notifications);
        return '';
    }
  }

  /// Export notifications to CSV format
  Future<String> exportNotificationsToCSV({
    List<QueryDocumentSnapshot<Map<String, dynamic>>>? notifications,
  }) async {
    List<Map<String, dynamic>> notificationList;

    if (notifications != null) {
      notificationList = notifications.map((doc) => doc.data()).toList();
    } else {
      final snapshot = await _db.collection('notifications').get();
      notificationList = snapshot.docs.map((doc) => doc.data()).toList();
    }

    final csv = StringBuffer();
    csv.writeln(
      'Type,Title,Message,Status,Created At,Event ID,User ID,Donor Name,Quantity,Item Type',
    );

    for (final notification in notificationList) {
      final type = _escapeCSV(notification['type']?.toString() ?? '');
      final title = _escapeCSV(notification['title']?.toString() ?? '');
      final message = _escapeCSV(notification['message']?.toString() ?? '');
      final status = _escapeCSV(notification['status']?.toString() ?? '');
      final createdAt = notification['createdAt'] is Timestamp
          ? (notification['createdAt'] as Timestamp).toDate().toString()
          : '';
      final eventId = _escapeCSV(notification['eventId']?.toString() ?? '');
      final userId = _escapeCSV(notification['userId']?.toString() ?? '');
      final donorName = _escapeCSV(notification['donorName']?.toString() ?? '');
      final quantity = notification['quantity']?.toString() ?? '';
      final itemType = _escapeCSV(notification['itemType']?.toString() ?? '');

      csv.writeln(
        '$type,$title,$message,$status,$createdAt,$eventId,$userId,$donorName,$quantity,$itemType',
      );
    }

    return csv.toString();
  }

  /// Export notifications to JSON format
  Future<String> exportNotificationsToJSON({
    List<QueryDocumentSnapshot<Map<String, dynamic>>>? notifications,
  }) async {
    List<Map<String, dynamic>> notificationList;

    if (notifications != null) {
      notificationList = notifications.map((doc) {
        final data = doc.data();
        // Convert Timestamp to ISO string
        if (data['createdAt'] is Timestamp) {
          data['createdAt'] = (data['createdAt'] as Timestamp)
              .toDate()
              .toIso8601String();
        }
        return data;
      }).toList();
    } else {
      final snapshot = await _db.collection('notifications').get();
      notificationList = snapshot.docs.map((doc) {
        final data = doc.data();
        if (data['createdAt'] is Timestamp) {
          data['createdAt'] = (data['createdAt'] as Timestamp)
              .toDate()
              .toIso8601String();
        }
        return data;
      }).toList();
    }

    return const JsonEncoder.withIndent('  ').convert(notificationList);
  }

  /// Export notifications to Excel format
  Future<void> exportNotificationsToExcel({
    List<QueryDocumentSnapshot<Map<String, dynamic>>>? notifications,
  }) async {
    List<Map<String, dynamic>> notificationList;

    if (notifications != null) {
      notificationList = notifications.map((doc) => doc.data()).toList();
    } else {
      final snapshot = await _db.collection('notifications').get();
      notificationList = snapshot.docs.map((doc) => doc.data()).toList();
    }

    final excel = Excel.createExcel();
    excel.delete('Sheet1');
    final sheet = excel['Notifications'];

    // Headers
    final headers = [
      'Type',
      'Title',
      'Message',
      'Status',
      'Created At',
      'Event ID',
      'User ID',
      'Donor Name',
      'Quantity',
      'Item Type',
    ];

    for (int col = 0; col < headers.length; col++) {
      final cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 0),
      );
      cell.value = headers[col];
    }

    // Data rows
    for (int row = 0; row < notificationList.length; row++) {
      final notification = notificationList[row];
      final values = [
        notification['type']?.toString() ?? '',
        notification['title']?.toString() ?? '',
        notification['message']?.toString() ?? '',
        notification['status']?.toString() ?? '',
        notification['createdAt'] is Timestamp
            ? (notification['createdAt'] as Timestamp).toDate().toString()
            : '',
        notification['eventId']?.toString() ?? '',
        notification['userId']?.toString() ?? '',
        notification['donorName']?.toString() ?? '',
        notification['quantity']?.toString() ?? '',
        notification['itemType']?.toString() ?? '',
      ];

      for (int col = 0; col < values.length; col++) {
        final cell = sheet.cell(
          CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row + 1),
        );
        cell.value = values[col];
      }
    }

    final excelBytes = excel.encode();
    if (excelBytes != null) {
      final bytes = Uint8List.fromList(excelBytes);
      await downloadOrShareFile(
        bytes: bytes,
        filename: 'notifications_export.xlsx',
        mimeType:
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
    }
  }

  /// Export notifications to PDF format
  Future<void> exportNotificationsToPDF({
    List<QueryDocumentSnapshot<Map<String, dynamic>>>? notifications,
  }) async {
    List<Map<String, dynamic>> notificationList;

    if (notifications != null) {
      notificationList = notifications.map((doc) => doc.data()).toList();
    } else {
      final snapshot = await _db.collection('notifications').get();
      notificationList = snapshot.docs.map((doc) => doc.data()).toList();
    }

    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (pw.Context context) {
          return [
            pw.Header(
              level: 0,
              child: pw.Text(
                'Notifications Export Report',
                style: pw.TextStyle(
                  fontSize: 24,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.SizedBox(height: 20),
            pw.Text(
              'Generated: ${DateTime.now().toString()}',
              style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
            ),
            pw.SizedBox(height: 20),
            pw.TableHelper.fromTextArray(
              headers: ['Type', 'Title', 'Status', 'Created At'],
              data: notificationList.map((notification) {
                return [
                  notification['type']?.toString() ?? '',
                  (notification['title']?.toString() ?? '').length > 30
                      ? '${(notification['title']?.toString() ?? '').substring(0, 30)}...'
                      : notification['title']?.toString() ?? '',
                  notification['status']?.toString() ?? '',
                  notification['createdAt'] is Timestamp
                      ? (notification['createdAt'] as Timestamp)
                            .toDate()
                            .toString()
                      : '',
                ];
              }).toList(),
              headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
              ),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.teal700,
              ),
              cellAlignment: pw.Alignment.centerLeft,
              cellPadding: const pw.EdgeInsets.all(5),
            ),
          ];
        },
      ),
    );

    final pdfBytes = await pdf.save();
    await downloadOrShareFile(
      bytes: Uint8List.fromList(pdfBytes),
      filename: 'notifications_export.pdf',
      mimeType: 'application/pdf',
    );
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
