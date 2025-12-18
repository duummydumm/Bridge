import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;

import 'firebase_options.dart';
import 'providers/auth_provider.dart';
import 'providers/user_provider.dart';
import 'providers/connectivity_provider.dart';
import 'providers/admin_provider.dart';
import 'providers/calamity_provider.dart';
import 'screens/admin/admin_home_screen.dart';
import 'screens/auth/login.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
  } catch (_) {
    // ignore duplicate init during hot reload
  }
  runApp(const BridgeAdminApp());
}

class BridgeAdminApp extends StatelessWidget {
  const BridgeAdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ConnectivityProvider()),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => UserProvider()),
        ChangeNotifierProvider(create: (_) => AdminProvider()),
        ChangeNotifierProvider(create: (_) => CalamityProvider()),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Bridge Admin',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF00897B),
            brightness: Brightness.light,
          ),
          useMaterial3: true,
          scaffoldBackgroundColor: const Color(0xFFF5F7FA),
        ),
        home: const _AdminAuthWrapper(),
        routes: {
          '/admin': (context) => const AdminHomeScreen(),
          '/login': (context) => const LoginScreen(),
        },
      ),
    );
  }
}

class _AdminAuthWrapper extends StatelessWidget {
  const _AdminAuthWrapper();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<firebase_auth.User?>(
      stream: firebase_auth.FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final user = snapshot.data;
        if (user == null) {
          return const LoginScreen();
        }

        final userProvider = Provider.of<UserProvider>(context, listen: true);
        if (userProvider.currentUser == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            userProvider.loadUserProfile(user.uid);
          });
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (userProvider.currentUser!.isAdmin) {
          return const AdminHomeScreen();
        }
        return const _NotAuthorizedScreen();
      },
    );
  }
}

// Removed placeholder login prompt; we navigate to LoginScreen instead when signed out.

class _NotAuthorizedScreen extends StatelessWidget {
  const _NotAuthorizedScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline, size: 48),
            const SizedBox(height: 12),
            const Text(
              'This account is not authorized for Admin.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () async {
                await firebase_auth.FirebaseAuth.instance.signOut();
              },
              child: const Text('Sign out'),
            ),
          ],
        ),
      ),
    );
  }
}
