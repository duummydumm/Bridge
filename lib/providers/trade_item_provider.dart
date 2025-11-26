import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/firestore_service.dart';
import '../models/trade_item_model.dart';

class TradeItemProvider extends ChangeNotifier {
  final FirestoreService _firestore = FirestoreService();

  List<TradeItemModel> _myTradeItems = [];
  List<TradeItemModel> _activeTradeItems = [];
  bool _isLoading = false;
  String? _errorMessage;

  List<TradeItemModel> get myTradeItems => _myTradeItems;
  List<TradeItemModel> get activeTradeItems => _activeTradeItems;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<void> loadMyTradeItems(String userId) async {
    try {
      _setLoading(true);
      _clearError();
      final data = await _firestore.getTradeItemsByUser(userId);
      _myTradeItems = data
          .map((m) => TradeItemModel.fromMap(m, m['id'] as String))
          .toList();
      _setLoading(false);
      notifyListeners();
    } catch (e) {
      _setError(e.toString());
      _setLoading(false);
      notifyListeners();
    }
  }

  Future<void> loadActiveTradeItems() async {
    try {
      _setLoading(true);
      _clearError();
      final data = await _firestore.getActiveTradeItems();
      _activeTradeItems = data
          .map((m) => TradeItemModel.fromMap(m, m['id'] as String))
          .toList();
      _setLoading(false);
      notifyListeners();
    } catch (e) {
      _setError(e.toString());
      _setLoading(false);
      notifyListeners();
    }
  }

  Future<String?> createTradeItem({
    required String offeredItemName,
    required String offeredCategory,
    required String offeredDescription,
    required List<String> offeredImageUrls,
    String? desiredItemName,
    String? desiredCategory,
    String? notes,
    required String location,
    required String offeredBy,
    bool isActive = true,
  }) async {
    try {
      _setLoading(true);
      _clearError();
      final payload = {
        'offeredItemName': offeredItemName,
        'offeredCategory': offeredCategory,
        'offeredDescription': offeredDescription,
        'offeredImageUrls': offeredImageUrls,
        'desiredItemName': desiredItemName,
        'desiredCategory': desiredCategory,
        'notes': notes,
        'location': location,
        'offeredBy': offeredBy,
        'status': isActive ? 'Open' : 'Closed',
        'createdAt': FieldValue.serverTimestamp(),
      };
      final id = await _firestore.createTradeItem(payload);
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

  Future<bool> updateTradeItemStatus(
    String tradeItemId,
    TradeStatus newStatus,
  ) async {
    try {
      _setLoading(true);
      _clearError();
      final statusString = newStatus == TradeStatus.open
          ? 'Open'
          : newStatus == TradeStatus.closed
          ? 'Closed'
          : 'Traded';
      await _firestore.updateTradeItem(tradeItemId, {
        'status': statusString,
        'updatedAt': DateTime.now(),
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

  Future<bool> setTradeItemActive(String tradeItemId, bool isActive) async {
    return await updateTradeItemStatus(
      tradeItemId,
      isActive ? TradeStatus.open : TradeStatus.closed,
    );
  }

  Future<TradeItemModel?> getTradeItem(String tradeItemId) async {
    try {
      _setLoading(true);
      _clearError();
      final data = await _firestore.getTradeItem(tradeItemId);
      if (data == null) {
        _setLoading(false);
        notifyListeners();
        return null;
      }
      final tradeItem = TradeItemModel.fromMap(data, data['id'] as String);
      _setLoading(false);
      notifyListeners();
      return tradeItem;
    } catch (e) {
      _setError(e.toString());
      _setLoading(false);
      notifyListeners();
      return null;
    }
  }

  Future<bool> updateTradeItem({
    required String tradeItemId,
    required String offeredItemName,
    required String offeredCategory,
    required String offeredDescription,
    required List<String> offeredImageUrls,
    String? desiredItemName,
    String? desiredCategory,
    String? notes,
    String? location,
    bool? isActive,
  }) async {
    try {
      _setLoading(true);
      _clearError();
      final payload = <String, dynamic>{
        'offeredItemName': offeredItemName,
        'offeredCategory': offeredCategory,
        'offeredDescription': offeredDescription,
        'offeredImageUrls': offeredImageUrls,
        'desiredItemName': desiredItemName,
        'desiredCategory': desiredCategory,
        'notes': notes,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (location != null) {
        payload['location'] = location;
      }
      if (isActive != null) {
        payload['status'] = isActive ? 'Open' : 'Closed';
      }
      await _firestore.updateTradeItem(tradeItemId, payload);
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

  Future<bool> deleteTradeItem(String tradeItemId, String userId) async {
    try {
      _setLoading(true);
      _clearError();

      await _firestore.deleteTradeItem(tradeItemId);

      // Reload items
      await loadMyTradeItems(userId);

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
