class AppRoutes {
  const AppRoutes._();

  static const splash = '/';
  static const onboarding = '/onboarding';
  static const nickname = '/nickname';
  static const main = '/main';
  static const profileMember = '/profile/member';
  static const profileDemo = '/profile/demo';

  static String council(String councilId) =>
      '/council/${Uri.encodeComponent(councilId)}';
  static String memberProfile(String uid) =>
      '$profileMember/${Uri.encodeComponent(uid)}';
  static String demoProfile(String profileId) =>
      '$profileDemo/${Uri.encodeComponent(profileId)}';
}
