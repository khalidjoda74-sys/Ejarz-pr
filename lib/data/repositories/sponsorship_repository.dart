import 'package:cloud_functions/cloud_functions.dart';

import '../models/sponsorship_campaign.dart';
import '../services/firestore_service.dart';

class SponsorshipInterestInput {
  const SponsorshipInterestInput({
    required this.sponsorName,
    required this.contactName,
    required this.contactPhone,
    required this.targetUrl,
    required this.placementScope,
    required this.categoryName,
    required this.durationLabel,
    this.logoUrl,
    this.notes,
    this.adPlacement = AdPlacement.councilSponsorship,
    this.packageId,
    this.packageLabel,
    this.priceLabel,
    this.durationHours,
    this.councilId,
  });

  final String sponsorName;
  final String contactName;
  final String contactPhone;
  final String targetUrl;
  final SponsorshipPlacementScope placementScope;
  final String categoryName;
  final String durationLabel;
  final String? logoUrl;
  final String? notes;
  final AdPlacement adPlacement;
  final String? packageId;
  final String? packageLabel;
  final String? priceLabel;
  final int? durationHours;
  final String? councilId;

  Map<String, dynamic> toCallablePayload() {
    final categoryId = placementScope == SponsorshipPlacementScope.allMajalis
        ? 'all'
        : SponsorshipCampaign.categoryIdFor(categoryName);

    return {
      'sponsorName': sponsorName.trim(),
      'contactName': contactName.trim(),
      'contactPhone': contactPhone.trim(),
      'targetUrl': targetUrl.trim(),
      'logoUrl': logoUrl?.trim(),
      'placementScope': _scopeToFirestore(placementScope),
      'categoryName': placementScope == SponsorshipPlacementScope.allMajalis
          ? 'كل الفرص'
          : categoryName.trim(),
      'categoryId': categoryId,
      'durationLabel': durationLabel.trim(),
      'notes': notes?.trim(),
      'placement': adPlacementToFirestore(adPlacement),
      'adPlacement': adPlacementToFirestore(adPlacement),
      'packageId': packageId?.trim(),
      'packageLabel': packageLabel?.trim(),
      'priceLabel': priceLabel?.trim(),
      'durationHours': durationHours,
      'councilId': councilId?.trim(),
    };
  }
}

class AdPackageOption {
  const AdPackageOption({
    required this.id,
    required this.label,
    required this.durationLabel,
    required this.priceLabel,
    required this.highlight,
    this.durationHours = 72,
  });

  final String id;
  final String label;
  final String durationLabel;
  final String priceLabel;
  final String highlight;
  final int durationHours;

  factory AdPackageOption.fromMap(String id, Map<String, dynamic> data) {
    return AdPackageOption(
      id: id,
      label: _stringValue(data['label'], fallback: _stringValue(data['name'])),
      durationLabel: _stringValue(data['durationLabel']),
      priceLabel: _stringValue(
        data['priceLabel'],
        fallback: _priceLabel(data['price'], data['currency']),
      ),
      highlight: _stringValue(
        data['highlight'],
        fallback: _stringValue(data['description']),
      ),
      durationHours: _intValue(data['durationHours'], fallback: 72),
    );
  }
}

class SponsorshipRepository {
  SponsorshipRepository._();

  static final SponsorshipRepository instance = SponsorshipRepository._();

  final FirestoreService _firestore = FirestoreService.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;
  final Set<String> _recordedImpressions = {};

  Stream<SponsorshipCampaign?> watchActiveForCategory(String categoryName) {
    final categoryId = SponsorshipCampaign.categoryIdFor(categoryName);

    return _firestore.sponsorshipCampaigns
        .where('status', isEqualTo: 'active')
        .limit(40)
        .snapshots()
        .map((snapshot) {
      final campaigns = snapshot.docs
          .map(SponsorshipCampaign.fromFirestore)
          .where((campaign) =>
              campaign.placement == AdPlacement.councilSponsorship)
          .toList();
      return SponsorshipCampaign.bestForCouncil(
        campaigns: campaigns,
        councilCategoryId: categoryId,
      );
    });
  }

  Stream<List<AdPackageOption>> watchPackagesFor(AdPlacement placement) {
    final fallback = defaultPackagesFor(placement);
    return _firestore.adPackages
        .where('status', isEqualTo: 'active')
        .limit(30)
        .snapshots()
        .map((snapshot) {
      final packages = snapshot.docs
          .where((doc) =>
              doc.data()['placement'] == adPlacementToFirestore(placement))
          .map((doc) => AdPackageOption.fromMap(doc.id, doc.data()))
          .where((package) =>
              package.label.isNotEmpty &&
              package.durationLabel.isNotEmpty &&
              package.priceLabel.isNotEmpty)
          .toList(growable: false);
      return packages.isEmpty ? fallback : packages.take(3).toList();
    });
  }

  Stream<SponsorshipCampaign?> watchActiveHomePlacement() {
    return _firestore.sponsorshipCampaigns
        .where('status', isEqualTo: 'active')
        .limit(40)
        .snapshots()
        .map((snapshot) {
      final now = DateTime.now();
      final campaigns = snapshot.docs
          .map(SponsorshipCampaign.fromFirestore)
          .where((campaign) => campaign.isActiveAt(now))
          .where((campaign) =>
              campaign.placement == AdPlacement.homeFeaturedCouncil ||
              campaign.placement == AdPlacement.homeBanner)
          .toList();
      if (campaigns.isEmpty) return null;
      campaigns.sort((a, b) => b.priority.compareTo(a.priority));
      return campaigns.first;
    });
  }

  List<AdPackageOption> defaultPackagesFor(AdPlacement placement) {
    switch (placement) {
      case AdPlacement.councilSponsorship:
        return const [
          AdPackageOption(
            id: 'sponsor_trial',
            label: 'تجربة',
            durationLabel: '3 أيام',
            priceLabel: 'يحدد من لوحة التحكم',
            highlight: 'ظهور داخل فرصة أو قسم محدد',
            durationHours: 72,
          ),
          AdPackageOption(
            id: 'sponsor_reach',
            label: 'انتشار',
            durationLabel: '7 أيام',
            priceLabel: 'يحدد من لوحة التحكم',
            highlight: 'مدة أطول ومراجعة أولوية',
            durationHours: 168,
          ),
          AdPackageOption(
            id: 'sponsor_priority',
            label: 'أولوية',
            durationLabel: '14 يوم',
            priceLabel: 'يحدد من لوحة التحكم',
            highlight: 'حضور أطول مع أولوية في الجدولة',
            durationHours: 336,
          ),
        ];
      case AdPlacement.homeFeaturedCouncil:
        return const [
          AdPackageOption(
            id: 'featured_day',
            label: 'يوم مميز',
            durationLabel: '24 ساعة',
            priceLabel: 'يحدد من لوحة التحكم',
            highlight: 'تثبيت فرصة واحدة في مساحة الرئيسية',
            durationHours: 24,
          ),
          AdPackageOption(
            id: 'featured_three',
            label: '3 أيام',
            durationLabel: '3 أيام',
            priceLabel: 'يحدد من لوحة التحكم',
            highlight: 'ظهور متكرر في مساحة الرئيسية',
            durationHours: 72,
          ),
          AdPackageOption(
            id: 'featured_week',
            label: 'أسبوع',
            durationLabel: '7 أيام',
            priceLabel: 'يحدد من لوحة التحكم',
            highlight: 'أعلى حضور لفرصة مميزة',
            durationHours: 168,
          ),
        ];
      case AdPlacement.homeBanner:
        return const [
          AdPackageOption(
            id: 'banner_day',
            label: 'بنر سريع',
            durationLabel: '24 ساعة',
            priceLabel: 'يحدد من لوحة التحكم',
            highlight: 'بنر كبير في الرئيسية',
            durationHours: 24,
          ),
          AdPackageOption(
            id: 'banner_three',
            label: 'بنر انتشار',
            durationLabel: '3 أيام',
            priceLabel: 'يحدد من لوحة التحكم',
            highlight: 'مناسب للعروض القصيرة',
            durationHours: 72,
          ),
          AdPackageOption(
            id: 'banner_week',
            label: 'بنر أسبوعي',
            durationLabel: '7 أيام',
            priceLabel: 'يحدد من لوحة التحكم',
            highlight: 'حضور ثابت في الرئيسية',
            durationHours: 168,
          ),
        ];
    }
  }

  Future<String?> submitInterest(SponsorshipInterestInput input) async {
    final callable = _functions.httpsCallable('createSponsorshipInterest');
    final result =
        await callable.call<Map<String, dynamic>>(input.toCallablePayload());
    return result.data['requestId']?.toString();
  }

  Future<void> recordImpression(String campaignId) {
    if (!_recordedImpressions.add(campaignId)) return Future<void>.value();
    return _recordEvent(campaignId: campaignId, eventType: 'impression');
  }

  Future<void> recordClick(String campaignId) {
    return _recordEvent(campaignId: campaignId, eventType: 'click');
  }

  Future<void> _recordEvent({
    required String campaignId,
    required String eventType,
  }) async {
    if (campaignId.trim().isEmpty) return;

    final callable = _functions.httpsCallable('recordSponsorshipEvent');
    await callable.call<void>({
      'campaignId': campaignId.trim(),
      'eventType': eventType,
    });
  }
}

String _scopeToFirestore(SponsorshipPlacementScope scope) {
  switch (scope) {
    case SponsorshipPlacementScope.allMajalis:
      return 'allMajalis';
    case SponsorshipPlacementScope.categoryMajlis:
      return 'categoryMajlis';
  }
}

String adPlacementToFirestore(AdPlacement placement) {
  switch (placement) {
    case AdPlacement.councilSponsorship:
      return 'council_sponsorship';
    case AdPlacement.homeFeaturedCouncil:
      return 'home_featured_council';
    case AdPlacement.homeBanner:
      return 'home_banner';
  }
}

String _stringValue(Object? value, {String fallback = ''}) {
  if (value is String && value.trim().isNotEmpty) return value.trim();
  return fallback;
}

int _intValue(Object? value, {int fallback = 0}) {
  if (value is int) return value;
  if (value is num) return value.round();
  return fallback;
}

String _priceLabel(Object? value, Object? currency) {
  if (value is! num) return '';
  final code = currency is String && currency.trim().isNotEmpty
      ? currency.trim()
      : 'ريال';
  return '${value.round()} $code';
}
