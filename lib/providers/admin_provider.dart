import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/admin_service.dart';
import '../services/analytics_service.dart';

class AdminProvider extends ChangeNotifier {
  final AdminService _adminService = AdminService();

  bool _isBusy = false;
  String? _error;
  Map<String, dynamic>? _analytics;
  AdminAnalyticsData? _analyticsData;

  bool get isBusy => _isBusy;
  String? get error => _error;
  Map<String, dynamic>? get analytics => _analytics;
  AdminAnalyticsData? get analyticsData => _analyticsData;

  Stream<QuerySnapshot<Map<String, dynamic>>> get unverifiedUsersStream =>
      _adminService.streamUnverifiedUsers();

  Stream<QuerySnapshot<Map<String, dynamic>>> get borrowRequestsStream =>
      _adminService.streamBorrowRequests();

  Stream<QuerySnapshot<Map<String, dynamic>>> get rentalRequestsStream =>
      _adminService.streamRentalRequests();

  Stream<QuerySnapshot<Map<String, dynamic>>> get tradeOffersStream =>
      _adminService.streamTradeOffers();

  Stream<QuerySnapshot<Map<String, dynamic>>> get giveawayClaimsStream =>
      _adminService.streamGiveawayClaims();

  Stream<QuerySnapshot<Map<String, dynamic>>> get itemsStream =>
      _adminService.streamItems();

  Stream<QuerySnapshot<Map<String, dynamic>>> reportsStream({
    String status = 'open',
  }) => _adminService.streamReports(status: status);

  Future<void> approveUser(String uid) async {
    await _adminService.approveUser(uid);
  }

  Future<void> rejectUser(String uid, {String? reason}) async {
    await _adminService.rejectUser(uid, reason: reason);
  }

  Future<void> suspendUser(String uid, {String? reason}) async {
    await _adminService.suspendUser(uid, reason: reason);
  }

  Future<void> restoreUser(String uid) async {
    await _adminService.restoreUser(uid);
  }

  Future<void> fileViolation(String userId, {String? note}) async {
    await _adminService.fileViolation(userId: userId, note: note);
  }

  Future<void> resolveReport(
    String reportId, {
    String resolution = 'resolved',
  }) async {
    await _adminService.resolveReport(reportId, resolution: resolution);
  }

  // Bulk operations
  Future<BulkOperationResult> bulkApproveUsers(List<String> uids) async {
    _setBusy(true);
    _clearError();
    try {
      final result = await _adminService.bulkApproveUsers(uids);
      return result;
    } catch (e) {
      _setError(e.toString());
      rethrow;
    } finally {
      _setBusy(false);
      notifyListeners();
    }
  }

  Future<BulkOperationResult> bulkRejectUsers(
    List<String> uids, {
    String? reason,
  }) async {
    _setBusy(true);
    _clearError();
    try {
      final result = await _adminService.bulkRejectUsers(uids, reason: reason);
      return result;
    } catch (e) {
      _setError(e.toString());
      rethrow;
    } finally {
      _setBusy(false);
      notifyListeners();
    }
  }

  Future<BulkOperationResult> bulkSuspendUsers(
    List<String> uids, {
    String? reason,
  }) async {
    _setBusy(true);
    _clearError();
    try {
      final result = await _adminService.bulkSuspendUsers(uids, reason: reason);
      return result;
    } catch (e) {
      _setError(e.toString());
      rethrow;
    } finally {
      _setBusy(false);
      notifyListeners();
    }
  }

  Future<BulkOperationResult> bulkRestoreUsers(List<String> uids) async {
    _setBusy(true);
    _clearError();
    try {
      final result = await _adminService.bulkRestoreUsers(uids);
      return result;
    } catch (e) {
      _setError(e.toString());
      rethrow;
    } finally {
      _setBusy(false);
      notifyListeners();
    }
  }

  Future<BulkOperationResult> bulkResolveReports(
    List<String> reportIds, {
    String resolution = 'resolved',
  }) async {
    _setBusy(true);
    _clearError();
    try {
      final result = await _adminService.bulkResolveReports(
        reportIds,
        resolution: resolution,
      );
      return result;
    } catch (e) {
      _setError(e.toString());
      rethrow;
    } finally {
      _setBusy(false);
      notifyListeners();
    }
  }

  Future<void> loadAnalytics() async {
    try {
      _setBusy(true);
      _clearError();
      // Legacy summary for backward compatibility
      _analytics = await _adminService.getAnalyticsSummary();
      // New aggregated analytics
      _analyticsData = await AnalyticsService().fetchAnalytics();
    } catch (e) {
      _setError(e.toString());
    } finally {
      _setBusy(false);
      notifyListeners();
    }
  }

  void _setBusy(bool v) {
    _isBusy = v;
  }

  void _setError(String e) {
    _error = e;
  }

  void _clearError() {
    _error = null;
  }
}
