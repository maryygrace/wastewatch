import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wastewatch/main.dart';
import 'package:wastewatch/models/user_role.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkInitialState();
  }

  Future<void> _checkInitialState() async {
    // Capture the context before the async gap.
    final navigator = Navigator.of(context);

    // Use a short delay to display the splash screen for a moment.
    await Future.delayed(const Duration(seconds: 3));

    if (!mounted) return;

    final prefs = await SharedPreferences.getInstance();
    final bool? hasOnboarded = prefs.getBool('has_onboarded');

    if (hasOnboarded != true) {
      // If the user hasn't completed onboarding, navigate to the onboarding screen.
      navigator.pushReplacementNamed('/onboarding');
    } else {
      // Onboarding is complete. Now check auth state.
      final session = supabase.auth.currentSession;
      if (session == null) {
        // No user logged in, go to auth screen.
        navigator.pushReplacementNamed('/auth');
      } else {
        // User is logged in, determine their role and navigate.
        final response = await supabase.from('users').select('role').eq('uid', session.user.id).maybeSingle();
        final userRole = response?['role'] as String? ?? 'user';
        final role = UserRole.fromString(userRole);

        if (role.isCollector) {
          navigator.pushReplacementNamed('/collector-home');
        } else {
          navigator.pushReplacementNamed('/home');
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.green.shade50,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.delete_outline_rounded,
              size: 100,
              color: Colors.green,
            ),
            const SizedBox(height: 20),
            Text(
              'WasteWatch',
              style: GoogleFonts.poppins(
                fontSize: 32,
                fontWeight: FontWeight.w700,
                color: Colors.green,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Together for a Greener Future',
              style: GoogleFonts.poppins(
                fontSize: 16,
                color: Colors.grey.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
