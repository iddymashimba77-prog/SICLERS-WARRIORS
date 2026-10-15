import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/responsive/responsive.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../../auth/presentation/widgets/session_scope.dart';
import '../../../blood_donation/presentation/pages/blood_donation_page.dart';
import '../../../doctor/presentation/pages/doctor_hub_page.dart';
import '../../../donations/presentation/pages/donations_page.dart';
import '../../../education/data/education_repository.dart';
import '../../../education/presentation/pages/education_page.dart';
import '../../../emergency/presentation/pages/emergency_page.dart';
import '../../../health/data/health_repository.dart';
import '../../../health/presentation/pages/health_dashboard_page.dart';
import '../../../health/presentation/pages/symptom_form_page.dart';
import '../../../medical/presentation/pages/medical_profile_page.dart';
import '../../../medication/presentation/pages/medication_page.dart';
import '../../../notifications/presentation/pages/notifications_page.dart';
import '../../../profile/presentation/pages/profile_page.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/widgets/app_emergency.dart';
import '../../../../shared/widgets/app_top_bar.dart';
import '../../../../shared/widgets/dashboard_widgets.dart';
import '../../../../shared/widgets/state_views.dart';
import '../../data/home_dashboard_loader.dart';
import '../../../../core/theme/app_shapes.dart';
import '../../../../shared/widgets/signed_out_gate.dart';

/// Sickler's Warriors — patient Home dashboard (FRONTEND-2).
///
/// Personalised header + health snapshot, all backed by the real API clients:
/// shared shell session ([SessionScope]) reaches `GET /patients/me/dashboard`,
/// `/auth/me`, notifications, education, emergency and blood requests. Sections
/// show honest empty/loading/offline states — never fabricated health data.
class HomePage extends StatelessWidget {
  const HomePage({super.key, this.controller, this.loader});

  // Deliberately no `routeName`: the patient home is the first tab of
  // [MainShell] ('/shell'). Registering '/' here as well would collide with
  // PublicHomePage.routeName, and only the public home owns the root route.

  /// Shared session override (widget tests inject an authenticated controller).
  final AuthController? controller;

  /// Aggregator override for deterministic tests; defaults to a real loader.
  final HomeDashboardLoader? loader;

  @override
  Widget build(BuildContext context) {
    final session = controller ?? SessionScope.controllerOf(context);
    final token = session.accessToken;
    if (token == null) {
      return const SignedOutGate();
    }
    return HomeDashboardView(
      accessToken: token,
      session: session,
      loader: loader,
    );
  }
}

/// Authenticated dashboard — orchestrates the aggregated load and renders the
/// responsive section grid. The only primary payload is the health dashboard;
/// every side read degrades independently to an honest empty state.
class HomeDashboardView extends StatefulWidget {
  const HomeDashboardView({
    super.key,
    required this.accessToken,
    required this.session,
    this.loader,
  });

  final String accessToken;
  final AuthController session;
  final HomeDashboardLoader? loader;

  @override
  State<HomeDashboardView> createState() => _HomeDashboardViewState();
}

class _HomeDashboardViewState extends State<HomeDashboardView> {
  late final HomeDashboardLoader _loader =
      widget.loader ?? HomeDashboardLoader();

  HomeDashboardData? _data;
  bool _loading = true;

  AuthController get _session => widget.session;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await _loader.load(access: widget.accessToken);
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _data = HomeDashboardData(dashboard: null);
        _loading = false;
      });
    }
  }

  String? get _personName {
    final data = _data;
    final first = data?.identity?.firstName;
    final last = data?.identity?.lastName;
    final joined = [first, last]
        .whereType<String>()
        .where((s) => s.trim().isNotEmpty)
        .join(' ')
        .trim();
    if (joined.isNotEmpty) return joined;
    final local = _session.displayName;
    if (local != null && local.isNotEmpty) return local;
    final email = _session.email;
    if (email != null && email.contains('@')) return email.split('@').first;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          children: [
            AppHomeHeader(
              personName: _personName,
              subtitle: AppStrings.homeSubtitle,
              unreadCount: _data?.unreadCount ?? 0,
              onNotificationsTap: () =>
                  Navigator.of(context).pushNamed(NotificationsPage.routeName),
              onAvatarTap: () =>
                  Navigator.of(context).pushNamed(ProfilePage.routeName),
              avatarName: _personName,
            ),
            _buildBody(context),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.lg),
        child: SkeletonCard(rows: 3, lines: 3),
      );
    }

    final data = _data;
    if (data == null || data.dashboard == null) {
      final online = data?.offline != true;
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: ErrorRetryView(
          icon: online ? Icons.cloud_off_outlined : Icons.wifi_off,
          title: online ? AppStrings.dashboardLoadFailed : AppStrings.youAreOffline,
          message: online
              ? 'We couldn\'t load your health dashboard. Check your connection '
                  'and try again.'
              : 'Connect to the internet, then refresh your dashboard.',
          onRetry: _load,
        ),
      );
    }

    return ResponsiveBuilder(
      builder: (context, size) {
        final padding = AppLayout.edgePadding(size);
        final columns = switch (size) {
          AppScreenSize.compact => 1,
          AppScreenSize.medium => 2,
          AppScreenSize.expanded => 3,
          AppScreenSize.large => 4,
        };
        return Padding(
          padding: EdgeInsets.only(
            left: padding,
            right: padding,
            top: AppSpacing.md,
            bottom: AppSpacing.xl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (data.offline) ..._offlineBanner(context),
              _CheckInCard(
                accessToken: widget.accessToken,
                repository: _loader.healthRepository,
                dashboard: data.dashboard!,
                onRefresh: _load,
              ),
              SectionHeader(title: AppStrings.quickActions),
              QuickActionsGrid(actions: _quickActions(context)),
              SectionHeader(title: AppStrings.alertsAndAttention),
              _AlertsCard(data: data),
              SectionHeader(title: AppStrings.healthSnapshot),
              SnapStatGrid(dashboard: data.dashboard!),
              SectionHeader(
                title: AppStrings.healthTrendTitle,
                actionLabel: AppStrings.viewHealthInsights,
                onAction: () => Navigator.of(context)
                    .pushNamed(HealthDashboardPage.routeName),
              ),
              _HealthTrendCard(dashboard: data.dashboard!),
              _AdaptiveGrid(
                columns: columns,
                children: [
                  _MedicationsCard(
                    dashboard: data.dashboard!,
                    onOpen: () => Navigator.of(context)
                        .pushNamed(MedicationPage.routeName),
                  ),
                  _PainSymptomsCard(
                    dashboard: data.dashboard!,
                    accessToken: widget.accessToken,
                    repository: _loader.healthRepository,
                    onRefresh: _load,
                  ),
                  _AppointmentCard(
                    onOpenDoctor: () => Navigator.of(context)
                        .pushNamed(DoctorHubPage.routeName),
                  ),
                  _ActivityCard(dashboard: data.dashboard!),
                  _LearnCard(articles: data.articles),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              Center(
                child: Text(
                  AppStrings.appTagline,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _offlineBanner(BuildContext context) {
    return [
      AlertCard(
        title: AppStrings.youAreOffline,
        message: AppStrings.noDataRecorded,
        icon: Icons.wifi_off,
        tone: AlertTone.warning,
      ),
      const SizedBox(height: AppSpacing.md),
    ];
  }

  List<QuickAction> _quickActions(BuildContext context) {
    void go(String route) => Navigator.of(context).pushNamed(route);
    return [
      QuickAction(
        icon: Icons.personal_injury_outlined,
        label: AppStrings.medicalProfile,
        accent: AppColors.blue,
        onTap: () => go(MedicalProfilePage.routeName),
      ),
      QuickAction(
        icon: Icons.medication_outlined,
        label: AppStrings.navTreatment,
        accent: AppColors.success,
        onTap: () => go(MedicationPage.routeName),
      ),
      QuickAction(
        icon: Icons.monitor_heart_outlined,
        label: AppStrings.healthTracking,
        accent: AppColors.blue,
        onTap: () => go(HealthDashboardPage.routeName),
      ),
      QuickAction(
        icon: Icons.medical_services_outlined,
        label: AppStrings.navDoctor,
        accent: AppColors.success,
        onTap: () => go(DoctorHubPage.routeName),
      ),
      QuickAction(
        icon: Icons.bloodtype_outlined,
        label: AppStrings.bloodDonation,
        accent: AppColors.emergency,
        onTap: () => go(BloodDonationPage.routeName),
      ),
      QuickAction(
        icon: Icons.volunteer_activism_outlined,
        label: AppStrings.navDonate,
        accent: AppColors.success,
        onTap: () => go(DonationsPage.routeName),
      ),
      QuickAction(
        icon: Icons.person_outline,
        label: AppStrings.navProfile,
        accent: AppColors.blue,
        onTap: () => go(ProfilePage.routeName),
      ),
      QuickAction(
        icon: Icons.school_outlined,
        label: AppStrings.education,
        accent: AppColors.blue,
        onTap: () => go(EducationPage.routeName),
      ),
    ];
  }
}

/// Grid that stacks cards on phones and flows into N columns on wider screens.
class _AdaptiveGrid extends StatelessWidget {
  const _AdaptiveGrid({required this.columns, required this.children});

  final int columns;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final gap = AppSpacing.md;
        final itemW =
            columns <= 1 ? constraints.maxWidth : (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [for (final c in children) SizedBox(width: itemW, child: c)],
        );
      },
    );
  }
}

/// Snapshot stat tiles (doses, adherence, symptoms, active meds).
class SnapStatGrid extends StatelessWidget {
  const SnapStatGrid({super.key, required this.dashboard});

  final HealthDashboard dashboard;

  @override
  Widget build(BuildContext context) {
    final doses = dashboard.dosesToday;
    final pct = dashboard.adherenceLast7.adherencePct;
    return StatGrid(
      children: [
        StatCard(
          label: AppStrings.activeMedications,
          value: '${dashboard.activeMedCount}',
          icon: Icons.medication,
          accent: AppColors.blue,
        ),
        StatCard(
          label: AppStrings.dosesTodayTitle,
          value: '${doses['taken'] ?? 0} / ${doses['expected'] ?? 0}',
          icon: Icons.check_circle_outline,
          accent: AppColors.success,
        ),
        StatCard(
          label: AppStrings.adherenceLast7Short,
          value: pct == null ? '--' : '${pct.round()}%',
          icon: Icons.trending_up,
          accent: AppColors.success,
        ),
        StatCard(
          label: AppStrings.symptomsRecorded,
          value: '${dashboard.recentSymptoms.length}',
          icon: Icons.healing_outlined,
          accent: AppColors.warning,
        ),
      ],
    );
  }
}

/// Daily check-in — a user-reported action (never a diagnosis). Reuses the
/// approved symptom-recording flow and refreshes the dashboard afterwards.
class _CheckInCard extends StatelessWidget {
  const _CheckInCard({
    required this.accessToken,
    required this.repository,
    required this.dashboard,
    required this.onRefresh,
  });

  final String accessToken;
  final HealthRepository repository;
  final HealthDashboard dashboard;
  final VoidCallback onRefresh;

  Future<void> _openCheckIn(BuildContext context) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => SymptomFormPage(
          accessToken: accessToken,
          repository: repository,
        ),
      ),
    );
    if (saved == true) onRefresh();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final symptom = dashboard.recentSymptoms.isNotEmpty
        ? dashboard.recentSymptoms.first
        : null;
    final last =
        symptom == null ? null : _symptomSummary(symptom, _relativeTime(symptom.recordedAt));
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.blue.withValues(alpha: 0.12),
                  borderRadius: AppShapes.tile,
                ),
                child: const Icon(Icons.today_outlined, color: AppColors.blue),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppStrings.dailyCheckin,
                      style: theme.textTheme.titleMedium,
                    ),
                    if (last != null)
                      Text(last, style: theme.textTheme.bodySmall)
                    else
                      Text(
                        AppStrings.noDataRecorded,
                        style: theme.textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(AppStrings.checkinIntro, style: theme.textTheme.bodySmall),
          const SizedBox(height: AppSpacing.md),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonalIcon(
              onPressed: () => _openCheckIn(context),
              icon: const Icon(Icons.add_circle_outline),
              label: Text(AppStrings.checkinAction),
            ),
          ),
        ],
      ),
    );
  }
}

String _symptomSummary(Symptom s, String time) {
  final parts = <String>[
    if (s.painLevel != null) '${AppStrings.painLevel} ${s.painLevel}/10',
    if (time.isNotEmpty) time,
  ];
  final name = s.symptomTypeName ?? s.symptomTypeCode;
  final tail = parts.join(' · ');
  return '${AppStrings.lastRecorded}: $name${tail.isEmpty ? '' : ' · $tail'}';
}

/// Medications, pending doses and an add/manage entry point.
class _MedicationsCard extends StatelessWidget {
  const _MedicationsCard({required this.dashboard, required this.onOpen});

  final HealthDashboard dashboard;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final meds = dashboard.medicalList;
    return _DashCard(
      title: AppStrings.medications,
      icon: Icons.medication_outlined,
      accent: AppColors.blue,
      trailing: TextButton(onPressed: onOpen, child: Text(AppStrings.viewAll)),
      child: meds.isEmpty
          ? _EmptyInline(
              icon: Icons.medication_outlined,
              message: AppStrings.noMedications,
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final m in meds.take(4))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            [m.name, m.strength]
                                .where((s) => s.isNotEmpty)
                                .join(' '),
                            style: theme.textTheme.bodyMedium,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (m.dosesTodayPending > 0)
                          Text(
                            '${m.dosesTodayPending} ${AppStrings.pendingDoses.toLowerCase()}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppColors.warning,
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

/// Latest pain/symptoms with a "log" affordance.
class _PainSymptomsCard extends StatelessWidget {
  const _PainSymptomsCard({
    required this.dashboard,
    required this.accessToken,
    required this.repository,
    required this.onRefresh,
  });

  final HealthDashboard dashboard;
  final String accessToken;
  final HealthRepository repository;
  final VoidCallback onRefresh;

  Future<void> _log(BuildContext context) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => SymptomFormPage(
          accessToken: accessToken,
          repository: repository,
        ),
      ),
    );
    if (saved == true) onRefresh();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final symptoms = dashboard.recentSymptoms;
    return _DashCard(
      title: AppStrings.symptoms,
      icon: Icons.healing_outlined,
      accent: AppColors.warning,
      trailing: TextButton(
        onPressed: () => _log(context),
        child: Text(AppStrings.logSymptom),
      ),
      child: symptoms.isEmpty
          ? _EmptyInline(
              icon: Icons.healing_outlined,
              message: AppStrings.noSymptoms,
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final s in symptoms.take(4))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                    child: Row(
                      children: [
                        Icon(
                          s.painLevel != null && s.painLevel! >= 7
                              ? Icons.warning_amber_rounded
                              : Icons.health_and_safety_outlined,
                          size: 18,
                          color: s.painLevel != null && s.painLevel! >= 7
                              ? AppColors.emergency
                              : AppColors.blue,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                s.symptomTypeName ?? s.symptomTypeCode,
                                style: theme.textTheme.bodyMedium,
                              ),
                              Text(
                                [
                                  if (s.painLevel != null)
                                    '${AppStrings.painLevel} ${s.painLevel}/10',
                                  if (s.durationMinutes != null)
                                    '${s.durationMinutes} min',
                                  _relativeTime(s.recordedAt),
                                ]
                                    .where((t) => t.isNotEmpty)
                                    .join(' · '),
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

/// Upcoming appointments — honest empty state until an appointment API exists.
class _AppointmentCard extends StatelessWidget {
  const _AppointmentCard({required this.onOpenDoctor});

  final VoidCallback onOpenDoctor;

  @override
  Widget build(BuildContext context) {
    return _DashCard(
      title: AppStrings.upcomingAppointments,
      icon: Icons.event_outlined,
      accent: AppColors.info,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _EmptyInline(
            icon: Icons.event_available_outlined,
            message: AppStrings.noAppointments,
          ),
          const SizedBox(height: AppSpacing.sm),
          TextButton.icon(
            onPressed: onOpenDoctor,
            icon: const Icon(Icons.medical_services_outlined),
            label: Text(AppStrings.navDoctor),
          ),
        ],
      ),
    );
  }
}

/// Adherence trend + link to the full health insights (Tiba).
class _HealthTrendCard extends StatelessWidget {
  const _HealthTrendCard({required this.dashboard});

  final HealthDashboard dashboard;

  @override
  Widget build(BuildContext context) {
    final block = dashboard.adherenceLast7;
    final pct = block.adherencePct;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (pct == null)
            _EmptyInline(
              icon: Icons.show_chart,
              message: AppStrings.noDataRecorded,
            )
          else
            ProgressCard(
              label: AppStrings.adherenceLastSeven,
              value: pct,
              max: 100,
              icon: Icons.trending_up,
              accent: pct >= 80 ? AppColors.success : AppColors.warning,
              caption: '${block.taken} of ${block.expected} doses taken',
            ),
        ],
      ),
    );
  }
}

/// Recent health timeline activity.
class _ActivityCard extends StatelessWidget {
  const _ActivityCard({required this.dashboard});

  final HealthDashboard dashboard;

  @override
  Widget build(BuildContext context) {
    final entries = dashboard.recentTimeline;
    return _DashCard(
      title: AppStrings.recentActivityTitle,
      icon: Icons.bolt_outlined,
      accent: AppColors.blue,
      child: entries.isEmpty
          ? _EmptyInline(
              icon: Icons.bolt_outlined,
              message: AppStrings.noRecentActivity,
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final t in entries.take(4))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                    child: Row(
                      children: [
                        const Icon(Icons.fiber_manual_record,
                            size: 12, color: AppColors.blue),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            t.summary,
                            style: Theme.of(context).textTheme.bodyMedium,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          _relativeTime(t.occurredAt),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

/// One education recommendation (real published content) + library entry.
class _LearnCard extends StatelessWidget {
  const _LearnCard({required this.articles});

  final List<EducationalContent> articles;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    EducationalContent? article;
    for (final a in articles) {
      if (a.isPublished) {
        article = a;
        break;
      }
    }
    return _DashCard(
      title: AppStrings.learnAndGrow,
      icon: Icons.school_outlined,
      accent: AppColors.info,
      trailing: TextButton(
        onPressed: () =>
            Navigator.of(context).pushNamed(EducationPage.routeName),
        child: Text(AppStrings.viewEducationLibrary),
      ),
      child: article == null
          ? _EmptyInline(
              icon: Icons.school_outlined,
              message: AppStrings.noEducationContent,
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  article.title,
                  style: theme.textTheme.titleSmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  [
                    article.category.name,
                    article.author.displayName,
                  ].where((s) => s.isNotEmpty).join(' · '),
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
    );
  }
}

/// Emergency / blood / all-clear alert. Red is reserved for a true active
/// emergency; open blood requests get an amber heads-up.
class _AlertsCard extends StatelessWidget {
  const _AlertsCard({required this.data});

  final HomeDashboardData data;

  @override
  Widget build(BuildContext context) {
    if (data.activeEmergencies.isNotEmpty) {
      return EmergencyCard(
        title: AppStrings.activeEmergencyTitle,
        message: '${AppStrings.activeEmergencyBody} '
            '${data.activeEmergencies.length} active request(s).',
        icon: Icons.sos,
        actionLabel: AppStrings.trackingTitle,
        onTap: () => Navigator.of(context).pushNamed(EmergencyPage.routeName),
      );
    }
    if (data.openBloodRequests.isNotEmpty) {
      return AlertCard(
        title: AppStrings.openBloodRequestTitle,
        message: AppStrings.activeBloodRequestBody,
        icon: Icons.bloodtype_outlined,
        tone: AlertTone.warning,
        actionLabel: AppStrings.viewAll,
        onTap: () =>
            Navigator.of(context).pushNamed(BloodDonationPage.routeName),
      );
    }
    return AlertCard(
      title: AppStrings.home,
      message: AppStrings.noActiveAlerts,
      icon: Icons.check_circle_outline,
      tone: AlertTone.success,
    );
  }
}

/// Section card shell for dashboard grid tiles.
class _DashCard extends StatelessWidget {
  const _DashCard({
    required this.title,
    required this.icon,
    required this.accent,
    required this.child,
    this.trailing,
  });

  final String title;
  final IconData icon;
  final Color accent;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: accent),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  title.toUpperCase(),
                  style: theme.textTheme.labelSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          child,
        ],
      ),
    );
  }
}

/// Compact in-card empty placeholder (no fabricated data).
class _EmptyInline extends StatelessWidget {
  const _EmptyInline({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(message, style: theme.textTheme.bodySmall)),
        ],
      ),
    );
  }
}

String _relativeTime(String? iso) {
  final dt = iso == null ? null : DateTime.tryParse(iso)?.toLocal();
  if (dt == null) return '';
  final diff = DateTime.now().difference(dt);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m';
  if (diff.inHours < 24) return '${diff.inHours}h';
  if (diff.inDays < 7) return '${diff.inDays}d';
  return '${dt.day}/${dt.month}/${dt.year}';
}