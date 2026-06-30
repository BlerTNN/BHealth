# BHealth

BHealth is a personal iOS health assistant focused on daily calorie awareness. It combines AI-assisted meal logging, local meal history, Apple Health/Fitness data, and a clean dashboard for tracking intake, burn, and calorie balance.

The app is designed around three main tabs:

- **Overview**: daily remaining calories, weekly trends, yearly calendar, and meal history.
- **AI Assistant**: natural-language meal logging and general health coaching.
- **Me**: profile, target data, language settings, Apple Health sync, and DeepSeek API key management.

## Features

### AI Meal Logging

BHealth lets you describe meals in natural language, for example:

- "Lunch: a bowl of millet porridge and an egg."
- "I ate lu zhu huo shao last night."
- "Backfill June 20 dinner: salmon, rice, and vegetables."

The AI assistant can:

- Understand food descriptions in context.
- Ask follow-up questions for missing meal type, date, or portion details.
- Estimate rough calories with a likely range.
- Confirm date, meal type, food items, and calories before saving.
- Save confirmed meal records locally.
- Support both today's logging and historical backfill through the same **Log Food** flow.

### Health Coach

The health coach mode provides general wellness and nutrition guidance based on local app context, including:

- Recent calorie intake and burn trends.
- Rough calorie deficit or surplus interpretation.
- Lightweight weight-change estimates.
- Diet and exercise suggestions.

Health coach responses are informational and do not create meal records.

### Dashboard

The Overview tab shows:

- Today's calorie balance.
- Intake, active burn, basal burn, and total burn.
- A default 7-day trend.
- A yearly calendar view with daily calorie balance summaries.
- Day-level detail views.
- Confirmed meal history filtered by date.
- Editing and deletion for saved meal records.

### Apple Health / Fitness Integration

BHealth can request HealthKit access and sync:

- Height
- Weight
- Age / date of birth
- Biological sex
- Active energy burned
- Basal energy burned, when available
- Step count

If basal energy is not available, the app estimates basal burn from the local profile. Active energy from Apple Fitness is included in daily burn calculations.

### Local-First Data Model

The app is intentionally local-first:

- Meal records are stored locally on the device.
- Profile data is stored locally.
- The DeepSeek API key is stored in iOS Keychain with `ThisDeviceOnly` accessibility.
- Apple Health data is read through HealthKit and merged into local dashboard summaries.
- API keys are not committed to the repository.

AI requests are sent to DeepSeek only when the user uses AI assistant features and has configured an API key.

### Language Support

BHealth supports:

- System language
- English
- Simplified Chinese

The selected language affects the UI and AI-facing response instructions.

## Tech Stack

- Swift
- SwiftUI
- HealthKit
- Security / Keychain Services
- Swift Testing
- DeepSeek Chat Completions API
- Model: `deepseek-v4-flash`

## Requirements

- macOS with Xcode installed
- iOS target compatible with the project deployment target
- An Apple Developer team configured in Xcode for device deployment
- A DeepSeek API key for AI assistant functionality
- An iPhone for full Apple Health / Fitness integration

The current project settings use:

- Bundle identifier: `com.tydnzs.BHealth`
- Version: `1.0`
- iOS deployment target: `26.5`

## Getting Started

### 1. Clone the Repository

```bash
git clone https://github.com/BlerTNN/BHealth.git
cd BHealth
```

### 2. Open in Xcode

```bash
open BHealth.xcodeproj
```

Select the `BHealth` scheme.

### 3. Configure Signing

In Xcode:

1. Select the `BHealth` project.
2. Open the `BHealth` target.
3. Go to **Signing & Capabilities**.
4. Select your Apple Developer team.
5. Make sure HealthKit capability is enabled.

If you use a different Apple Developer account, you may need to change the bundle identifier.

### 4. Run on Simulator

The app can run on simulator for UI and basic local flows:

```bash
xcodebuild -project BHealth.xcodeproj \
  -scheme BHealth \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  build
```

HealthKit availability may be limited on simulator. Use a physical iPhone for the complete Apple Health / Fitness experience.

### 5. Run on iPhone

Connect an iPhone, trust the Mac, then build from Xcode or run:

```bash
xcodebuild -project BHealth.xcodeproj \
  -scheme BHealth \
  -destination 'generic/platform=iOS' \
  build
```

For direct command-line installation, first build for the connected device, then install the generated `.app` bundle with `xcrun devicectl`.

## App Setup

### Configure the API Key

1. Open the app.
2. Go to **Me**.
3. Find the DeepSeek API key field.
4. Paste your API key.
5. Save it.

The key is stored in Keychain and should not be written to source files.

### Sync Apple Health

1. Open **Me**.
2. Tap the Apple Health sync action.
3. Grant the requested HealthKit permissions.
4. Return to Overview to see active burn, total burn, and yearly summaries update.

### Log Food

1. Open **AI Assistant**.
2. Choose **Log Food**.
3. Describe what you ate and when.
4. Answer follow-up questions if needed.
5. Confirm the generated record.
6. The saved meal appears in Overview and meal history.

### Ask for Health Advice

1. Open **AI Assistant**.
2. Choose **Health Coach**.
3. Ask about intake, burn, trends, or weight goals.

## Data and Privacy

BHealth avoids cloud storage for personal health data. The app uses:

- `UserDefaults` / local JSON storage for app preferences and local records.
- iOS Keychain for the DeepSeek API key.
- HealthKit APIs for Apple Health / Fitness reads.

Do not hardcode API keys in the project. Before committing, scan for your API provider's secret prefix and remove any accidental matches.

## Development

### Run Unit Tests

```bash
xcodebuild test -project BHealth.xcodeproj \
  -scheme BHealth \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:BHealthTests
```

### Build Without Code Signing

Useful for CI-style validation:

```bash
xcodebuild -project BHealth.xcodeproj \
  -scheme BHealth \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

### Validate Formatting

```bash
git diff --check
```

## Project Structure

```text
BHealth/
  AppSettings.swift             Language preference and localization helpers
  AppText.swift                 Shared bilingual text formatting
  BHealthApp.swift              App entry point
  ContentView.swift             Main SwiftUI UI, tabs, dashboard, assistant screens
  DeepSeekClient.swift          DeepSeek API client
  FoodAssistantViewModel.swift  AI assistant state, prompt, parsing, meal save flow
  FoodNutritionIndex.swift      Food index models, meal records, local persistence
  HealthDashboardStore.swift    Dashboard state, HealthKit sync, yearly summaries
  KeychainAPIKeyStore.swift     Secure local API key storage
  Data/FoodNutritionIndex.json  Bundled food reference data
BHealthTests/
  BHealthTests.swift            Unit tests for assistant parsing, language, date logic
BHealthUITests/
  BHealthUITests.swift          UI test scaffold
```

## Troubleshooting

### AI Assistant Says No API Key Is Saved

Add your DeepSeek API key in **Me**. The app intentionally does not ship with a key.

### AI Replies Are Unavailable

Possible causes:

- API key is missing or invalid.
- Network is unavailable.
- DeepSeek API returns a non-2xx response.
- The model response is empty or malformed.

The app may show the API error and continue the conversation where possible.

### Apple Health Data Does Not Appear

Check:

- You are running on a physical iPhone.
- HealthKit permissions were granted.
- Apple Fitness has active energy data for the selected dates.
- The app has been opened after granting permissions so it can refresh.

### GitHub Push Fails

Check network and DNS first:

```bash
git remote -v
git status --short --branch
git push origin main
```

If `github.com` cannot be resolved, fix the Mac network connection before retrying.

## Notes

BHealth is a personal health management tool, not medical software. Calorie estimates are approximate and should be treated as guidance, not clinical or nutritional advice.
