import 'package:flutter/material.dart';

import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_spacing.dart';
import 'animated_page_banner.dart';
import 'healthcare_banner_art.dart';

/// Every authenticated surface that owns a healthcare banner.
///
/// The catalogue is the single source of truth for copy keys, scene and brand
/// palette. Pages select a [BannerPage]; they never duplicate banner layout or
/// hardcode translations.
enum BannerPage {
  dashboard,
  aiAssistant,
  doctorNetwork,
  bloodDonation,
  education,
  healthDashboard,
  community,
  familyNetwork,
  appointments,
}

@immutable
class BannerPageSpec {
  const BannerPageSpec({
    required this.scene,
    required this.palette,
    required this.titleKey,
    required this.descriptionKey,
    required this.semanticsKey,
  });

  final BannerScene scene;
  final BannerPalette palette;
  final String titleKey;
  final String descriptionKey;
  final String semanticsKey;
}

const Map<BannerPage, BannerPageSpec> bannerPageCatalog = {
  BannerPage.dashboard: BannerPageSpec(
    scene: BannerScene.careTeam,
    palette: BannerPalette.midnight,
    titleKey: 'banner.dashboard.title',
    descriptionKey: 'banner.dashboard.description',
    semanticsKey: 'banner.dashboard.semantics',
  ),
  BannerPage.aiAssistant: BannerPageSpec(
    scene: BannerScene.aiCompanion,
    palette: BannerPalette.ocean,
    titleKey: 'banner.ai.title',
    descriptionKey: 'banner.ai.description',
    semanticsKey: 'banner.ai.semantics',
  ),
  BannerPage.doctorNetwork: BannerPageSpec(
    scene: BannerScene.doctorNetwork,
    palette: BannerPalette.midnight,
    titleKey: 'banner.doctors.title',
    descriptionKey: 'banner.doctors.description',
    semanticsKey: 'banner.doctors.semantics',
  ),
  BannerPage.bloodDonation: BannerPageSpec(
    scene: BannerScene.bloodDonation,
    palette: BannerPalette.crimson,
    titleKey: 'banner.blood.title',
    descriptionKey: 'banner.blood.description',
    semanticsKey: 'banner.blood.semantics',
  ),
  BannerPage.education: BannerPageSpec(
    scene: BannerScene.medicalEducation,
    palette: BannerPalette.ocean,
    titleKey: 'banner.education.title',
    descriptionKey: 'banner.education.description',
    semanticsKey: 'banner.education.semantics',
  ),
  BannerPage.healthDashboard: BannerPageSpec(
    scene: BannerScene.healthMonitoring,
    palette: BannerPalette.midnight,
    titleKey: 'banner.health.title',
    descriptionKey: 'banner.health.description',
    semanticsKey: 'banner.health.semantics',
  ),
  BannerPage.community: BannerPageSpec(
    scene: BannerScene.communitySupport,
    palette: BannerPalette.ocean,
    titleKey: 'banner.community.title',
    descriptionKey: 'banner.community.description',
    semanticsKey: 'banner.community.semantics',
  ),
  BannerPage.familyNetwork: BannerPageSpec(
    scene: BannerScene.familyCare,
    palette: BannerPalette.midnight,
    titleKey: 'banner.family.title',
    descriptionKey: 'banner.family.description',
    semanticsKey: 'banner.family.semantics',
  ),
  BannerPage.appointments: BannerPageSpec(
    scene: BannerScene.appointments,
    palette: BannerPalette.ocean,
    titleKey: 'banner.appointments.title',
    descriptionKey: 'banner.appointments.description',
    semanticsKey: 'banner.appointments.semantics',
  ),
};

/// Localised shortcut for adding a catalogue banner to an authenticated page.
class PageBanner extends StatelessWidget {
  const PageBanner({
    super.key,
    required this.page,
    this.margin = const EdgeInsets.fromLTRB(
      AppSpacing.lg,
      AppSpacing.md,
      AppSpacing.lg,
      0,
    ),
    this.height,
    this.compact,
    this.animate = true,
  });

  final BannerPage page;
  final EdgeInsetsGeometry margin;
  final double? height;
  final bool? compact;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final spec = bannerPageCatalog[page]!;
    final s = AppLocalizations.of(context);
    return AnimatedPageBanner(
      key: ValueKey<String>('page-banner-${page.name}'),
      title: s.tr(spec.titleKey),
      description: s.tr(spec.descriptionKey),
      semanticsLabel: s.tr(spec.semanticsKey),
      scene: spec.scene,
      palette: spec.palette,
      margin: margin,
      height: height,
      compact: compact,
      animate: animate,
    );
  }
}
