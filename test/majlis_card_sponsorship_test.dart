import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:majalisna/core/widgets/majlis_card.dart';
import 'package:majalisna/data/models/council_model.dart';
import 'package:majalisna/data/models/sponsorship_campaign.dart';

void main() {
  testWidgets('shows sponsor strip inside today majlis card', (tester) async {
    await tester.pumpWidget(
      _TestHost(
        child: MajlisCard(
          council: _council(),
          onVote: (_) {},
          showVotingActions: false,
          sponsorship: _campaign(),
          onSponsorTap: () {},
        ),
      ),
    );

    expect(find.text('برعاية'), findsOneWidget);
    expect(find.text('كافيه المجلس'), findsOneWidget);
    expect(find.text('اعرف أكثر'), findsOneWidget);
  });

  testWidgets('keeps today majlis clean when no sponsor exists', (tester) async {
    await tester.pumpWidget(
      _TestHost(
        width: 320,
        child: MajlisCard(
          council: _council(),
          onVote: (_) {},
          showVotingActions: false,
        ),
      ),
    );

    expect(find.text('مساحة إعلان راعي متاحة لهذا المجلس'), findsNothing);
    expect(find.text('احجز'), findsNothing);
  });
}

class _TestHost extends StatelessWidget {
  const _TestHost({required this.child, this.width = 390});

  final Widget child;
  final double width;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: Center(
            child: SizedBox(width: width, child: child),
          ),
        ),
      ),
    );
  }
}

CouncilModel _council() {
  return CouncilModel(
    id: 'c1',
    title: 'هل إعلان الراعي يظهر بشكل أنيق؟',
    description: 'اختبار بطاقة مجلس اليوم.',
    category: 'سيارات',
    status: CouncilStatus.active,
    participants: 120,
    commentsCount: 10,
    votesCount: 80,
    supportPercent: 50,
    againstPercent: 30,
    neutralPercent: 20,
    endsIn: '08:30:00',
    comments: [],
  );
}

SponsorshipCampaign _campaign() {
  final now = DateTime(2026, 6, 30, 12);
  return SponsorshipCampaign(
    id: 's1',
    sponsorName: 'كافيه المجلس',
    logoUrl: '',
    categoryId: SponsorshipCampaign.categoryIdFor('سيارات'),
    categoryName: 'سيارات',
    targetUrl: 'https://example.com',
    status: SponsorshipCampaignStatus.active,
    startsAt: now.subtract(const Duration(days: 1)),
    endsAt: now.add(const Duration(days: 1)),
    impressionsCount: 0,
    clicksCount: 0,
  );
}
