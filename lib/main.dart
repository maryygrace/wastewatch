import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/splash_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/auth_screen.dart';
import 'screens/user/user_home_screen.dart';
import 'screens/user/settings_screen.dart';
import 'screens/collector/collector_home_screen.dart';
import 'models/user_role.dart';
import 'theme_provider.dart';

// Create a global Supabase client instance for easy access.
final supabase = Supabase.instance.client;

void main() async {
  // Ensure Flutter is initialized
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment variables
  await dotenv.load(fileName: ".env");

  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );

  runApp(
    ChangeNotifierProvider(
      create: (_) => ThemeProvider(),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  // Navigator key to show SnackBars from anywhere
  final _navigatorKey = GlobalKey<NavigatorState>();
  late final StreamSubscription<AuthState> _authStateSubscription;

  @override
  void initState() {
    super.initState();
    _setupAuthListener();
  }

  void _setupAuthListener() {
    User? previousUser;

    // Listen to auth state changes.
    _authStateSubscription = supabase.auth.onAuthStateChange.listen((data) {
      final AuthChangeEvent event = data.event;
      final Session? session = data.session;

      if (event == AuthChangeEvent.userUpdated) {
        // This event fires when user metadata changes, including email confirmation.
        final currentUser = session?.user;
        if (currentUser != null &&
            previousUser != null &&
            previousUser?.emailConfirmedAt == null &&
            currentUser.emailConfirmedAt != null) {
          // The user has just confirmed their email.
          _showEmailConfirmedSnackbar();
        }
      }

      // Update the previous user state for the next event.
      previousUser = session?.user;

      if (event == AuthChangeEvent.signedIn) {
        // User has signed in. Navigate them to the correct dashboard.
        _handleNavigation(session!.user.id);
      } else if (event == AuthChangeEvent.signedOut) {
        // User signed out, navigate to the auth screen.
        _navigatorKey.currentState?.pushNamedAndRemoveUntil('/auth', (route) => false);
      }
    });
  }

  Future<void> _handleNavigation(String userId) async {
    // Use .maybeSingle() to prevent an exception if the user record doesn't exist yet.
    // This can happen briefly after signup before the database trigger completes.
    final response = await supabase.from('users').select('role').eq('uid', userId).maybeSingle();

    // If response is null, default to 'user' role. The app can handle this state
    // or the user can try again shortly.
    final userRole = response?['role'] as String? ?? 'user';
    final role = UserRole.fromString(userRole);

    if (role.isCollector) {
      _navigatorKey.currentState?.pushReplacementNamed('/collector-home');
    } else {
      _navigatorKey.currentState?.pushReplacementNamed('/home');
    }
  }
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Initialize previousUser with the current user when the widget is first built.
    _authStateSubscription.onData((data) {
      if (data.session?.user != null) {
        // This is a bit of a workaround to get the initial user state
        // without triggering the confirmation logic on app start.
        // The listener in initState will handle subsequent changes.
      }
    });
  }

  @override
  void dispose() {
    _authStateSubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        return MaterialApp(
          navigatorKey: _navigatorKey,
          debugShowCheckedModeBanner: false,
          title: 'WasteWatch',
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.green, brightness: Brightness.light),
            textTheme: GoogleFonts.poppinsTextTheme(Theme.of(context).textTheme),
            useMaterial3: true,
          ),
          darkTheme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.green, brightness: Brightness.dark),
            textTheme: GoogleFonts.poppinsTextTheme(Theme.of(context).primaryTextTheme),
            useMaterial3: true,
          ),
          themeMode: themeProvider.themeMode,
          initialRoute: '/',
          routes: {
            '/': (context) => const SplashScreen(),
            '/onboarding': (context) => const OnboardingScreen(),
            '/auth': (context) => const AuthScreen(),
            '/home': (context) => const UserHomeScreen(),
            '/settings': (context) => const SettingsScreen(),
            '/collector-home': (context) => const CollectorHomeScreen(),
          },
        );
      },
    );
  }
  void _showEmailConfirmedSnackbar() {
    final context = _navigatorKey.currentState?.overlay?.context;
    if (context != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Email confirmed successfully! You can now log in.'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 5),
        ),
      );
    }
  }
  }
