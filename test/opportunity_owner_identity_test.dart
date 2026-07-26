import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:majalisna/core/widgets/opportunity_owner_identity.dart';
import 'package:majalisna/data/models/council_model.dart';

void main() {
  test('council reads the published owner snapshot', () {
    final council = CouncilModel.fromMap('real-council', {
      'title': 'فرصة حقيقية',
      'description': 'تفاصيل الفرصة',
      'category': 'شراكة',
      'status': 'active',
      'ownerSnapshot': {
        'displayName': 'سارة محمد',
        'photoUrl': 'https://example.com/owner.jpg',
        'avatarEmoji': 'business:handshake',
      },
    });

    expect(council.ownerDisplayName, 'سارة محمد');
    expect(council.createdByPhotoUrl, 'https://example.com/owner.jpg');
    expect(council.ownerAvatarLabel, 'business:handshake');
  });

  test('demo opportunity has a professional editorial owner fallback', () {
    final council = CouncilModel.fromMap('demo_opportunity', {
      'title': 'فرصة توضيحية',
      'description': 'تفاصيل توضيحية',
      'category': 'فرص',
      'status': 'active',
    });

    expect(council.isEditorialContent, isTrue);
    expect(council.ownerDisplayName, 'فريق فرصة برو');
    expect(council.ownerAvatarLabel, 'business:verified');
  });

  testWidgets('owner identity shows the role and publisher name',
      (tester) async {
    final council = CouncilModel.fromMap('real-council', {
      'title': 'فرصة حقيقية',
      'description': 'تفاصيل الفرصة',
      'category': 'شراكة',
      'status': 'active',
      'ownerSnapshot': {
        'displayName': 'سارة محمد',
        'avatarEmoji': 'business:handshake',
      },
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: OpportunityOwnerIdentity(council: council),
          ),
        ),
      ),
    );

    expect(find.text('صاحب الفرصة'), findsOneWidget);
    expect(find.text('سارة محمد'), findsOneWidget);
    expect(find.byIcon(Icons.handshake_rounded), findsOneWidget);
  });

  testWidgets('owner avatar and name use one profile action', (tester) async {
    var taps = 0;
    final council = CouncilModel.fromMap('real-council', {
      'title': 'فرصة حقيقية',
      'description': 'تفاصيل الفرصة',
      'category': 'شراكة',
      'status': 'active',
      'createdBy': 'member-1',
      'createdByName': 'عضو حقيقي',
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OpportunityOwnerIdentity(
            council: council,
            onTap: () => taps++,
          ),
        ),
      ),
    );

    await tester.tap(find.text('عضو حقيقي'));
    expect(taps, 1);
  });
}
