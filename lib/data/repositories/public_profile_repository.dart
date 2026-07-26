import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/utils/reusable_stream.dart';
import '../models/public_profile_model.dart';
import '../services/firestore_service.dart';

class PublicProfileRepository {
  PublicProfileRepository({FirestoreService? firestore})
      : _firestore = firestore ?? FirestoreService.instance;

  static final PublicProfileRepository instance = PublicProfileRepository();

  final FirestoreService _firestore;

  Stream<PublicProfileModel?> watchPublicProfile(
    PublicProfileTarget target,
  ) {
    final seed = target.seed;
    if (target.isDemo) {
      return reusableValueStream<PublicProfileModel?>(seed);
    }

    final uid = target.uid?.trim() ?? '';
    if (uid.isEmpty) {
      return reusableValueStream<PublicProfileModel?>(seed);
    }

    return Stream<PublicProfileModel?>.multi((controller) {
      if (seed != null) controller.add(seed);

      late final StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>
          subscription;
      subscription = _firestore.publicProfile(uid).snapshots().listen(
        (snapshot) {
          if (!snapshot.exists) {
            controller.add(null);
            return;
          }

          final profile = PublicProfileModel.fromFirestore(snapshot);
          controller.add(
            profile.isVisible && !profile.demo && profile.uid == uid
                ? profile
                : null,
          );
        },
        onError: (Object error, StackTrace stackTrace) {
          if (seed != null) {
            controller.add(seed);
          } else {
            controller.addError(error, stackTrace);
          }
        },
        onDone: controller.close,
      );

      controller.onPause = subscription.pause;
      controller.onResume = subscription.resume;
      controller.onCancel = () {
        unawaited(subscription.cancel());
      };
    });
  }
}
