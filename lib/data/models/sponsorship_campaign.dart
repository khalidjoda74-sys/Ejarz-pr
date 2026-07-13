import 'package:cloud_firestore/cloud_firestore.dart';

enum SponsorshipCampaignStatus {
  pending,
  approved,
  draft,
  scheduled,
  active,
  waitlisted,
  ended,
  rejected,
}

enum SponsorshipPlacementScope { categoryMajlis, allMajalis }

enum AdPlacement {
  councilSponsorship,
  homeFeaturedCouncil,
  homeBanner,
}

class SponsorshipCampaign {
  const SponsorshipCampaign({
    required this.id,
    required this.sponsorName,
    required this.logoUrl,
    required this.categoryId,
    required this.categoryName,
    required this.targetUrl,
    required this.status,
    required this.startsAt,
    required this.endsAt,
    required this.impressionsCount,
    required this.clicksCount,
    this.scope = SponsorshipPlacementScope.categoryMajlis,
    this.packageLabel = 'إعلان راعي',
    this.priority = 0,
    this.placement = AdPlacement.councilSponsorship,
    this.title = '',
    this.description = '',
    this.imageUrl = '',
    this.councilId,
  });

  final String id;
  final String sponsorName;
  final String logoUrl;
  final String categoryId;
  final String categoryName;
  final String targetUrl;
  final SponsorshipCampaignStatus status;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final int impressionsCount;
  final int clicksCount;
  final SponsorshipPlacementScope scope;
  final String packageLabel;
  final int priority;
  final AdPlacement placement;
  final String title;
  final String description;
  final String imageUrl;
  final String? councilId;

  bool get isAllMajalis => scope == SponsorshipPlacementScope.allMajalis;

  bool isActiveAt(DateTime now) {
    if (status != SponsorshipCampaignStatus.active) return false;
    if (startsAt != null && startsAt!.isAfter(now)) return false;
    if (endsAt != null && endsAt!.isBefore(now)) return false;
    return true;
  }

  bool matchesCouncilCategory(String councilCategoryId) {
    if (isAllMajalis) return true;
    return categoryId == councilCategoryId;
  }

  factory SponsorshipCampaign.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    return SponsorshipCampaign.fromMap(
        snapshot.id, snapshot.data() ?? const {});
  }

  factory SponsorshipCampaign.fromMap(String id, Map<String, dynamic> data) {
    return SponsorshipCampaign(
      id: id,
      sponsorName: _stringValue(data['sponsorName'], fallback: 'راعي الفرصة'),
      logoUrl: _stringValue(data['logoUrl']),
      categoryId: _stringValue(data['categoryId'], fallback: 'all'),
      categoryName: _stringValue(data['categoryName'], fallback: 'كل الفرص'),
      targetUrl: _stringValue(
        data['targetUrl'],
        fallback: _stringValue(data['linkUrl'],
            fallback: _stringValue(data['externalUrl'])),
      ),
      status: _statusFromValue(data['status']),
      startsAt: _dateValue(data['startsAt']),
      endsAt: _dateValue(data['endsAt']),
      impressionsCount: _intValue(
        data['impressionsCount'],
        fallback: _intValue(data['impressions']),
      ),
      clicksCount: _intValue(
        data['clicksCount'],
        fallback: _intValue(data['clicks']),
      ),
      scope: _scopeFromValue(data['scope'], data['placement']),
      packageLabel: _stringValue(
        data['packageLabel'],
        fallback: _stringValue(data['adText'], fallback: 'إعلان راعي'),
      ),
      priority: _intValue(data['priority']),
      placement: _placementFromValue(data['placement']),
      title: _stringValue(
        data['title'],
        fallback: _stringValue(data['headline'], fallback: _stringValue(data['sponsorName'])),
      ),
      description: _stringValue(
        data['description'],
        fallback: _stringValue(data['subtitle'], fallback: _stringValue(data['body'])),
      ),
      imageUrl: _stringValue(
        data['imageUrl'],
        fallback: _stringValue(data['bannerImageUrl'], fallback: _stringValue(data['coverImageUrl'])),
      ),
      councilId: _nullableString(data['councilId']),
    );
  }

  static SponsorshipCampaign? bestForCouncil({
    required Iterable<SponsorshipCampaign> campaigns,
    required String councilCategoryId,
    DateTime? now,
  }) {
    final currentTime = now ?? DateTime.now();
    final eligible = campaigns
        .where((campaign) => campaign.isActiveAt(currentTime))
        .where((campaign) => campaign.matchesCouncilCategory(councilCategoryId))
        .toList();

    if (eligible.isEmpty) return null;

    eligible.sort((a, b) {
      if (a.isAllMajalis != b.isAllMajalis) {
        return a.isAllMajalis ? 1 : -1;
      }
      final priorityCompare = b.priority.compareTo(a.priority);
      if (priorityCompare != 0) return priorityCompare;
      final aStart = a.startsAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bStart = b.startsAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bStart.compareTo(aStart);
    });

    return eligible.first;
  }

  static String categoryIdFor(String categoryName) {
    final normalized = categoryName
        .trim()
        .replaceAll(RegExp(r'\s+'), '_')
        .replaceAll(RegExp(r'[^\u0600-\u06FF\w_]'), '')
        .toLowerCase();
    return normalized.isEmpty || normalized == 'الكل' ? 'all' : normalized;
  }

  static SponsorshipCampaignStatus _statusFromValue(Object? value) {
    switch (value) {
      case 'pending':
        return SponsorshipCampaignStatus.pending;
      case 'approved':
        return SponsorshipCampaignStatus.approved;
      case 'draft':
        return SponsorshipCampaignStatus.draft;
      case 'scheduled':
        return SponsorshipCampaignStatus.scheduled;
      case 'waitlisted':
        return SponsorshipCampaignStatus.waitlisted;
      case 'ended':
        return SponsorshipCampaignStatus.ended;
      case 'rejected':
        return SponsorshipCampaignStatus.rejected;
      case 'active':
      default:
        return SponsorshipCampaignStatus.active;
    }
  }

  static SponsorshipPlacementScope _scopeFromValue(
    Object? value, [
    Object? placement,
  ]) {
    if (placement == 'home' || placement == 'council_of_day') {
      return SponsorshipPlacementScope.allMajalis;
    }
    switch (value) {
      case 'allMajalis':
        return SponsorshipPlacementScope.allMajalis;
      case 'categoryMajlis':
      default:
        return SponsorshipPlacementScope.categoryMajlis;
    }
  }

  static AdPlacement _placementFromValue(Object? value) {
    switch (value) {
      case 'home_featured_council':
      case 'homeFeaturedCouncil':
        return AdPlacement.homeFeaturedCouncil;
      case 'home_banner':
      case 'homeBanner':
        return AdPlacement.homeBanner;
      case 'council_sponsorship':
      case 'councilSponsorship':
      default:
        return AdPlacement.councilSponsorship;
    }
  }

  static DateTime? _dateValue(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }

  static String _stringValue(Object? value, {String fallback = ''}) {
    if (value is String && value.trim().isNotEmpty) return value.trim();
    return fallback;
  }

  static String? _nullableString(Object? value) {
    if (value is String && value.trim().isNotEmpty) return value.trim();
    return null;
  }

  static int _intValue(Object? value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.round();
    return fallback;
  }
}
