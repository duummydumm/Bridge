import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/firestore_service.dart';
import '../models/calamity_event_model.dart';
import '../models/calamity_donation_model.dart';

class CalamityProvider extends ChangeNotifier {
  final FirestoreService _firestore = FirestoreService();

  List<CalamityEventModel> _calamityEvents = [];
  List<CalamityEventModel> _activeCalamityEvents = [];
  List<CalamityDonationModel> _calamityDonations = [];
  bool _isLoading = false;
  String? _errorMessage;

  List<CalamityEventModel> get calamityEvents => _calamityEvents;
  List<CalamityEventModel> get activeCalamityEvents => _activeCalamityEvents;
  List<CalamityDonationModel> get calamityDonations => _calamityDonations;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<void> loadAllCalamityEvents() async {
    try {
      _setLoading(true);
      _clearError();
      final data = await _firestore.getAllCalamityEvents();
      final now = DateTime.now();
      final events = <CalamityEventModel>[];

      // Process events and auto-expire if deadline passed
      for (final m in data) {
        final event = CalamityEventModel.fromMap(m, m['id'] as String);

        // Auto-expire: If deadline < now() and status is active, update to expired
        if (event.status == CalamityEventStatus.active &&
            event.deadline.isBefore(now)) {
          // Update status to expired in Firestore
          await _firestore.updateCalamityEvent(event.eventId, {
            'status': CalamityEventStatus.expired.name,
            'updatedAt': FieldValue.serverTimestamp(),
          });
          // Create updated event with expired status
          events.add(
            CalamityEventModel(
              eventId: event.eventId,
              title: event.title,
              description: event.description,
              bannerUrl: event.bannerUrl,
              calamityType: event.calamityType,
              neededItems: event.neededItems,
              dropoffLocation: event.dropoffLocation,
              deadline: event.deadline,
              createdBy: event.createdBy,
              status: CalamityEventStatus.expired,
              createdAt: event.createdAt,
              updatedAt: event.updatedAt,
            ),
          );
        } else {
          events.add(event);
        }
      }

      _calamityEvents = events;
      _setLoading(false);
      notifyListeners();
    } catch (e) {
      _setError(e.toString());
      _setLoading(false);
      notifyListeners();
    }
  }

  Future<void> loadActiveCalamityEvents() async {
    try {
      _setLoading(true);
      _clearError();
      final data = await _firestore.getActiveCalamityEvents();
      final now = DateTime.now();
      final events = <CalamityEventModel>[];

      // Process events and auto-expire if deadline passed
      for (final m in data) {
        final event = CalamityEventModel.fromMap(m, m['id'] as String);

        // Only include events that are active and not closed
        if (event.status != CalamityEventStatus.active) {
          continue;
        }

        // Auto-expire: If deadline < now() and status is active, update to expired
        if (event.deadline.isBefore(now)) {
          // Update status to expired in Firestore
          await _firestore.updateCalamityEvent(event.eventId, {
            'status': CalamityEventStatus.expired.name,
            'updatedAt': FieldValue.serverTimestamp(),
          });
          // Skip expired events from active list
          continue;
        }

        // Only add events that are active, not closed, and not expired
        events.add(event);
      }

      _activeCalamityEvents = events;
      _setLoading(false);
      notifyListeners();
    } catch (e) {
      _setError(e.toString());
      _setLoading(false);
      notifyListeners();
    }
  }

  Future<String?> createCalamityEvent({
    required String title,
    required String description,
    required String bannerUrl,
    required String calamityType,
    required List<String> neededItems,
    required String dropoffLocation,
    required DateTime deadline,
    String createdBy = 'admin',
  }) async {
    try {
      _setLoading(true);
      _clearError();
      final payload = {
        'title': title,
        'description': description,
        'bannerUrl': bannerUrl,
        'calamityType': calamityType,
        'neededItems': neededItems,
        'dropoffLocation': dropoffLocation,
        'deadline': deadline,
        'createdBy': createdBy,
        'status': CalamityEventStatus.active.name,
        'createdAt': FieldValue.serverTimestamp(),
      };
      final id = await _firestore.createCalamityEvent(payload);
      _setLoading(false);
      await loadAllCalamityEvents();
      notifyListeners();
      return id;
    } catch (e) {
      _setError(e.toString());
      _setLoading(false);
      notifyListeners();
      return null;
    }
  }

  Future<bool> updateCalamityEvent({
    required String eventId,
    String? title,
    String? description,
    String? bannerUrl,
    String? calamityType,
    List<String>? neededItems,
    String? dropoffLocation,
    DateTime? deadline,
    CalamityEventStatus? status,
  }) async {
    try {
      _setLoading(true);
      _clearError();
      final payload = <String, dynamic>{
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (title != null) payload['title'] = title;
      if (description != null) payload['description'] = description;
      if (bannerUrl != null) payload['bannerUrl'] = bannerUrl;
      if (calamityType != null) payload['calamityType'] = calamityType;
      if (neededItems != null) payload['neededItems'] = neededItems;
      if (dropoffLocation != null) payload['dropoffLocation'] = dropoffLocation;
      if (deadline != null) payload['deadline'] = deadline;
      if (status != null) payload['status'] = status.name;

      await _firestore.updateCalamityEvent(eventId, payload);
      _setLoading(false);
      await loadAllCalamityEvents();
      notifyListeners();
      return true;
    } catch (e) {
      _setError(e.toString());
      _setLoading(false);
      notifyListeners();
      return false;
    }
  }

  Future<bool> deleteCalamityEvent(String eventId) async {
    try {
      _setLoading(true);
      _clearError();
      await _firestore.deleteCalamityEvent(eventId);
      _setLoading(false);
      await loadAllCalamityEvents();
      notifyListeners();
      return true;
    } catch (e) {
      _setError(e.toString());
      _setLoading(false);
      notifyListeners();
      return false;
    }
  }

  Future<CalamityEventModel?> getCalamityEvent(String eventId) async {
    try {
      _setLoading(true);
      _clearError();
      final data = await _firestore.getCalamityEvent(eventId);
      if (data == null) {
        _setLoading(false);
        notifyListeners();
        return null;
      }
      var event = CalamityEventModel.fromMap(data, data['id'] as String);

      // Auto-expire: If deadline < now() and status is active, update to expired
      final now = DateTime.now();
      if (event.status == CalamityEventStatus.active &&
          event.deadline.isBefore(now)) {
        // Update status to expired in Firestore
        await _firestore.updateCalamityEvent(event.eventId, {
          'status': CalamityEventStatus.expired.name,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        // Return updated event with expired status
        event = CalamityEventModel(
          eventId: event.eventId,
          title: event.title,
          description: event.description,
          bannerUrl: event.bannerUrl,
          calamityType: event.calamityType,
          neededItems: event.neededItems,
          dropoffLocation: event.dropoffLocation,
          deadline: event.deadline,
          createdBy: event.createdBy,
          status: CalamityEventStatus.expired,
          createdAt: event.createdAt,
          updatedAt: event.updatedAt,
        );
      }

      _setLoading(false);
      notifyListeners();
      return event;
    } catch (e) {
      _setError(e.toString());
      _setLoading(false);
      notifyListeners();
      return null;
    }
  }

  Future<String?> createCalamityDonation({
    required String eventId,
    required String donorEmail,
    required String itemType,
    required int quantity,
    String? notes,
  }) async {
    try {
      _setLoading(true);
      _clearError();
      final payload = {
        'eventId': eventId,
        'donorEmail': donorEmail,
        'itemType': itemType,
        'quantity': quantity,
        'notes': notes,
        'status': CalamityDonationStatus.pending.name,
        'createdAt': FieldValue.serverTimestamp(),
      };
      final id = await _firestore.createCalamityDonation(payload);

      // Send notification to admin
      try {
        await _firestore.sendCalamityDonationNotification(
          eventId: eventId,
          donationId: id,
          donorEmail: donorEmail,
          itemType: itemType,
          quantity: quantity,
        );
      } catch (_) {
        // Best-effort; don't fail the donation if notification fails
      }

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

  Future<void> loadDonationsByEvent(String eventId) async {
    try {
      _setLoading(true);
      _clearError();
      final data = await _firestore.getDonationsByEvent(eventId);
      _calamityDonations = data
          .map((m) => CalamityDonationModel.fromMap(m, m['id'] as String))
          .toList();
      _setLoading(false);
      notifyListeners();
    } catch (e) {
      _setError(e.toString());
      _setLoading(false);
      notifyListeners();
    }
  }

  Future<void> loadDonationsByDonor(String donorEmail) async {
    try {
      _setLoading(true);
      _clearError();
      final data = await _firestore.getDonationsByDonor(donorEmail);
      _calamityDonations = data
          .map((m) => CalamityDonationModel.fromMap(m, m['id'] as String))
          .toList();
      _setLoading(false);
      notifyListeners();
    } catch (e) {
      _setError(e.toString());
      _setLoading(false);
      notifyListeners();
    }
  }

  Future<bool> updateDonationStatus({
    required String donationId,
    required CalamityDonationStatus status,
  }) async {
    try {
      _setLoading(true);
      _clearError();
      await _firestore.updateCalamityDonation(donationId, {
        'status': status.name,
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

  void _setLoading(bool v) {
    _isLoading = v;
  }

  void _setError(String msg) {
    _errorMessage = msg;
  }

  void _clearError() {
    _errorMessage = null;
  }

  Future<int> getDonationCountByEvent(String eventId) async {
    try {
      return await _firestore.getDonationCountByEvent(eventId);
    } catch (e) {
      return 0;
    }
  }
}
