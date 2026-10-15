import 'package:flutter/widgets.dart';

/// Localized UI copy for the whole app (English + Kiswahili).
///
/// Historically these were `static const` English strings, which meant they
/// could not react to the in-app language switch and produced mixed-language
/// screens (some `tr(...)` copy in the chosen language, some hardcoded English
/// or hardcoded Swahili). They are now runtime getters resolved against the
/// [bind] locale, so a single language choice renders a single language
/// everywhere.
///
/// The active language is bound from [AppLocalizationsDelegate] (see
/// `core/l10n/app_localizations.dart`) which is what Flutter reloads whenever
/// the user changes language, guaranteeing [AppStrings] is set before widgets
/// rebuild. Defaults to English when nothing is bound (tests, cold start).
class AppStrings {
  AppStrings._();

  static Locale _locale = const Locale('en');

  /// Bind the active language. Called by the localizations delegate whenever
  /// Flutter (re)loads localizations, i.e. on every language change.
  static void bind(Locale locale) {
    _locale = Locale(locale.languageCode);
  }

  static bool get _sw => _locale.languageCode == 'sw';

  static String _t(String en, String sw) => _sw ? sw : en;

  // ------------------------------------------------------------------- brand
  static String get appName => "Sickler's Warriors";
  static String get appTagline =>
      _t('Strength Together, Fight Together', 'Nguvu Pamoja, Kupambana Pamoja');

  // -------------------------------------------------------------------- auth
  static String get login => _t('Login', 'Ingia');
  static String get register => _t('Register', 'Jiandikishe');
  static String get logout => _t('Logout', 'Toka');
  static String get email => _t('Email', 'Barua pepe');
  static String get password => _t('Password', 'Nenosiri');
  static String get phoneNumber => _t('Phone Number', 'Namba ya simu');
  static String get forgottenPassword =>
      _t('Forgot password?', 'Umesahau nenosiri?');
  static String get loginFailed =>
      _t('Unable to sign in. Check your details.',
          'Imeshindikana kuingia. Angalia taarifa zako.');
  static String get dontHaveAccount =>
      _t("Don't have an account? ", 'Hauna akaunti? ');
  static String get alreadyHaveAccount =>
      _t('Already have an account? ', 'Tayari una akaunti? ');

  // ------------------------------------------------- profile / medical id
  static String get profile => _t('Profile', 'Wasifu');
  static String get save => _t('Save', 'Hifadhi');
  static String get cancel => _t('Cancel', 'Ghairi');
  static String get saved => _t('Saved', 'Imehifadhiwa');
  static String get saving => _t('Saving…', 'Inahifadhi…');
  static String get loadingProfile => _t('Loading profile…', 'Inapakia wasifu…');
  static String get profileLoadFailed =>
      _t('Unable to load your profile.', 'Imeshindikana kupakia wasifu wako.');
  static String get editProfile => _t('Edit Profile', 'Hariri Wasifu');
  static String get dateOfBirth => _t('Date of birth', 'Tarehe ya kuzaliwa');
  static String get gender => _t('Gender', 'Jinsia');
  static String get genotype => _t('Genotype', 'Jenotaipu');
  static String get diagnosisDate => _t('Diagnosis date', 'Tarehe ya utambuzi');
  static String get primaryDiagnosis =>
      _t('Primary diagnosis', 'Utambuzi mkuu');
  static String get emergencyContactName =>
      _t('Emergency contact name', 'Jina la mtu wa dharura');
  static String get emergencyContactPhone =>
      _t('Emergency contact phone', 'Simu ya mtu wa dharura');
  static String get emergencyContactRelation =>
      _t('Emergency contact relation', 'Uhusiano wa mtu wa dharura');
  static String get addressRegion => _t('Address region', 'Mkoa wa anwani');
  static String get addressCity => _t('Address city', 'Jiji la anwani');
  static String get treatingFacility =>
      _t('Treating facility', 'Kituo cha matibabu');
  static String get facilityRequired => _t(
      'Choose the clinic or hospital where you receive treatment.',
      'Chagua kliniki au hospitali unapopata matibabu.');
  static String get facilityNotSet => _t('Not set yet', 'Haijawekwa bado');
  static String get facilityDirectoryUnavailable => _t(
      'Facility directory unavailable — check your connection and retry.',
      'Orodha ya vituo haipatikani — angalia mtandao wako na ujaribu tena.');
  static String get notes => _t('Notes', 'Maelezo');
  static String get privateNote => _t(
      'Private — visible only to you and authorised care providers.',
      'Ya faragha — inaonekana kwako na kwa wahudumu wa afya walioruhusiwa.');
  static String get medicalIdentity => _t(
      'Medical identity and emergency contact details. Private and consent '
          'protected.',
      'Taarifa za utambulisho wa matibabu na mtu wa dharura. Ni za faragha na '
          'zinalindwa kwa ridhaa.');
  static String get identity => _t('Identity', 'Utambulisho');

  // ------------------------------------------------------ home / navigation
  static String get home => _t('Home', 'Nyumbani');
  static String get emergency => _t('Emergency', 'Dharura');
  static String get community => _t('Community', 'Jamii');
  static String get notifications => _t('Notifications', 'Taarifa');
  static String get settings => _t('Settings', 'Mipangilio');

  // Primary patient navigation — approved labels.
  static String get navHome => _t('Home', 'Nyumbani');
  static String get navDoctor => _t('Doctor', 'Daktari');
  static String get navTreatment => _t('Treatment', 'Tiba');
  static String get navDonate => _t('Donate', 'Changia');
  static String get navProfile => _t('Profile', 'Wasifu');

  // ------------------------------------------------------- shell / hubs
  static String get doctor => _t('Doctor', 'Daktari');
  static String get treatment => _t('Treatment', 'Tiba');
  static String get donate => _t('Donate', 'Changia');
  static String get contributions => _t('Contributions', 'Michango');
  static String get greeting => _t('Hello', 'Habari');
  static String get explore => _t('Explore', 'Chunguza');
  static String get quickActions => _t('Quick Actions', 'Vitendo vya Haraka');
  static String get comingSoon => _t('Coming soon', 'Inakuja hivi karibuni');
  static String get viewAll => _t('View all', 'Ona zote');

  // ------------------------------------ navigation destinations (post-auth)
  static String get health => _t('Health', 'Afya');
  static String get blood => _t('Blood', 'Damu');
  static String get more => _t('More', 'Zaidi');
  static String get sos => _t('SOS', 'SOS');
  static String get medicalProfile => _t('Medical Profile', 'Wasifu wa Matibabu');
  static String get medicalRecords => _t('Health Records', 'Kumbukumbu za Afya');
  static String get medicationReminders =>
      _t('Medication Reminders', 'Vikumbusho vya Dawa');
  static String get clinicCalendar => _t('Clinic Calendar', 'Kalenda ya Kliniki');

  // ---------------------------------------------------- blood & donations
  static String get bloodDonation => _t('Blood Donation', 'Uchangiaji Damu');
  static String get financialDonations =>
      _t('Financial Donations', 'Michango ya Fedha');
  static String get donations => _t('Donations', 'Michango');
  static String get campaigns => _t('Campaigns', 'Kampeni');
  static String get verifiedCampaigns =>
      _t('Verified Campaigns', 'Kampeni Zilizothibitishwa');
  static String get donateNow => _t('Donate now', 'Changia sasa');
  static String get donates => _t('donated', 'amechangia');
  static String get goalOf => _t('of', 'kati ya');
  static String get raisedSoFar => _t('Raised so far', 'Iliyokusanywa hadi sasa');
  static String get campaignOwner => _t('Campaign owner', 'Mmiliki wa kampeni');
  static String get noCampaigns => _t(
      'No verified campaigns yet. Check back soon.',
      'Hakuna kampeni zilizothibitishwa bado. Angalia tena hivi karibuni.');
  static String get campaignsLoadFailed => _t(
      'Unable to load campaigns. Check your connection and try again.',
      'Imeshindikana kupakia kampeni. Angalia mtandao na ujaribu tena.');
  static String get donationsLoadFailed => _t(
      'Unable to load your donation history.',
      'Imeshindikana kupakia historia ya michango yako.');
  static String get donationInitiated => _t('Donation initiated', 'Mchango umeanzishwa');
  static String get donationInitiatedBody => _t(
      'Your payment is pending provider confirmation. The donation will be '
          'recorded as confirmed only after the payment provider verifies it.',
      'Malipo yako yanasubiri uthibitisho wa mtoa huduma. Mchango utarekodiwa '
          'kama umethibitishwa tu baada ya mtoa huduma wa malipo kuthibitisha.');
  static String get paymentConfirmed => _t('Payment confirmed', 'Malipo yamethibitishwa');
  static String get paymentFailed => _t('Payment failed', 'Malipo yameshindikana');
  static String get retryingDonation =>
      _t('Checking payment status…', 'Inaangalia hali ya malipo…');
  static String get donationUpdated =>
      _t('Donation status updated.', 'Hali ya mchango imesasishwa.');
  static String get donationActionFailed =>
      _t('Unable to update the donation.', 'Imeshindikana kusasisha mchango.');
  static String get retryDonation => _t('Retry payment', 'Jaribu malipo tena');
  static String get donationAmount => _t('Donation amount (TZS)', 'Kiasi cha mchango (TZS)');
  static String get donationAmountError =>
      _t('Enter an amount to donate.', 'Weka kiasi cha kuchangia.');
  static String get paymentMethod => _t('Payment method', 'Njia ya malipo');
  static String get shareDonationRef => _t(
      'I consent to share my donation reference.',
      'Nakubali kushiriki kumbukumbu ya mchango wangu.');
  static String get confirmDonation => _t('Confirm donation', 'Thibitisha mchango');
  static String get donationsHistory => _t('Donation history', 'Historia ya michango');
  static String get noDonations =>
      _t('No donations yet. Support a campaign above.', 'Hakuna michango bado. Saidia kampeni hapo juu.');
  static String get receiptTitle => _t('Donation receipt', 'Risiti ya mchango');
  static String get receiptNumber => _t('Receipt number', 'Namba ya risiti');
  static String get receiptFor => _t('Campaign', 'Kampeni');
  static String get receiptAmount => _t('Amount', 'Kiasi');
  static String get receiptDate => _t('Donated on', 'Ilichangiwa tarehe');
  static String get transactionRef => _t('Transaction', 'Muamala');
  static String get receiptNotAvailable => _t(
      'Receipts are available once the payment is confirmed.',
      'Risiti zinapatikana mara baada ya malipo kuthibitishwa.');
  static String get checkStatus => _t('Check status', 'Angalia hali');
  static String get payoutPending => _t('Pending', 'Inasubiri');
  static String get donationConfirmed => _t('Confirmed', 'Imethibitishwa');
  static String get donationRefused => _t('Failed', 'Imeshindikana');
  static String get providerRefLabel => _t('Reference', 'Kumbukumbu');
  static String get retryOnlyPendingOrFailed => _t(
      'Payments can only be retried while pending or failed.',
      'Malipo yanaweza kujaribiwa tena yakiwa yanasubiri au yameshindikana.');

  // --------------------------------------------------------- doctor network
  static String get doctorNetwork => _t('Doctor Network', 'Mtandao wa Madaktari');
  static String get verifiedDoctors => _t('Verified Doctors', 'Madaktari Waliothibitishwa');

  // -------------------------------------------------------------- emergency
  static String get emergencySupport => _t('Emergency Support', 'Msaada wa Dharura');

  // -------------------------------------------------------------------- ai
  static String get aiAssistant => _t('AI Assistant', 'Msaidizi wa AI');

  // ----------------------------------------------------------------- admin
  static String get adminPanel => _t('Admin Panel', 'Paneli ya Msimamizi');

  // ------------------------------------------------------ shared async state
  static String get retry => _t('Retry', 'Jaribu tena');
  static String get close => _t('Close', 'Funga');

  static String get notSignedIn =>
      _t('Sign in to use this feature.', 'Ingia ili kutumia kipengele hiki.');

  // ------------------------------------------------------------- medication
  static String get medications => _t('Medications', 'Dawa');
  static String get noMedications => _t('No medications yet.', 'Hakuna dawa bado.');
  static String get addMedication => _t('Add Medication', 'Ongeza Dawa');
  static String get editMedication => _t('Edit Medication', 'Hariri Dawa');
  static String get medicationName => _t('Medication name', 'Jina la dawa');
  static String get medicationNameHint => _t('e.g. Hydroxyurea', 'mf. Hydroxyurea');
  static String get genericName => _t('Generic name', 'Jina la jumla');
  static String get strength => _t('Strength', 'Nguvu');
  static String get strengthHint => _t('e.g. 500 mg', 'mf. 500 mg');
  static String get dosage => _t('Dosage', 'Kipimo');
  static String get dosageHint =>
      _t('e.g. 1 tablet twice daily', 'mf. kibonge kimoja mara mbili kwa siku');
  static String get route => _t('Route', 'Njia');
  static String get frequency => _t('Frequency', 'Mara ngapi');
  static String get frequencyHint =>
      _t('e.g. daily, twice a day', 'mf. kila siku, mara mbili kwa siku');
  static String get startDate => _t('Start date', 'Tarehe ya kuanza');
  static String get endDate => _t('End date (optional)', 'Tarehe ya kuisha (si lazima)');
  static String get stopMedication => _t('Stop medication', 'Sitisha dawa');
  static String get stopMedicationConfirm => _t(
      'Stop this medication? It will be hidden from your active list.',
      'Sitisha dawa hii? Itafichwa kwenye orodha yako ya dawa zinazotumika.');
  static String get active => _t('Active', 'Inatumika');
  static String get stopped => _t('Stopped', 'Imesitishwa');
  static String get startDateAfterEnd => _t(
      'Start date must be on or before end date.',
      'Tarehe ya kuanza lazima iwe kabla au sawa na tarehe ya kuisha.');
  static String get medicationSaveFailed =>
      _t('Unable to save the medication.', 'Imeshindikana kuhifadhi dawa.');
  static String get medicationLoadFailed =>
      _t('Unable to load your medications.', 'Imeshindikana kupakia dawa zako.');

  // -------------------------------------------------------------- schedules
  static String get schedules => _t('Schedule', 'Ratiba');
  static String get addSchedule => _t('Add schedule', 'Ongeza ratiba');
  static String get removeSchedule => _t('Remove schedule', 'Ondoa ratiba');
  static String get scheduleTime => _t('Dose time', 'Muda wa kipimo');
  static String get scheduleDays => _t('Days of week', 'Siku za wiki');
  static String get scheduleNotes => _t('Schedule notes', 'Maelezo ya ratiba');
  static String get noSchedules => _t(
      'No schedules yet. Add one to track dose times.',
      'Hakuna ratiba bado. Ongeza moja kufuatilia muda wa kipimo.');
  static String get scheduleSaved => _t('Schedule saved.', 'Ratiba imehifadhiwa.');
  static String get scheduleRemoved => _t('Schedule removed.', 'Ratiba imeondolewa.');
  static String get scheduleTimeHint => _t('Select time', 'Chagua muda');
  static String get today => _t('Today', 'Leo');

  // ----------------------------------------------------------- dose logging
  static String get logDose => _t('Log dose', 'Rekodi kipimo');
  static String get doseTaken => _t('Taken', 'Imetumika');
  static String get doseMissed => _t('Missed', 'Imekosekana');
  static String get doseSkipped => _t('Skipped', 'Imerukwa');
  static String get doseSnoozed => _t('Snoozed', 'Imeahirishwa');
  static String get doseLogged => _t('Dose recorded.', 'Kipimo kimerekodiwa.');
  static String get doseLogFailed =>
      _t('Unable to record the dose.', 'Imeshindikana kurekodi kipimo.');
  static String get doseHistory => _t('Dose history', 'Historia ya vipimo');
  static String get noDoseHistory =>
      _t('No doses recorded yet.', 'Hakuna vipimo vilivyorekodiwa bado.');
  static String get recordDose => _t('Record dose', 'Rekodi kipimo');

  // ------------------------------------------------------- stats / adherence
  static String get adherence => _t('Adherence', 'Ufuataji');
  static String get adherenceHelp => _t(
      'Adherence is a monitoring aid — always follow your care plan.',
      'Ufuataji ni msaada wa ufuatiliaji — fuata mpango wako wa matibabu kila '
          'wakati.');
  static String get adherenceLastSeven =>
      _t('Adherence (last 7 days)', 'Ufuataji (siku 7 zilizopita)');
  static String get expectedDoses =>
      _t('Expected doses', 'Vipimo vinavyotarajiwa');
  static String get takenDoses => _t('Taken', 'Zilizotumika');
  static String get pendingDoses => _t('Pending', 'Zinasubiri');
  static String get statsLoadFailed => _t(
      'Unable to load your adherence stats.',
      'Imeshindikana kupakia takwimu za ufuataji.');

  // ------------------------------------------------------- health tracking
  static String get healthTracking => _t('Health Tracking', 'Ufuatiliaji wa Afya');
  static String get dashboardLoadFailed => _t(
      'Unable to load your health dashboard.',
      'Imeshindikana kupakia dashibodi yako ya afya.');
  static String get symptoms => _t('Symptoms', 'Dalili');
  static String get recordSymptom => _t('Record Symptom', 'Rekodi Dalili');
  static String get logSymptom => _t('Log Symptom', 'Rekodi Dalili');
  static String get noSymptoms =>
      _t('No symptoms recorded yet.', 'Hakuna dalili zilizorekodiwa bado.');
  static String get symptomType => _t('Symptom', 'Dalili');
  static String get painLevel => _t('Pain level', 'Kiwango cha maumivu');
  static String get painScale => _t(
      'Pain level (0 = none, 10 = worst)',
      'Kiwango cha maumivu (0 = hakuna, 10 = vibaya zaidi)');
  static String get triggers => _t('Triggers', 'Visababishi');
  static String get durationMinutes => _t('Duration (minutes)', 'Muda (dakika)');
  static String get recordedAt => _t('Recorded at', 'Ilirekodiwa saa');
  static String get symptomSaveFailed =>
      _t('Unable to record the symptom.', 'Imeshindikana kurekodi dalili.');
  static String get symptomSaved => _t('Symptom recorded.', 'Dalili zimerekodiwa.');
  static String get painCrisisTitle => _t('Painful crisis', 'Mgogoro wa maumivu');
  static String get crisisHelp => _t(
      'If this is a painful crisis, follow the care plan set with your doctor.',
      'Kama huu ni mgogoro wa maumivu, fuata mpango wa matibabu uliowekwa na '
          'daktari wako.');
  static String get timeline => _t('Timeline', 'Mstari wa matukio');
  static String get timelineLoadFailed => _t(
      'Unable to load your health timeline.',
      'Imeshindikana kupakia mstari wa matukio ya afya yako.');
  static String get viewTimeline => _t('View Timeline', 'Ona Mstari wa Matukio');
  static String get noTimelineEdits =>
      _t('No health activity yet.', 'Hakuna shughuli za afya bado.');

  // ------------------------------------------------------------ blood network
  static String get bloodRequests => _t('Blood Requests', 'Maombi ya Damu');
  static String get newBloodRequest => _t('New Blood Request', 'Ombi Jipya la Damu');
  static String get requestBlood => _t('Request Blood', 'Omba Damu');
  static String get bloodGroupNeeded =>
      _t('Blood group needed', 'Kundi la damu linalohitajika');
  static String get unitsNeeded => _t('Units needed', 'Vipimo vinavyohitajika');
  static String get urgency => _t('Urgency', 'Uharaka');
  static String get reasonForRequest => _t('Reason (optional)', 'Sababu (si lazima)');
  static String get requestLocation => _t('Location (optional)', 'Mahali (si lazima)');
  static String get facilityUidHint =>
      _t('Verified facility UID (optional)', 'UID ya kituo kilichothibitishwa (si lazima)');
  static String get noBloodRequests => _t(
      'No blood requests yet. Create one if you or a warrior needs blood.',
      'Hakuna maombi ya damu bado. Tengeneza moja kama wewe au shujaa anahitaji '
          'damu.');
  static String get bloodLoadFailed =>
      _t('Unable to load blood requests.', 'Imeshindikana kupakia maombi ya damu.');
  static String get bloodSaveFailed => _t(
      'Unable to submit the blood request.',
      'Imeshindikana kuwasilisha ombi la damu.');
  static String get bloodRequestCreated => _t(
      'Blood request submitted for verification.',
      'Ombi la damu limewasilishwa kwa uthibitisho.');
  static String get cancelRequest => _t('Cancel request', 'Ghairi ombi');
  static String get cancelRequestConfirm => _t(
      'Cancel this blood request? This cannot be undone.',
      'Ghairi ombi hili la damu? Hili haliwezi kutenduliwa.');
  static String get requestCancelled =>
      _t('Blood request cancelled.', 'Ombi la damu limeghairiwa.');
  static String get matches => _t('Matches', 'Wiana');
  static String get noMatches => _t('No donor matches yet.', 'Hakuna wiana wa watoa damu bado.');
  static String get matchScore => _t('Match score', 'Alama ya uwiano');
  static String get accept => _t('Accept', 'Kubali');
  static String get decline => _t('Decline', 'Kataa');
  static String get matchResponded =>
      _t('Match response recorded.', 'Majibu ya uwiano yamerekodiwa.');
  static String get matchRespondFailed =>
      _t('Unable to respond to the match.', 'Imeshindikana kujibu uwiano.');
  static String get donorProfile => _t('Donor Profile', 'Wasifu wa Mtoa Damu');
  static String get becomeDonor => _t('Become a donor', 'Kuwa mtoa damu');
  static String get donorProfileHelp => _t(
      'Your contact details stay private. Only blood group, region, city, '
          'availability and donation history are shared (BR-006).',
      'Taarifa zako za mawasiliano zinabaki za faragha. Ni kundi la damu, mkoa, '
          'jiji, upatikanaji na historia ya uchangiaji tu vinashirikiwa (BR-006).');
  static String get bloodGroup => _t('Blood group', 'Kundi la damu');
  static String get region => _t('Region', 'Mkoa');
  static String get city => _t('City', 'Jiji');
  static String get availableToDonate =>
      _t('Available to donate', 'Napatikana kuchangia');
  static String get donorVerified => _t('Verified donor', 'Mtoa damu aliyethibitishwa');
  static String get donorSaved =>
      _t('Donor profile saved.', 'Wasifu wa mtoa damu umehifadhiwa.');
  static String get donorSaveFailed => _t(
      'Unable to save your donor profile.',
      'Imeshindikana kuhifadhi wasifu wako wa mtoa damu.');
  static String get donationHistory => _t('Donations', 'Michango');

  // --------------------------------------------------------- emergency (4.8)
  static String get emergencyHome => _t('Emergency', 'Dharura');
  static String get triggerEmergency => _t('Trigger Emergency', 'Anzisha Dharura');
  static String get emergencyType => _t('Emergency type', 'Aina ya dharura');
  static String get emergencySeverity => _t('Severity', 'Ukali');
  static String get describeEmergency => _t(
      'Describe what is happening (optional)',
      'Eleza kinachotokea (si lazima)');
  static String get submitEmergency =>
      _t('Send Emergency Alert', 'Tuma Tahadhari ya Dharura');
  static String get emergencyCreated => _t(
      'Emergency alert sent. Help is on the way.',
      'Tahadhari ya dharura imetumwa. Msaada unakuja.');
  static String get emergencyCreateFailed => _t(
      'Unable to send the emergency alert.',
      'Imeshindikana kutuma tahadhari ya dharura.');
  static String get activeEmergencies =>
      _t('Active emergencies', 'Dharura zinazoendelea');
  static String get noEmergencies => _t('No emergency requests.', 'Hakuna maombi ya dharura.');
  static String get emergencyLoadFailed => _t(
      'Unable to load emergency requests.',
      'Imeshindikana kupakia maombi ya dharura.');
  static String get respondEmergency => _t('Respond', 'Jibu');
  static String get validateEmergency => _t('Validate', 'Thibitisha');
  static String get escalateEmergency => _t('Escalate', 'Pandisha');
  static String get resolveEmergency => _t('Resolve', 'Maliza');
  static String get cancelEmergency => _t('Cancel', 'Ghairi');
  static String get emergencyUpdated =>
      _t('Emergency request updated.', 'Ombi la dharura limesasishwa.');
  static String get emergencyActionFailed => _t(
      'Unable to update the emergency request.',
      'Imeshindikana kusasisha ombi la dharura.');
  static String get emergencyCallNote => _t(
      'For immediate danger, also call your local emergency number.',
      'Kwa hatari ya haraka, piga pia namba yako ya dharura ya eneo lako.');

  // ------------------------------------------------------- emergency SOS (4.9)
  static String get sosHoldToArm =>
      _t('Press and hold to arm SOS', 'Bonyeza na ushikilie kuandaa SOS');
  static String get sosArmed => _t('SOS armed', 'SOS imeandaliwa');
  static String get sosConfirmTitle => _t('Confirm emergency', 'Thibitisha dharura');
  static String get sosConfirmBody => _t(
      'This raises an emergency alert to responders. It is NOT a replacement '
          'for emergency services.',
      'Hii inatuma tahadhari ya dharura kwa watoa msaada. HAIYAELEKEZI badala '
          'ya huduma za dharura.');
  static String get sosCallInstruction => _t(
      'If you are in immediate danger, call your local emergency number (112) '
          'or the nearest facility now.',
      'Kama uko hatarini mara moja, piga namba ya dharura ya eneo lako (112) au '
          'kituo cha karibu sasa.');
  static String get sosShareConsent => _t(
      'Share my emergency profile (contact, location, notes) with responders.',
      'Shiriki wasifu wangu wa dharura (mawasiliano, mahali, maelezo) na watoa '
          'msaada.');
  static String get sosConsentRequired =>
      _t('Consent is required to send an alert.', 'Ridhaa inahitajika kutuma tahadhari.');
  static String get sosLocationLabel => _t('Where are you? (optional)', 'Uko wapi? (si lazima)');
  static String get sosNotSentCallNow => _t(
      'Alert not sent. Call emergency services or the nearest facility now.',
      'Tahadhari haijatumwa. Piga huduma za dharura au kituo cha karibu sasa.');
  static String get sosRateLimited => _t(
      'You have raised several alerts recently. Call emergency services now.',
      'Umetuma tahadhari kadhaa hivi karibuni. Piga huduma za dharura sasa.');
  static String get emergencyPrefill =>
      _t('Using your emergency contact', 'Inatumia mtu wako wa dharura');
  static String get trackingTitle => _t('Emergency status', 'Hali ya dharura');
  static String get trackingTimeline => _t('Status progress', 'Maendeleo ya hali');
  static String get trackingResponders => _t('Responders', 'Watoa msaada');
  static String get trackingNoResponders =>
      _t('No responder has acknowledged yet.', 'Hakuna mtoa msaada aliyethibitisha bado.');
  static String get trackingLocation => _t('Location', 'Mahali');
  static String get trackingResolvedTitle => _t('Emergency resolved', 'Dharura imemalizika');
  static String get trackingResolvedBody => _t(
      'Your emergency request is resolved. If symptoms return, raise a new '
          'alert or call emergency services.',
      'Ombi lako la dharura limemalizika. Kama dalili zinarudi, anzisha '
          'tahadhari mpya au piga huduma za dharura.');
  static String get accessStatus => _t('Emergency access', 'Ufikiaji wa dharura');
  static String get accessGrantedUntil =>
      _t('Professional access granted until', 'Ufikiaji wa mtaalamu umetolewa hadi');
  static String get accessNone =>
      _t('No professional has emergency access.', 'Hakuna mtaalamu mwenye ufikiaji wa dharura.');
  static String get callEmergencyServices =>
      _t('Call emergency services', 'Piga huduma za dharura');

  // ------------------------------------------------------------ notifications
  static String get inbox => _t('Inbox', 'Kikasha');
  static String get preferences => _t('Preferences', 'Mapendeleo');
  static String get markAllRead => _t('Mark all read', 'Weka zote kama zimesomwa');
  static String get notificationsAllRead =>
      _t('All notifications marked read.', 'Taarifa zote zimewekwa kama zimesomwa.');
  static String get noNotifications => _t('No notifications yet.', 'Hakuna taarifa bado.');
  static String get notificationsLoadFailed => _t(
      'Unable to load your notifications.', 'Imeshindikana kupakia taarifa zako.');
  static String get notificationsReadFailed =>
      _t('Unable to update notifications.', 'Imeshindikana kusasisha taarifa.');
  static String get categoriesLoadFailed => _t(
      'Unable to load notification preferences.',
      'Imeshindikana kupakia mapendeleo ya taarifa.');
  static String get categorySaveFailed =>
      _t('Unable to update the preference.', 'Imeshindikana kusasisha pendeleo.');
  static String get read => _t('Read', 'Imesomwa');
  static String get unread => _t('Unread', 'Haijasomwa');
  static String get all => _t('All', 'Zote');
  static String get medicalAndSafety => _t('Medical & Safety', 'Matibabu na Usalama');
  static String get bloodAndDonations => _t('Blood & Donations', 'Damu na Michango');
  static String get communityAndAcademy => _t('Community & Academy', 'Jamii na Chuo');
  static String get accountAndPlatform => _t('Account & Platform', 'Akaunti na Jukwaa');
  static String get notificationGroupHelp => _t(
      'Notifications are grouped by category. Open one to see related screens.',
      'Taarifa zimepangwa kwa kundi. Fungua moja kuona skrini zinazohusiana.');
  static String get emergencyAlwaysOn => _t('Always on', 'Imewashwa kila wakati');
  static String get emergencyLockedHelp => _t(
      'Emergency alerts can never be turned off.',
      'Tahadhari za dharura haziwezi kuzimwa.');
  static String get notificationsUnavailable => _t(
      'Notifications are unavailable right now.', 'Taarifa hazipatikani kwa sasa.');

  // ---------------------------------------------------------------- community
  static String get communityFeed => _t('Community', 'Jamii');
  static String get createPost => _t('Create Post', 'Tengeneza Chapisho');
  static String get postTitle => _t('Title (optional)', 'Kichwa (si lazima)');
  static String get postContent =>
      _t('Share something with the community', 'Shiriki kitu na jamii');
  static String get postCategory => _t('Category', 'Kundi');
  static String get postShareConsent => _t(
      'Do not share private medical details here. Community posts are visible '
          'to members and may be moderated.',
      'Usishiriki maelezo ya matibabu ya faragha hapa. Machapisho ya jamii '
          'yanaonekana kwa wanachama na yanaweza kusimamiwa.');
  static String get publishPost => _t('Publish', 'Chapisha');
  static String get postPublished => _t('Post published.', 'Chapisho limechapishwa.');
  static String get postSaveFailed =>
      _t('Unable to publish the post.', 'Imeshindikana kuchapisha chapisho.');
  static String get noPosts =>
      _t('No posts yet. Start the conversation.', 'Hakuna machapisho bado. Anzisha mazungumzo.');
  static String get communityLoadFailed =>
      _t('Unable to load community posts.', 'Imeshindikana kupakia machapisho ya jamii.');
  static String get allPosts => _t('All', 'Zote');
  static String get myPosts => _t('My Posts', 'Machapisho Yangu');
  static String get comments => _t('Comments', 'Maoni');
  static String get addComment => _t('Add a comment', 'Ongeza maoni');
  static String get commentHint =>
      _t('Write a supportive comment', 'Andika maoni ya kutia moyo');
  static String get commentPosted => _t('Comment added.', 'Maoni yameongezwa.');
  static String get commentFailed =>
      _t('Unable to add the comment.', 'Imeshindikana kuongeza maoni.');
  static String get noComments => _t('No comments yet.', 'Hakuna maoni bado.');
  static String get likePost => _t('Support', 'Saidia');
  static String get reportContent => _t('Report', 'Ripoti');
  static String get reportReason => _t('Reason for reporting', 'Sababu ya kuripoti');
  static String get reportReasonHint =>
      _t('Tell us why this content is a problem', 'Tuambie kwa nini maudhui haya yana tatizo');
  static String get reportSubmitted =>
      _t('Report submitted for review.', 'Ripoti imewasilishwa kwa ukaguzi.');
  static String get reportFailed =>
      _t('Unable to submit the report.', 'Imeshindikana kuwasilisha ripoti.');
  static String get reportDuplicate =>
      _t('You have already reported this content.', 'Umesharipoti maudhui haya.');
  static String get deletePost => _t('Delete post', 'Futa chapisho');
  static String get deletePostConfirm => _t(
      'Delete this post? This cannot be undone.',
      'Futa chapisho hili? Hili haliwezi kutenduliwa.');
  static String get postDeleted => _t('Post deleted.', 'Chapisho limefutwa.');
  static String get deleteFailed => _t('Unable to delete.', 'Imeshindikana kufuta.');
  static String get underReview => _t('Under review', 'Inakaguliwa');
  static String get authoredBy => _t('by', 'na');

  // -------------------------------------------------------------------- chat
  static String get messages => _t('Messages', 'Ujumbe');
  static String get noConversations => _t('No conversations yet.', 'Hakuna mazungumzo bado.');
  static String get conversationsLoadFailed =>
      _t('Unable to load conversations.', 'Imeshindikana kupakia mazungumzo.');
  static String get threadLoadFailed =>
      _t('Unable to load messages.', 'Imeshindikana kupakia ujumbe.');
  static String get privateDoctorChat =>
      _t('Private · verified professional', 'Faragha · mtaalamu aliyethibitishwa');
  static String get sendMessageHint => _t('Type a message', 'Andika ujumbe');
  static String get messageSendFailed =>
      _t('Unable to send the message.', 'Imeshindikana kutuma ujumbe.');
  static String get messageDeletedSelf =>
      _t('You deleted this message', 'Ulifuta ujumbe huu');
  static String get messageDeleted => _t('This message was deleted', 'Ujumbe huu ulifutwa');
  static String get leaveConversation => _t('Leave conversation', 'Ondoka kwenye mazungumzo');
  static String get leaveConversationConfirm => _t(
      'Leave this conversation? You will no longer see its messages.',
      'Ondoka kwenye mazungumzo haya? Hutaona ujumbe wake tena.');
  static String get conversationLeft =>
      _t('You left the conversation.', 'Umeondoka kwenye mazungumzo.');
  static String get leaveFailed =>
      _t('Unable to leave the conversation.', 'Imeshindikana kuondoka kwenye mazungumzo.');

  // ----------------------------------------------------- education / academy
  static String get education => _t('Education', 'Elimu');
  static String get bookmarks => _t('Bookmarks', 'Vialamisho');
  static String get searchEducation => _t('Search topics…', 'Tafuta mada…');
  static String get allCategories => _t('All', 'Zote');
  static String get noEducationContent =>
      _t('No articles here yet. Check back soon.', 'Hakuna makala hapa bado. Angalia tena hivi karibuni.');
  static String get educationLoadFailed => _t(
      'Unable to load the education library.',
      'Imeshindikana kupakia maktaba ya elimu.');
  static String get educationNotMedicalAdvice => _t(
      'Educational articles are general information, not a substitute for '
          'professional medical advice from your care team.',
      'Makala za elimu ni taarifa za jumla, si mbadala wa ushauri wa kitaalamu '
          'wa matibabu kutoka kwa timu yako ya afya.');
  static String get bookmarkedSaved => _t('Saved', 'Imehifadhiwa');
  static String get publishedOn => _t('By', 'Na');
  static String get noBookmarks => _t('No bookmarks yet.', 'Hakuna vialamisho bado.');
  static String get noBookmarksHint => _t(
      'Saved articles stay on this device for this session only.',
      'Makala zilizohifadhiwa zinabaki kwenye kifaa hiki kwa kipindi hiki pekee.');

  // --------------------------------------------------------- health constants
  static List<String> get triggerOptions => _sw
      ? const ['Baridi', 'Msongo wa mawazo', 'Uchovu', 'Maambukizi',
          'Upungufu wa maji', 'Mazoezi', 'Hedhi', 'Hakuna']
      : const ['Cold', 'Stress', 'Fatigue', 'Infection', 'Dehydration',
          'Exercise', 'Menstruation', 'None'];

  // ------------------------------------------------- patient home (FRONTEND-2)
  static String get homeSubtitle => _t('Stay strong, warrior', 'Kaa imara, shujaa');
  static String get dailyCheckin => _t('Daily Check-in', 'Ukaguzi wa Kila Siku');
  static String get checkinIntro => _t(
      'How are you feeling today? Logging symptoms helps you and your care '
          'team spot patterns early.',
      'Unajisikiaje leo? Kurekodi dalili kunakusaidia wewe na timu yako ya afya '
          'kubaini mifumo mapema.');
  static String get checkinAction =>
      _t("Log how I'm feeling", 'Rekodi ninavyojisikia');
  static String get lastRecorded => _t('Last recorded', 'Ilirekodiwa mwisho');
  static String get healthSnapshot => _t('Health Snapshot', 'Muhtasari wa Afya');
  static String get activeMedications =>
      _t('Active medications', 'Dawa zinazotumika');
  static String get dosesTodayTitle => _t('Doses today', 'Vipimo leo');
  static String get adherenceLast7Short => _t('Adherence (7 days)', 'Ufuataji (siku 7)');
  static String get symptomsRecorded =>
      _t('Symptoms recorded', 'Dalili zilizorekodiwa');
  static String get viewMedications => _t('Manage medications', 'Simamia dawa');
  static String get addFirstMedication => _t('Add medication', 'Ongeza dawa');
  static String get noDataRecorded =>
      _t('No data recorded yet.', 'Hakuna data iliyorekodiwa bado.');
  static String get upcomingAppointments =>
      _t('Upcoming appointments', 'Miadi inayokuja');
  static String get noAppointments => _t(
      'No upcoming appointments yet. Ask your care team to schedule a visit.',
      'Hakuna miadi inayokuja bado. Omba timu yako ya afya kupanga ziara.');
  static String get healthTrendTitle => _t('Health trend', 'Mwelekeo wa afya');
  static String get viewHealthInsights =>
      _t('View health insights', 'Ona ufahamu wa afya');
  static String get recentActivityTitle =>
      _t('Recent activity', 'Shughuli za hivi karibuni');
  static String get noRecentActivity => _t(
      'No health activity yet. Record a symptom to start your timeline.',
      'Hakuna shughuli za afya bado. Rekodi dalili kuanza mstari wako wa '
          'matukio.');
  static String get learnAndGrow => _t('Learn & grow', 'Jifunze na kua');
  static String get viewEducationLibrary => _t('View library', 'Ona maktaba');
  static String get alertsAndAttention => _t('Alerts', 'Tahadhari');
  static String get noActiveAlerts =>
      _t('No active alerts right now.', 'Hakuna tahadhari zinazoendelea kwa sasa.');
  static String get openBloodRequestTitle =>
      _t('Blood request in progress', 'Ombi la damu linaendelea');
  static String get activeBloodRequestBody => _t(
      'You have an open blood request awaiting donors. Review its status.',
      'Una ombi la damu lililo wazi linalosubiri watoa damu. Angalia hali yake.');
  static String get activeEmergencyTitle =>
      _t('Active emergency alert', 'Tahadhari ya dharura inayoendelea');
  static String get activeEmergencyBody => _t(
      'An emergency request is still active. Follow the tracking status.',
      'Ombi la dharura bado linaendelea. Fuata hali ya ufuatiliaji.');
  static String get youAreOffline => _t(
      'You appear to be offline. Showing the most recent information '
          'available.',
      'Inaonekana hauko mtandaoni. Inaonyesha taarifa za hivi karibuni '
          'zilizopo.');
  static String get inboxWithUnread =>
      _t('Unread notifications', 'Taarifa ambazo hazijasomwa');

  // ------------------------------------------- FRONTEND-3 — Tiba / records
  static String get tibaSubtitle => _t(
      'Your health at a glance — medications, tracking, timeline and records.',
      'Afya yako kwa muhtasari — dawa, ufuatiliaji, mstari wa matukio na '
          'kumbukumbu.');
  static String get tibaQuickActions => _t('Take action', 'Chukua hatua');
  static String get manageMedications => _t('Manage medications', 'Simamia dawa');
  static String get logSymptomShort => _t('Log symptom', 'Rekodi dalili');
  static String get reviewTimeline => _t('View timeline', 'Ona mstari wa matukio');
  static String get doctorMedications => _t('Medications', 'Dawa');
  static String get patient => _t('Patient', 'Mgonjwa');
  static String get noPatientsFound => _t(
      'No registered patients yet. Verify a prescriber profile to reach this '
          'surface.',
      'Hakuna wagonjwa waliosajiliwa bado. Thibitisha wasifu wa mtoa dawa '
          'kufikia eneo hili.');
  static String get healthRecords => _t('Health Records', 'Kumbukumbu za Afya');
  static String get noHealthRecords => _t('No health records yet.', 'Hakuna kumbukumbu za afya bado.');
  static String get carePlan => _t('Care plan', 'Mpango wa matibabu');
  static String get carePlanUnavailable => _t(
      'Care plans are set by your care team and shared under consent. '
          'Nothing has been shared yet.',
      'Mipango ya matibabu huwekwa na timu yako ya afya na kushirikiwa kwa '
          'ridhaa. Hakuna kilichoshirikiwa bado.');
  static String get healthHistory => _t('Health History', 'Historia ya Afya');
  static String get viewTimelineShort => _t('Timeline', 'Mstari wa matukio');
  static String get recordIssue => _t('Record issue', 'Rekodi tatizo');
  static String get upcomingVisits => _t('Upcoming visits', 'Ziara zinazokuja');

  // ------------------------------------------------------------ medical records
  static String get recordsSharedWithYou => _t(
      'Records shared with you by your care team appear here, protected by '
          'consent and access control.',
      'Kumbukumbu zilizoshirikiwa na timu yako ya afya zinaonekana hapa, '
          'zikilindwa kwa ridhaa na udhibiti wa ufikiaji.');
  static String get recordsEmptyTitle => _t('No records shared yet', 'Hakuna kumbukumbu zilizoshirikiwa bado');
  static String get recordsEmptyBody => _t(
      'Your care team adds records here when they share them with you. '
          'Nothing has been shared yet.',
      'Timu yako ya afya huongeza kumbukumbu hapa wanapokushirikisha. Hakuna '
          'kilichoshirikiwa bado.');
  static String get recordsPrivacy =>
      _t('Health records are never exposed without authorization.', 'Kumbukumbu za afya hazifichuliwi kamwe bila idhini.');

  // --------------------------------------------------------------- passwords
  static String get changePassword => _t('Change password', 'Badilisha nenosiri');
  static String get currentPassword => _t('Current password', 'Nenosiri la sasa');
  static String get newPassword => _t('New password', 'Nenosiri jipya');
  static String get confirmNewPassword => _t('Confirm new password', 'Thibitisha nenosiri jipya');
  static String get passwordsDoNotMatch => _t('Passwords do not match.', 'Manenosiri hayafanani.');
  static String get newPasswordHint => _t(
      'At least 8 characters and not too easy to guess.',
      'Angalau herufi 8 na si rahisi kukisia.');
  static String get passwordChanged => _t(
      'Password updated. All other sessions were signed out — please sign in '
          'again.',
      'Nenosiri limesasishwa. Vikao vingine vyote vimetolewa — tafadhali ingia '
          'tena.');
  static String get passwordChangeFailed =>
      _t('Unable to change the password.', 'Imeshindikana kubadilisha nenosiri.');
  static String get updatePassword => _t('Update password', 'Sasisha nenosiri');

  // ------------------------------------------------- security & privacy (Wasifu)
  static String get securityAndPrivacy => _t('Security & privacy', 'Usalama na faragha');
  static String get account => _t('Account', 'Akaunti');
  static String get consentAndPrivacy => _t('Consent & privacy', 'Ridhaa na faragha');
  static String get consentBody => _t(
      'Your health data is shared only when you consent. Access granted to '
          'professionals is shown in Emergency access and stays revocable.',
      'Data yako ya afya inashirikiwa tu unapokubali. Ufikiaji unaotolewa kwa '
          'wataalamu unaonekana kwenye Ufikiaji wa dharura na unaweza '
          'kuondolewa.');
  static String get sharedUnderConsent =>
      _t('Shared only with your consent', 'Inashirikiwa tu kwa ridhaa yako');
  static String get notificationPreferences =>
      _t('Notification preferences', 'Mapendeleo ya taarifa');
  static String get signOut => _t('Sign out', 'Toka');
  static String get signOutConfirm => _t(
      'Sign out of this device? You will need to sign in again.',
      'Toka kwenye kifaa hiki? Utahitaji kuingia tena.');
  static String get sessionOnThisDevice =>
      _t('Signed in on this device', 'Umeingia kwenye kifaa hiki');
  static String get roleWorkspace => _t('Role workspace', 'Eneo la jukumu');
  static String get roleWorkspaceHeading => _t('Your role is active', 'Jukumu lako linaendelea');
  static String get roleWorkspaceBody => _t(
      'This account has a role that has no dedicated experience in this app '
          'version yet. Your granted permissions below are enforced by the '
          'backend; more surfaces will arrive with future updates.',
      'Akaunti hii ina jukumu ambalo halina uzoefu maalum katika toleo hili la '
          'app bado. Ruhusa zako zilizotolewa hapa chini zinatekelezwa na '
          'backend; skrini zaidi zitakuja katika masasisho yajayo.');
  static String get roleGranted =>
      _t('Granted by your organization', 'Imetolewa na taasisi yako');
  static String get roleWorkspacePermissions =>
      _t('Granted permissions', 'Ruhusa zilizotolewa');
  static String get noPermissionsGranted =>
      _t('No permissions granted yet.', 'Hakuna ruhusa zilizotolewa bado.');

  // --------------------------------------------------------------- doctor role
  static String get doctorDirectoryTitle =>
      _t('Verified care directory', 'Orodha ya huduma zilizothibitishwa');
  static String get doctorDirectoryEmpty => _t(
      'No verified doctors are discoverable yet. The directory opens as '
          'facilities verify their care teams.',
      'Hakuna madaktari waliothibitishwa wanaopatikana bado. Orodha inafunguka '
          'vituo vinapothibitisha timu zao za afya.');
  static String get doctorDirectoryBody => _t(
      'No doctor profiles are shown to avoid exposing unverified care '
          'providers. When verified, you can search by specialty and location. '
          'Use Messages to reach your care team today.',
      'Hakuna wasifu wa madaktari unaoonyeshwa ili kuepuka kuweka hadharani '
          'watoa huduma ambao hawajathibitishwa. Wanapothibitishwa, unaweza '
          'kutafuta kwa taaluma na eneo. Tumia Ujumbe kufikia timu yako ya afya '
          'leo.');
  static String get reachCareTeam =>
      _t('Message your care team', 'Tuma ujumbe kwa timu yako ya afya');

  // -------------------------------------------------------------- doctor shell
  static String get doctorHome => _t('Doctor Home', 'Nyumbani kwa Daktari');
  static String get todayAppointments => _t("Today's appointments", 'Miadi ya leo');
  static String get noAppointmentsToday => _t('No appointments today.', 'Hakuna miadi leo.');
  static String get pendingRequests => _t('Pending requests', 'Maombi yanayosubiri');
  static String get noPendingRequests => _t('No pending requests.', 'Hakuna maombi yanayosubiri.');
  static String get patientCommunication => _t('Patient communication', 'Mawasiliano na mgonjwa');
  static String get recentPatientActivity =>
      _t('Recent patient activity', 'Shughuli za mgonjwa za hivi karibuni');
  static String get noAuthorizedActivity => _t(
      'Nothing to show. Authorized patient activity appears here when your '
          'care team shares records with you.',
      'Hakuna cha kuonyesha. Shughuli za mgonjwa zilizoruhusiwa zinaonekana '
          'hapa timu yako ya afya inaposhiriki kumbukumbu nawe.');
  static String get doctorTasks => _t('Tasks', 'Kazi');
  static String get noTasks => _t('No tasks assigned.', 'Hakuna kazi zilizopewa.');
  static String get patientsSection => _t('Patients', 'Wagonjwa');
  static String get patientsUnavailable => _t(
      'Authorized patient details appear once your facility connects and '
          'patients consent to share records with you.',
      'Maelezo ya wagonjwa yaliyoruhusiwa yanaonekana kituo chako '
          'kinapounganishwa na wagonjwa wanapokubali kushiriki kumbukumbu nawe.');
  static String get doctorOnlyAuthorized => _t(
      'You can only see what the backend authorizes for your role.',
      'Unaweza kuona tu kile backend inaruhusu kwa jukumu lako.');

  // ------------------------------------------------------------ blood donor role
  static String get donorHome => _t('Donor Home', 'Nyumbani kwa Mtoa Damu');
  static String get myDonorProfile => _t('My donor profile', 'Wasifu wangu wa mtoa damu');
  static String get donorEligibilityNote => _t(
      'Eligibility is confirmed at the donation center on the day.',
      'Ustahiki unathibitishwa kwenye kituo cha kuchangia siku hiyo.');
  static String get openBloodRequests => _t('Open blood requests', 'Maombi ya damu yaliyo wazi');
  static String get noOpenRequests =>
      _t('No open blood requests right now.', 'Hakuna maombi ya damu yaliyo wazi kwa sasa.');
  static String get availabilityNote => _t(
      'The network only matches you against requests when you are available.',
      'Mtandao unakulinganisha na maombi tu unapopatikana.');
  static String get donationEvents => _t('Donations', 'Michango');
  static String get noDonationEvents =>
      _t('No donations recorded yet.', 'Hakuna michango iliyorekodiwa bado.');

  // --------------------------------------------------------------- caregiver role
  static String get caregiverHome => _t('Caregiver Home', 'Nyumbani kwa Mlezi');
  static String get linkedPatients => _t('Linked patients', 'Wagonjwa waliounganishwa');
  static String get noLinkedPatients => _t(
      'No linked patients yet. A patient (or their care team) must authorize '
          'your caregiver access first.',
      'Hakuna wagonjwa waliounganishwa bado. Mgonjwa (au timu yake ya afya) '
          'lazima aruhusu ufikiaji wako wa mlezi kwanza.');
  static String get caregiverOnlyAuthorized => _t(
      'You only ever see what the patient authorized you to see.',
      'Unaona tu kile mgonjwa alikuruhusu kuona.');
  static String get caregiverHealthUpdates => _t('Health updates', 'Masasisho ya afya');
  static String get noHealthUpdates => _t(
      'Authorized health updates will appear here once a patient links you.',
      'Masasisho ya afya yaliyoruhusiwa yataonekana hapa mgonjwa '
          'anapokuunganisha.');
  static String get caregiverCommunication => _t('Communication', 'Mawasiliano');
  static String get medicationReminderAccess => _t(
      'Medication reminders appear only for authorized linked patients.',
      'Vikumbusho vya dawa vinaonekana tu kwa wagonjwa waliounganishwa '
          'walioruhusiwa.');

  // --------------------------------------------------- community post editing
  static String get editPost => _t('Edit post', 'Hariri chapisho');
  static String get updatePost => _t('Save changes', 'Hifadhi mabadiliko');
  static String get postUpdated => _t('Post updated.', 'Chapisho limesasishwa.');
  static String get postEditFailed =>
      _t('Unable to update the post.', 'Imeshindikana kusasisha chapisho.');
  static String get editOwnPostsOnly =>
      _t('You can edit posts you wrote.', 'Unaweza kuhariri machapisho uliyoandika.');
}
