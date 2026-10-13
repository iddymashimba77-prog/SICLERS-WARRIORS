import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/constants/app_strings.dart';
import 'core/l10n/app_localizations.dart';
import 'core/l10n/locale_controller.dart';
import 'core/navigation/not_found_page.dart';
import 'core/prefs/app_preferences.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';
import 'features/admin/presentation/pages/admin_panel_page.dart';
import 'features/ai_assistant/presentation/pages/ai_assistant_page.dart';
import 'features/auth/data/auth_repository.dart';
import 'features/auth/data/token_store.dart';
import 'features/auth/presentation/controllers/auth_controller.dart';
import 'features/auth/presentation/pages/continue_as_page.dart';
import 'features/auth/presentation/pages/doctor_verification_page.dart';
import 'features/auth/presentation/pages/forgot_password_page.dart';
import 'features/auth/presentation/pages/login_page.dart';
import 'features/auth/presentation/pages/organization_verification_page.dart';
import 'features/auth/presentation/pages/reset_password_page.dart';
import 'features/auth/presentation/pages/role_workspace_page.dart';
import 'features/auth/presentation/pages/set_pin_page.dart';
import 'features/auth/presentation/pages/signup_page.dart';
import 'features/auth/presentation/pages/verification_submission_page.dart';
import 'features/auth/presentation/widgets/auth_gate.dart';
import 'features/auth/presentation/widgets/session_scope.dart';
import 'features/blood_donation/presentation/pages/blood_donation_page.dart';
import 'features/blood_donation/presentation/pages/donor_home_page.dart';
import 'features/blood_donation/presentation/pages/donor_shell.dart';
import 'features/caregiver/presentation/pages/caregiver_shell.dart';
import 'features/clinic/presentation/pages/clinic_page.dart';
import 'features/chat/presentation/pages/conversation_list_page.dart';
import 'features/community/presentation/pages/community_page.dart';
import 'features/doctor_network/presentation/pages/doctor_network_page.dart';
import 'features/donations/presentation/pages/changia_hub_page.dart';
import 'features/donations/presentation/pages/donations_page.dart';
import 'features/doctor/presentation/pages/doctor_hub_page.dart';
import 'features/doctor/presentation/pages/doctor_medications_page.dart';
import 'features/doctor/presentation/pages/doctor_shell.dart';
import 'features/emergency/presentation/pages/emergency_page.dart';
import 'features/education/presentation/pages/doctor_education_page.dart';
import 'features/education/presentation/pages/education_page.dart';
import 'features/health/presentation/pages/health_dashboard_page.dart';
import 'features/medical/presentation/pages/medical_profile_page.dart';
import 'features/medical/presentation/pages/medical_records_page.dart';
import 'features/medication/presentation/pages/medication_page.dart';
import 'features/notifications/presentation/pages/notifications_page.dart';
import 'features/profile/presentation/pages/profile_page.dart';
import 'features/public/presentation/controllers/branding_controller.dart';
import 'features/public/presentation/pages/news_list_page.dart';
import 'features/public/presentation/pages/public_home_page.dart';
import 'shared/widgets/main_shell.dart';

class SicklersWarriorsApp extends StatefulWidget {
  const SicklersWarriorsApp({super.key, this.preferences, this.tokenStore});

  /// Optional injection point so widget tests can avoid plugin channels.
  final AppPreferences? preferences;
  final TokenStore? tokenStore;

  const SicklersWarriorsApp.testing({super.key, this.preferences, this.tokenStore});

  @override
  State<SicklersWarriorsApp> createState() => _SicklersWarriorsAppState();
}

class _SicklersWarriorsAppState extends State<SicklersWarriorsApp> {
  late final AppPreferences _prefs;
  late final ThemeController _theme;
  late final LocaleController _locale;
  late final BrandingController _branding;

  /// One session for the whole app: owned here so tokens survive navigation
  /// from the login page into the shell (FRONTEND-2).
  late final AuthController _session;

  @override
  void initState() {
    super.initState();
    // In tests the caller supplies an in-memory preferences store; otherwise
    // the app reads (and writes) the device settings.
    final hasTestPrefs = widget.preferences != null;
    _prefs = widget.preferences ?? AppPreferences.memory();
    _theme = ThemeController(_prefs);
    _locale = LocaleController(_prefs);
    _branding = BrandingController();
    _session = AuthController(
      repository: AuthRepository(
        tokenStore: widget.tokenStore ?? SharedPrefsTokenStore(),
      ),
    );
    _branding.load();
    if (!hasTestPrefs) {
      // Boot the plugin-backed preferences before trusting stored values.
      _prefsLoad();
    } else {
      // Restore session on app start (tests / production).
      _session.restoreSession();
    }
  }

  Future<void> _prefsLoad() async {
    // Swap the memory snapshot for the device-backed preferences and re-seed
    // both controllers from the persisted values, then restore the session.
    // Plugin channels can be absent (widget tests); fall back to memory prefs.
    AppPreferences loaded;
    try {
      loaded = await AppPreferences.load();
    } catch (_) {
      loaded = AppPreferences.memory();
    }
    if (!mounted) return;
    _theme.reload(loaded);
    _locale.reload(loaded);
    await _session.restoreSession();
  }

  @override
  void dispose() {
    _session.dispose();
    _theme.dispose();
    _locale.dispose();
    _branding.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SessionScope(
      controller: _session,
      child: BrandingScope(
        controller: _branding,
        child: ThemeScope(
          controller: _theme,
          child: LocaleScope(
            controller: _locale,
            child: const _MaterialAppView(),
          ),
        ),
      ),
    );
  }
}

/// Builds the [MaterialApp] so it rebuilds whenever the theme or language
/// scope notifies. Without depending on both scopes here, toggling theme or
/// language from any surface would flip the control's own icon/label but never
/// propagate to the running app's `themeMode`/`locale`.
class _MaterialAppView extends StatelessWidget {
  const _MaterialAppView();

  @override
  Widget build(BuildContext context) {
    final themeController = ThemeScope.of(context);
    final localeController = LocaleScope.of(context);
    return MaterialApp(
      title: AppStrings.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeController.value,
      locale: localeController.value,
      supportedLocales: const [Locale('en'), Locale('sw')],
      localeResolutionCallback: (requested, supportedLocales) {
        if (requested == null) return const Locale('en');
        return AppLocalizationsDelegate.supportedLocales
            .firstWhere(
              (l) => l.languageCode == requested.languageCode,
              orElse: () => const Locale('en'),
            );
      },
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      initialRoute: AuthGate.routeName,
      routes: {
        // '/': the public home doubles as the "shell root", so sign-out's
        // `pushNamedAndRemoveUntil('/')` semantics keep working.
        PublicHomePage.routeName: (_) => const PublicHomePage(),
        NewsListPage.routeName: (_) => const NewsListPage(),
        AuthGate.routeName: (_) => const AuthGate(),
        LoginPage.routeName: (_) => const LoginPage(),
        SignupPage.routeName: (_) => const SignupPage(),
        VerificationSubmissionPage.routeName: (context) {
          final args = ModalRoute.of(context)?.settings.arguments;
          final roleCode = args is Map ? (args['roleCode'] as String? ?? '') : null;
          return VerificationSubmissionPage(roleCode: roleCode);
        },
        ForgotPasswordPage.routeName: (_) => const ForgotPasswordPage(),
        // Same argument contract as EmailVerificationPage: a `token` map
        // entry lets a caller hand the reset code straight over, while the
        // plain `pushNamed('/reset-password')` path falls back to the
        // user-entered code field on the page itself.
        ResetPasswordPage.routeName: (context) {
          final args = ModalRoute.of(context)?.settings.arguments;
          final token = args is Map ? (args['token'] as String? ?? '') : '';
          return ResetPasswordPage(token: token);
        },
        ContinueAsPage.routeName: (_) => const ContinueAsPage(),
        SetPinPage.routeName: (_) => const SetPinPage(),
        DoctorVerificationPage.routeName: (_) =>
            const DoctorVerificationPage(),
        OrganizationVerificationPage.routeName: (_) =>
            const OrganizationVerificationPage(),
        RoleWorkspacePage.routeName: (_) => const RoleWorkspacePage(),
        ProfilePage.routeName: (_) => const ProfilePage(),
        EmergencyPage.routeName: (_) => const EmergencyPage(),
        CommunityPage.routeName: (_) => const CommunityPage(),
        EducationPage.routeName: (_) => const EducationPage(),
        DoctorEducationPage.routeName: (_) => const DoctorEducationPage(),
        ConversationListPage.routeName: (_) =>
            const ConversationListPage(),
        MedicalProfilePage.routeName: (_) => const MedicalProfilePage(),
        MedicationPage.routeName: (_) => const MedicationPage(),
        HealthDashboardPage.routeName: (_) =>
            const HealthDashboardPage(),
        BloodDonationPage.routeName: (_) => const BloodDonationPage(),
        DonorHomePage.routeName: (_) => const DonorHomePage(),
        DoctorNetworkPage.routeName: (_) => const DoctorNetworkPage(),
        ClinicPage.routeName: (_) => const ClinicPage(),
        DonationsPage.routeName: (_) => const DonationsPage(),
        NotificationsPage.routeName: (_) => const NotificationsPage(),
        AiAssistantPage.routeName: (_) => const AiAssistantPage(),
        AdminPanelPage.routeName: (_) => const AdminPanelPage(),
        DoctorHubPage.routeName: (_) => const DoctorHubPage(),
        ChangiaHubPage.routeName: (_) => const ChangiaHubPage(),
        MedicalRecordsPage.routeName: (_) => const MedicalRecordsPage(),
        DoctorShell.routeName: (_) => const DoctorShell(),
        DoctorMedicationsPage.routeName: (_) => const DoctorMedicationsPage(),
        DonorShell.routeName: (_) => const DonorShell(),
        CaregiverShell.routeName: (_) => const CaregiverShell(),
        MainShell.routeName: (_) => const MainShell(),
      },
      // Stale deep links and mis-typed named routes must degrade to a real
      // page: WidgetsApp throws (debug) / null-check crashes (release) when
      // no generator can resolve a route.
      onUnknownRoute: (settings) => MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => NotFoundPage(failedRoute: settings.name),
      ),
    );
  }
}