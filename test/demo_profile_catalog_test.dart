import 'package:flutter_test/flutter_test.dart';
import 'package:majalisna/data/mock/demo_profile_catalog.dart';
import 'package:majalisna/data/mock/mock_data.dart';

void main() {
  test('all mock councils and authors are explicit editorial profiles', () {
    final councils = MockData.councils();
    final ownerIds = <String>{};

    for (final council in councils) {
      expect(council.isSeedContent, isTrue, reason: council.id);
      expect(council.isEditorialContent, isTrue, reason: council.id);
      expect(council.createdBy, isNotEmpty, reason: council.id);
      expect(
        DemoProfileCatalog.ownerForCouncil(council).id,
        council.createdBy,
        reason: council.id,
      );
      ownerIds.add(council.createdBy!);
    }

    expect(ownerIds.length, councils.length);

    final comments = MockData.sampleComments();
    final authorIds = <String>{};
    for (final comment in comments) {
      expect(comment.isSeedContent, isTrue, reason: comment.id);
      expect(comment.authorId, isNotEmpty, reason: comment.id);
      expect(
        DemoProfileCatalog.authorForComment(comment).id,
        comment.authorId,
        reason: comment.id,
      );
      authorIds.add(comment.authorId!);
    }

    expect(authorIds.length, comments.length);
  });
}
