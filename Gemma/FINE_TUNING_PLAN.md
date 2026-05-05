# Gemma Fine-Tuning + Daily Companion Plan: PanicGuard

**Project:** PanicGuard — Privacy-First Panic Disorder Daily Companion
**Dataset:** WESAD (Wearable Stress and Affect Detection) + PanicGuard User Journal Corpus
**Models:**
- Random Forest → Fast biometric classification (on-device, ~99% accuracy)
- Gemma E2B → Daily companion, reasoning, personalization, longitudinal analysis
**Target Deployment:** iPhone (Core ML + ANE)
**Horizon:** 14-Day Hackathon

---

## 1. Architecture Recap: Where Each Model Belongs

The core architectural decision driving everything:

```
REALTIME (every 1-5 seconds)
    │
    ▼
┌──────────────────────────────────────────┐
│  Random Forest (CoreML)                  │
│  Input:  RMSSD, SDNN, HR mean, HR std,   │
│           LF/HF ratio, age, time_of_day   │
│  Output: panic_confidence (0.0-1.0)       │
│  Latency: ~10ms                           │
│  Accuracy: ~99% on WESAD (PMC12526660)    │
└──────────────┬───────────────────────────┘
               │ panic confirmed (≥0.85)
               ▼
┌──────────────────────────────────────────┐
│  Gemma E2B (On-Device LLM)              │
│  Role: Human layer — NOT classifier      │
│                                          │
│  During episode:                         │
│  - Generate compassionate explanation    │
│  - Sequence and personalize interventions│
│  - Draft escalation SMS                  │
│                                          │
│  Between episodes (DAILY COMPANION):     │
│  - Review journal + episode history      │
│  - Identify trigger correlations         │
│  - Generate proactive nudges             │
│  - Draft psychiatrist reports            │
│  - Log therapy notes                     │
│                                          │
│  Gemma NEVER touches the classifier.     │
└──────────────────────────────────────────┘
```

**Why this split is correct:**
- RF is a fast, stable decision boundary — perfect for ~10ms binary decisions
- LLM classification fails on temporal physiological signals (PMC12526660: 71% vs RF's 99%)
- Gemma's strength is **reasoning over context**, not pattern matching on raw biometrics
- The daily companion features are where Gemma actually earns its spot

---

## 2. The Daily Companion Loop (What's New)

### 2.1 Journal + Episode History → Trigger Correlation Engine

This is the genuinely novel feature. The insight: most panic attacks have identifiable pre cursors — calendar events, time-of-day patterns, journal sentiment trends, sleep quality — but neither the user nor their therapist can see the connections without manual review.

**Gemma's job:** Periodically (or on-demand) review the user's episode history and journal entries, then surface correlations the user wouldn't notice on their own.

**Input data Gemma reads:**
```
Episode history (last 90 days):
  - timestamp, duration, peak HR, lowest RMSSD, resolution type
  - user journal entries (if any) attached to each episode
  - voluntary mood check-ins (non-episodic)

Calendar events (linked via HealthKit or manual entry):
  - marked as "work", "social", "exercise", "therapy", "travel"
  - time relative to episode onset

Sleep data (HealthKit):
  - hours slept, sleep quality score (if available)

General journal corpus:
  - free-text entries tagged by the user as "anxious", "stressed", "okay", etc.
```

**Gemma's output (correlation report):**
```
Based on your last 12 episodes:

⏰ TIME PATTERNS
  - 4 of 12 episodes occurred between 10pm–1am
  - 3 of 12 episodes happened on days where you slept < 6 hours
  - Morning episodes (6am–12pm) are rare (1/12)

📅 TRIGGER CORRELATIONS  
  - Your episodes cluster around "work meeting" calendar events
    (4 episodes within 2 hours of a meeting you marked as high-stakes)
  - No clear pattern with exercise or social events
  - 2 episodes followed days where you journaled about "can't stop thinking"

💤 SLEEP CONNECTION
  - Average sleep before an episode: 5h 48m
  - Average sleep on non-episode days: 7h 12m
  - Sleep debt appears to be a meaningful multiplier

🗓️ UPCOMING: You have 3 "work meeting" events this week.
  Consider提前准备 a grounding practice before each one.
```

**How the nudge works:**
When Gemma detects a high-probability trigger window approaching (e.g., "work meeting in 30 minutes" from calendar, or "you slept 4 hours last night"), it generates a gentle proactive notification:

```
"Morning — you have a team presentation at 2pm. 
Looking at your history, presentations tend to be triggers 
when you've had less sleep. Want to do a quick 2-minute 
grounding exercise now, or set a reminder for 1:45pm?"
```

This is the proactive nudge. It uses Gemma's reasoning, not its classifier.

---

### 2.2 Gemma's Expanded Role Map

| Mode | Gemma Task | Output |
|------|-----------|--------|
| **Crisis (during episode)** | Generate compassionate explanation of what's happening physiologically | Text + TTS |
| **Crisis (during episode)** | Select and sequence interventions based on HR trajectory | InterventionType |
| **Crisis (during episode)** | Draft escalation SMS with user's name, location, current state | SMS draft |
| **Daily (journal review)** | Identify correlations across 90-day episode history | CorrelationReport |
| **Daily (proactive nudge)** | Generate trigger-warning nudge before known upcoming triggers | Push notification text |
| **Daily (on-demand)** | Answer: "why do I keep having episodes at night?" | Natural language explanation |
| **Daily (journaling)** | Process free-text journal entry, extract emotional state, suggest follow-up | Logged note + optional response |
| **Weekly (therapist prep)** | Draft a structured weekly summary for the user's therapist | Formatted report |
| **Post-episode (optional)** | Generate narrative debrief from episode biometrics + user input | Episode story |

---

## 3. Dataset Construction

### 3.1 WESAD → Random Forest Training

The RF does NOT need fine-tuning. It needs feature engineering + training.

**Features extracted per 30-second window (from WESAD wrist sensors):**
```
HR (BPM)          = mean instantaneous heart rate
RMSSD (ms)        = root mean square of successive R-R intervals
SDNN (ms)         = standard deviation of R-R intervals
LF/HF ratio       = low-frequency / high-frequency power ratio
pNN50 (%)         = proportion of R-R intervals differing >50ms
HR std            = standard deviation of HR over window
SCL (µS)          = skin conductance level (EDA tonic)
SCR frequency     = phasic EDA peaks per minute
age_group         = categorical: 18-30, 31-45, 46+
time_of_day       = categorical: night, morning, afternoon, evening
sleep_hours       = continuous (if available from Apple Health)
```

**Labels:** `baseline`, `stress_response`, `panic_onset` (synthetic — see below)

**Synthetic panic construction:**
- Panic = stress label + (HR > 90th percentile for subject) + (RMSSD below subject's 25th percentile) + absence of amusement markers
- This yields ~1,500 synthetic panic windows from WESAD's 52 subjects

**Training:** scikit-learn `RandomForestClassifier`, 500 trees, subject-level 5-fold CV.

### 3.2 Gemma Instruction-Tuning Dataset

Gemma is fine-tuned on **two task families**, not just classification:

#### Task Family A: Crisis Response (during detection)

```
<|im_start|>user
You are PanicGuard, an on-device mental wellness companion.
You are running entirely on-device. No user data ever leaves the device.

The Random Forest has detected a panic episode with 0.87 confidence.
The user's current state:
- heart_rate: 108 bpm (baseline: 72 bpm)
- rmssd: 18 ms (baseline: 52 ms)  
- sdnn: 31 ms
- age_group: 18-30
- time_of_day: evening
- sleep_hours: 5.5
- recent_episodes_count (last 7 days): 2

Generate a JSON response with:
- explanation: a calm, reassuring 1-2 sentence explanation of what the data shows
- primary_intervention: the most appropriate first intervention
- secondary_intervention: what to escalate to if no improvement in 2 minutes
- escalation_sms_draft: a draft SMS to the emergency contact (if needed)

<|im_start|>assistant
{
  "explanation": "Your heart rate has risen 36bpm above your resting baseline while your nervous system balance (HRV) has dropped to its lowest point in 3 days. This combination, especially with limited sleep, matches your previous episodes.",
  "primary_intervention": "breathing_exercise",
  "secondary_intervention": "grounding_prompt",
  "escalation_sms_draft": "[PanicGuard Alert] [Name] may be experiencing a panic attack. Time: 11:42pm, May 4. Location: [last known address]. Reply or call directly."
}
```

#### Task Family B: Journal Review + Correlation Analysis (daily companion)

```
<|im_start|>user
You are PanicGuard's daily companion. Review the user's recent history and identify patterns.

Episode summary (last 30 days):
- Total episodes: 8
- Peak times: 10pm-1am (4 episodes), 2pm-4pm (3 episodes), morning (1 episode)
- Average sleep before episode: 5h 42m
- Average sleep non-episode days: 7h 8m
- Calendar tags near episodes: "work meeting" (4), "travel" (2), "social" (1), "none" (1)
- Journal themes near episodes: "couldn't sleep", "thinking about tomorrow", "argument"

Upcoming calendar (next 7 days):
- May 11, 2pm: "quarterly review" (work)
- May 13, 10am: "dentist appointment"
- May 15: "travel day"

Generate:
1. A correlation report identifying the strongest trigger patterns
2. A proactive nudge for the highest-risk upcoming calendar event
3. A suggested journal prompt to help the user prepare

<|im_start|>assistant
{
  "correlation_report": "Your episodes show two distinct patterns. First, evening clustering: 4 of 8 episodes occurred between 10pm-1am, and all 4 followed days with less than 6 hours sleep. Second, work stress: 4 of 8 episodes occurred within 2 hours of a 'work meeting' event, and in 3 of those 4 cases you journaled about sleep difficulty the night before. Sleep debt appears to be the primary amplifier — when you sleep poorly AND have a work meeting, episodes are much more likely.",
  "proactive_nudge": "You have a quarterly review on May 11 at 2pm. Looking at your history, work meetings are a trigger — especially after short sleep nights. Want to do a 3-minute box breathing exercise at 1:45pm today as preparation?",
  "journal_prompt": "What typically happens during or before your work meetings that feels stressful? Even a few words helps Gemma understand what support would be most useful."
}
```

#### Task Family C: Post-Episode Debrief + Narrative Logging

```
<|im_start|>user
Generate a narrative debrief for this episode. Keep it compassionate, factual, and clinically useful.

Biometric data:
- Detection time: 11:42pm, May 4
- Peak HR: 124 bpm
- Lowest RMSSD: 16 ms
- Duration: 6m 12s
- Resolution: user_dismissed (after interventions)
- Interventions delivered: breathing_exercise (completed), grounding_prompt (partial)
- Sleep prior night: 4h 30m
- Episode count last 7 days: 3

<|im_start|>assistant
Episode #14 — May 4, 2026, 11:42pm
Duration: 6m 12s | Peak HR: 124bpm | Lowest RMSSD: 16ms (below your personal baseline of 48ms)

What happened: You were lying in bed unable to sleep, ruminating about tomorrow's presentation. The physiological pattern — HR spike + HRV collapse at late night + severe sleep debt — matches your November episode cluster. This combination (night + sleep deprivation + anticipatory anxiety) appears to be a high-risk context for you.

What helped: You completed the breathing exercise and transitioned into the grounding prompt before dismissing. That's meaningful — 6 minutes from detection to recovery is faster than your last 3 episodes.

Pattern note: 3 episodes in 7 days with this specific combination suggests you may want to discuss a temporary adjustment with your therapist before your quarterly review on May 11.
```

### 3.3 Dataset Size

| Task Family | Samples | Source |
|-------------|---------|--------|
| Crisis response (A) | 2,000 | Generated from WESAD feature ranges |
| Journal correlation (B) | 1,500 | Synthetically generated with varied patterns |
| Post-episode debrief (C) | 1,000 | Template + variable generation |
| Therapy report drafting (D) | 800 | Generated with varied structures |
| **Total** | **5,300** | |

---

## 4. Model Training

### 4.1 Random Forest (offline, separate from Gemma pipeline)

```python
from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import StratifiedKFold
import joblib

# Features: RMSSD, SDNN, HR mean, HR std, LF/HF, pNN50, age_group, time_of_day, sleep_hours
rf = RandomForestClassifier(
    n_estimators=500,
    max_depth=12,
    min_samples_leaf=5,
    class_weight='balanced',  # Handle class imbalance
    random_state=42
)

# 5-fold subject-level CV
skf = StratifiedKFold(n_splits=5)
# ... training loop ...

# Export to CoreML
import coremltools as ct
coreml_model = ct.converters.sklearn.convert(rf)
coreml_model.save("PanicGuardRF.mlpackage")
```

**Target metrics:** Recall (panic_onset) ≥ 0.92, AUROC ≥ 0.93

### 4.2 Gemma Fine-Tuning (QLoRA)

```yaml
# axolotl config: qlora-panic-guard-companion.yaml
base_model: google/gemma-4-2b-it
model_type: gemma
quantization:
  load_in_4bit: true
  qlora: true

lora_config:
  lora_r: 64
  lora_alpha: 128
  lora_dropout: 0.05
  target_modules:
    - q_proj
    - k_proj
    - v_proj
    - o_proj
    - gate_proj
    - up_proj
    - down_proj

sequence_len: 1024
max_steps: 1500
epochs: 2
optimizer: adamw_torch
lr: 2e-4
warmup_ratio: 0.1
cosine_annealing: true
bf16: true
gradient_accumulation_steps: 4
batch_size: 4  # Smaller batch for longer context (journal review needs more tokens)
```

**Important:** Unlike the RF, Gemma fine-tuning focuses on the **reasoning + generation** tasks (Task Families B, C, D). Gemma should NOT be fine-tuned on classification — that's RF's job and the PMC paper showed LLM classification fails.

### 4.3 Memory Requirements

| Model | Precision | Memory |
|-------|-----------|--------|
| Random Forest | N/A | ~50 MB (.mlmodel) |
| Gemma 2B + QLoRA 4-bit | 4-bit | ~1.2 GB |
| Training (gradients + optimizer) | bf16 | ~2.4 GB |
| **Total GPU needed** | | **~8 GB** (RTX 4090, M2 Pro, or similar) |

---

## 5. iOS Integration Architecture

### 5.1 App Data Flow

```
HEALTHKIT (Apple Watch)
    │
    │ HR + RR-interval samples (every 1-5s)
    ▼
HRVFeatureExtractor.swift
    │ Rolling 30-second buffer
    │ Computes: RMSSD, SDNN, HR mean, HR std
    ▼
┌─────────────────────────────────────┐
│  RandomForestClassifier.swift       │
│  CoreML .mlmodel                    │
│  Input: [rmssd, sdnn, hr_mean,     │
│          hr_std, age_group,         │
│          time_of_day, sleep_hours]  │
│  Output: panic_confidence (Float)   │
└────────────┬────────────────────────┘
             │ confidence ≥ 0.85
             ▼
┌─────────────────────────────────────┐
│  GemmaPromptBuilder.swift           │
│  Builds context-rich prompt from:   │
│  - RF output (confidence, features) │
│  - Episode history (last 7 days)    │
│  - User journal entries             │
│  - Upcoming calendar triggers       │
│  - Sleep history                    │
└────────────┬────────────────────────┘
             │
             ▼
┌─────────────────────────────────────┐
│  GemmaService.swift                 │
│  MediaPipe LLM Inference            │
│  Grammar-constrained JSON output    │
│  (explanation, interventions,       │
│   escalation_sms_draft)            │
└────────────┬────────────────────────┘
             │
             ▼
┌─────────────────────────────────────┐
│  GemmaDispatch.swift               │
│  Parse JSON → InterventionType      │
│  Dispatch via NotificationCenter    │
└────────────┬────────────────────────┘
             │
    ┌────────┴────────┐
    ▼                 ▼
InterventionService   EscalationService
(breathing/TTS)       (SMS via Cloudflare Worker)
```

### 5.2 Daily Companion Flow (non-crisis)

```
USER ACTION (anytime)
    │
    ▼
GemmaJournalView.swift
    │ Free-text input OR proactive nudge trigger
    ▼
┌─────────────────────────────────────┐
│  GemmaPromptBuilder.buildJournalPrompt() │
│  Attaches:                           │
│  - Recent journal entries            │
│  - Episode history (90 days)         │
│  - Calendar events                  │
│  - Sleep history                    │
│  - Trigger correlation context      │
└────────────┬────────────────────────┘
             │
             ▼
GemmaService.infer()
    │
    ▼
Response (correlation report OR nudge OR journal acknowledgment)
    │
    ├──► Display in JournalView
    ├──► Log to EpisodeNarrativeStore (SQLite)
    └──► If proactive trigger detected → schedule UserNotification
```

### 5.3 Data Storage Schema (SQLite)

```sql
-- Episode metadata (structured, existing)
CREATE TABLE episodes (
    id TEXT PRIMARY KEY,
    timestamp TEXT NOT NULL,
    duration_seconds INTEGER,
    peak_hr REAL,
    lowest_rmssd REAL,
    rf_confidence REAL,
    resolution TEXT,  -- 'user_dismissed', 'escalated', 'resolved'
    interventions_delivered TEXT,  -- JSON array
    created_at TEXT
);

-- Narrative journal entries (free-text)
CREATE TABLE journal_entries (
    id TEXT PRIMARY KEY,
    timestamp TEXT NOT NULL,
    content TEXT NOT NULL,
    emotional_tags TEXT,  -- JSON: ['anxious', 'stressed', 'okay']
    linked_episode_id TEXT,
    gemma_summary TEXT,  -- Gemma's one-line summary
    created_at TEXT
);

-- Trigger correlations (derived, refreshed after each episode)
CREATE TABLE trigger_correlations (
    id TEXT PRIMARY KEY,
    pattern_type TEXT,  -- 'time_of_day', 'calendar_event', 'sleep', 'journal_theme'
    pattern_description TEXT,
    confidence REAL,
    episode_count INTEGER,
    last_updated TEXT
);

-- Proactive nudges (logged)
CREATE TABLE nudge_log (
    id TEXT PRIMARY KEY,
    scheduled_time TEXT,
    delivered_time TEXT,
    trigger_context TEXT,  -- JSON describing why nudge was triggered
    gemma_output TEXT,
    user_responded INTEGER,  -- 0/1
    created_at TEXT
);

-- Therapy reports (generated weekly or on-demand)
CREATE TABLE therapy_reports (
    id TEXT PRIMARY KEY,
    week_start TEXT,
    week_end TEXT,
    episode_count INTEGER,
    total_duration_minutes REAL,
    dominant_patterns TEXT,  -- JSON
    gemma_report_body TEXT,  -- Full generated report
    created_at TEXT
);
```

---

## 6. Privacy Architecture

| Data | Storage | Leaves Device? |
|------|---------|----------------|
| HR/HRV (rolling buffer) | In-memory only | Never |
| RMSSD/SDNN features | In-memory only | Never |
| Baseline calibration | UserDefaults | Never |
| Emergency contact | Keychain | Only via SMS at escalation |
| Episode metadata | SQLite (local) | Never |
| Journal entries | SQLite (local) | Never |
| Calendar context | In-memory only | Never |
| Gemma model weights | On-device bundle | Never |
| Location (escalation) | Reverse geocoded locally | Only in emergency SMS |
| Proactive nudges | UserNotification (local) | Never |
| Therapy reports | SQLite (local) | Never |

**No account. No analytics. No crash reporting that sends data off-device. No cloud sync.**

The only egress is:
1. Emergency SMS (user-triggered, intentional)
2. User explicitly exports a therapy report to share

---

## 7. 14-Day Timeline

### Days 1–3: Foundation
| Day | Random Forest Track | Gemma Companion Track |
|-----|--------------------|-----------------------|
| 1 | Download WESAD, extract RMSSD/SDNN/HR features to CSV | Audit current Gemma prompt templates, design journal correlation prompts |
| 2 | Train RF on 5-fold CV, verify ≥99% accuracy on stress/baseline | Build instruction dataset (Task Families B, C, D) |
| 3 | Export RF to CoreML `.mlpackage` | Smoke-test Gemma fine-tuning on fold 1 |

### Days 4–6: Detection Core + Fine-Tuning
| Day | Task |
|-----|------|
| 4 | Wire RF into DetectionEngine, replace threshold logic |
| 5 | Fine-tune Gemma on Tasks B+C, first 500-step checkpoint |
| 6 | Full Gemma fine-tune run (1500 steps), evaluate on held-out journal tasks |

### Days 7–9: Daily Companion Mode
| Day | Task |
|-----|------|
| 7 | Build `GemmaJournalView` + `GemmaPromptBuilder.buildJournalPrompt()` |
| 8 | Implement `TriggerCorrelationEngine` (episodes + calendar + sleep analysis) |
| 9 | Implement proactive nudge scheduling via `UserNotifications` |

### Days 10–12: Integration + Crisis Polish
| Day | Task |
|-----|------|
| 10 | Wire daily companion into HomeView, add journal entry UI |
| 11 | Build `TherapyReportGenerator`, test Gemma report output quality |
| 12 | Full pipeline integration test, fix edge cases |

### Days 13–14: Polish + Demo
| Day | Task |
|-----|------|
| 13 | Demo mode update (RF confidence + Gemma daily companion demo scenario) |
| 14 | Final testing, README, repo cleanup |

---

## 8. What's Novel vs. Existing Apps

| Feature | Existing Apps | PanicGuard |
|---------|--------------|------------|
| Panic detection from wearables | Basic HR threshold | RF on RMSSD/HRV (99% acc) |
| AI response during episode | Generic script | Gemma-personalized explanation + intervention sequence |
| Proactive trigger identification | None | Gemma reviews 90-day history, finds correlations |
| Proactive nudges before triggers | None | Gemma generates context-aware preparation prompts |
| Post-episode narrative | Timestamp only | Gemma generates compassionate story + pattern note |
| Therapy report drafting | None | Gemma generates structured weekly summary |
| Daily journaling with AI | Generic sentiment | Gemma reads context, identifies sub-clinical trends |

---

## 9. File Manifest

```
/mnt/c/Users/abiyy/Documents/Work/panic-guard/
├── Detection/
│   ├── DetectionEngine.swift          ← Rewritten: calls RF, not thresholds
│   ├── HRVFeatureExtractor.swift       ← RMSSD/SDNN rolling buffer
│   └── PanicGuardRF.mlpackage         ← Trained Random Forest CoreML model
├── Gemma/
│   ├── GemmaService.swift              ← Inference (unchanged)
│   ├── GemmaDispatch.swift             ← Unchanged
│   ├── GemmaPromptBuilder.swift        ← Expanded: journal + correlation prompts
│   ├── GemmaJournalCorrelator.swift    ← NEW: trigger correlation engine
│   ├── GemmaTherapyReportGenerator.swift ← NEW: weekly report drafting
│   ├── GemmaProactiveNudgeScheduler.swift ← NEW: nudge scheduling
│   ├── GemmaPromptBuilder+Journal.swift ← NEW: journal-specific prompt templates
│   ├── GemmaPromptBuilder+Therapy.swift ← NEW: therapy report templates
│   └── FINE_TUNING_PLAN.md             ← this file
├── Models/
│   ├── PanicEpisode.swift              ← Unchanged
│   ├── JournalEntry.swift              ← NEW
│   ├── TriggerCorrelation.swift        ← NEW
│   └── TherapyReport.swift             ← NEW
├── Services/
│   ├── EpisodeLogger.swift            ← Expanded: journal + nudge log
│   └── CalendarIntegrationService.swift ← NEW: reads calendar events (optional)
├── Views/
│   ├── HomeView.swift                  ← Updated: daily companion entry point
│   ├── JournalView.swift               ← NEW: Gemma conversation interface
│   ├── TriggerCorrelationView.swift   ← NEW: shows identified patterns
│   └── TherapyReportView.swift         ← NEW: displays generated reports
├── project.yml                         ← Updated: MediaPipe + RF bundle
└── ios/
```

---

## 10. What May Not Fit the Timeline

| Task | Risk | Mitigation |
|------|------|------------|
| Calendar integration | HealthKit calendar access is limited | Make calendar entry manual (user tags events as "work", "stress") |
| WESAD download | Kaggle bot detection | Manual download or HuggingFace parquet alternative |
| Fine-tuning compute | 8GB VRAM required | Use Google Colab A100 or modal.com serverless GPU |
| Real push notifications | iOS permission required | Add during onboarding |
| Proactive nudge scheduling | Background app refresh limits | Use BGTaskScheduler, acknowledge iOS limitations |

---

## 11. References

1. **WESAD Dataset** — Schmidt et al., 2018. https://www.kaggle.com/datasets/orvile/wesad-wearable-stress-affect-detection-dataset
2. **PMC12526660** — Panic Attack Detection Using ML on Wearable Sensor Data, J Med Internet Res, 2025.
3. **Gemma Model Card** — google/gemma-4-2b-it, HuggingFace
4. **CoreML Random Forest** — Apple Developer Docs: `coremltools.converters.sklearn`
5. **Axolotl** — https://axolotl-ai-cloud.github.io/axolotl/
6. **TRL SFTTrainer** — https://huggingface.co/docs/trl
