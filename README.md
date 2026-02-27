# LMB Lund – Work Log

An iOS app for logging work shifts and syncing them to Apple Calendar with automatic travel-time-based alarms.

## Features

- **Shift Logging** – Pick a day and start/end times, or use quick templates.
- **Calendar Sync** – Automatically creates calendar events with location, travel time estimates, and alarms.
- **iCloud CalDAV** – Optional direct CalDAV sync writes Apple's proprietary `X-APPLE-TRAVEL-*` properties so Calendar shows native "Based on location" driving travel time, time-to-leave notifications, and travel-aware alarms. Requires an app-specific password from appleid.apple.com.
- **History** – Browse past shifts with duration display and weekly/monthly hour summaries.
- **CSV Export** – Export your work log history via the share sheet.
- **Configurable** – Customize destination address, calendar name, event title, and shift templates in Settings.

## Requirements

- iOS 17.0+
- Xcode 15+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

## Building

1. Install XcodeGen:

   ```bash
   brew install xcodegen
   ```

2. Generate the Xcode project:

   ```bash
   xcodegen generate --spec project.yml
   ```

3. Open `WorkLog.xcodeproj` in Xcode and build.

## Running Tests

After generating the project, select the **WorkLogTests** scheme in Xcode and press `Cmd+U`.

## CI

The GitHub Actions workflow (`.github/workflows/build-ipa.yml`) builds an unsigned IPA on every push to `main`.
