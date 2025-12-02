import 'package:bridge_app/screens/home.dart';
import 'package:bridge_app/screens/auth/login.dart';
import 'package:bridge_app/screens/auth/register.dart';
import 'package:bridge_app/screens/profile.dart';
import 'package:bridge_app/screens/settings/settings.dart';
import 'package:bridge_app/screens/list_item_screen.dart';
import 'package:bridge_app/screens/onboardingscreen/onboarding_screen.dart';
import 'package:bridge_app/screens/borrow/borrow_items_screen.dart';
import 'package:bridge_app/screens/my_listings_screen.dart';
import 'package:bridge_app/screens/chat_list_screen.dart';
import 'package:bridge_app/screens/chat/create_group_screen.dart';
import 'package:bridge_app/screens/notifications_screen.dart';
import 'screens/all_activity_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';
import 'providers/auth_provider.dart';
import 'providers/user_provider.dart';
import 'providers/users_list_provider.dart';
import 'providers/item_provider.dart';
import 'providers/chat_provider.dart';
import 'providers/connectivity_provider.dart';
import 'providers/admin_provider.dart';
import 'providers/rental_listing_provider.dart';
import 'providers/rental_request_provider.dart';
import 'providers/rental_payment_provider.dart';
import 'providers/trade_item_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/notification_preferences_provider.dart';
import 'providers/chat_theme_provider.dart';
import 'providers/locale_provider.dart';
import 'screens/admin/admin_home_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/local_notifications_service.dart';
import 'services/fcm_service.dart';
import 'package:flutter/foundation.dart';
import 'screens/rental/rental_listing_editor_screen.dart';
import 'screens/rental/rental_detail_screen.dart';
import 'screens/rental/rent_item_screen.dart';
import 'screens/rental/rent_items_screen.dart';
import 'screens/trade/add_trade_item_screen.dart';
import 'screens/trade/trade_items_screen.dart';
import 'screens/trade/make_trade_offer_screen.dart';
import 'screens/trade/incoming_trade_offers_screen.dart';
import 'screens/trade/trade_offer_detail_screen.dart';
import 'screens/trade/accepted_trades.dart';
import 'screens/trade/history_trade.dart';
import 'screens/donate/giveaways_screen.dart';
import 'screens/donate/add_giveaway_screen.dart';
import 'screens/donate/giveaway_detail_screen.dart';
import 'screens/donate/donor_analytics_screen.dart';
import 'screens/donate/giveaway_rating_screen.dart';
import 'screens/donate/calamity_events_screen.dart';
import 'screens/donate/calamity_event_detail_screen.dart';
import 'screens/donate/my_calamity_donations_screen.dart';
import 'screens/admin/calamity_events_admin_screen.dart';
import 'screens/admin/calamity_event_detail_admin_screen.dart';
import 'providers/giveaway_provider.dart';
import 'providers/calamity_provider.dart';
import 'providers/giveaway_rating_provider.dart';
import 'providers/donor_analytics_provider.dart';
import 'screens/auth/verify_email.dart';
import 'services/email_service.dart';
import 'screens/pending_requests_screen.dart';
import 'screens/borrow/borrow_pending_request.dart';
import 'screens/borrow/approved_borrow.dart';
import 'screens/borrow/currently_borrowed.dart';
import 'screens/borrow/returned_items.dart';
import 'screens/borrow/pending_returns_screen.dart';
import 'screens/borrow/currently_lent_screen.dart';
import 'screens/borrow/disputed_returns_screen.dart';
import 'screens/rental/rental_pending_request.dart';
import 'screens/rental/disputed_rentals_screen.dart';
import 'screens/trade/trade_pending_request.dart';
import 'screens/trade/disputed_trades_screen.dart';
import 'screens/borrow/borrowed_items_detail_screen.dart';
import 'screens/due_soon_items_detail_screen.dart';
import 'screens/my_lenders_detail_screen.dart';
import 'screens/upcoming_reminders_calendar_screen.dart';
import 'services/verification_service.dart';
import 'reusable_widgets/protected_route.dart';
import 'screens/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
  } catch (e) {
    // Ignore duplicate initialization errors during hot restart
  }
  // Enable Firestore offline persistence on web (mobile is on by default)
  if (kIsWeb) {
    try {
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
      );
    } catch (_) {
      // Ignore if not supported in this environment
    }
  }
  // Initialize local notifications (skip on web)
  if (!kIsWeb) {
    await LocalNotificationsService().initialize();
  }
  // Initialize FCM for push notifications (works on both mobile and web)
  await FCMService().initialize();

  // Configure EmailJS
  // Get these from https://dashboard.emailjs.com/

  // Backend API URL configuration
  // For local development: Use localhost or emulator IP
  // For production: Use your deployed backend URL (e.g., https://your-app.herokuapp.com)
  // Temporarily using Render for testing in debug mode
  const String backendApiUrl =
      'https://bridge-emailjs-backend.onrender.com'; // Render backend URL
  // const String backendApiUrl = kDebugMode
  //     ? 'http://192.168.1.11:3000' // Local development (use your computer's IP address)
  //     : 'https://bridge-emailjs-backend.onrender.com'; // Render backend URL

  await EmailService().configure(
    serviceId: 'service_hql50hi', // Replace with your EmailJS Service ID
    templateId:
        'template_oyfh658', // Replace with your OTP verification template ID
    publicKey:
        'V4g4u9Bklz22oCTI1', // Replace with your EmailJS Public Key (User ID)
    welcomeTemplateId:
        'template_dx6t43s', // Optional: Replace with your welcome email template ID
    backendApiUrl:
        backendApiUrl, // Automatically uses local for debug, production for release
  );

  // Background rescheduling via WorkManager is temporarily disabled to avoid
  // Android build plugin compatibility issues. Local reminders still work.
  runApp(BridgeApp());
}

class BridgeApp extends StatelessWidget {
  const BridgeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ConnectivityProvider()),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => UserProvider()),
        ChangeNotifierProvider(create: (_) => UsersListProvider()),
        ChangeNotifierProvider(create: (_) => ItemProvider()),
        ChangeNotifierProvider(create: (_) => ChatProvider()),
        ChangeNotifierProvider(create: (_) => AdminProvider()),
        ChangeNotifierProvider(create: (_) => RentalListingProvider()),
        ChangeNotifierProvider(create: (_) => RentalRequestProvider()),
        ChangeNotifierProvider(create: (_) => RentalPaymentsProvider()),
        ChangeNotifierProvider(create: (_) => TradeItemProvider()),
        ChangeNotifierProvider(create: (_) => GiveawayProvider()),
        ChangeNotifierProvider(create: (_) => CalamityProvider()),
        ChangeNotifierProvider(create: (_) => GiveawayRatingProvider()),
        ChangeNotifierProvider(create: (_) => DonorAnalyticsProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(
          create: (_) => NotificationPreferencesProvider(),
        ),
        ChangeNotifierProvider(create: (_) => ChatThemeProvider()),
        ChangeNotifierProvider(create: (_) => LocaleProvider()),
      ],
      child: Consumer2<ThemeProvider, LocaleProvider>(
        builder: (context, themeProvider, localeProvider, _) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            locale: localeProvider.locale,
            supportedLocales: const [Locale('en'), Locale('fil')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            theme: ThemeProvider.lightTheme,
            darkTheme: ThemeProvider.darkTheme,
            themeMode: themeProvider.themeModeForMaterial,
            initialRoute: '/',
            routes: {
              '/': (context) => SplashScreen(
                duration: const Duration(seconds: 2),
                child: _AuthWrapper(),
              ),
              '/onboarding': (context) => const OnboardingScreen(),
              '/login': (context) => const LoginScreen(),
              '/register': (context) => const RegisterScreen(),
              '/verify-email': (context) => const VerifyEmailScreen(),
              '/home': (context) {
                return ProtectedRoute(
                  child: Builder(
                    builder: (context) {
                      final userProvider = Provider.of<UserProvider>(
                        context,
                        listen: true,
                      );
                      if (userProvider.currentUser?.isAdmin == true) {
                        return const AdminHomeScreen();
                      }
                      return const HomePage();
                    },
                  ),
                );
              },
              '/profile': (context) =>
                  ProtectedRoute(child: const ProfileScreen()),
              '/settings': (context) =>
                  ProtectedRoute(child: const SettingsScreen()),
              '/list-item': (context) =>
                  ProtectedRoute(child: const ListItemScreen()),
              '/my-listings': (context) =>
                  ProtectedRoute(child: const MyListingsScreen()),
              '/borrow': (context) =>
                  ProtectedRoute(child: const BorrowItemsScreen()),
              '/rent': (context) =>
                  ProtectedRoute(child: const RentItemsScreen()),
              '/chat': (context) =>
                  ProtectedRoute(child: const ChatListScreen()),
              '/chat/create-group': (context) =>
                  ProtectedRoute(child: const CreateGroupScreen()),
              '/notifications': (context) =>
                  ProtectedRoute(child: const NotificationsScreen()),
              '/pending-requests': (context) =>
                  ProtectedRoute(child: const PendingRequestsScreen()),
              '/activity/all': (context) =>
                  ProtectedRoute(child: const AllActivityScreen()),
              '/borrow/pending-requests': (context) =>
                  ProtectedRoute(child: const BorrowPendingRequestScreen()),
              '/borrow/approved': (context) =>
                  ProtectedRoute(child: const ApprovedBorrowScreen()),
              '/borrow/currently-borrowed': (context) =>
                  ProtectedRoute(child: const CurrentlyBorrowedScreen()),
              '/borrow/returned-items': (context) =>
                  ProtectedRoute(child: const ReturnedItemsScreen()),
              '/borrow/pending-returns': (context) =>
                  ProtectedRoute(child: const PendingReturnsScreen()),
              '/borrow/currently-lent': (context) =>
                  ProtectedRoute(child: const CurrentlyLentScreen()),
              '/borrow/disputed-returns': (context) =>
                  ProtectedRoute(child: const DisputedReturnsScreen()),
              '/rental/disputed-rentals': (context) =>
                  ProtectedRoute(child: const DisputedRentalsScreen()),
              '/rental/pending-requests': (context) =>
                  ProtectedRoute(child: const RentalPendingRequestScreen()),
              '/trade/pending-requests': (context) =>
                  ProtectedRoute(child: const TradePendingRequestScreen()),
              '/trade/disputed-trades': (context) =>
                  ProtectedRoute(child: const DisputedTradesScreen()),
              '/borrowed-items-detail': (context) =>
                  ProtectedRoute(child: const BorrowedItemsDetailScreen()),
              '/due-soon-items-detail': (context) =>
                  ProtectedRoute(child: const DueSoonItemsDetailScreen()),
              '/my-lenders-detail': (context) =>
                  ProtectedRoute(child: const MyLendersDetailScreen()),
              '/upcoming-reminders': (context) => ProtectedRoute(
                child: const UpcomingRemindersCalendarScreen(),
              ),
              '/admin': (context) => ProtectedRoute(
                allowAdmins: true,
                child: const AdminHomeScreen(),
              ),
              // Rental screens (MVP)
              '/rental/listing-editor': (context) =>
                  const RentalListingEditorScreen(),
              '/rental/detail': (context) => const RentalDetailScreen(),
              '/rental/rent-item': (context) => const RentItemScreen(),
              // Trade screens
              '/trade': (context) => const TradeItemsScreen(),
              '/trade/add-item': (context) => const AddTradeItemScreen(),
              '/trade/make-offer': (context) => const MakeTradeOfferScreen(),
              '/trade/incoming-offers': (context) {
                final args = ModalRoute.of(context)?.settings.arguments;
                final tradeItemId = args is Map
                    ? args['tradeItemId'] as String?
                    : null;
                return ProtectedRoute(
                  child: IncomingTradeOffersScreen(tradeItemId: tradeItemId),
                );
              },
              '/trade/offer-detail': (context) {
                final args = ModalRoute.of(context)?.settings.arguments as Map?;
                return ProtectedRoute(
                  child: TradeOfferDetailScreen(
                    offerId: args?['offerId'] as String? ?? '',
                    canAcceptDecline:
                        args?['canAcceptDecline'] as bool? ?? false,
                  ),
                );
              },
              '/trade/accepted-trades': (context) =>
                  ProtectedRoute(child: const AcceptedTradesScreen()),
              '/trade/history': (context) {
                final args = ModalRoute.of(context)?.settings.arguments;
                final filter = args is Map ? args['filter'] as String? : null;
                return ProtectedRoute(
                  child: TradeHistoryScreen(initialFilter: filter),
                );
              },
              // Giveaway screens
              '/giveaway': (context) => const GiveawaysScreen(),
              '/giveaway/add': (context) => const AddGiveawayScreen(),
              '/giveaway/detail': (context) => const GiveawayDetailScreen(),
              '/giveaway/analytics': (context) =>
                  ProtectedRoute(child: const DonorAnalyticsScreen()),
              '/giveaway/rating': (context) {
                final args = ModalRoute.of(context)?.settings.arguments as Map?;
                return ProtectedRoute(
                  child: GiveawayRatingScreen(
                    giveawayId: args?['giveawayId'] as String? ?? '',
                    donorId: args?['donorId'] as String? ?? '',
                    donorName: args?['donorName'] as String? ?? '',
                    giveawayTitle: args?['giveawayTitle'] as String? ?? '',
                  ),
                );
              },
              // Calamity Donation screens
              '/calamity': (context) => const CalamityEventsScreen(),
              '/calamity/detail': (context) {
                final args = ModalRoute.of(context)?.settings.arguments as Map?;
                return ProtectedRoute(
                  child: CalamityEventDetailScreen(
                    eventId: args?['eventId'] as String? ?? '',
                  ),
                );
              },
              '/calamity/my-donations': (context) =>
                  ProtectedRoute(child: const MyCalamityDonationsScreen()),
              // Admin Calamity screens
              '/admin/calamity': (context) => ProtectedRoute(
                allowAdmins: true,
                child: const CalamityEventsAdminScreen(),
              ),
              '/admin/calamity/event-detail': (context) {
                final args = ModalRoute.of(context)?.settings.arguments as Map?;
                return ProtectedRoute(
                  allowAdmins: true,
                  child: CalamityEventDetailAdminScreen(
                    eventId: args?['eventId'] as String? ?? '',
                  ),
                );
              },
              // Removed test barangay id route
            },
          );
        },
      ),
    );
  }
}

class _AuthWrapper extends StatefulWidget {
  @override
  State<_AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<_AuthWrapper> {
  bool _hasSeenOnboarding = false;
  bool _isLoadingOnboarding = true;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    // Wait for Firebase Auth to restore session first (important for web)
    await Future.delayed(const Duration(milliseconds: 100));

    // Check if user is already authenticated (persisted session)
    final firebaseAuth = firebase_auth.FirebaseAuth.instance;
    final currentUser = firebaseAuth.currentUser;

    // If user is already authenticated, mark onboarding as seen and skip it
    if (currentUser != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('has_seen_onboarding', true);
      setState(() {
        _hasSeenOnboarding = true;
        _isLoadingOnboarding = false;
      });
      return;
    }

    // Otherwise, check onboarding status
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _hasSeenOnboarding = prefs.getBool('has_seen_onboarding') ?? false;
        _isLoadingOnboarding = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingOnboarding = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, authProvider, child) {
        // Hide loading during splash screen - splash screen handles the visual
        if (_isLoadingOnboarding) {
          return const Scaffold(
            body: SizedBox.shrink(), // Empty/transparent during loading
          );
        }

        // If user hasn't seen onboarding, show onboarding first
        if (!_hasSeenOnboarding) {
          return const OnboardingScreen();
        }

        // Otherwise, proceed with normal auth flow
        return _buildAuthFlow(authProvider);
      },
    );
  }

  Widget _buildAuthFlow(AuthProvider authProvider) {
    // Listen to auth state changes
    return StreamBuilder<firebase_auth.User?>(
      stream: firebase_auth.FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // Show loading while checking auth state
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            body: Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(
                  const Color(0xFF1E88E5),
                ),
              ),
            ),
          );
        }

        // If user is authenticated, ensure profile is loaded then show home page
        final user = snapshot.data ?? authProvider.user;
        if (user != null) {
          final userProvider = Provider.of<UserProvider>(context, listen: true);
          if (userProvider.currentUser == null) {
            // Defer to next frame to avoid setState during build
            WidgetsBinding.instance.addPostFrameCallback((_) {
              userProvider.loadUserProfile(user.uid);
            });
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }

          // Check email verification for non-admin users
          final bool isAdmin = userProvider.currentUser?.isAdmin == true;
          if (!isAdmin) {
            // Check both Firebase Auth and Firestore email verification
            final bool firebaseEmailVerified = user.emailVerified;

            // Check Firestore emailVerified status (for EmailJS verification)
            return FutureBuilder<bool>(
              future: _checkEmailVerification(user.uid),
              builder: (context, verificationSnapshot) {
                if (verificationSnapshot.connectionState ==
                    ConnectionState.waiting) {
                  return const Scaffold(
                    body: Center(child: CircularProgressIndicator()),
                  );
                }

                final bool firestoreEmailVerified =
                    verificationSnapshot.data ?? false;
                final bool isEmailVerified =
                    firebaseEmailVerified || firestoreEmailVerified;

                // Bypass emails (for testing)
                final String signedInEmail = (user.email ?? '').toLowerCase();
                const Set<String> kVerificationBypassEmails = {
                  'balafamily4231@gmail.com',
                  'applejeantizon09@gmail.com',
                };
                final bool isBypassEmail = kVerificationBypassEmails.contains(
                  signedInEmail,
                );

                // If email is not verified and not a bypass email, redirect to verification screen
                if (!isBypassEmail && !isEmailVerified) {
                  // Use postFrameCallback to avoid setState during build
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    Navigator.of(context).pushReplacementNamed('/verify-email');
                  });
                  return const Scaffold(
                    body: Center(child: CircularProgressIndicator()),
                  );
                }

                // Email is verified, proceed to home
                return PopScope(
                  canPop: false, // Block default back navigation
                  onPopInvokedWithResult: (didPop, result) async {
                    if (!didPop) {
                      // Show confirmation dialog
                      final shouldExit = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text(
                            'Exit App',
                            textAlign: TextAlign.center,
                          ),
                          content: const Text(
                            'Are you sure you want to exit?',
                            textAlign: TextAlign.center,
                          ),
                          actions: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.of(context).pop(false),
                                  child: const Text('Cancel'),
                                ),
                                TextButton(
                                  onPressed: () => SystemNavigator.pop(),
                                  style: TextButton.styleFrom(
                                    foregroundColor: Colors.red,
                                  ),
                                  child: const Text('Exit'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );

                      // If user confirmed exit, pop the route
                      if (shouldExit == true && context.mounted) {
                        Navigator.of(context).pop();
                      }
                    }
                  },
                  child: const HomePage(),
                );
              },
            );
          }

          // Route admins directly to the Admin Dashboard (admins bypass verification)
          return const AdminHomeScreen();
        }

        // Otherwise, show login page
        return const LoginScreen();
      },
    );
  }

  Future<bool> _checkEmailVerification(String userId) async {
    try {
      final verificationService = VerificationService();
      return await verificationService.isEmailVerified(userId);
    } catch (e) {
      debugPrint('_AuthWrapper: Error checking email verification: $e');
      return false;
    }
  }
}
