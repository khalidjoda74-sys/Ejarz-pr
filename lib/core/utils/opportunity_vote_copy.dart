import 'package:flutter/material.dart';

import '../../data/models/council_model.dart';
import '../theme/app_colors.dart';

class OpportunityVoteCopy {
  const OpportunityVoteCopy({
    required this.prompt,
    required this.supportLabel,
    required this.againstLabel,
    required this.neutralLabel,
    required this.supportResultLabel,
    required this.againstResultLabel,
    required this.neutralResultLabel,
    required this.supportIcon,
    required this.againstIcon,
    required this.neutralIcon,
    required this.supportColor,
    required this.againstColor,
    required this.neutralColor,
  });

  final String prompt;
  final String supportLabel;
  final String againstLabel;
  final String neutralLabel;
  final String supportResultLabel;
  final String againstResultLabel;
  final String neutralResultLabel;
  final IconData supportIcon;
  final IconData againstIcon;
  final IconData neutralIcon;
  final Color supportColor;
  final Color againstColor;
  final Color neutralColor;

  static OpportunityVoteCopy forCouncil(CouncilModel council) {
    return forCategory(council.category);
  }

  static OpportunityVoteCopy forCategory(String category) {
    final value = category.trim();

    if (value.contains('تقبيل')) {
      return const OpportunityVoteCopy(
        prompt: 'هل تستحق المعاينة؟',
        supportLabel: 'تستحق المعاينة',
        againstLabel: 'مخاطر عالية',
        neutralLabel: 'أحتاج أرقام',
        supportResultLabel: 'تستحق المعاينة',
        againstResultLabel: 'مخاطر',
        neutralResultLabel: 'تحتاج أرقام',
        supportIcon: Icons.visibility_rounded,
        againstIcon: Icons.warning_amber_rounded,
        neutralIcon: Icons.request_quote_rounded,
        supportColor: AppColors.primaryGreen,
        againstColor: AppColors.red,
        neutralColor: AppColors.warningGold,
      );
    }

    if (value.contains('مطلوبة') || value.contains('مطلوب')) {
      return const OpportunityVoteCopy(
        prompt: 'هل تستطيع مساعدته؟',
        supportLabel: 'لدي فرصة',
        againstLabel: 'أعرف جهة',
        neutralLabel: 'أحتاج تفاصيل',
        supportResultLabel: 'لديهم فرصة',
        againstResultLabel: 'يعرفون جهة',
        neutralResultLabel: 'تحتاج تفاصيل',
        supportIcon: Icons.work_outline_rounded,
        againstIcon: Icons.connect_without_contact_rounded,
        neutralIcon: Icons.manage_search_rounded,
        supportColor: AppColors.primaryGreen,
        againstColor: AppColors.primaryDarkGreen,
        neutralColor: AppColors.warningGold,
      );
    }

    if (value.contains('شراكة')) {
      return const OpportunityVoteCopy(
        prompt: 'ما موقفك من الشراكة؟',
        supportLabel: 'مهتم',
        againstLabel: 'مخاطر عالية',
        neutralLabel: 'أحتاج تفاصيل',
        supportResultLabel: 'مهتمون',
        againstResultLabel: 'مخاطر',
        neutralResultLabel: 'تحتاج تفاصيل',
        supportIcon: Icons.handshake_rounded,
        againstIcon: Icons.report_problem_rounded,
        neutralIcon: Icons.manage_search_rounded,
        supportColor: AppColors.primaryGreen,
        againstColor: AppColors.red,
        neutralColor: AppColors.warningGold,
      );
    }

    return const OpportunityVoteCopy(
      prompt: 'ما تقييمك للتجربة؟',
      supportLabel: 'مفيدة',
      againstLabel: 'أرى غير ذلك',
      neutralLabel: 'تجربة مشابهة',
      supportResultLabel: 'مفيدة',
      againstResultLabel: 'رأي آخر',
      neutralResultLabel: 'تجارب مشابهة',
      supportIcon: Icons.thumb_up_alt_rounded,
      againstIcon: Icons.forum_rounded,
      neutralIcon: Icons.history_rounded,
      supportColor: AppColors.primaryGreen,
      againstColor: AppColors.red,
      neutralColor: AppColors.warningGold,
    );
  }

  String labelFor(VoteOption option) {
    switch (option) {
      case VoteOption.support:
        return supportLabel;
      case VoteOption.against:
        return againstLabel;
      case VoteOption.neutral:
        return neutralLabel;
    }
  }

  String resultLabelFor(VoteOption option) {
    switch (option) {
      case VoteOption.support:
        return supportResultLabel;
      case VoteOption.against:
        return againstResultLabel;
      case VoteOption.neutral:
        return neutralResultLabel;
    }
  }

  IconData iconFor(VoteOption option) {
    switch (option) {
      case VoteOption.support:
        return supportIcon;
      case VoteOption.against:
        return againstIcon;
      case VoteOption.neutral:
        return neutralIcon;
    }
  }

  Color colorFor(VoteOption option) {
    switch (option) {
      case VoteOption.support:
        return supportColor;
      case VoteOption.against:
        return againstColor;
      case VoteOption.neutral:
        return neutralColor;
    }
  }
}