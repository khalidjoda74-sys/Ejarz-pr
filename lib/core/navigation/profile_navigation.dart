import 'package:flutter/material.dart';

import '../../data/mock/demo_profile_catalog.dart';
import '../../data/models/comment_model.dart';
import '../../data/models/council_model.dart';
import '../../data/models/public_profile_model.dart';
import '../../navigation/app_routes.dart';

class ProfileNavigation {
  const ProfileNavigation._();

  static Future<void> openCouncilOwner(
    BuildContext context,
    CouncilModel council,
  ) async {
    if (council.isEditorialContent) {
      final profile = DemoProfileCatalog.ownerForCouncil(council);
      return openTarget(
        context,
        PublicProfileTarget.demo(seed: profile),
      );
    }

    final uid = council.createdBy?.trim() ?? '';
    if (uid.isEmpty) {
      return showUnavailable(context);
    }

    return openTarget(
      context,
      PublicProfileTarget.member(uid: uid),
    );
  }

  static Future<void> openCommentAuthor(
    BuildContext context,
    CommentModel comment,
  ) async {
    final authorId = comment.authorId?.trim() ?? '';
    if (comment.isSeedContent || authorId.startsWith('demo_')) {
      final profile = DemoProfileCatalog.authorForComment(comment);
      return openTarget(
        context,
        PublicProfileTarget.demo(seed: profile),
      );
    }

    if (authorId.isEmpty) {
      return showUnavailable(context);
    }

    return openTarget(
      context,
      PublicProfileTarget.member(uid: authorId),
    );
  }

  static Future<void> openTarget(
    BuildContext context,
    PublicProfileTarget target,
  ) {
    final route = target.isDemo
        ? AppRoutes.demoProfile(target.id)
        : AppRoutes.memberProfile(target.id);
    return Navigator.of(context).pushNamed<void>(
      route,
      arguments: target,
    );
  }

  static Future<void> showUnavailable(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        icon: const Icon(Icons.person_off_outlined),
        title: const Text('الملف غير متاح'),
        content: const Text(
          'لا تتوفر بيانات عامة لهذا العضو حاليًا.',
          textAlign: TextAlign.center,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('حسنًا'),
          ),
        ],
      ),
    );
  }
}
