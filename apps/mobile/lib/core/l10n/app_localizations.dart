import 'package:flutter/widgets.dart';

import '../prefs/app_preferences.dart';

/// Lightweight, dependency-free localizations for English + Kiswahili.
///
/// A single [Map] per language keeps translations honest (no fake selector):
/// every migrated surface reads real, curated EN / SW strings through
/// [tr]. Missing keys fall back to English, then to the key itself, so
/// surfaces that have not yet been migrated never throw.
///
/// Registered as [AppLocalizationsDelegate] and queried via
/// `AppLocalizations.of(context)`.
class AppLocalizations {
  const AppLocalizations(this.locale);

  final Locale locale;

  static const LocalizationsDelegate<AppLocalizations> delegate =
      AppLocalizationsDelegate();

  /// Kiswahili-first brand fallback used when a widget is pumped outside a
  /// Localizations scope (standalone widget tests, isolated previews) — the
  /// same default language the platform surfaces on Swahili devices.
  static final AppLocalizations _fallback = AppLocalizations(const Locale('sw'));

  static AppLocalizations of(BuildContext context) =>
      Localizations.of<AppLocalizations>(context, AppLocalizations) ??
      _fallback;

  bool get isSwahili => locale.languageCode == 'sw';

  /// The active translation table (English or Kiswahili).
  Map<String, String> get table => isSwahili ? _sw : _en;

  /// Every defined translation key (union of both tables).
  Set<String> get keys => {..._en.keys, ..._sw.keys};

  /// Look up [key]; falls back EN, then the key itself.
  String tr(String key, {Map<String, String> args = const {}}) {
    final table = isSwahili ? _sw : _en;
    var raw = table[key] ?? _en[key] ?? key;
    if (args.isNotEmpty) {
      for (final entry in args.entries) {
        raw = raw.replaceAll('{{${entry.key}}}', entry.value);
      }
    }
    return raw;
  }
}

class AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => kAppLanguageTags.contains(locale.languageCode);

  static const List<Locale> supportedLocales = [Locale('en'), Locale('sw')];

  @override
  Future<AppLocalizations> load(Locale locale) async {
    // Use the region-free language code so 'en-US'/'sw-TZ' all map cleanly.
    final normalized =
        Locale(kAppLanguageTags.contains(locale.languageCode) ? locale.languageCode : 'en');
    return AppLocalizations(normalized);
  }

  @override
  bool shouldReload(AppLocalizationsDelegate old) => false;

  @override
  String toString() => 'AppLocalizationsDelegate';
}

const Map<String, String> _en = {
  // ----------------------------------------------------------------- common
  'app.name': "Sickler's Warriors",
  'common.loading': 'Loading…',
  'common.retry': 'Retry',
  'common.close': 'Close',
  'common.cancel': 'Cancel',
  'common.save': 'Save',
  'common.search': 'Search',
  'common.viewAll': 'View all',
  'common.readMore': 'Read more',
  'common.signIn': 'Login',
  'common.signOut': 'Sign out',
  'common.signUp': 'Sign up',
  'common.createAccount': 'Create Account',
  'common.delete': 'Delete',
  'common.edit': 'Edit',
  'common.back': 'Back',
  'common.continue': 'Continue',
  'common.open': 'Open',
  'common.learnMore': 'Learn more',
  'common.notifications': 'Notifications',
  'common.language': 'Language',
  'common.appearance': 'Appearance',
  'common.theme': 'Theme',
  'common.themeLight': 'Light',
  'common.themeDark': 'Dark',
  'common.themeSystem': 'System',
  'common.followDevice': 'Use device setting',
  'common.settings': 'Settings',
  'common.more': 'More',
  // ------------------------------------------------------------------- nav
  'nav.home': 'Home',
  'nav.health': 'Health',
  'nav.doctor': 'Find a Doctor',
  'nav.treatment': 'Medication',
  'nav.donate': 'Donate',
  'nav.profile': 'Profile',
  'nav.messages': 'Messages',
  'nav.records': 'Medical Records',
  'nav.blood': 'Blood',
  'nav.community': 'Community',
  'nav.news': 'News',
  'nav.resources': 'Resources',
  'nav.about': 'About',
  'nav.education': 'Education',
  'nav.aiCoach': 'AI Coach',
  'nav.timeline': 'Health Timeline',
  'nav.appointments': 'Appointments & Clinic',
  'nav.supportDonations': 'Support Donations',
  'news.readMore': 'Read More Updates',
  'about.about': 'About Sickler\'s Warriors',
  'about.mission': 'Our Mission',
  'about.howItWorks': 'How It Works',
  'about.team': 'Team & Partners',
  'about.contact': 'Contact Us',
  'nav.sos': 'SOS',
  // ------------------------------------------------------------ public home
  'home.heroTitle': 'Empowering Every Warrior.',
  'home.heroSubtitle': 'Connecting Care, Community and Hope.',
  'home.heroBody':
      'A digital health, blood and support platform for people living with sickle cell, their families, caregivers, healthcare providers and donors.',
  'home.readLatest': 'Read the latest updates',
  'home.tagline': 'Community · Care · Courage',
  'home.sectionsTitle': 'Everything a Warrior Needs',
  'home.sectionsSubtitle': 'Seven connected corners of care, support and community.',
  'home.trustTitle': 'Trust, Privacy & Consent',
  'home.trustBody':
      "Your health data is yours. We are transparent about what we collect, why we collect it, and your control over it — with consent at the centre of every decision.",
  'home.trustEncrypted': 'Encrypted & Secure',
  'home.trustConsent': 'Consent-Based',
  'home.trustPrivacy': 'Privacy First',
  'home.trustAccess': 'Authorized Access Only',
  'home.finalCtaTitle': 'Ready to Join Our Community?',
  'home.finalCtaBody':
      "Create your account today and start your journey with Sickler's Warriors.",
  'home.sosFooter': 'Emergency? Sign in to reach the SOS pathway.',
  'home.signedInOnly': 'Available in the app for signed-in members.',
  'home.explore': 'Explore',
  'home.newsLatest': 'Latest News',
  'home.newsSubtitle': 'Updates and stories from the Warrior community.',
  'home.newsEmpty': 'Fresh updates from the Warrior community land here first.',
  'home.newsFeatured': 'Featured Stories',
  'home.newsViewAll': 'View all news',
  'home.newsLatestUpdate': 'Latest Update',
  'home.footerRights': '© 2026 Sickler\'s Warriors. All rights reserved.',
  // ------------------------------------------------------- service sections
  'srv.healthTitle': 'Health Management',
  'srv.healthSubtitle':
      'Medication tracking, symptom logs, health timeline and clinic visits — one clear view of your care.',
  'srv.doctorTitle': 'Doctor Connection',
  'srv.doctorSubtitle':
      'Find and stay connected with authorized healthcare professionals who understand sickle cell disease.',
  'srv.bloodTitle': 'Blood Network',
  'srv.bloodSubtitle':
      'Request blood, offer a donation, and support the warriors who need it most.',
  'srv.emergencyTitle': 'Emergency Support',
  'srv.emergencySubtitle':
      "A dedicated SOS pathway for crises, tuned for the community's urgent moments.",
  'srv.educationTitle': 'Education — Warrior Academy',
  'srv.educationSubtitle':
      'Trusted, reviewed resources about sickle cell: what it is, how it is managed and how to live well.',
  'srv.communityTitle': 'Community',
  'srv.communitySubtitle':
      'A safe space for warriors, caregivers and supporters to connect, share and lift each other up.',
  'srv.donateTitle': 'Donate & Support',
  'srv.donateSubtitle':
      'Blood donations and financial support campaigns that keep the network strong.',
  // ----------------------------------------------------------- section CTA
  'act.healthDashboard': 'Open Health Dashboard',
  'act.manageMedication': 'Manage Medication',
  'act.findDoctor': 'Find a Doctor',
  'act.visitClinic': 'Visit the Clinic',
  'act.bloodNetwork': 'Blood & Donor Network',
  'act.donateBlood': 'Donate Blood',
  'act.emergencySos': 'Emergency & SOS',
  'act.openAcademy': 'Open Warrior Academy',
  'act.joinCommunity': 'Join the Community',
  'act.messages': 'Messages',
  'act.aiCoach': 'AI Coach',
  'act.makeDonation': 'Make a Donation',
  'act.changiaHub': 'Changia Hub',
  // ------------------------------------------------------------------ auth
  'auth.welcomeBack': 'Welcome back',
  'auth.emailOrPhone': 'Email or phone',
  'auth.requiredEmail': 'Enter your email or phone',
  'auth.password': 'Password',
  'auth.requiredPassword': 'Enter your password',
  'auth.confirmPassword': 'Confirm password',
  'auth.firstName': 'First name',
  'auth.lastName': 'Last name',
  'auth.phone': 'Phone (optional)',
  'auth.forgotPassword': 'Forgot password?',
  'auth.noAccount': "Don't have an account?",
  'auth.haveAccount': 'Already have an account?',
  'auth.createYourAccount': 'Create your account',
  'auth.signUpCta': 'Create Account',
  'auth.resetPassword': 'Reset password',
  'auth.verificationCode': 'Verification code',
  'auth.resendCode': 'Resend code',
  'auth.acceptTerms': 'By continuing you agree to our privacy and terms.',
  // ------------------------------------------------------ profile / settings
  'profile.title': 'Profile',
  'profile.securityPrivacy': 'Security & Privacy',
  'profile.medicalProfile': 'Medical Profile',
  'profile.medicalIdentity': 'Your blood type, genotype and diagnoses.',
  'profile.notificationPreferences': 'Notification preferences',
  'profile.emergencyAlwaysOn': 'SOS notifications stay on in emergencies.',
  'profile.changePassword': 'Change password',
  'profile.sessionOnDevice': 'Manage the password for this device session.',
  'profile.consentPrivacy': 'Consent & Privacy',
  'profile.consentBody':
      'Your data stays yours. Review what you share and with whom, and withdraw consent at any time.',
  'profile.preferences': 'Preferences',
  'profile.appearanceLanguage': 'Appearance & language',
  'profile.adaptExperience': 'Theme and language follow your device or your choice.',
  'settings.themeLight': 'Light',
  'settings.themeDark': 'Dark',
  'settings.themeSystem': 'System',
  'settings.languageEnglish': 'English',
  'settings.languageKiswahili': 'Kiswahili',
  'settings.languageDevice': 'Follow device',
  'settings.themeFollowDevice': 'Follow device setting',
  // ------------------------------------------------------------------ sos
  'sos.label': 'SOS',
  'sos.holdToArm': 'Press and hold to arm SOS',
  // ---------------------------------------------------------------- errors
  'err.generic': 'Something went wrong. Please try again.',
  'err.network': 'Connection lost. Check your network and try again.',
  'err.server': 'Service unavailable right now. Please try again later.',
  'err.session': 'Your session has expired. Please sign in again.',
  'err.noToken': 'Sign in required to use this feature.',
  'err.badResponse': 'Unexpected server response. Please try again.',
};

const Map<String, String> _sw = {
  // ----------------------------------------------------------------- common
  'app.name': "Sickler's Warriors",
  'common.loading': 'Inapakia…',
  'common.retry': 'Jaribu tena',
  'common.close': 'Funga',
  'common.cancel': 'Ghairi',
  'common.save': 'Hifadhi',
  'common.search': 'Tafuta',
  'common.viewAll': 'Ona vyote',
  'common.readMore': 'Soma zaidi',
  'common.signIn': 'Login',
  'common.signOut': 'Toka',
  'common.signUp': 'Jisajili',
  'common.createAccount': 'Unda Akaunti',
  'common.delete': 'Futa',
  'common.edit': 'Badilisha',
  'common.back': 'Rudi',
  'common.continue': 'Endelea',
  'common.open': 'Fungua',
  'common.learnMore': 'Jifunze zaidi',
  'common.notifications': 'Arifa',
  'common.language': 'Lugha',
  'common.appearance': 'Muonekano',
  'common.theme': 'Mandhari',
  'common.themeLight': 'Mwangaza',
  'common.themeDark': 'Giza',
  'common.themeSystem': 'Mfumo',
  'common.followDevice': 'Tumia mpangilio wa kifaa',
  'common.settings': 'Mipangilio',
  'common.more': 'Zaidi',
  // ------------------------------------------------------------------- nav
  'nav.home': 'Nyumbani',
  'nav.health': 'Afya',
  'nav.doctor': 'Daktari',
  'nav.treatment': 'Tiba',
  'nav.donate': 'Changia',
  'nav.profile': 'Wasifu',
  'nav.messages': 'Ujumbe',
  'nav.records': 'Kumbukumbu za Matibabu',
  'nav.blood': 'Damu',
  'nav.community': 'Jamii',
  'nav.news': 'Habari',
  'nav.resources': 'Nyenzo',
  'nav.about': 'Kuhusu',
  'nav.education': 'Elimu',
  'nav.aiCoach': 'Mshauri wa AI',
  'nav.timeline': 'Rekodi ya Afya',
  'nav.appointments': 'Miadi na Kliniki',
  'nav.supportDonations': 'Changia Misaada',
  'news.readMore': 'Soma Maboresho Zaidi',
  'about.about': 'Kuhusu Sickler\'s Warriors',
  'about.mission': 'Dhamira Yetu',
  'about.howItWorks': 'Inavyofanya Kazi',
  'about.team': 'Timu na Washirika',
  'about.contact': 'Wasiliana Nasi',
  'nav.sos': 'SOS',
  // ------------------------------------------------------------ public home
  'home.heroTitle': 'Kuwapa Nguvu Kila Shujaa.',
  'home.heroSubtitle': 'Tunaunganisha Huduma, Jamii na Tumaini.',
  'home.heroBody':
      'Jukwaa la kidijitali la afya, damu na msaada kwa watu wanaoishi na ugonjwa wa seli mundu, familia zao, walezi, watoa huduma za afya na wachangiaji damu.',
  'home.readLatest': 'Soma habari za hivi punde',
  'home.tagline': 'Jamii · Utunzaji · Ujasiri',
  'home.sectionsTitle': 'Kila Anachohitaji Shujaa',
  'home.sectionsSubtitle': 'Sehemu saba zilizounganishwa za huduma, msaada na jamii.',
  'home.trustTitle': 'Amani, Usiri na Idhini',
  'home.trustBody':
      'Data yako ya afya ni yako. Tuko wazi kuhusu kile tunachokusanya, kwanini tunakikusanya, na udhibiti wako juu yake — kwa idhini kuwa kitovu cha kila uamuzi.',
  'home.trustEncrypted': 'Imesimbwa na Salama',
  'home.trustConsent': 'Kwa Idhini',
  'home.trustPrivacy': 'Usiri Kwanza',
  'home.trustAccess': 'Wanaoidhinishwa Pekee',
  'home.finalCtaTitle': 'Tayari Kujiunga na Jamii Yetu?',
  'home.finalCtaBody': 'Unda akaunti yako leo na uanze safari yako na Sickler\'s Warriors.',
  'home.sosFooter': 'Dharura? Ingia ili kufikia njia ya SOS.',
  'home.signedInOnly': 'Inapatikana kwenye programu kwa wanachama walioingia.',
  'home.explore': 'Chunguza',
  'home.newsLatest': 'Habari za Hivi Punde',
  'home.newsSubtitle': 'Maboresho na hadithi kutoka kwenye jamii ya Mashujaa.',
  'home.newsEmpty': 'Habari mpya kutoka jamii ya Mashujaa zinatangazwa hapa kwanza.',
  'home.newsFeatured': 'Hadithi Zilizochaguliwa',
  'home.newsViewAll': 'Ona habari zote',
  'home.newsLatestUpdate': 'Taarifa ya Hivi Punde',
  'home.footerRights': '© 2026 Sickler\'s Warriors. Haki zote zimehifadhiwa.',
  // ------------------------------------------------------- service sections
  'srv.healthTitle': 'Udhibiti wa Afya',
  'srv.healthSubtitle':
      'Kufuatilia dawa, kumbukumbu za dalili, rekodi ya afya na ziara za kliniki — mtazamo mmoja wazi wa huduma yako.',
  'srv.doctorTitle': 'Mawasiliano ya Daktari',
  'srv.doctorSubtitle':
      'Tafuta na uendelee kuwa karibu na wataalamu wa afya walioidhinishwa wanaoelewa ugonjwa wa seli mundu.',
  'srv.bloodTitle': 'Mtandao wa Damu',
  'srv.bloodSubtitle':
      'Omba damu, changia damu, na usaidie mashujaa wanaohitaji zaidi.',
  'srv.emergencyTitle': 'Msaada wa Dharura',
  'srv.emergencySubtitle':
      'Njia maalum ya SOS kwa nyakati za hatari, iliyoundwa kwa ajili ya nyakati za dharura za jamii.',
  'srv.educationTitle': 'Elimu — Chuo cha Mashujaa',
  'srv.educationSubtitle':
      'Nyenzo za kuaminika na zilizokaguliwa kuhusu seli mundu: ni nini, inavyodhibitiwa na jinsi ya kuishi vizuri.',
  'srv.communityTitle': 'Jamii',
  'srv.communitySubtitle':
      'Nafasi salama kwa mashujaa, walezi na wafuasi kuungana, kushirikiana na kutiana moyo.',
  'srv.donateTitle': 'Changia na Usaidie',
  'srv.donateSubtitle':
      'Michango ya damu na kampeni za msaada wa fedha zinazoilinda mtandao.',
  // ----------------------------------------------------------- section CTA
  'act.healthDashboard': 'Fungua Dashibodi ya Afya',
  'act.manageMedication': 'Dhibiti Dawa',
  'act.findDoctor': 'Tafuta Daktari',
  'act.visitClinic': 'Tembelea Kliniki',
  'act.bloodNetwork': 'Mtandao wa Damu na Wachangiaji',
  'act.donateBlood': 'Changia Damu',
  'act.emergencySos': 'Dharura na SOS',
  'act.openAcademy': 'Fungua Chuo',
  'act.joinCommunity': 'Jiunge na Jamii',
  'act.messages': 'Ujumbe',
  'act.aiCoach': 'Mshauri wa AI',
  'act.makeDonation': 'Toa Mchango',
  'act.changiaHub': 'Kituo cha Changia',
  // ------------------------------------------------------------------ auth
  'auth.welcomeBack': 'Karibu tena',
  'auth.emailOrPhone': 'Barua pepe au namba',
  'auth.requiredEmail': 'Andika barua pepe au namba yako',
  'auth.password': 'Nenosiri',
  'auth.requiredPassword': 'Andika nenosiri lako',
  'auth.confirmPassword': 'Thibitisha nenosiri',
  'auth.firstName': 'Jina la kwanza',
  'auth.lastName': 'Jina la mwisho',
  'auth.phone': 'Namba ya simu (hiari)',
  'auth.forgotPassword': 'Umesahau nenosiri?',
  'auth.noAccount': 'Huna akaunti?',
  'auth.haveAccount': 'Tayari una akaunti?',
  'auth.createYourAccount': 'Unda akaunti yako',
  'auth.signUpCta': 'Unda Akaunti',
  'auth.resetPassword': 'Weka upya nenosiri',
  'auth.verificationCode': 'Namba ya uthibitisho',
  'auth.resendCode': 'Tuma tena namba',
  'auth.acceptTerms': 'Kwa kuendelea unakubali sera ya faragha na sheria zetu.',
  // ------------------------------------------------------ profile / settings
  'profile.title': 'Wasifu',
  'profile.securityPrivacy': 'Usalama na Faragha',
  'profile.medicalProfile': 'Wasifu wa Matibabu',
  'profile.medicalIdentity': 'Kundi la damu, jenotipu na uchunguzi wako.',
  'profile.notificationPreferences': 'Mapendeleo ya arifa',
  'profile.emergencyAlwaysOn': 'Arifa za SOS hubaki wazi nyakati za dharura.',
  'profile.changePassword': 'Badilisha nenosiri',
  'profile.sessionOnDevice': 'Dhibiti nenosiri la kipindi cha kifaa hiki.',
  'profile.consentPrivacy': 'Idhini na Faragha',
  'profile.consentBody':
      'Data yako inabaki yako. Kagua unachoshiriki na cha nani, na utengue idhini wakati wowote.',
  'profile.preferences': 'Mapendeleo',
  'profile.appearanceLanguage': 'Muonekano na lugha',
  'profile.adaptExperience': 'Mandhari na lugha vinafuata kifaa chako au chaguo lako.',
  'settings.themeLight': 'Mwangaza',
  'settings.themeDark': 'Giza',
  'settings.themeSystem': 'Mfumo',
  'settings.languageEnglish': 'English',
  'settings.languageKiswahili': 'Kiswahili',
  'settings.languageDevice': 'Fuata kifaa',
  'settings.themeFollowDevice': 'Fuata mpangilio wa kifaa',
  // ------------------------------------------------------------------ sos
  'sos.label': 'SOS',
  'sos.holdToArm': 'Bonyeza na ushikilie ili kuamilisha SOS',
  // ---------------------------------------------------------------- errors
  'err.generic': 'Kuna hitilafu imetokea. Tafadhali jaribu tena.',
  'err.network': 'Muunganisho umepotea. Angalia mtandao wako na ujaribu tena.',
  'err.server': 'Huduma haipatikani sasa hivi. Tafadhali jaribu tena baadae.',
  'err.session': 'Kipindi chako kimeisha. Tafadhali ingia tena.',
  'err.noToken': 'Ingia ili kutumia kipengele hiki.',
  'err.badResponse': 'Jibu lisilotarajiwa kutoka kwa seva. Tafadhali jaribu tena.',
};

/// Convenience helper that keeps expressions short: `s.tr('nav.home')`.
AppLocalizations l10n(BuildContext context) => AppLocalizations.of(context);