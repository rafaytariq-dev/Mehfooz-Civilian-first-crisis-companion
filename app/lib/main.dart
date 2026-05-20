import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';

import 'firebase_options.dart';
import 'router.dart';
import 'theme.dart';
import 'services/offline_cache.dart';
import 'services/connectivity_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Initialize M13 Offline Cache and Sync
  await OfflineCache.init();
  ConnectivityService().init();

  runApp(
    const ProviderScope(
      child: MehfoozApp(),
    ),
  );
}

class MehfoozApp extends StatelessWidget {
  const MehfoozApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mehfooz',
      debugShowCheckedModeBanner: false,
      theme: MTheme.light(),
      initialRoute: AppRouter.home,
      onGenerateRoute: AppRouter.onGenerateRoute,
    );
  }
}
