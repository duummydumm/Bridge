import 'package:flutter/material.dart';
import '../services/firestore_service.dart';

class UsersListProvider extends ChangeNotifier {
  final FirestoreService _firestoreService = FirestoreService();

  List<Map<String, dynamic>> _users = [];
  bool _isLoading = false;
  String? _errorMessage;
  String _searchQuery = '';
  String _selectedBarangay = '';
  String _selectedCity = '';
  String _selectedProvince = '';

  // Getters
  List<Map<String, dynamic>> get users => _users;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  int get usersCount => _users.length;

  // Load all users
  Future<bool> loadUsers() async {
    try {
      _setLoading(true);
      _clearError();

      final users = await _firestoreService.getAllUsers();
      _users = users;

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

  // Refresh users list
  Future<bool> refreshUsers() async {
    return await loadUsers();
  }

  // Add user to list (for real-time updates)
  void addUser(Map<String, dynamic> user) {
    _users.add(user);
    notifyListeners();
  }

  // Update user in list
  void updateUser(String userId, Map<String, dynamic> updatedUser) {
    final index = _users.indexWhere((user) => user['id'] == userId);
    if (index != -1) {
      _users[index] = updatedUser;
      notifyListeners();
    }
  }

  // Remove user from list
  void removeUser(String userId) {
    _users.removeWhere((user) => user['id'] == userId);
    notifyListeners();
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

  void clearUsers() {
    _users.clear();
    notifyListeners();
  }

  // Filter methods
  List<Map<String, dynamic>> getFilteredUsers() {
    var filtered = _users;

    // Filter by role (get borrowers)
    filtered = filtered.where((user) {
      final roleString = (user['role'] ?? 'both').toString().toLowerCase();
      return roleString == 'borrower' || roleString == 'both';
    }).toList();

    // Filter by location
    if (_selectedProvince.isNotEmpty) {
      filtered = filtered
          .where(
            (user) =>
                (user['province'] ?? '').toString().toLowerCase() ==
                _selectedProvince.toLowerCase(),
          )
          .toList();
    }

    if (_selectedCity.isNotEmpty) {
      filtered = filtered
          .where(
            (user) =>
                (user['city'] ?? '').toString().toLowerCase() ==
                _selectedCity.toLowerCase(),
          )
          .toList();
    }

    if (_selectedBarangay.isNotEmpty) {
      filtered = filtered
          .where(
            (user) =>
                (user['barangay'] ?? '').toString().toLowerCase() ==
                _selectedBarangay.toLowerCase(),
          )
          .toList();
    }

    // Filter by search query
    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((user) {
        final name =
            '${user['firstName']} ${user['middleInitial']} ${user['lastName']}'
                .toLowerCase();
        final email = (user['email'] ?? '').toString().toLowerCase();
        return name.contains(_searchQuery.toLowerCase()) ||
            email.contains(_searchQuery.toLowerCase());
      }).toList();
    }

    return filtered;
  }

  // Group users by location
  Map<String, List<Map<String, dynamic>>> getUsersByBarangay() {
    final filtered = getFilteredUsers();
    final Map<String, List<Map<String, dynamic>>> grouped = {};

    for (var user in filtered) {
      final barangay = user['barangay'] ?? 'Unknown';
      final city = user['city'] ?? '';
      final province = user['province'] ?? '';
      final key = '$barangay, $city, $province';

      if (!grouped.containsKey(key)) {
        grouped[key] = [];
      }
      grouped[key]!.add(user);
    }

    // Sort the map by key
    final sortedEntries = grouped.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    return Map.fromEntries(sortedEntries);
  }

  // Get unique locations
  List<String> getUniqueProvinces() {
    final provinces = _users
        .where(
          (user) =>
              user['province'] != null &&
              user['province'].toString().isNotEmpty,
        )
        .map((user) => user['province'].toString())
        .toSet()
        .toList();
    provinces.sort();
    return provinces;
  }

  List<String> getUniqueCities() {
    var cities = _users
        .where(
          (user) => user['city'] != null && user['city'].toString().isNotEmpty,
        )
        .map((user) => user['city'].toString())
        .toSet()
        .toList();

    // Filter by province if selected
    if (_selectedProvince.isNotEmpty) {
      cities = _users
          .where(
            (user) =>
                user['province']?.toString().toLowerCase() ==
                    _selectedProvince.toLowerCase() &&
                user['city'] != null &&
                user['city'].toString().isNotEmpty,
          )
          .map((user) => user['city'].toString())
          .toSet()
          .toList();
    }

    cities.sort();
    return cities;
  }

  List<String> getUniqueBarangays() {
    var barangays = _users
        .where(
          (user) =>
              user['barangay'] != null &&
              user['barangay'].toString().isNotEmpty,
        )
        .map((user) => user['barangay'].toString())
        .toSet()
        .toList();

    // Filter by city if selected
    if (_selectedCity.isNotEmpty) {
      barangays = _users
          .where(
            (user) =>
                user['city']?.toString().toLowerCase() ==
                    _selectedCity.toLowerCase() &&
                user['barangay'] != null &&
                user['barangay'].toString().isNotEmpty,
          )
          .map((user) => user['barangay'].toString())
          .toSet()
          .toList();
    }

    barangays.sort();
    return barangays;
  }

  // Set filters
  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  void setSelectedBarangay(String barangay) {
    _selectedBarangay = barangay;
    notifyListeners();
  }

  void setSelectedCity(String city) {
    _selectedCity = city;
    notifyListeners();
  }

  void setSelectedProvince(String province) {
    _selectedProvince = province;
    notifyListeners();
  }

  void clearFilters() {
    _searchQuery = '';
    _selectedBarangay = '';
    _selectedCity = '';
    _selectedProvince = '';
    notifyListeners();
  }
}
