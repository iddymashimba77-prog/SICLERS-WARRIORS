# Sickler's Warriors — Mobile App

Flutter (Android + iOS) application for the Sickler's Warriors platform — a
sickle cell community, medical management and emergency support system.

## Structure

```
lib/
├── app.dart                  # Root widget (MaterialApp + routes)
├── main.dart                 # Entry point
├── core/
│   ├── constants/            # AppStrings, AppColors
│   ├── theme/                # AppTheme (light / dark)
│   ├── router/               # Navigation configuration
│   ├── network/              # API client
│   └── utils/                # Helpers
├── features/
│   ├── auth/                 # Login / registration
│   ├── profile/              # User profile
│   ├── medical/              # Medical profile & health records
│   ├── medication/           # Medication reminders
│   ├── clinic/               # Clinic calendar
│   ├── blood_donation/       # Blood donation network
│   ├── emergency/            # SOS / emergency support
│   ├── doctor_network/       # Verified doctor directory & chat
│   ├── community/            # Warrior community
│   ├── donations/            # Financial donations
│   ├── notifications/        # Push notifications
│   ├── ai_assistant/         # AI / intelligence layer
│   └── admin/                # Admin integration
└── shared/
    └── widgets/              # Reusable UI widgets
```

## Development

```bash
flutter pub get
flutter run
flutter test
flutter analyze
```