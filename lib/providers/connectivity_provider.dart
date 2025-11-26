import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'dart:async';

class ConnectivityProvider extends ChangeNotifier {
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  bool _isConnected = true;
  bool _isOnline = true;

  ConnectivityProvider() {
    _initConnectivity();
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
      _updateConnectionStatus,
    );
  }

  bool get isConnected => _isConnected;
  bool get isOnline => _isOnline;
  String get statusMessage => _isOnline
      ? ''
      : 'You are offline. Please check your internet connection.';

  Future<void> _initConnectivity() async {
    final connectivityResult = await _connectivity.checkConnectivity();
    _updateConnectionStatus(connectivityResult);
  }

  void _updateConnectionStatus(List<ConnectivityResult> connectivityResult) {
    // Check if there's any type of connection
    _isConnected =
        connectivityResult.contains(ConnectivityResult.mobile) ||
        connectivityResult.contains(ConnectivityResult.wifi) ||
        connectivityResult.contains(ConnectivityResult.ethernet) ||
        connectivityResult.contains(ConnectivityResult.vpn) ||
        connectivityResult.contains(ConnectivityResult.bluetooth) ||
        connectivityResult.contains(ConnectivityResult.other);

    // For now, treat connected as online
    // In production, you might want to ping a server to verify actual internet access
    _isOnline = _isConnected;

    notifyListeners();
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    super.dispose();
  }
}
