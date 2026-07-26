import 'package:flutter_test/flutter_test.dart';
import 'package:majalisna/data/models/conversation_model.dart';
import 'package:majalisna/data/models/public_profile_model.dart';
import 'package:majalisna/data/repositories/messaging_repository.dart';

void main() {
  group('public profiles', () {
    test('maps only the explicit public contract', () {
      final profile = PublicProfileModel.fromMap(
        {
          'uid': 'member_1',
          'id': 'member_1',
          'displayName': 'مستثمر الرياض',
          'username': '@riyadh_investor',
          'avatarEmoji': 'business:growth',
          'publicPhotoUrl': null,
          'isVisible': true,
          'demo': false,
          'email': 'must-not-be-copied@example.com',
        },
        documentId: 'member_1',
      );

      expect(profile.uid, 'member_1');
      expect(profile.displayName, 'مستثمر الرياض');
      expect(profile.isVisible, isTrue);
      expect(
        profile.toFirestore().keys.toSet(),
        equals({
          'uid',
          'id',
          'displayName',
          'username',
          'avatarEmoji',
          'publicPhotoUrl',
          'isVisible',
          'demo',
        }),
      );
    });

    test('demo targets never carry a Firebase uid', () {
      final target = PublicProfileTarget.demo(
        seed: PublicProfileModel.seed(
          uid: '',
          id: 'demo_owner',
          displayName: 'حساب تجريبي',
          demo: true,
        ),
      );

      expect(target.isDemo, isTrue);
      expect(target.uid, isNull);
    });
  });

  group('conversation compatibility', () {
    test('legacy opportunity conversations remain opportunities', () {
      final conversation = ConversationModel.fromMap(
        'legacy',
        {
          'councilId': 'council_1',
          'councilTitle': 'فرصة',
          'ownerId': 'owner',
          'requesterId': 'requester',
          'participantIds': ['owner', 'requester'],
          'participantSnapshots': {
            'owner': {'displayName': 'المالك'},
            'requester': {'displayName': 'المهتم'},
          },
          'unreadCounts': {'owner': 0, 'requester': 1},
          'status': 'active',
        },
      );

      expect(conversation.contextType, ConversationContextType.opportunity);
      expect(conversation.hasOpportunityContext, isTrue);
      expect(conversation.targetId, 'owner');
      expect(conversation.initiatorId, 'requester');
    });

    test('direct conversations have no opportunity card', () {
      final conversation = ConversationModel.fromMap(
        'direct_a_b',
        {
          'contextType': 'direct',
          'initiatorId': 'a',
          'targetId': 'b',
          'participantIds': ['a', 'b'],
          'participantSnapshots': {
            'a': {'displayName': 'الأول'},
            'b': {'displayName': 'الثاني'},
          },
          'unreadCounts': {'a': 0, 'b': 0},
          'status': 'active',
        },
      );

      expect(conversation.isDirect, isTrue);
      expect(conversation.hasOpportunityContext, isFalse);
      expect(conversation.otherParticipantUid('a'), 'b');
      expect(conversation.otherParticipant('a')?.displayName, 'الثاني');
    });

    test('direct id is deterministic from either side', () {
      expect(
        directConversationDocumentId('uid_b', 'uid_a'),
        'direct_uid_a_uid_b',
      );
      expect(
        directConversationDocumentId('uid_a', 'uid_b'),
        'direct_uid_a_uid_b',
      );
      expect(
        () => directConversationDocumentId('', 'uid_b'),
        throwsArgumentError,
      );
    });
  });
}
