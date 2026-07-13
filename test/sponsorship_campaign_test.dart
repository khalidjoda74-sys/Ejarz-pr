import 'package:flutter_test/flutter_test.dart';
import 'package:majalisna/data/models/sponsorship_campaign.dart';

void main() {
  test('prefers matching majlis sponsor over all-majalis sponsor', () {
    final now = DateTime(2026, 6, 30, 12);
    final campaigns = [
      SponsorshipCampaign(
        id: 'all',
        sponsorName: 'راعي عام',
        logoUrl: '',
        categoryId: 'all',
        categoryName: 'كل المجالس',
        targetUrl: 'https://example.com',
        status: SponsorshipCampaignStatus.active,
        startsAt: now.subtract(const Duration(days: 1)),
        endsAt: now.add(const Duration(days: 1)),
        impressionsCount: 0,
        clicksCount: 0,
        scope: SponsorshipPlacementScope.allMajalis,
      ),
      SponsorshipCampaign(
        id: 'cars',
        sponsorName: 'راعي السيارات',
        logoUrl: '',
        categoryId: SponsorshipCampaign.categoryIdFor('سيارات'),
        categoryName: 'سيارات',
        targetUrl: 'https://cars.example.com',
        status: SponsorshipCampaignStatus.active,
        startsAt: now.subtract(const Duration(hours: 1)),
        endsAt: now.add(const Duration(days: 1)),
        impressionsCount: 0,
        clicksCount: 0,
      ),
    ];

    final selected = SponsorshipCampaign.bestForCouncil(
      campaigns: campaigns,
      councilCategoryId: SponsorshipCampaign.categoryIdFor('سيارات'),
      now: now,
    );

    expect(selected?.id, 'cars');
  });

  test('falls back to all-majalis sponsor when no matching sponsor exists', () {
    final now = DateTime(2026, 6, 30, 12);
    final selected = SponsorshipCampaign.bestForCouncil(
      campaigns: [
        SponsorshipCampaign(
          id: 'all',
          sponsorName: 'راعي عام',
          logoUrl: '',
          categoryId: 'all',
          categoryName: 'كل المجالس',
          targetUrl: 'https://example.com',
          status: SponsorshipCampaignStatus.active,
          startsAt: now.subtract(const Duration(days: 1)),
          endsAt: now.add(const Duration(days: 1)),
          impressionsCount: 0,
          clicksCount: 0,
          scope: SponsorshipPlacementScope.allMajalis,
        ),
      ],
      councilCategoryId: SponsorshipCampaign.categoryIdFor('عقار'),
      now: now,
    );

    expect(selected?.id, 'all');
  });
}
