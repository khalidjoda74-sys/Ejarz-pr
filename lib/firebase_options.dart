import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError(
          'Firebase options are configured for Android, iOS, and Web only.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyD2kc2MfwJ7X3BRzpNf-BMwHvIBDmWHsdY',
    appId: '1:475770424762:web:a767f1b067c33af85ea183',
    messagingSenderId: '475770424762',
    projectId: 'ejarz-pro-20260624',
    authDomain: 'ejarz-pro-20260624.firebaseapp.com',
    storageBucket: 'ejarz-pro-20260624.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCvt6D6Th7WCK6AUEOHy2AyGj8UngcHO4Y',
    appId: '1:475770424762:android:cb21cf45e21c593a5ea183',
    messagingSenderId: '475770424762',
    projectId: 'ejarz-pro-20260624',
    storageBucket: 'ejarz-pro-20260624.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyAcSzNqIJz6Jl3f9oeqhvReqRmjYo1LlpY',
    appId: '1:475770424762:ios:a209c44989390c5a5ea183',
    messagingSenderId: '475770424762',
    projectId: 'ejarz-pro-20260624',
    storageBucket: 'ejarz-pro-20260624.firebasestorage.app',
    iosBundleId: 'sa.aqoodpro.app',
  );
}
