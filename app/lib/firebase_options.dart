// File generated manually (flutterfire_cli crashed on Kotlin DSL gradle files).
// Keep in sync with android/app/google-services.json.
//
// ignore_for_file: type=lint
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        'DefaultFirebaseOptions have not been configured for web - '
        'rerun FlutterFire CLI for web support.',
      );
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        throw UnsupportedError(
          'DefaultFirebaseOptions are only configured for android. '
          'Rerun FlutterFire CLI to add other platforms.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCiS8q2N_TBdL0N4KbM7FEnq0Rp2JZQgsU',
    appId: '1:666747846029:android:7c19fd81bcbedf733651c4',
    messagingSenderId: '666747846029',
    projectId: 'mehfooz-prod-cc1e3',
    storageBucket: 'mehfooz-prod-cc1e3.firebasestorage.app',
  );
}
