import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'firebase_options.dart';
import 'router.dart';
import 'screens/home_screen.dart';
import 'screens/onboarding_screen.dart';
import 'services/connectivity_service.dart';
import 'services/firestore_seed.dart';
import 'services/location_service.dart';
import 'services/offline_cache.dart';
import 'theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  await OfflineCache.init();
  ConnectivityService().init();

  // Seed reference data (helplines, safe spots) on first run
  FirestoreSeed.runIfNeeded().catchError((_) {});

  runApp(const ProviderScope(child: MehfoozApp()));
}

class MehfoozApp extends StatelessWidget {
  const MehfoozApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mehfooz',
      debugShowCheckedModeBanner: false,
      theme: MTheme.light(),
      home: const _AuthGate(),
      onGenerateRoute: AppRouter.onGenerateRoute,
    );
  }
}

/// Routes to onboarding if not signed in, home if signed in.
class _AuthGate extends StatefulWidget {
  const _AuthGate();

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final user = snapshot.data;

        if (user != null) {
          // Start location tracking for logged-in user
          LocationService().startTracking(user.uid);
          return const HomeScreen();
        }

        return const OnboardingScreen();
      },
    );
  }
}
