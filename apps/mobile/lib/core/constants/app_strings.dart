class AppStrings {
  AppStrings._();

  static const String appName = 'Sickler\'s Warriors';
  static const String appTagline = 'Strength Together, Fight Together';

  // Auth
  static const String login = 'Login';
  static const String register = 'Register';
  static const String logout = 'Logout';
  static const String email = 'Email';
  static const String password = 'Password';
  static const String phoneNumber = 'Phone Number';
  static const String forgottenPassword = 'Forgot password?';
  static const String loginFailed = 'Unable to sign in. Check your details.';
  static const String dontHaveAccount = 'Don\'t have an account? ';
  static const String alreadyHaveAccount = 'Already have an account? ';

  // Profile / Medical identity (Stage 4.5)
  static const String profile = 'Profile';
  static const String save = 'Save';
  static const String cancel = 'Cancel';
  static const String saved = 'Saved';
  static const String saving = 'Saving…';
  static const String loadingProfile = 'Loading profile…';
  static const String profileLoadFailed = 'Unable to load your profile.';
  static const String editProfile = 'Edit Profile';
  static const String dateOfBirth = 'Date of birth';
  static const String gender = 'Gender';
  static const String genotype = 'Genotype';
  static const String diagnosisDate = 'Diagnosis date';
  static const String primaryDiagnosis = 'Primary diagnosis';
  static const String emergencyContactName = 'Emergency contact name';
  static const String emergencyContactPhone = 'Emergency contact phone';
  static const String emergencyContactRelation = 'Emergency contact relation';
  static const String addressRegion = 'Address region';
  static const String addressCity = 'Address city';
  static const String notes = 'Notes';
  static const String privateNote =
      'Private — visible only to you and authorised care providers.';
  static const String medicalIdentity =
      'Medical identity and emergency contact details. Private and consent '
      'protected.';
  static const String identity = 'Identity';

  // Home / Navigation
  static const String home = 'Home';
  static const String emergency = 'Emergency';
  static const String community = 'Community';
  static const String notifications = 'Notifications';
  static const String settings = 'Settings';

  // Primary patient navigation (FRONTEND-1) — approved Swahili labels.
  static const String navHome = 'Nyumbani';
  static const String navDoctor = 'Daktari';
  static const String navTreatment = 'Tiba';
  static const String navDonate = 'Changia';
  static const String navProfile = 'Wasifu';

  // Shell / hubs
  static const String doctor = 'Doctor';
  static const String treatment = 'Treatment';
  static const String donate = 'Donate';
  static const String contributions = 'Contributions';
  static const String greeting = 'Habari';
  static const String explore = 'Explore';
  static const String quickActions = 'Quick Actions';
  static const String comingSoon = 'Coming soon';
  static const String viewAll = 'View all';

  // Navigation destinations (post-auth shell)
  static const String health = 'Health';
  static const String blood = 'Blood';
  static const String more = 'More';
  static const String sos = 'SOS';
  static const String medicalProfile = 'Medical Profile';
  static const String medicalRecords = 'Health Records';
  static const String medicationReminders = 'Medication Reminders';
  static const String clinicCalendar = 'Clinic Calendar';

  // Blood & Donations
  static const String bloodDonation = 'Blood Donation';
  static const String financialDonations = 'Financial Donations';

  // Financial Donations (Stage 4.12)
  static const String donations = 'Donations';
  static const String campaigns = 'Campaigns';
  static const String verifiedCampaigns = 'Verified Campaigns';
  static const String donateNow = 'Donate now';
  static const String donates = 'donated';
  static const String goalOf = 'of';
  static const String raisedSoFar = 'Raised so far';
  static const String campaignOwner = 'Campaign owner';
  static const String noCampaigns =
      'No verified campaigns yet. Check back soon.';
  static const String campaignsLoadFailed =
      'Unable to load campaigns. Check your connection and try again.';
  static const String donationsLoadFailed =
      'Unable to load your donation history.';
  static const String donationInitiated = 'Donation initiated';
  static const String donationInitiatedBody =
      'Your payment is pending provider confirmation. The donation will be '
      'recorded as confirmed only after the payment provider verifies it.';
  static const String paymentConfirmed = 'Payment confirmed';
  static const String paymentFailed = 'Payment failed';
  static const String retryingDonation = 'Checking payment status…';
  static const String donationUpdated = 'Donation status updated.';
  static const String donationActionFailed = 'Unable to update the donation.';
  static const String retryDonation = 'Retry payment';
  static const String donationAmount = 'Donation amount (TZS)';
  static const String donationAmountError = 'Enter an amount to donate.';
  static const String paymentMethod = 'Payment method';
  static const String shareDonationRef = 'I consent to share my donation reference.';
  static const String confirmDonation = 'Confirm donation';
  static const String donationsHistory = 'Donation history';
  static const String noDonations = 'No donations yet. Support a campaign above.';
  static const String receiptTitle = 'Donation receipt';
  static const String receiptNumber = 'Receipt number';
  static const String receiptFor = 'Campaign';
  static const String receiptAmount = 'Amount';
  static const String receiptDate = 'Donated on';
  static const String transactionRef = 'Transaction';
  static const String receiptNotAvailable =
      'Receipts are available once the payment is confirmed.';
  static const String checkStatus = 'Check status';
  static const String payoutPending = 'Pending';
  static const String donationConfirmed = 'Confirmed';
  static const String donationRefused = 'Failed';
  static const String providerRefLabel = 'Reference';
  static const String retryOnlyPendingOrFailed =
      'Payments can only be retried while pending or failed.';

  // Doctor Network
  static const String doctorNetwork = 'Doctor Network';
  static const String verifiedDoctors = 'Verified Doctors';

  // Emergency
  static const String emergencySupport = 'Emergency Support';

  // AI
  static const String aiAssistant = 'AI Assistant';

  // Admin
  static const String adminPanel = 'Admin Panel';

  // Shared async state
  static const String retry = 'Retry';
  static const String close = 'Close';
  static const String notSignedIn =
      'Sign in to manage your medications and health tracking.';

  // Medication (Stage 4.6)
  static const String medications = 'Medications';
  static const String noMedications =
      'No medications yet. Add your first medication to start tracking.';
  static const String addMedication = 'Add Medication';
  static const String editMedication = 'Edit Medication';
  static const String medicationName = 'Medication name';
  static const String medicationNameHint = 'e.g. Hydroxyurea';
  static const String genericName = 'Generic name';
  static const String strength = 'Strength';
  static const String strengthHint = 'e.g. 500 mg';
  static const String dosage = 'Dosage';
  static const String dosageHint = 'e.g. 1 tablet twice daily';
  static const String route = 'Route';
  static const String frequency = 'Frequency';
  static const String frequencyHint = 'e.g. daily, twice a day';
  static const String startDate = 'Start date';
  static const String endDate = 'End date (optional)';
  static const String stopMedication = 'Stop medication';
  static const String stopMedicationConfirm =
      'Stop this medication? It will be hidden from your active list.';
  static const String active = 'Active';
  static const String stopped = 'Stopped';
  static const String startDateAfterEnd = 'Start date must be on or before end date.';
  static const String medicationSaveFailed = 'Unable to save the medication.';
  static const String medicationLoadFailed = 'Unable to load your medications.';

  // Schedules
  static const String schedules = 'Schedule';
  static const String addSchedule = 'Add schedule';
  static const String removeSchedule = 'Remove schedule';
  static const String scheduleTime = 'Dose time';
  static const String scheduleDays = 'Days of week';
  static const String scheduleNotes = 'Schedule notes';
  static const String noSchedules = 'No schedules yet. Add one to track dose times.';
  static const String scheduleSaved = 'Schedule saved.';
  static const String scheduleRemoved = 'Schedule removed.';
  static const String scheduleTimeHint = 'Select time';
  static const String today = 'Today';

  // Dose logging
  static const String logDose = 'Log dose';
  static const String doseTaken = 'Taken';
  static const String doseMissed = 'Missed';
  static const String doseSkipped = 'Skipped';
  static const String doseSnoozed = 'Snoozed';
  static const String doseLogged = 'Dose recorded.';
  static const String doseLogFailed = 'Unable to record the dose.';
  static const String doseHistory = 'Dose history';
  static const String noDoseHistory = 'No doses recorded yet.';
  static const String recordDose = 'Record dose';

  // Stats / adherence
  static const String adherence = 'Adherence';
  static const String adherenceHelp =
      'Adherence is a monitoring aid — always follow your care plan.';
  static const String adherenceLastSeven = 'Adherence (last 7 days)';
  static const String expectedDoses = 'Expected doses';
  static const String takenDoses = 'Taken';
  static const String pendingDoses = 'Pending';
  static const String statsLoadFailed = 'Unable to load your adherence stats.';

  // Health tracking (Stage 4.6)
  static const String healthTracking = 'Health Tracking';
  static const String dashboardLoadFailed = 'Unable to load your health dashboard.';
  static const String symptoms = 'Symptoms';
  static const String recordSymptom = 'Record Symptom';
  static const String logSymptom = 'Log Symptom';
  static const String noSymptoms = 'No symptoms recorded yet.';
  static const String symptomType = 'Symptom';
  static const String painLevel = 'Pain level';
  static const String painScale = 'Pain level (0 = none, 10 = worst)';
  static const String triggers = 'Triggers';
  static const String durationMinutes = 'Duration (minutes)';
  static const String recordedAt = 'Recorded at';
  static const String symptomSaveFailed = 'Unable to record the symptom.';
  static const String symptomSaved = 'Symptom recorded.';
  static const String painCrisisTitle = 'Painful crisis';
  static const String crisisHelp =
      'If this is a painful crisis, follow the care plan set with your doctor.';
  static const String timeline = 'Timeline';
  static const String timelineLoadFailed = 'Unable to load your health timeline.';
  static const String viewTimeline = 'View Timeline';
  static const String noTimelineEdits = 'No health activity yet.';

  // Blood network (Stage 4.8)
  static const String bloodRequests = 'Blood Requests';
  static const String newBloodRequest = 'New Blood Request';
  static const String requestBlood = 'Request Blood';
  static const String bloodGroupNeeded = 'Blood group needed';
  static const String unitsNeeded = 'Units needed';
  static const String urgency = 'Urgency';
  static const String reasonForRequest = 'Reason (optional)';
  static const String requestLocation = 'Location (optional)';
  static const String facilityUidHint = 'Verified facility UID (optional)';
  static const String noBloodRequests =
      'No blood requests yet. Create one if you or a warrior needs blood.';
  static const String bloodLoadFailed = 'Unable to load blood requests.';
  static const String bloodSaveFailed = 'Unable to submit the blood request.';
  static const String bloodRequestCreated = 'Blood request submitted for verification.';
  static const String cancelRequest = 'Cancel request';
  static const String cancelRequestConfirm =
      'Cancel this blood request? This cannot be undone.';
  static const String requestCancelled = 'Blood request cancelled.';
  static const String matches = 'Matches';
  static const String noMatches = 'No donor matches yet.';
  static const String matchScore = 'Match score';
  static const String accept = 'Accept';
  static const String decline = 'Decline';
  static const String matchResponded = 'Match response recorded.';
  static const String matchRespondFailed = 'Unable to respond to the match.';
  static const String donorProfile = 'Donor Profile';
  static const String becomeDonor = 'Become a donor';
  static const String donorProfileHelp =
      'Your contact details stay private. Only blood group, region, city, '
      'availability and donation history are shared (BR-006).';
  static const String bloodGroup = 'Blood group';
  static const String region = 'Region';
  static const String city = 'City';
  static const String availableToDonate = 'Available to donate';
  static const String donorVerified = 'Verified donor';
  static const String donorSaved = 'Donor profile saved.';
  static const String donorSaveFailed = 'Unable to save your donor profile.';
  static const String donationHistory = 'Donations';

  // Emergency (Stage 4.8)
  static const String emergencyHome = 'Emergency';
  static const String triggerEmergency = 'Trigger Emergency';
  static const String emergencyType = 'Emergency type';
  static const String emergencySeverity = 'Severity';
  static const String describeEmergency = 'Describe what is happening (optional)';
  static const String submitEmergency = 'Send Emergency Alert';
  static const String emergencyCreated = 'Emergency alert sent. Help is on the way.';
  static const String emergencyCreateFailed = 'Unable to send the emergency alert.';
  static const String activeEmergencies = 'Active emergencies';
  static const String noEmergencies = 'No emergency requests.';
  static const String emergencyLoadFailed = 'Unable to load emergency requests.';
  static const String respondEmergency = 'Respond';
  static const String validateEmergency = 'Validate';
  static const String escalateEmergency = 'Escalate';
  static const String resolveEmergency = 'Resolve';
  static const String cancelEmergency = 'Cancel';
  static const String emergencyUpdated = 'Emergency request updated.';
  static const String emergencyActionFailed = 'Unable to update the emergency request.';
  static const String emergencyCallNote =
      'For immediate danger, also call your local emergency number.';

  // Emergency SOS flow (Stage 4.9)
  static const String sosHoldToArm = 'Press and hold to arm SOS';
  static const String sosArmed = 'SOS armed';
  static const String sosConfirmTitle = 'Confirm emergency';
  static const String sosConfirmBody =
      'This raises an emergency alert to responders. It is NOT a replacement '
      'for emergency services.';
  static const String sosCallInstruction =
      'If you are in immediate danger, call your local emergency number (112) '
      'or the nearest facility now.';
  static const String sosShareConsent =
      'Share my emergency profile (contact, location, notes) with responders.';
  static const String sosConsentRequired = 'Consent is required to send an alert.';
  static const String sosLocationLabel = 'Where are you? (optional)';
  static const String sosNotSentCallNow =
      'Alert not sent. Call emergency services or the nearest facility now.';
  static const String sosRateLimited =
      'You have raised several alerts recently. Call emergency services now.';
  static const String emergencyPrefill = 'Using your emergency contact';
  static const String trackingTitle = 'Emergency status';
  static const String trackingTimeline = 'Status progress';
  static const String trackingResponders = 'Responders';
  static const String trackingNoResponders = 'No responder has acknowledged yet.';
  static const String trackingLocation = 'Location';
  static const String trackingResolvedTitle = 'Emergency resolved';
  static const String trackingResolvedBody =
      'Your emergency request is resolved. If symptoms return, raise a new '
      'alert or call emergency services.';
  static const String accessStatus = 'Emergency access';
  static const String accessGrantedUntil = 'Professional access granted until';
  static const String accessNone = 'No professional has emergency access.';
  static const String callEmergencyServices = 'Call emergency services';

  // Notifications (Stage 4.8)
  static const String inbox = 'Inbox';
  static const String preferences = 'Preferences';
  static const String markAllRead = 'Mark all read';
  static const String notificationsAllRead = 'All notifications marked read.';
  static const String noNotifications = 'No notifications yet.';
  static const String notificationsLoadFailed = 'Unable to load your notifications.';
  static const String notificationsReadFailed = 'Unable to update notifications.';
  static const String categoriesLoadFailed = 'Unable to load notification preferences.';
  static const String categorySaveFailed = 'Unable to update the preference.';
  static const String read = 'Read';

  // Notification center (Stage 4.13)
  static const String unread = 'Unread';
  static const String all = 'All';
  static const String medicalAndSafety = 'Medical & Safety';
  static const String bloodAndDonations = 'Blood & Donations';
  static const String communityAndAcademy = 'Community & Academy';
  static const String accountAndPlatform = 'Account & Platform';
  static const String notificationGroupHelp =
      'Notifications are grouped by category. Open one to see related screens.';
  static const String emergencyAlwaysOn = 'Always on';
  static const String emergencyLockedHelp =
      'Emergency alerts can never be turned off.';
  static const String notificationsUnavailable =
      'Notifications are unavailable right now.';

  // Community (Stage 4.10)
  static const String communityFeed = 'Community';
  static const String createPost = 'Create Post';
  static const String postTitle = 'Title (optional)';
  static const String postContent = 'Share something with the community';
  static const String postCategory = 'Category';
  static const String postShareConsent =
      'Do not share private medical details here. Community posts are visible '
      'to members and may be moderated.';
  static const String publishPost = 'Publish';
  static const String postPublished = 'Post published.';
  static const String postSaveFailed = 'Unable to publish the post.';
  static const String noPosts = 'No posts yet. Start the conversation.';
  static const String communityLoadFailed = 'Unable to load community posts.';
  static const String allPosts = 'All';
  static const String myPosts = 'My Posts';
  static const String comments = 'Comments';
  static const String addComment = 'Add a comment';
  static const String commentHint = 'Write a supportive comment';
  static const String commentPosted = 'Comment added.';
  static const String commentFailed = 'Unable to add the comment.';
  static const String noComments = 'No comments yet.';
  static const String likePost = 'Support';
  static const String reportContent = 'Report';
  static const String reportReason = 'Reason for reporting';
  static const String reportReasonHint = 'Tell us why this content is a problem';
  static const String reportSubmitted = 'Report submitted for review.';
  static const String reportFailed = 'Unable to submit the report.';
  static const String reportDuplicate = 'You have already reported this content.';
  static const String deletePost = 'Delete post';
  static const String deletePostConfirm = 'Delete this post? This cannot be undone.';
  static const String postDeleted = 'Post deleted.';
  static const String deleteFailed = 'Unable to delete.';
  static const String underReview = 'Under review';
  static const String authoredBy = 'by';

  // Chat (Stage 4.10)
  static const String messages = 'Messages';
  static const String noConversations = 'No conversations yet.';
  static const String conversationsLoadFailed = 'Unable to load conversations.';
  static const String threadLoadFailed = 'Unable to load messages.';
  static const String privateDoctorChat = 'Private · verified professional';
  static const String sendMessageHint = 'Type a message';
  static const String messageSendFailed = 'Unable to send the message.';
  static const String messageDeletedSelf = 'You deleted this message';
  static const String messageDeleted = 'This message was deleted';
  static const String leaveConversation = 'Leave conversation';
  static const String leaveConversationConfirm =
      'Leave this conversation? You will no longer see its messages.';
  static const String conversationLeft = 'You left the conversation.';
  static const String leaveFailed = 'Unable to leave the conversation.';

  // Education / Warrior Academy (Stage 4.11)
  static const String education = 'Education';
  static const String bookmarks = 'Bookmarks';
  static const String searchEducation = 'Search topics…';
  static const String allCategories = 'All';
  static const String noEducationContent = 'No articles here yet. Check back soon.';
  static const String educationLoadFailed = 'Unable to load the education library.';
  static const String educationNotMedicalAdvice =
      'Educational articles are general information, not a substitute for '
      'professional medical advice from your care team.';
  static const String bookmarkedSaved = 'Saved';
  static const String publishedOn = 'By';
  static const String noBookmarks = 'No bookmarks yet.';
  static const String noBookmarksHint =
      'Saved articles stay on this device for this session only.';

  // Health constants
  static const List<String> triggerOptions = [
    'Cold',
    'Stress',
    'Fatigue',
    'Infection',
    'Dehydration',
    'Exercise',
    'Menstruation',
    'None',
  ];

  // Patient Home dashboard (FRONTEND-2)
  static const String homeSubtitle = 'Stay strong, warrior';
  static const String dailyCheckin = 'Daily Check-in';
  static const String checkinIntro =
      'How are you feeling today? Logging symptoms helps you and your care '
      'team spot patterns early.';
  static const String checkinAction = 'Log how I\'m feeling';
  static const String lastRecorded = 'Last recorded';
  static const String healthSnapshot = 'Health Snapshot';
  static const String activeMedications = 'Active medications';
  static const String dosesTodayTitle = 'Doses today';
  static const String adherenceLast7Short = 'Adherence (7 days)';
  static const String symptomsRecorded = 'Symptoms recorded';
  static const String viewMedications = 'Manage medications';
  static const String addFirstMedication = 'Add medication';
  static const String noDataRecorded = 'No data recorded yet.';
  static const String upcomingAppointments = 'Upcoming appointments';
  static const String noAppointments =
      'No upcoming appointments yet. Ask your care team to schedule a visit.';
  static const String healthTrendTitle = 'Health trend';
  static const String viewHealthInsights = 'View health insights';
  static const String recentActivityTitle = 'Recent activity';
  static const String noRecentActivity =
      'No health activity yet. Record a symptom to start your timeline.';
  static const String learnAndGrow = 'Learn & grow';
  static const String viewEducationLibrary = 'View library';
  static const String alertsAndAttention = 'Alerts';
  static const String noActiveAlerts = 'No active alerts right now.';
  static const String openBloodRequestTitle = 'Blood request in progress';
  static const String activeBloodRequestBody =
      'You have an open blood request awaiting donors. Review its status.';
  static const String activeEmergencyTitle = 'Active emergency alert';
  static const String activeEmergencyBody =
      'An emergency request is still active. Follow the tracking status.';
  static const String youAreOffline =
      'You appear to be offline. Showing the most recent information '
      'available.';
  static const String inboxWithUnread = 'Unread notifications';

  // FRONTEND-3 — Tiba landing, records, security, roles.

  // Tiba landing
  static const String tibaSubtitle =
      'Your health at a glance — medications, tracking, timeline and records.';
  static const String tibaQuickActions = 'Take action';
  static const String manageMedications = 'Manage medications';
  static const String logSymptomShort = 'Log symptom';
  static const String reviewTimeline = 'View timeline';
  static const String healthRecords = 'Health Records';
  static const String noHealthRecords = 'No health records yet.';
  static const String carePlan = 'Care plan';
  static const String carePlanUnavailable =
      'Care plans are set by your care team and shared under consent. '
      'Nothing has been shared yet.';
  static const String healthHistory = 'Health History';
  static const String viewTimelineShort = 'Timeline';
  static const String recordIssue = 'Record issue';
  static const String upcomingVisits = 'Upcoming visits';

  // Medical Records (honest state — records arrive from the care team)
  static const String recordsSharedWithYou =
      'Records shared with you by your care team appear here, protected by '
      'consent and access control.';
  static const String recordsEmptyTitle = 'No records shared yet';
  static const String recordsEmptyBody =
      'Your care team adds records here when they share them with you. '
      'Nothing has been shared yet.';
  static const String recordsPrivacy =
      'Health records are never exposed without authorization.';

  // Change password
  static const String changePassword = 'Change password';
  static const String currentPassword = 'Current password';
  static const String newPassword = 'New password';
  static const String confirmNewPassword = 'Confirm new password';
  static const String passwordsDoNotMatch = 'Passwords do not match.';
  static const String newPasswordHint =
      'At least 8 characters and not too easy to guess.';
  static const String passwordChanged =
      'Password updated. All other sessions were signed out — please sign in '
      'again.';
  static const String passwordChangeFailed = 'Unable to change the password.';
  static const String updatePassword = 'Update password';

  // Security & privacy (Wasifu)
  static const String securityAndPrivacy = 'Security & privacy';
  static const String account = 'Account';
  static const String consentAndPrivacy = 'Consent & privacy';
  static const String consentBody =
      'Your health data is shared only when you consent. Access granted to '
      'professionals is shown in Emergency access and stays revocable.';
  static const String sharedUnderConsent =
      'Shared only with your consent';
  static const String notificationPreferences = 'Notification preferences';
  static const String signOut = 'Sign out';
  static const String signOutConfirm =
      'Sign out of this device? You will need to sign in again.';
  static const String sessionOnThisDevice = 'Signed in on this device';

  // Doctor role (doctor directory unavailable yet — honest state)
  static const String doctorDirectoryTitle = 'Verified care directory';
  static const String doctorDirectoryEmpty =
      'No verified doctors are discoverable yet. The directory opens as '
      'facilities verify their care teams.';
  static const String doctorDirectoryBody =
      'No doctor profiles are shown to avoid exposing unverified care '
      'providers. When verified, you can search by specialty and location. '
      'Use Messages to reach your care team today.';
  static const String reachCareTeam = 'Message your care team';

  // Doctor Shell
  static const String doctorHome = 'Doctor Home';
  static const String todayAppointments = 'Today\'s appointments';
  static const String noAppointmentsToday = 'No appointments today.';
  static const String pendingRequests = 'Pending requests';
  static const String noPendingRequests = 'No pending requests.';
  static const String patientCommunication = 'Patient communication';
  static const String recentPatientActivity = 'Recent patient activity';
  static const String noAuthorizedActivity =
      'Nothing to show. Authorized patient activity appears here when your '
      'care team shares records with you.';
  static const String doctorTasks = 'Tasks';
  static const String noTasks = 'No tasks assigned.';
  static const String patientsSection = 'Patients';
  static const String patientsUnavailable =
      'Authorized patient details appear once your facility connects and '
      'patients consent to share records with you.';
  static const String doctorOnlyAuthorized =
      'You can only see what the backend authorizes for your role.';

  // Blood donor role
  static const String donorHome = 'Donor Home';
  static const String myDonorProfile = 'My donor profile';
  static const String donorEligibilityNote =
      'Eligibility is confirmed at the donation center on the day.';
  static const String openBloodRequests = 'Open blood requests';
  static const String noOpenRequests = 'No open blood requests right now.';
  static const String availabilityNote =
      'The network only matches you against requests when you are available.';
  static const String donationEvents = 'Donations';
  static const String noDonationEvents = 'No donations recorded yet.';

  // Caregiver role
  static const String caregiverHome = 'Caregiver Home';
  static const String linkedPatients = 'Linked patients';
  static const String noLinkedPatients =
      'No linked patients yet. A patient (or their care team) must authorize '
      'your caregiver access first.';
  static const String caregiverOnlyAuthorized =
      'You only ever see what the patient authorized you to see.';
  static const String caregiverHealthUpdates = 'Health updates';
  static const String noHealthUpdates =
      'Authorized health updates will appear here once a patient links you.';
  static const String caregiverCommunication = 'Communication';
  static const String medicationReminderAccess =
      'Medication reminders appear only for authorized linked patients.';

  // Community post editing (own posts)
  static const String editPost = 'Edit post';
  static const String updatePost = 'Save changes';
  static const String postUpdated = 'Post updated.';
  static const String postEditFailed = 'Unable to update the post.';
  static const String editOwnPostsOnly = 'You can edit posts you wrote.';
}
