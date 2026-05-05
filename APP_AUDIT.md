# PanicGuard App Audit — Full Working Document

**Status:** Audit Complete — Implementation Pending
**Last Updated:** 2026-05-04
**Project Path:** `/mnt/c/Users/abiyy/Documents/Work/panic-guard/`
**PRD:** `/mnt/c/Users/abiyy/Documents/mindpalace/llm-wiki/hackathon-prd-panic-guard.md`
**Fine-Tuning Plan:** `Gemma/FINE_TUNING_PLAN.md`

---

## Product Vision (Reference)

> *"on-device, privacy-first panic disorder companion that splits intelligence where it belongs: a Random Forest model handles the fast, accurate biometric detection — continuously reading HR, HRV, and respiratory rate from your wearable — while Gemma E2B acts as the human layer, translating clinical signals into compassionate responses, guided interventions, and longitudinal care support. Nothing leaves your device without your explicit approval. Between episodes, Gemma becomes your personal disorder manager — logging episodes in natural language, tracking therapy progress, drafting psychiatrist reports, and suggesting appointments — positioning it not as a crisis tool you hope to never use, but a daily companion that makes living with panic disorder genuinely manageable."*

---

## Architecture: The Split That Drives Everything

```
REALTIME (every 1-5 seconds)
    │
    ▼
┌──────────────────────────────────────────────┐
│  RANDOM FOREST (CoreML .mlpackage)           │
│  Input:  RMSSD, SDNN, HR mean, HR std,       │
│           LF/HF ratio, age, time_of_day,      │
│           sleep_hours                          │
│  Output: panic_confidence (0.0-1.0 Float)     │
│  Latency: ~10ms                               │
│  Accuracy target: ≥99% on WESAD               │
│  Location: On-device, never leaves phone     │
└──────────────────┬───────────────────────────┘
                   │ panic_confidence ≥ 0.85
                   ▼
┌──────────────────────────────────────────────┐
│  GEMMA E2B (On-Device LLM)                  │
│  NEVER touches the classifier.               │
│                                              │
│  CRISIS MODE (during episode):               │
│  - Generate compassionate explanation        │
│  - Sequence & personalize interventions      │
│  - Draft escalation SMS draft                │
│                                              │
│  DAILY COMPANION (between episodes):         │
│  - Journal review → trigger correlations    │
│  - Proactive nudges before known triggers   │
│  - Post-episode narrative debriefs          │
│  - Therapy report drafting (weekly)         │
│  - Answer: "why do I keep having X?"        │
└──────────────────────────────────────────────┘
```

**Why Gemma is NOT the classifier:** PMC12526660 showed LLM-based classification achieved 71.43% accuracy vs. Random Forest's 99.27% on the same WESAD data. The LLM fails because: (1) panic onset is a ~30-second physiological event — autoregressive token generation is too slow for the detection loop; (2) class imbalance is severe — panic episodes are rare and LLM decoders don't handle that well; (3) the feature space (RMSSD/HR/SDNN) is low-dimensional — LLMs need high-dimensional semantic context to add value. Gemma's job is reasoning over context, not pattern-matching on raw biometrics.

---

## Current File Inventory

```
/mnt/c/Users/abiyy/Documents/Work/panic-guard/
├── App/
│   ├── PanicGuardApp.swift          ✅ 82 lines — App entry, routes Onboarding/Home
│   ├── PanicGuardCoordinator.swift  ✅ 303 lines — Pipeline wiring (MISSING reset())
│   ├── PanicGuard.entitlements      ✅ — HealthKit + background delivery
│   └── Info.plist                  ✅
├── Views/
│   ├── HomeView.swift              ✅ 105 lines — Crisis-only dashboard, no daily companion
│   └── (JournalView.swift          ❌ MISSING)
│   └── (TriggerCorrelationView.swift ✅ 357 lines)
│   └── (TherapyReportView.swift     ❌ MISSING)
├── Models/
│   ├── PanicEpisode.swift          ⚠️  70 lines — Schema too shallow
│   ├── (JournalEntry.swift         ❌ MISSING)
│   ├── (TriggerCorrelation.swift    ✅ 204 lines)
│   └── (TherapyReport.swift         ❌ MISSING)
├── Services/
│   ├── HealthKitService.swift      ⚠️  112 lines — No background delivery impl
│   ├── EpisodeLogger.swift         ⚠️  145 lines — Schema incomplete, missing tables
│   ├── EscalationService.swift     ❌ MISSING — Build error if called
│   ├── WatchConnectivityService.swift ✅
│   └── HapticService.swift         ✅
├── Detection/
│   ├── DetectionEngine.swift       🔴 562 lines — RULE-BASED, NOT RF
│   └── HRVFeatureExtractor.swift    ✅ 334 lines — RMSSD/SDNN buffer (RF feature source)
├── Gemma/
│   ├── GemmaService.swift          ✅ 415 lines — MediaPipe integration (needs expansion)
│   ├── GemmaDispatch.swift         ✅ 317 lines — JSON parsing + dispatch
│   ├── GemmaPromptBuilder.swift    ⚠️  189 lines — Crisis only, missing journal/therapy prompts
│   ├── GemmaJournalCorrelator.swift ❌ MISSING
│   ├── GemmaTherapyReportGenerator.swift ❌ MISSING
│   ├── GemmaProactiveNudgeScheduler.swift ❌ MISSING
│   └── FINE_TUNING_PLAN.md         ✅ Updated with full daily companion plan
├── Intervention/
│   ├── InterventionService.swift   ✅ 110 lines — TTS + breathing/grounding
│   ├── BreathingCircleView.swift    ✅
│   ├── GroundingPromptView.swift    ✅
│   ├── ImOkayButton.swift          ✅
│   └── InterventionOverlayView.swift ✅ 183 lines
├── Onboarding/
│   └── OnboardingView.swift        ✅ 224 lines — 5-step flow
├── Settings/
│   └── SettingsView.swift          ✅ 96 lines — Contact, calibration, demo toggle
├── Demo/
│   └── DemoService.swift           ✅ 99 lines — 5-phase simulation
├── Escalation/
│   └── (EscalationService.swift    ❌ MISSING — but referenced by Coordinator)
└── project.yml                     ⚠️  59 lines — Missing MediaPipe + RF bundle
```

---

## 🔴 CRITICAL — Must Fix Before App Compiles or Runs

### C1. EscalationService.swift — Missing (Build Error)
**Referenced by:** `PanicGuardCoordinator.swift` lines 15, 236, 258, 275
**File path:** `Services/EscalationService.swift` (does not exist)

`PanicGuardCoordinator` imports and calls `EscalationService.shared.escalate()` but the file is completely absent. The app will crash or fail to compile if any escalation code path is hit.

**Required:** Write full `EscalationService.swift`:
- `escalate(contact:, userFirstName:, episodeId:)` async method → calls Cloudflare Worker → Twilio
- `cancelEscalation(episodeId:)` — stops SMS if user dismisses before send
- Location deferred until actual escalation trigger (NOT at init)
- Returns `Bool` success/failure
- Simulation mode for demo (returns success immediately)

```swift
final class EscalationService: ObservableObject {
    static let shared = EscalationService()
    private let cloudflareWorkerURL = "https://panicguard-escalation.your-account.workers.dev"

    @Published var isEscalationActive: Bool = false

    func escalate(contact: EmergencyContact, userFirstName: String, episodeId: UUID) async -> Bool {
        // 1. Get current location (deferred — only now)
        // 2. Reverse geocode to readable address
        // 3. POST to Cloudflare Worker
        // 4. Return success
    }

    func cancelEscalation(episodeId: UUID) async {
        // idempotency key = episodeId UUID — prevents double-send
    }
}
```

**Cloudflare Worker** already exists at `/mnt/c/Users/abiyy/Documents/Work/panic-guard-escalation/` — PRD section 12 has the full implementation.

---

### C2. DetectionEngine.reset() — Method Missing
**File:** `Detection/DetectionEngine.swift`
**Called by:** `PanicGuardCoordinator.stopMonitoring()` line 67

`DetectionEngine` has no `reset()` method. Calling it will be a compile error.

**Required:** Add to `DetectionEngine`:
```swift
func reset() {
    panicOnsetTimer = nil
    firstPanicDetectedAt = nil
    escalationTimer?.invalidate()
    escalationTimer = nil
    exerciseContextActive = false
    exerciseRecoveryTimer = nil
    state = .idle
    currentConfidence = 0.0
    rollingHRBuffer.removeAll()
    rollingRMSSDBuffer.removeAll()
    rollingSDNNBuffer.removeAll()
}
```

---

### C3. DetectionEngine is Rule-Based — Not Random Forest
**File:** `Detection/DetectionEngine.swift` (562 lines)

This is the **single largest gap** between the codebase and the product description.

**Current implementation:** Hardcoded if-then threshold logic.
```swift
let meetsPanicThreshold = hrSpike >= threshold.hrSpikeMin &&
                          hrvDropRatio >= threshold.hrvDropRatioMin
```
The file header claims "Random Forest accuracy: 99.27%" in a comment but this is false — no RF model exists in the code.

**Product requirement:** *"a Random Forest model handles the fast, accurate biometric detection"*

**What needs to happen:**

#### Step 1: Train the Random Forest (offline, before iOS work)

```python
# train_rf.py — run on laptop/Colab, NOT on device
from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import StratifiedKFold
import pandas as pd
import numpy as np

# WESAD features per 30-second window:
# RMSSD, SDNN, HR_mean, HR_std, LF/HF_ratio, pNN50, age_group, time_of_day, sleep_hours

rf = RandomForestClassifier(
    n_estimators=500,
    max_depth=12,
    min_samples_leaf=5,
    class_weight='balanced',
    random_state=42
)

# 5-fold subject-level CV (never mix same person's data across train/test)
skf = StratifiedKFold(n_splits=5)
# ... train and evaluate ...

# Export to CoreML
import coremltools as ct
coreml_model = ct.converters.sklearn.convert(rf)
coreml_model.save("PanicGuardRF.mlpackage")
```

**Target metrics:**
- Recall (panic_onset) ≥ 0.92
- AUROC ≥ 0.93
- Overall accuracy ≥ 0.88

#### Step 2: Add PanicGuardRF.mlpackage to Xcode bundle
- Place `PanicGuardRF.mlpackage` in the Detection folder
- Add to project.yml sources
- NO new dependency needed — CoreML is built into iOS

#### Step 3: Rewrite DetectionEngine to use the RF
**Keep:** `HRVFeatureExtractor` — it computes the RMSSD/SDNN/HR features the RF needs.
**Replace:** threshold logic with RF inference call.

```swift
import CoreML

final class DetectionEngine: ObservableObject {
    // Replace the threshold struct with RF model
    private var rfModel: PanicGuardRF?
    private let rfQueue = DispatchQueue(label: "com.panicguard.rf.inference", qos: .userInteractive)

    // RF input feature vector
    struct RFFeatureVector {
        let rmssd: Float
        let sdnn: Float
        let hrMean: Float
        let hrStd: Float
        let lfHfRatio: Float
        let ageGroup: Int  // 0=18-30, 1=31-45, 2=46+
        let timeOfDay: Int  // 0=night, 1=morning, 2=afternoon, 3=evening
        let sleepHours: Float
    }

    private func loadRFModel() {
        // Load bundled PanicGuardRF.mlpackage
        let config = MLModelConfiguration()
        config.computeUnits = .all  // CPU + ANE
        rfModel = try? PanicGuardRF(configuration: config)
    }

    // Replace runPanicDetection() threshold logic with:
    private func runRFPanicDetection(featureVector: RFFeatureVector) {
        rfQueue.async { [weak self] in
            guard let rfModel = self?.rfModel else { return }

            // Build MultiArray input
            let inputVector = try? rfModel.featureVector([
                featureVector.rmssd,
                featureVector.sdnn,
                featureVector.hrMean,
                featureVector.hrStd,
                featureVector.lfHfRatio,
                Float(featureVector.ageGroup),
                Float(featureVector.timeOfDay),
                featureVector.sleepHours
            ])

            // Get panic probability
            let panicProbability = inputVector.featureValue(for: "panic_probability")?.doubleValue ?? 0.0

            DispatchQueue.main.async {
                if panicProbability >= 0.85 {
                    self?.triggerPanicDetected(confidence: Float(panicProbability))
                } else if panicProbability >= 0.6 {
                    self?.state = .signalElevated(confidence: Float(panicProbability))
                } else {
                    self?.state = .monitoring
                }
            }
        }
    }
}
```

**Note:** The RF outputs a probability, not a binary decision. The 0.85 threshold means "panic confirmed" — feed directly to Gemma as `confidence`. The 0.6-0.85 range = "signal elevated" = check-in prompt.

---

## 🔴 CRITICAL — Daily Companion (Biggest Feature Gap)

### C4. No Daily Companion Mode — Gemma Only Runs During Crisis

The product describes Gemma as a **daily companion** between episodes. The current codebase has zero support for this. This is not a bug — it's a missing product mode.

**Existing Gemma pipeline:**
```
DetectionEngine → GemmaService.makeDecision() → InterventionService
```

**Required Gemma pipeline (TWO modes):**

```
MODE 1 — CRISIS (existing, needs refinement)
DetectionEngine (RF confidence ≥ 0.85)
  → Gemma: Generate explanation + sequence interventions + draft SMS

MODE 2 — DAILY COMPANION (MISSING — needs full implementation)
User opens Journal tab
  → User types free-text entry OR asks a question
  → Gemma reads: journal entry + 90-day episode history + calendar events + sleep data
  → Gemma generates: correlation report OR empathetic response OR trigger analysis

Proactive: Calendar event "work meeting" approaches
  → Gemma generates nudge: "You have a quarterly review at 2pm. Looking at your history,
    presentations tend to be triggers when you've slept poorly. Want to do a grounding
    exercise at 1:45pm?"
```

---

### C5. Missing Models

#### `Models/JournalEntry.swift` (NEW)
```swift
struct JournalEntry: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let content: String  // free-text from user
    let emotionalTags: [String]  // ['anxious', 'stressed', 'okay', etc.]
    let linkedEpisodeId: UUID?  // attached to a panic episode
    let gemmaSummary: String?  // Gemma's one-line summary
    let gemmaInsights: [String]?  // Gemma's identified patterns
}
```

#### `Models/TriggerCorrelation.swift` (NEW)
```swift
struct TriggerCorrelation: Identifiable, Codable {
    let id: UUID
    let patternType: PatternType  // .timeOfDay, .calendarEvent, .sleepDebt, .journalTheme
    let patternDescription: String  // e.g., "episodes within 2h of 'work meeting' when sleep < 6h"
    let confidence: Double  // how strongly Gemma believes this
    let episodeCount: Int  // supporting episodes
    let supportingDetails: String  // e.g., "4 of last 12 episodes matched this pattern"
    let lastUpdated: Date
    let isActive: Bool  // user can disable patterns they've noticed

    enum PatternType: String, Codable {
        case timeOfDay, calendarEvent, sleepDebt, journalTheme, exerciseContext, none
    }
}
```

#### `Models/TherapyReport.swift` (NEW)
```swift
struct TherapyReport: Identifiable, Codable {
    let id: UUID
    let weekStart: Date
    let weekEnd: Date
    let episodeCount: Int
    let totalDurationMinutes: Double
    let dominantPatterns: [String]  // top 2-3 identified triggers this week
    let episodeDates: [Date]
    let averageSleepHours: Double?
    let gemmaReportBody: String  // full generated report, user-editable before sharing
    let createdAt: Date
    let isShared: Bool  // has user exported/shares this yet
}
```

---

### C6. Missing Views

#### `Views/JournalView.swift` (NEW)
- Text input field for free-text journal entry
- Optional emotional tags (anxious / stressed / okay / calm)
- "Attach to last episode" toggle if an episode just occurred
- Gemma's response displayed below
- Scrollable history of past journal entries

#### `Views/TriggerCorrelationView.swift` (NEW)
- Shows all `TriggerCorrelation` records
- Active vs. inactive patterns
- "Help me understand this" button → Gemma explains the pattern
- Toggle to disable a pattern

#### `Views/TherapyReportView.swift` (NEW)
- Displays generated weekly report
- Editable text area (user can modify before sharing)
- "Share with therapist" button → exports as text/email
- History of past reports

---

### C7. Missing Gemma Components

#### `Gemma/GemmaJournalCorrelator.swift` (NEW)
Reads 90-day episode history + journal entries + calendar events → identifies trigger correlations.

**Input data:**
- Episode metadata: timestamps, duration, peak HR, RMSSD, resolution
- Journal entries: content + emotional tags
- Calendar events: tagged as "work", "social", "therapy", "exercise", "travel"
- Sleep data: from HealthKit (sleep analysis sample type)

**Output:** Array of `TriggerCorrelation` objects + a natural language summary Gemma can display.

**Trigger example Gemma might find:**
```
"Your last 4 episodes happened within 2 hours of a calendar event
marked 'work meeting' when you'd slept less than 6 hours."
```

#### `Gemma/GemmaTherapyReportGenerator.swift` (NEW)
Reads past week's episode data → generates structured therapy report.

**Output:**
```
"Week of May 4–11, 2026:
Total episodes: 3 (down from 5 the prior week)

Episodes:
  - May 4, 11:42pm: 6m 12s, peak HR 124, resolved after interventions
  - May 7, 9:15pm: 4m 30s, peak HR 118, escalated (contact notified)
  - May 10, 2:30pm: 3m 45s, peak HR 112, user dismissed

Dominant patterns this week:
  1. Evening clustering (2 of 3 episodes after 9pm)
  2. Sleep debt amplifier (all 3 episodes followed nights with < 6h sleep)

Notes for discussion:
  - May 7 escalation occurred despite user having journaled 'anxious' that morning
  - Breathing exercise consistently helped (completed in 2 of 3 episodes)"
```

#### `Gemma/GemmaProactiveNudgeScheduler.swift` (NEW)
Monitors upcoming calendar events + active trigger correlations → schedules proactive nudges.

**Logic:**
```
IF upcoming_calendar_event.type == "work meeting"
   AND user.episode_history.has_pattern(near: "work meeting", confidence: > 0.7)
   AND user.recent_sleep_hours < 6
THEN schedule nudge: "You have [event] at [time]. Your episodes tend to cluster around
  high-stakes work events after short sleep. Want to do a 2-minute grounding practice now?"
```

Uses `UserNotifications` to deliver nudge at the scheduled time.

#### `Gemma/GemmaPromptBuilder+Journal.swift` (NEW)
Prompt templates for journal review + correlation analysis tasks.

**Template family B (from FINE_TUNING_PLAN):**
```
Input: Episode history (90 days), journal entries, calendar events, sleep data
Output: correlation_report (string), proactive_nudge (string), journal_prompt (string)
```

#### `Gemma/GemmaPromptBuilder+Therapy.swift` (NEW)
Prompt templates for therapy report generation.

**Template family D (from FINE_TUNING_PLAN):**
```
Input: week's episode metadata + journal entries + sleep data
Output: structured therapy report body
```

---

### C8. Missing Services

#### `Services/CalendarIntegrationService.swift` (NEW)
Reads calendar events from EventKit. User manually tags events as trigger categories.

**Design note:** Full calendar read access is privacy-sensitive. Two options:
1. Read-only EventKit access — user explicitly grants, shows in onboarding
2. Manual event tagging — user creates "PanicGuard trigger" events with category in event title (e.g., "[PG-work] quarterly review")

Recommendation: Start with option 2 (manual tagging) — simpler, more private, user has full control over what's shared.

```swift
final class CalendarIntegrationService: ObservableObject {
    func fetchUpcomingTriggers(daysAhead: Int = 7) -> [CalendarTrigger] {
        // Parse events titled "[PG-work]", "[PG-social]", "[PG-therapy]", etc.
        // Return array of CalendarTrigger(emoji-free title, date, category)
    }
}
```

---

## 🔴 CRITICAL — Privacy & Consent

### C9. Explicit Escalation Consent — Not Enforced

**Product requirement:** *"Nothing leaves your device without your explicit approval."*

**Current behavior:** SMS auto-sends after 5 minutes with no user prompt.
```swift
// PanicGuardCoordinator.handleEscalation — fires automatically
let success = await escalationService.escalate(contact: contact, ...)
```

**Required:** Add setting in `SettingsView`:
- "Auto-escalate after 5 minutes" (toggle, default ON for safety)
- If OFF: show confirmation prompt before SMS fires ("I'm about to notify [Contact]. Cancel or Send?")

Both modes still log the episode. The difference is explicit user approval before the network call.

---

### C10. Location Deferred Until Escalation — Not at Init

**PRD:** Location "only fetched at escalation time."

**Current pattern (EscalationService would have):**
```swift
// WRONG — called at init
locationManager.requestWhenInUseAuthorization()
```

**Correct:**
```swift
// Called only when escalation triggers
private func getCurrentLocationAddress() async -> String {
    locationManager.requestWhenInUseAuthorization()  // deferred until here
    // ... reverse geocode ...
}
```

---

## 🟡 MODERATE — Needs Work

### M1. EpisodeLogger Schema Incomplete
**File:** `Services/EpisodeLogger.swift`

**Missing tables:**
```sql
CREATE TABLE journal_entries (...);
CREATE TABLE trigger_correlations (...);
CREATE TABLE nudge_log (...);
CREATE TABLE therapy_reports (...);
```

See Models section (C5) for full schema.

---

### M2. HealthKitService — Background Delivery Not Implemented
**File:** `Services/HealthKitService.swift`

Entitlements set `com.apple.developer.healthkit.background-delivery: true` but code uses foreground-only `HKAnchoredObjectQuery`. For truly passive detection (app in background), need:

```swift
func startBackgroundDelivery() {
    let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate)!
    healthStore.enableBackgroundDelivery(for: heartRateType, frequency: .immediate)
    // ... also for HRV type ...
}
```

---

### M3. GemmaService — getRecentEpisodeContext() Returns Placeholder
**File:** `Gemma/GemmaService.swift` line 340

```swift
func getRecentEpisodeContext() -> (count: Int, hoursSinceLast: Float?) {
    return (0, nil)  // STUB
}
```

Must query `EpisodeLogger` for real episode history. This is required for both the crisis pipeline (recent episode context) and the daily companion correlation engine.

---

### M4. GemmaPromptBuilder — Missing Prompt Families
**File:** `Gemma/GemmaPromptBuilder.swift`

Current prompts: crisis detection, check-in follow-up, escalation assessment.

**Missing (per FINE_TUNING_PLAN):**
- Task Family B: Journal correlation analysis (trigger identification)
- Task Family C: Post-episode narrative debrief
- Task Family D: Therapy report drafting

Also: current `PhysiologicalState` struct needs `lfHfRatio: Float?` and `hrStd: Float?` added for the RF feature vector completeness.

---

### M5. HomeView Has No Daily Companion Entry Point
**File:** `Views/HomeView.swift`

HomeView is a pure crisis-monitoring dashboard. No way to access:
- Journal / talk to Gemma
- View trigger patterns
- See therapy report
- Adjust nudge settings

**Required additions to HomeView:**
- Navigation to JournalView (bottom tab or prominent button)
- Subtle indicator when Gemma has identified new trigger patterns
- "Weekly summary ready" badge when therapy report is generated

---

### M6. project.yml — Missing MediaPipe + RF Bundle
**File:** `project.yml`

Missing:
1. `MediaPipeTasksGenAI` package (for GemmaService MediaPipe integration)
2. `PanicGuardRF.mlpackage` in Detection/ folder (source, not dependency)

---

## 🟢 Minor / Clean Up

### m1. Formatting Bug
`GemmaPromptBuilder.swift` line 156: `" midday"` → should be `"midday"` (leading space)

### m2. GemmaService Grammar Constraint Not Applied
`LlmInferenceOptions.setupJSONGrammar()` (line 364) is an empty stub. The JSON grammar constraint described in the file header is not actually enforced. The `responseMimeType = "application/json"` at line 110 is real, but no schema/enum constraint is applied.

---

## Implementation Priority Order

### Phase 1: Make It Compile + Run (Fix Critical Build Errors)
1. Write `EscalationService.swift` — missing file causing build errors
2. Add `DetectionEngine.reset()` — missing method causing compile errors
3. Add `PanicGuardRF.mlpackage` to project (trained RF model)
4. Update `project.yml` with MediaPipe dependency

### Phase 2: Detection Core — Random Forest
5. Train RF on WESAD features offline (Python/sklearn → CoreML)
6. Rewrite `DetectionEngine` to call RF instead of threshold logic
7. Keep `HRVFeatureExtractor` — feeds RF features

### Phase 3: Daily Companion — Journal + Correlation
8. Write new models: `JournalEntry`, `TriggerCorrelation`, `TherapyReport`
9. Expand `EpisodeLogger` schema with new tables
10. Write `JournalView` + `GemmaJournalCorrelator`
11. Expand `GemmaPromptBuilder` with journal/therapy prompt families
12. Write `GemmaProactiveNudgeScheduler`

### Phase 4: Therapy Reports + Proactive Nudges
13. Write `GemmaTherapyReportGenerator`
14. Write `TherapyReportView`
15. Write `TriggerCorrelationView`
16. Write `CalendarIntegrationService`
17. Add proactive nudge settings to `SettingsView`

### Phase 5: Privacy + Polishing
18. Implement explicit escalation consent (toggle + prompt)
19. Fix location deferred-until-escalation
20. Implement HealthKit background delivery
21. Add daily companion entry to `HomeView`
22. Demo mode update (RF confidence + Gemma companion scenario)

---

## Fine-Tuning Reference (From FINE_TUNING_PLAN.md)

Gemma fine-tuning is separate from iOS app development. It can run in parallel.

**Task Families for Gemma Fine-Tuning:**
- Task A: Crisis response (existing — generate explanation + interventions)
- Task B: Journal correlation analysis (NEW — identify trigger patterns from history)
- Task C: Post-episode debrief (NEW — narrative generation from biometric data)
- Task D: Therapy report drafting (NEW — structured weekly summaries)

**What Gemma should NOT be fine-tuned on:** classification. RF owns that.

**Memory requirement:** ~8GB VRAM (RTX 4090, M2 Pro, or Google Colab A100)
**Training time:** ~4 hours per fold on RTX 4090
**Dataset size:** ~5,300 total samples across all task families

---

## Key Files Reference

| File | Purpose |
|------|---------|
| `Detection/DetectionEngine.swift` | Replace threshold → RF call |
| `Detection/HRVFeatureExtractor.swift` | Keep — computes RF input features |
| `Detection/PanicGuardRF.mlpackage` | NEW — trained RF model bundle |
| `Gemma/GemmaService.swift` | Expand with journal/therapy inference methods |
| `Gemma/GemmaPromptBuilder.swift` | Add prompt families B, C, D |
| `Gemma/GemmaJournalCorrelator.swift` | NEW — trigger correlation engine |
| `Gemma/GemmaTherapyReportGenerator.swift` | NEW — weekly report generation |
| `Gemma/GemmaProactiveNudgeScheduler.swift` | NEW — proactive nudge scheduling |
| `Models/JournalEntry.swift` | NEW |
| `Models/TriggerCorrelation.swift` | NEW |
| `Models/TherapyReport.swift` | NEW |
| `Models/PanicEpisode.swift` | Expand schema |
| `Services/EpisodeLogger.swift` | Add tables: journal_entries, trigger_correlations, nudge_log, therapy_reports |
| `Services/EscalationService.swift` | NEW — currently missing, build error |
| `Services/CalendarIntegrationService.swift` | NEW — manual event tag reader |
| `Views/HomeView.swift` | Add daily companion navigation |
| `Views/JournalView.swift` | NEW — Gemma journal interface |
| `Views/TriggerCorrelationView.swift` | NEW |
| `Views/TherapyReportView.swift` | NEW |
| `Settings/SettingsView.swift` | Add escalation consent toggle, nudge settings |
| `project.yml` | Add MediaPipe package, RF mlpackage |

---

## Privacy Architecture (Keep Intact)

| Data | Storage | Leaves Device? |
|------|---------|----------------|
| HR/HRV rolling buffer | In-memory only | Never |
| RMSSD/SDNN features | In-memory only | Never |
| Baseline calibration | UserDefaults | Never |
| Emergency contact | Keychain | Only via SMS at escalation |
| Episode metadata | SQLite (local) | Never |
| Journal entries | SQLite (local) | Never |
| Trigger correlations | SQLite (local) | Never |
| Therapy reports | SQLite (local) | Only if user explicitly exports/shares |
| Calendar events | In-memory only | Never |
| Gemma model weights | On-device bundle | Never |
| Location | Reverse geocoded locally | Only in emergency SMS |
| Proactive nudges | UserNotification (local) | Never |

**No account. No analytics. No crash reporting that sends data off-device. No cloud sync.**
