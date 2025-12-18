import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/firestore_service.dart';
import '../models/giveaway_listing_model.dart';
import '../models/giveaway_claim_request_model.dart';

class GiveawayProvider extends ChangeNotifier {
  final FirestoreService _firestore = FirestoreService();

  List<GiveawayListingModel> _activeGiveaways = [];
  List<GiveawayListingModel> _myGiveaways = [];
  List<GiveawayClaimRequestModel> _myClaimRequests = [];
  List<GiveawayClaimRequestModel> _claimsForMyGiveaways = [];
  bool _isLoading = false;
  String? _errorMessage;

  List<GiveawayListingModel> get activeGiveaways => _activeGiveaways;
  List<GiveawayListingModel> get myGiveaways => _myGiveaways;
  List<GiveawayClaimRequestModel> get myClaimRequests => _myClaimRequests;
  List<GiveawayClaimRequestModel> get claimsForMyGiveaways =>
      _claimsForMyGiveaways;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<void> loadActiveGiveaways() async {
    try {
      _setLoading(true);
      _clearError();
      final data = await _firestore.getActiveGiveaways();
      _activeGiveaways = data
          .map((m) => GiveawayListingModel.fromMap(m, m['id'] as String))
          .toList();
      _setLoading(false);
      notifyListeners();
    } catch (e) {
      _setError(e.toString());
      _setLoading(false);
      notifyListeners();
    }
  }

  Future<void> loadMyGiveaways(String userId) async {
    try {
      _setLoading(true);
      _clearError();
      final data = await _firestore.getGiveawaysByUser(userId);
      _myGiveaways = data
          .map((m) => GiveawayListingModel.fromMap(m, m['id'] as String))
          .toList();
      _setLoading(false);
      notifyListeners();
    } catch (e) {
      _setError(e.toString());
      _setLoading(false);
      notifyListeners();
    }
  }

  Future<void> loadMyClaimRequests(String userId) async {
    try {
      _setLoading(true);
      _clearError();
      final data = await _firestore.getClaimRequestsByClaimant(userId);
      _myClaimRequests = data
          .map((m) => GiveawayClaimRequestModel.fromMap(m, m['id'] as String))
          .toList();
      _setLoading(false);
      notifyListeners();
    } catch (e) {
      _setError(e.toString());
      _setLoading(false);
      notifyListeners();
    }
  }

  Future<void> loadClaimsForMyGiveaways(String donorId) async {
    try {
      _setLoading(true);
      _clearError();
      final data = await _firestore.getClaimRequestsByDonor(donorId);
      _claimsForMyGiveaways = data
          .map((m) => GiveawayClaimRequestModel.fromMap(m, m['id'] as String))
          .toList();
      _setLoading(false);
      notifyListeners();
    } catch (e) {
      _setError(e.toString());
      _setLoading(false);
      notifyListeners();
    }
  }

  Future<String?> createGiveaway({
    required String donorId,
    required String donorName,
    required String title,
    required String description,
    required List<String> images,
    required String category,
    String? condition,
    required String location,
    required ClaimMode claimMode,
    String? pickupNotes,
  }) async {
    try {
      _setLoading(true);
      _clearError();
      final payload = {
        'donorId': donorId,
        'donorName': donorName,
        'title': title,
        'description': description,
        'images': images,
        'category': category,
        'condition': condition,
        'location': location,
        'status': GiveawayStatus.active.name,
        'claimMode': claimMode.name,
        'pickupNotes': pickupNotes,
        'reportCount': 0,
        'isReported': false,
        'createdAt': FieldValue.serverTimestamp(),
      };
      final id = await _firestore.createGiveaway(payload);
      _setLoading(false);
      notifyListeners();
      return id;
    } catch (e) {
      _setError(e.toString());
      _setLoading(false);
      notifyListeners();
      return null;
    }
  }

  Future<bool> updateGiveawayStatus(
    String giveawayId,
    GiveawayStatus newStatus,
  ) async {
    try {
      _setLoading(true);
      _clearError();
      await _firestore.updateGiveaway(giveawayId, {
        'status': newStatus.name,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      _setLoading(false);
      notifyListeners();
      return true;
    } catch (e) {
      _setError(e.toString());
      _setLoading(false);
      notifyListeners();
      return false;
    }
  }

  Future<bool> markGiveawayAsClaimed({
    required String giveawayId,
    required String claimedBy,
    required String claimedByName,
  }) async {
    try {
      _setLoading(true);
      _clearError();

      // Use a transaction to atomically check and claim the giveaway
      // This prevents race conditions when multiple users try to claim simultaneously
      await _firestore.runTransaction((transaction) async {
        final giveawayRef = _firestore.getGiveawayRef(giveawayId);
        final giveawayDoc = await transaction.get(giveawayRef);

        if (!giveawayDoc.exists) {
          throw Exception('Giveaway not found');
        }

        final giveawayData = giveawayDoc.data();
        final currentStatus = giveawayData?['status'] as String?;

        // Only allow claiming if status is still 'active'
        if (currentStatus != GiveawayStatus.active.name) {
          throw Exception(
            'This giveaway is no longer available. It may have already been claimed.',
          );
        }

        // Atomically update the giveaway to claimed status
        transaction.update(giveawayRef, {
          'status': GiveawayStatus.claimed.name,
          'claimedBy': claimedBy,
          'claimedByName': claimedByName,
          'claimedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });

      _setLoading(false);
      notifyListeners();
      return true;
    } catch (e) {
      _setError(e.toString());
      _setLoading(false);
      notifyListeners();
      return false;
    }
  }

  Future<String?> createClaimRequest({
    required String giveawayId,
    required String claimantId,
    required String claimantName,
    required String donorId,
    String? message,
  }) async {
    try {
      _setLoading(true);
      _clearError();
      final payload = {
        'giveawayId': giveawayId,
        'claimantId': claimantId,
        'claimantName': claimantName,
        'donorId': donorId,
        'message': message,
        'status': ClaimRequestStatus.pending.name,
        'createdAt': FieldValue.serverTimestamp(),
      };
      final id = await _firestore.createClaimRequest(payload);
      _setLoading(false);
      notifyListeners();
      return id;
    } catch (e) {
      _setError(e.toString());
      _setLoading(false);
      notifyListeners();
      return null;
    }
  }

  Future<bool> approveClaimRequest({
    required String claimRequestId,
    required String giveawayId,
    required String claimantId,
    required String claimantName,
  }) async {
    try {
      _setLoading(true);
      _clearError();

      // Get all pending claims for this giveaway
      final allClaims = await _firestore.getClaimRequestsForGiveaway(
        giveawayId,
      );
      final otherPendingClaims = allClaims
          .where(
            (claim) =>
                claim['id'] != claimRequestId &&
                (claim['status'] as String?) == 'pending',
          )
          .toList();

      // Update claim request status to approved
      await _firestore.updateClaimRequest(claimRequestId, {
        'status': ClaimRequestStatus.approved.name,
        'approvedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Mark giveaway as claimed
      await markGiveawayAsClaimed(
        giveawayId: giveawayId,
        claimedBy: claimantId,
        claimedByName: claimantName,
      );

      // Reject all other pending claims and notify those users
      if (otherPendingClaims.isNotEmpty) {
        // Reject each other pending claim
        for (final otherClaim in otherPendingClaims) {
          final otherClaimId = otherClaim['id'] as String;

          // Reject the claim with a clear reason
          // Note: updateClaimRequest will automatically send a notification to the claimant
          await _firestore.updateClaimRequest(otherClaimId, {
            'status': ClaimRequestStatus.rejected.name,
            'rejectionReason': 'This item was already claimed by another user.',
            'rejectedAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      }

      _setLoading(false);
      notifyListeners();
      return true;
    } catch (e) {
      _setError(e.toString());
      _setLoading(false);
      notifyListeners();
      return false;
    }
  }

  Future<bool> rejectClaimRequest({
    required String claimRequestId,
    String? rejectionReason,
  }) async {
    try {
      _setLoading(true);
      _clearError();
      await _firestore.updateClaimRequest(claimRequestId, {
        'status': ClaimRequestStatus.rejected.name,
        'rejectionReason': rejectionReason,
        'rejectedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      _setLoading(false);
      notifyListeners();
      return true;
    } catch (e) {
      _setError(e.toString());
      _setLoading(false);
      notifyListeners();
      return false;
    }
  }

  Future<bool> markGiveawayAsCompleted({required String giveawayId}) async {
    try {
      _setLoading(true);
      _clearError();

      // Verify the giveaway is claimed before marking as completed
      final giveaway = await _firestore.getGiveaway(giveawayId);
      if (giveaway == null) {
        _setError('Giveaway not found');
        _setLoading(false);
        notifyListeners();
        return false;
      }

      final currentStatus = (giveaway['status'] as String?)?.toLowerCase();
      if (currentStatus != 'claimed') {
        _setError('Only claimed giveaways can be marked as completed');
        _setLoading(false);
        notifyListeners();
        return false;
      }

      // Mark giveaway as completed
      await _firestore.updateGiveaway(giveawayId, {
        'status': GiveawayStatus.completed.name,
        'completedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      _setLoading(false);
      notifyListeners();
      return true;
    } catch (e) {
      _setError(e.toString());
      _setLoading(false);
      notifyListeners();
      return false;
    }
  }

  Future<GiveawayListingModel?> getGiveaway(String giveawayId) async {
    try {
      _setLoading(true);
      _clearError();
      final data = await _firestore.getGiveaway(giveawayId);
      if (data == null) {
        _setLoading(false);
        notifyListeners();
        return null;
      }
      final giveaway = GiveawayListingModel.fromMap(data, data['id'] as String);
      _setLoading(false);
      notifyListeners();
      return giveaway;
    } catch (e) {
      _setError(e.toString());
      _setLoading(false);
      notifyListeners();
      return null;
    }
  }

  Future<bool> reportGiveaway(String giveawayId) async {
    try {
      _setLoading(true);
      _clearError();
      final giveaway = await _firestore.getGiveaway(giveawayId);
      if (giveaway == null) return false;

      final currentReportCount = (giveaway['reportCount'] ?? 0) is int
          ? (giveaway['reportCount'] ?? 0)
          : int.tryParse('${giveaway['reportCount']}') ?? 0;

      await _firestore.updateGiveaway(giveawayId, {
        'reportCount': currentReportCount + 1,
        'isReported': true,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      _setLoading(false);
      notifyListeners();
      return true;
    } catch (e) {
      _setError(e.toString());
      _setLoading(false);
      notifyListeners();
      return false;
    }
  }

  Future<bool> deleteGiveaway(String giveawayId) async {
    try {
      _setLoading(true);
      _clearError();
      // Check if giveaway has pending or approved claim requests
      final giveaway = await _firestore.getGiveaway(giveawayId);
      if (giveaway == null) {
        _setError('Giveaway not found');
        _setLoading(false);
        notifyListeners();
        return false;
      }

      final status = (giveaway['status'] as String?)?.toLowerCase();
      if (status == 'claimed' || status == 'completed') {
        _setError('Cannot delete giveaway that has been claimed or completed');
        _setLoading(false);
        notifyListeners();
        return false;
      }

      // Check for pending claim requests
      final claimRequests = await _firestore.getClaimRequestsForGiveaway(
        giveawayId,
      );
      final hasPendingClaims = claimRequests.any(
        (req) =>
            (req['status'] as String?)?.toLowerCase() == 'pending' ||
            (req['status'] as String?)?.toLowerCase() == 'approved',
      );

      if (hasPendingClaims) {
        _setError(
          'Cannot delete giveaway with pending or approved claim requests',
        );
        _setLoading(false);
        notifyListeners();
        return false;
      }

      await _firestore.deleteGiveaway(giveawayId);
      _setLoading(false);
      notifyListeners();
      return true;
    } catch (e) {
      _setError(e.toString());
      _setLoading(false);
      notifyListeners();
      return false;
    }
  }

  void _setLoading(bool v) {
    _isLoading = v;
  }

  void _setError(String msg) {
    _errorMessage = msg;
  }

  void _clearError() {
    _errorMessage = null;
  }
}
