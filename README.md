# RunTracker

A SwiftUI iOS app for tracking runs with Strava integration and AI coaching powered by Claude.

## Features

- **Manual run logging** — log distance, duration, date, and notes
- **Strava sync** — pull activities via OAuth, auto-upsert by Strava ID
- **AI coaching** — Claude analyzes your training data and provides feedback
  - **Analyze** — mileage progression, easy day pacing, HR trends, goal alignment
  - **Weekly summary** — what you did, what went well, plan for next week
  - **Ask** — free-form questions answered with your training context
- **Training context builder** — weekly mileage trends with % change, long run history, pace averages (easy vs workout), heart rate drift detection (3 bpm threshold), 14-day pattern view

## Requirements

- Xcode 16+
- iOS 17.0+
- Strava API app (Client ID + Secret) from [developers.strava.com](https://developers.strava.com)
- Anthropic API key from [console.anthropic.com](https://console.anthropic.com)

## Setup

1. Open `RunTracker.xcodeproj` in Xcode
2. Build and run on a simulator or device
3. Go to **Settings** tab:
   - Enter your Anthropic API key
   - Enter Strava Client ID and Client Secret
   - Tap **Connect Strava** and authorize
   - Tap **Sync Activities** to pull your runs
4. Optionally set a goal race (name, date, target time, weekly mileage target)
5. Go to **Coach** tab and tap **Analyze Training**

## Project Structure

```
RunTracker/
  RunTrackerApp.swift              App entry point, SwiftData container
  Models/
    Run.swift                      Run model with Strava fields
    UserProfile.swift              Goal race configuration
    CoachingResponse.swift         Coaching history
  Views/
    ContentView.swift              TabView (Runs / Coach / Settings)
    RunListView.swift              Run list with summary stats
    AddRunView.swift               Manual run logging form
    RunDetailView.swift            Run detail with Strava data section
    CoachView.swift                AI coaching interface
    SettingsView.swift             API keys, Strava connect, goal race
  Services/
    StravaAuth.swift               OAuth via ASWebAuthenticationSession
    StravaClient.swift             Strava API activity sync
    ClaudeCoach.swift              Training context builder + Claude API
  Utilities/
    PaceFormatter.swift            Pace/duration/distance formatting
  Resources/
    coaching-persona.md            Bundled coaching prompt
```

## Design Decisions

- **No external dependencies** — URLSession for all HTTP, no SPM packages
- **Single Run model** — Strava and manual runs in one SwiftData model
- **UserDefaults for credentials** — simple `@AppStorage` bindings for personal use
- **Context uses miles** (coaching convention), app UI uses km
