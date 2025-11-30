import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/firestore_service.dart';

class NotificationPreferencesProvider extends ChangeNotifier {
  static const String _prefsPrefix = 'notification_pref_';
  final FirestoreService _firestoreService = FirestoreService();

  // Default preferences - all enabled
  bool _borrowRequests = true;
  bool _rentalRequests = true;
  bool _tradeOffers = true;
  bool _donations = true;
  bool _messages = true;
  bool _reminders = true;
  bool _systemUpdates = true;
  bool _marketing = false; // Marketing disabled by default

  bool _isLoading = false;
  bool _isInitialized = false;

  // Getters
  bool get borrowRequests => _borrowRequests;
  bool get rentalRequests => _rentalRequests;
  bool get tradeOffers => _tradeOffers;
  bool get donations => _donations;
  bool get messages => _messages;
  bool get reminders => _reminders;
  bool get systemUpdates => _systemUpdates;
  bool get marketing => _marketing;
  bool get isLoading => _isLoading;
  bool get isInitialized => _isInitialized;

  NotificationPreferencesProvider() {
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    _isLoading = true;
    notifyListeners();

    try {
      // Try to load from Firestore first (for cross-device sync)
      final auth = FirebaseAuth.instance.currentUser;
      if (auth != null) {
        final userData = await _firestoreService.getUser(auth.uid);
        if (userData != null && userData['notificationPreferences'] != null) {
          final prefs =
              userData['notificationPreferences'] as Map<String, dynamic>;
          _borrowRequests = prefs['borrowRequests'] ?? true;
          _rentalRequests = prefs['rentalRequests'] ?? true;
          _tradeOffers = prefs['tradeOffers'] ?? true;
          _donations = prefs['donations'] ?? true;
          _messages = prefs['messages'] ?? true;
          _reminders = prefs['reminders'] ?? true;
          _systemUpdates = prefs['systemUpdates'] ?? true;
          _marketing = prefs['marketing'] ?? false;

          // Also save to local storage for offline access
          await _saveToLocalStorage();
          _isInitialized = true;
          _isLoading = false;
          notifyListeners();
          return;
        }
      }

      // Fallback to local storage
      final prefs = await SharedPreferences.getInstance();
      _borrowRequests = prefs.getBool('${_prefsPrefix}borrowRequests') ?? true;
      _rentalRequests = prefs.getBool('${_prefsPrefix}rentalRequests') ?? true;
      _tradeOffers = prefs.getBool('${_prefsPrefix}tradeOffers') ?? true;
      _donations = prefs.getBool('${_prefsPrefix}donations') ?? true;
      _messages = prefs.getBool('${_prefsPrefix}messages') ?? true;
      _reminders = prefs.getBool('${_prefsPrefix}reminders') ?? true;
      _systemUpdates = prefs.getBool('${_prefsPrefix}systemUpdates') ?? true;
      _marketing = prefs.getBool('${_prefsPrefix}marketing') ?? false;
    } catch (e) {
      debugPrint('Error loading notification preferences: $e');
    } finally {
      _isInitialized = true;
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _saveToLocalStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('${_prefsPrefix}borrowRequests', _borrowRequests);
      await prefs.setBool('${_prefsPrefix}rentalRequests', _rentalRequests);
      await prefs.setBool('${_prefsPrefix}tradeOffers', _tradeOffers);
      await prefs.setBool('${_prefsPrefix}donations', _donations);
      await prefs.setBool('${_prefsPrefix}messages', _messages);
      await prefs.setBool('${_prefsPrefix}reminders', _reminders);
      await prefs.setBool('${_prefsPrefix}systemUpdates', _systemUpdates);
      await prefs.setBool('${_prefsPrefix}marketing', _marketing);
    } catch (e) {
      debugPrint('Error saving notification preferences to local storage: $e');
    }
  }

  Future<void> _saveToFirestore() async {
    try {
      final auth = FirebaseAuth.instance.currentUser;
      if (auth == null) return;

      await _firestoreService.setUser(auth.uid, {
        'notificationPreferences': {
          'borrowRequests': _borrowRequests,
          'rentalRequests': _rentalRequests,
          'tradeOffers': _tradeOffers,
          'donations': _donations,
          'messages': _messages,
          'reminders': _reminders,
          'systemUpdates': _systemUpdates,
          'marketing': _marketing,
          'updatedAt': FieldValue.serverTimestamp(),
        },
      });
    } catch (e) {
      debugPrint('Error saving notification preferences to Firestore: $e');
    }
  }

  Future<void> updateBorrowRequests(bool value) async {
    if (_borrowRequests == value) return;
    _borrowRequests = value;
    notifyListeners();
    await _saveToLocalStorage();
    await _saveToFirestore();
  }

  Future<void> updateRentalRequests(bool value) async {
    if (_rentalRequests == value) return;
    _rentalRequests = value;
    notifyListeners();
    await _saveToLocalStorage();
    await _saveToFirestore();
  }

  Future<void> updateTradeOffers(bool value) async {
    if (_tradeOffers == value) return;
    _tradeOffers = value;
    notifyListeners();
    await _saveToLocalStorage();
    await _saveToFirestore();
  }

  Future<void> updateDonations(bool value) async {
    if (_donations == value) return;
    _donations = value;
    notifyListeners();
    await _saveToLocalStorage();
    await _saveToFirestore();
  }

  Future<void> updateMessages(bool value) async {
    if (_messages == value) return;
    _messages = value;
    notifyListeners();
    await _saveToLocalStorage();
    await _saveToFirestore();
  }

  Future<void> updateReminders(bool value) async {
    if (_reminders == value) return;
    _reminders = value;
    notifyListeners();
    await _saveToLocalStorage();
    await _saveToFirestore();
  }

  Future<void> updateSystemUpdates(bool value) async {
    if (_systemUpdates == value) return;
    _systemUpdates = value;
    notifyListeners();
    await _saveToLocalStorage();
    await _saveToFirestore();
  }

  Future<void> updateMarketing(bool value) async {
    if (_marketing == value) return;
    _marketing = value;
    notifyListeners();
    await _saveToLocalStorage();
    await _saveToFirestore();
  }

  // Check if a specific notification type should be sent
  bool shouldSendNotification(String notificationType) {
    switch (notificationType.toLowerCase()) {
      case 'borrow_request':
      case 'borrow_request_decision':
      case 'item_overdue_lender':
        return _borrowRequests;
      case 'rental_request':
      case 'rental_request_decision':
      case 'rental_overdue':
        return _rentalRequests;
      case 'trade_offer':
      case 'trade_offer_decision':
        return _tradeOffers;
      case 'giveaway':
      case 'calamity_donation':
        return _donations;
      case 'message':
      case 'chat_message':
        return _messages;
      case 'reminder':
      case 'due_reminder':
        return _reminders;
      case 'system':
      case 'verification':
        return _systemUpdates;
      case 'marketing':
      case 'promotion':
        return _marketing;
      default:
        return true; // Default to enabled for unknown types
    }
  }
}
