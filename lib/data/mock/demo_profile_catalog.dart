import '../models/comment_model.dart';
import '../models/council_model.dart';
import '../models/public_profile_model.dart';

class DemoProfileCatalog {
  const DemoProfileCatalog._();

  static final ownerPartnerRiyadh = _demo(
    'demo_owner_partner_riyadh',
    'نورة العتيبي',
    '@demo_noura',
    'business:handshake',
  );
  static final ownerLaundry = _demo(
    'demo_owner_laundry_riyadh',
    'فهد الزهراني',
    '@demo_fahad',
    'business:transfer',
  );
  static final ownerFundingDammam = _demo(
    'demo_owner_funding_dammam',
    'سارة القحطاني',
    '@demo_sara',
    'business:funding',
  );
  static final ownerMarketMakkah = _demo(
    'demo_owner_market_makkah',
    'منصور الحربي',
    '@demo_mansour',
    'business:experience',
  );
  static final ownerWarehouse = _demo(
    'demo_owner_warehouse_riyadh',
    'ريم الدوسري',
    '@demo_reem',
    'business:search',
  );
  static final ownerBakery = _demo(
    'demo_owner_bakery',
    'عبدالله الشهري',
    '@demo_abdullah',
    'business:storefront',
  );
  static final ownerTechPartner = _demo(
    'demo_owner_tech_partner',
    'تركي الغامدي',
    '@demo_turki',
    'business:growth',
  );
  static final ownerCoffeeResult = _demo(
    'demo_owner_coffee_result',
    'هيا المطيري',
    '@demo_haya',
    'business:verified',
  );
  static final ownerServicesResult = _demo(
    'demo_owner_services_result',
    'مازن العنزي',
    '@demo_mazen',
    'business:briefcase',
  );
  static final ownerShowroomResult = _demo(
    'demo_owner_showroom_result',
    'دلال السبيعي',
    '@demo_dalal',
    'business:person_growth',
  );

  static final commentOwnerReview = _demo(
    'demo_comment_owner_review',
    'صاحب رأي',
    '@demo_opinion',
    'business:person_growth',
  );
  static final commentAdvisor = _demo(
    'demo_comment_advisor',
    'المستشار',
    '@demo_advisor',
    'business:briefcase',
  );
  static final commentMarketExpert = _demo(
    'demo_comment_market_expert',
    'خبير السوق',
    '@demo_market_expert',
    'business:experience',
  );
  static final replyServiceOperator = _demo(
    'demo_reply_service_operator',
    'مشغل خدمات',
    '@demo_operator',
    'business:briefcase',
  );
  static final replyAccountant = _demo(
    'demo_reply_accountant',
    'محاسب مشاريع',
    '@demo_accountant',
    'business:verified',
  );
  static final replyOpportunitySeeker = _demo(
    'demo_reply_opportunity_seeker',
    'باحث عن فرصة',
    '@demo_seeker',
    'business:search',
  );
  static final replyServicesInvestor = _demo(
    'demo_reply_services_investor',
    'مستثمر خدمات',
    '@demo_investor',
    'business:growth',
  );
  static final replyPreviousOwner = _demo(
    'demo_reply_previous_owner',
    'صاحب نشاط سابق',
    '@demo_previous_owner',
    'business:transfer',
  );
  static final replyOperationsExpert = _demo(
    'demo_reply_operations_expert',
    'خبير تشغيل',
    '@demo_operations',
    'business:storefront',
  );
  static final editorialFallback = _demo(
    'demo_editorial_profile',
    'فريق فرصة برو',
    '@forsa_pro_demo',
    'business:verified',
  );

  static final Map<String, PublicProfileModel> _profiles = {
    for (final profile in <PublicProfileModel>[
      ownerPartnerRiyadh,
      ownerLaundry,
      ownerFundingDammam,
      ownerMarketMakkah,
      ownerWarehouse,
      ownerBakery,
      ownerTechPartner,
      ownerCoffeeResult,
      ownerServicesResult,
      ownerShowroomResult,
      commentOwnerReview,
      commentAdvisor,
      commentMarketExpert,
      replyServiceOperator,
      replyAccountant,
      replyOpportunitySeeker,
      replyServicesInvestor,
      replyPreviousOwner,
      replyOperationsExpert,
      editorialFallback,
    ])
      profile.id: profile,
  };

  static final Map<String, String> _ownerProfileIdsByCouncilId = {
    'demo_council_partner_riyadh': ownerPartnerRiyadh.id,
    'demo_laundry_public': ownerLaundry.id,
    'demo_council_funding_dammam': ownerFundingDammam.id,
    'demo_council_market_makkah': ownerMarketMakkah.id,
    'c5': ownerWarehouse.id,
    'c6': ownerBakery.id,
    'c7': ownerTechPartner.id,
    'demo_result_coffee_riyadh': ownerCoffeeResult.id,
    'demo_result_home_services': ownerServicesResult.id,
    'demo_result_showroom': ownerShowroomResult.id,
  };

  static final Map<String, String> _commentProfileIdsByCommentId = {
    'cm1': commentOwnerReview.id,
    'cm2': commentAdvisor.id,
    'cm3': commentMarketExpert.id,
    'cm1_r1': replyServiceOperator.id,
    'cm1_r2': replyAccountant.id,
    'cm1_r3': replyOpportunitySeeker.id,
    'cm2_r1': replyServicesInvestor.id,
    'cm2_r2': replyPreviousOwner.id,
    'cm3_r1': replyOperationsExpert.id,
  };

  static PublicProfileModel? byId(String? profileId) {
    final safeId = profileId?.trim() ?? '';
    return safeId.isEmpty ? null : _profiles[safeId];
  }

  static PublicProfileModel ownerForCouncil(CouncilModel council) {
    return byId(council.createdBy) ??
        byId(_ownerProfileIdsByCouncilId[council.id]) ??
        editorialFallback;
  }

  static PublicProfileModel authorForComment(CommentModel comment) {
    return byId(comment.authorId) ??
        byId(_commentProfileIdsByCommentId[comment.id]) ??
        editorialFallback;
  }

  static PublicProfileModel _demo(
    String id,
    String displayName,
    String username,
    String avatarEmoji,
  ) {
    return PublicProfileModel.seed(
      uid: '',
      id: id,
      displayName: displayName,
      username: username,
      avatarEmoji: avatarEmoji,
      demo: true,
    );
  }
}
