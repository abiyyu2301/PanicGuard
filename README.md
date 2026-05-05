# PanicGuard

iOS panic attack detection app using HRV-based Random Forest ML, HealthKit integration, and a Gemma LLM-powered companion for journaling, trigger correlation, and therapy reporting.

---

## Features

**Detection**
- Real-time panic attack detection via HRV features (RMSSD, SDNN, HR, LF/HF, pNN50) computed from Apple Watch heart rate data
- Random Forest classifier (`PanicGuardRF.mlpackage`) trained on the WESAD dataset
- Confidence-gated alerts: `≥ 0.85` triggers crisis intervention, `0.6–0.85` prompts elevated check-in

**Companion**
- Daily journaling with Gemma-powered trigger correlation over 90-day history
- Proactive nudges based on calendar context + sleep deprivation
- Weekly therapy report generation

**Escalation**
- SMS escalation via Cloudflare Worker → Twilio (configurable emergency contacts)
- Location deferred until escalation trigger (privacy-first)
- Simulation mode for demo / development

**Integrations**
- Apple HealthKit (background delivery for continuous monitoring)
- EventKit (calendar tagged events)
- WatchConnectivity (Apple Watch companion)

---

## Prerequisites

| Tool | Version | Install |
|------|---------|---------|
| Xcode | 15.0+ | Mac App Store |
| XcodeGen | 2.35+ | `brew install xcodegen` |
| Ruby | 2.7+ | Comes with macOS |
| Python | 3.10+ | For ML retraining (optional) |
| Kaggle account | — | [kaggle.com](https://kaggle.com) — for WESAD download |
| Apple Developer account | Free tier works for development and testing. Paid ($99/yr) required only to enable HealthKit background delivery and Push Notifications on a physical device. |

> **macOS is required** to run Xcode and build the app.

---

## Setup

### 1. Clone the repo

```bash
git clone git@github.com:abiyyu2301/PanicGuard.git
cd PanicGuard
```

### 2. Generate the Xcode project

```bash
xcodegen generate
```

This reads `project.yml` and produces `PanicGuard.xcodeproj`. SPM packages (SnapKit, SQLite.swift, MediaPipeTasksGenAI) resolve automatically on first open — no CocoaPods.

### 3. Configure signing

1. Open `PanicGuard.xcodeproj` in Xcode
2. Select the `PanicGuard` target → **Signing & Capabilities**
3. Set your Team and Bundle Identifier
4. Repeat for the `WatchPanicGuard` target if using the watchOS companion

### 4. Enable capabilities

> **Free account**: Steps 4–5 below require a **paid Apple Developer account ($99/yr)** only if you want HealthKit background delivery and Push Notifications on a physical device. For development and testing on the simulator, these steps are optional.

The following capabilities must be added to your Apple Developer account and Xcode project for full functionality:

- **HealthKit** — read: heart rate, HRV, step count, sleep analysis; write: mindful minutes
- **Background Modes** — Background processing, Background fetch, Remote notifications
- **Push Notifications**
- **Location When In Use** — deferred until escalation trigger (privacy-first)
- **EventKit** — calendar read access

### 5. Apple Watch (optional)

Pairing an Apple Watch significantly improves HRV accuracy. Without one, detection falls back to iPhone motion sensors (reduced precision).

---

## Running the App

### Build and run

```bash
open PanicGuard.xcodeproj
# Select a simulator or paired Apple Watch
# Press ⌘R to build and run
```

### Demo mode

Enable `DemoService` in `App/PanicGuardApp.swift` to run with simulated sensor data — no Apple Watch or HealthKit access required:

```swift
// In PanicGuardApp.swift, uncomment:
@StateObject private var demoService = DemoService()
```

### Key settings

| Setting | Default | Location |
|---------|---------|---------|
| `autoEscalate` | ON | SettingsView |
| `nudgeEnabled` | ON | SettingsView |
| `healthKitSync` | ON | SettingsView |
| `demoMode` | OFF | SettingsView |

---

## ML Model — Retrain with WESAD Data

The bundled `PanicGuardRF.mlpackage` was trained on the WESAD dataset. Retraining requires macOS (for CoreML export).

```bash
# 1. Install Python dependencies
pip install numpy pandas scikit-learn==1.5.1 coremltools imbalanced-learn joblib wfdb

# 2. Download WESAD from Kaggle
mkdir -p Detection/WESAD
kaggle datasets download -d orvile/wesad-wearable-stress-affect-detection-dataset -p Detection/WESAD --unzip

# 3. Run training (macOS only)
cd Detection
KAGGLE_TOKEN="your_kaggle_token" python3 train_rf_real.py
```

This regenerates `Detection/PanicGuardRF.mlpackage` and `Detection/training_metrics.json`.

> **Note:** WESAD has no clinical panic labels — panic windows are inferred from physiology (HR > 100bpm + RMSSD < 20ms). Retrain on labeled panic disorder data for production use.

---

## Cloudflare Worker (Escalation)

Deploy your own Worker for SMS escalation:

```bash
cd ../panic-guard-escalation
wrangler deploy
```

Set the `WORKER_URL` in `EscalationService.swift`:

```swift
private let workerURL = "https://your-worker.your-subdomain.workers.dev/escalate"
```

---

## Architecture

```
PanicGuard/
├── App/
│   ├── PanicGuardApp.swift       # App entry, navigation
│   └── PanicGuardCoordinator.swift
├── Detection/
│   ├── DetectionEngine.swift     # RF inference + state machine
│   ├── HRVFeatureExtractor.swift  # Feature computation
│   ├── PanicGuardRF.mlpackage/   # CoreML model
│   ├── train_rf_real.py          # WESAD training pipeline
│   └── retrain_rf.py
├── Services/
│   ├── HealthKitService.swift     # Background delivery
│   ├── EpisodeLogger.swift        # SQLite persistence
│   ├── EscalationService.swift    # Cloudflare Worker → Twilio
│   └── CalendarIntegrationService.swift
├── Gemma/
│   ├── GemmaService.swift
│   ├── GemmaPromptBuilder.swift   # Prompt families A–D
│   ├── GemmaJournalCorrelator.swift
│   ├── GemmaProactiveNudgeScheduler.swift
│   └── GemmaTherapyReportGenerator.swift
├── Intervention/
│   ├── InterventionService.swift
│   ├── BreathingCircleView.swift
│   └── GroundingPromptView.swift
├── Views/
│   ├── HomeView.swift             # Main companion entry points
│   ├── JournalView.swift
│   ├── TriggerCorrelationView.swift
│   └── TherapyReportView.swift
├── Models/
│   ├── PanicEpisode.swift
│   ├── TriggerCorrelation.swift
│   └── TherapyReport.swift
└── Settings/
    └── SettingsView.swift
```

---

## API Reference

### Core ML Input Features

| Feature | Unit | Description |
|---------|------|-------------|
| `rmssd` | ms | Root mean square of successive RR differences |
| `sdnn` | ms | Standard deviation of NN intervals |
| `hrMean` | BPM | Mean heart rate |
| `hrStd` | BPM | Heart rate standard deviation |
| `lfHfRatio` | — | LF/HF ratio (variance proxy) |
| `pnn50` | % | pNN50 — % of successive pairs > 50ms apart |
| `ageGroup` | — | 0=18-30, 1=31-45, 2=46+ |
| `timeOfDay` | — | 0=night, 1=morning, 2=afternoon, 3=evening |
| `sleepHours` | h | Hours slept last night |

### Detection States

| State | Confidence | Action |
|-------|-----------|--------|
| `nominal` | < 0.6 | Continuous monitoring |
| `elevated` | 0.6–0.85 | Signal check-in prompt |
| `crisis` | ≥ 0.85 | Trigger intervention overlay + escalation timer |

---

## License

MIT
