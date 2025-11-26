import 'package:flutter/material.dart';
import '../services/firestore_service.dart';
import '../services/storage_service.dart';
import '../models/item_model.dart';

class ItemProvider extends ChangeNotifier {
  final FirestoreService _firestoreService = FirestoreService();
  final StorageService _storageService = StorageService();

  List<ItemModel> _items = [];
  List<ItemModel> _myItems = []; // Items listed by current user
  Stream<List<ItemModel>>? _myItemsStream;
  ItemModel? _selectedItem;
  bool _isLoading = false;
  String? _errorMessage;
  // Borrower activity cache
  List<Map<String, dynamic>> _pendingBorrowRequests = [];
  List<Map<String, dynamic>> _borrowedByMe = [];
  DateTime? _borrowerActivityFetchedAt;

  // Getters
  List<ItemModel> get items => _items;
  List<ItemModel> get myItems => _myItems;
  Stream<List<ItemModel>>? get myItemsStream => _myItemsStream;
  ItemModel? get selectedItem => _selectedItem;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  List<Map<String, dynamic>> get pendingBorrowRequests =>
      _pendingBorrowRequests;
  List<Map<String, dynamic>> get borrowedByMe => _borrowedByMe;

  // Get all items
  Future<void> loadAllItems() async {
    try {
      _setLoading(true);
      _clearError();

      final itemsData = await _firestoreService.getAllItems();
      _items = itemsData
          .map((data) => ItemModel.fromMap(data, data['id']))
          .toList();

      _setLoading(false);
      notifyListeners();
    } catch (e) {
      _setError(e.toString());
      _setLoading(false);
      notifyListeners();
    }
  }

  // Get items by lender
  Future<void> loadMyItems(String lenderId) async {
    try {
      _setLoading(true);
      _clearError();

      final itemsData = await _firestoreService.getItemsByLender(lenderId);
      _myItems = itemsData
          .map((data) => ItemModel.fromMap(data, data['id']))
          .toList();

      _setLoading(false);
      notifyListeners();
    } catch (e) {
      _setError(e.toString());
      _setLoading(false);
      notifyListeners();
    }
  }

  // Subscribe to my items as a stream for snappy UI updates
  void subscribeToMyItems(String lenderId) {
    _myItemsStream = _firestoreService
        .getItemsByLenderStream(lenderId)
        .map(
          (snapshot) => snapshot.docs.map((doc) {
            final data = doc.data();
            data['id'] = doc.id;
            return ItemModel.fromMap(data, data['id']);
          }).toList(),
        );
    notifyListeners();
  }

  // Get available items only
  Future<void> loadAvailableItems() async {
    try {
      _setLoading(true);
      _clearError();

      final itemsData = await _firestoreService.getAvailableItems();
      _items = itemsData
          .map((data) => ItemModel.fromMap(data, data['id']))
          .toList();

      _setLoading(false);
      notifyListeners();
    } catch (e) {
      _setError(e.toString());
      _setLoading(false);
      notifyListeners();
    }
  }

  // Create a new item
  Future<bool> createItem({
    required String lenderId,
    required String lenderName,
    required String title,
    required String description,
    required List<String> images,
    required String category,
    required String type,
    required String condition,
    double? pricePerDay,
    String? location,
  }) async {
    try {
      _setLoading(true);
      _clearError();

      final itemData = {
        'lenderId': lenderId,
        'lenderName': lenderName,
        'title': title,
        'description': description,
        'images': images,
        'category': category,
        'type': type,
        'condition': condition,
        'status': ItemStatus.available.name.toLowerCase(),
        'pricePerDay': pricePerDay,
        'location': location,
        'createdAt': DateTime.now(),
      };

      await _firestoreService.createItem(itemData);
      // Do not reload here; My Listings listens via stream and will update.

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

  // Load and cache borrower activity (pending requests + borrowed items)
  Future<void> loadBorrowerActivity(
    String borrowerId, {
    bool forceRefresh = false,
  }) async {
    // Return cached data if fetched within the last 60 seconds
    if (!forceRefresh && _borrowerActivityFetchedAt != null) {
      final age = DateTime.now().difference(_borrowerActivityFetchedAt!);
      if (age.inSeconds < 60) return;
    }
    try {
      _setLoading(true);
      _clearError();

      final pending = await _firestoreService
          .getPendingBorrowRequestsForBorrower(borrowerId);
      final borrowed = await _firestoreService.getBorrowedItemsByBorrower(
        borrowerId,
      );

      _pendingBorrowRequests = pending;
      _borrowedByMe = borrowed;
      _borrowerActivityFetchedAt = DateTime.now();
      _setLoading(false);
      notifyListeners();
    } catch (e) {
      _setError(e.toString());
      _setLoading(false);
      notifyListeners();
    }
  }

  // Update an item
  Future<bool> updateItem(ItemModel item) async {
    try {
      _setLoading(true);
      _clearError();

      final updateData = item.toMap();
      updateData['lastUpdated'] = DateTime.now();

      await _firestoreService.updateItem(item.itemId, updateData);

      // Reload items
      await loadMyItems(item.lenderId);

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

  // Delete an item
  Future<bool> deleteItem(String itemId, String lenderId) async {
    try {
      _setLoading(true);
      _clearError();

      await _firestoreService.deleteItem(itemId);

      // Reload items
      await loadMyItems(lenderId);

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

  // Get a single item by ID
  Future<void> loadItemById(String itemId) async {
    try {
      _setLoading(true);
      _clearError();

      final itemData = await _firestoreService.getItem(itemId);
      if (itemData != null) {
        _selectedItem = ItemModel.fromMap(itemData, itemId);
      }

      _setLoading(false);
      notifyListeners();
    } catch (e) {
      _setError(e.toString());
      _setLoading(false);
      notifyListeners();
    }
  }

  // Set selected item
  void setSelectedItem(ItemModel? item) {
    _selectedItem = item;
    notifyListeners();
  }

  // Update item status
  Future<bool> updateItemStatus(
    String itemId,
    ItemStatus newStatus, {
    String? borrowerId,
    DateTime? borrowedDate,
    DateTime? returnDate,
  }) async {
    try {
      _setLoading(true);
      _clearError();

      final updateData = {
        'status': newStatus.name.toLowerCase(),
        'lastUpdated': DateTime.now(),
        if (borrowerId != null) 'currentBorrowerId': borrowerId,
        if (borrowedDate != null) 'borrowedDate': borrowedDate,
        if (returnDate != null) 'returnDate': returnDate,
      };

      await _firestoreService.updateItem(itemId, updateData);

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

  // Upload item image
  // Note: This method is deprecated. Use StorageService directly with userId and listingType.
  Future<String?> uploadItemImage({
    required dynamic file,
    required String itemId,
    required String userId,
    required String listingType, // 'borrow' or 'donate'
  }) async {
    try {
      _setLoading(true);
      _clearError();

      final imageUrl = await _storageService.uploadItemImage(
        file: file,
        itemId: itemId,
        userId: userId,
        listingType: listingType,
      );

      _setLoading(false);
      notifyListeners();
      return imageUrl;
    } catch (e) {
      _setError(e.toString());
      _setLoading(false);
      notifyListeners();
      return null;
    }
  }

  // Helper methods
  void _setLoading(bool loading) {
    _isLoading = loading;
  }

  void _setError(String error) {
    _errorMessage = error;
  }

  void _clearError() {
    _errorMessage = null;
  }

  void clearError() {
    _clearError();
    notifyListeners();
  }

  void clearItems() {
    _items = [];
    _myItems = [];
    _selectedItem = null;
    notifyListeners();
  }
}
