import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not configured for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyAUjs8uZvCoj2FnbLGGDBpdnhM3URXYSDg',
    appId: '1:163358763366:web:f8e565cc5504a3ca7580a7',
    messagingSenderId: '163358763366',
    projectId: 'majalisna-discussions-20260629',
    authDomain: 'majalisna-discussions-20260629.firebaseapp.com',
    storageBucket: 'majalisna-discussions-20260629.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyB8QNJP7kNwiQLrDSNTZ6iPvp6rDRzMRyI',
    appId: '1:163358763366:android:0489f03761abbd797580a7',
    messagingSenderId: '163358763366',
    projectId: 'majalisna-discussions-20260629',
    storageBucket: 'majalisna-discussions-20260629.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyC-jZncq3nttu0rVicJZrJEzcyDXmznRzc',
    appId: '1:163358763366:ios:41c69dc381c58f5d7580a7',
    messagingSenderId: '163358763366',
    projectId: 'majalisna-discussions-20260629',
    storageBucket: 'majalisna-discussions-20260629.firebasestorage.app',
    iosBundleId: 'com.forsapro.app',
  );
}
