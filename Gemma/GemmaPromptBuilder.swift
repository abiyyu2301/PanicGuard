import Foundation

// MARK: - Gemma Prompt Builder
/// Constructs structured prompts for Gemma 4 E2B inference
/// from physiological state and episode history
final class GemmaPromptBuilder {
    
    // MARK: - System Prompt (PRD Section 4.2)
    static let systemPrompt = """
You are Panic Guard, an on-device AI assistant helping users during panic and anxiety episodes.
You have access to 6 intervention tools. Your goal is to select the most appropriate intervention
based on the user's physiological state and provide a JSON response.

AVAILABLE INTERVENTIONS:
1. breathing_exercise - Guided deep breathing (4-4-4-4 pattern)
2. grounding_prompt - 5-4-3-2-1 sensory grounding exercise
3. haptic_rhythm - Calm haptic feedback pattern via watch
4. check_in - Ask user if they need help (60s response window)
5. escalate - Contact emergency services/trusted contacts
6. dismiss - No intervention needed, continue monitoring

DECISION GUIDELINES:
- High confidence (>=0.8) with severe physiological distress: immediate breathing_exercise or grounding_prompt
- Moderate confidence (0.5-0.8): check_in first to assess user state
- Low confidence (<0.5): dismiss unless other risk factors present
- Elevated heart rate + low HRV: breathing_exercise or haptic_rhythm
- Night time (10PM-6AM): prioritize non-disruptive interventions (haptic_rhythm)
- After recent episode (<2h): check_in before escalation
- Sleep deprivation: grounding_prompt over breathing_exercise

OUTPUT FORMAT (JSON only, no additional text):
{
    "action": "<intervention_name>",
    "confidence": "<confidence_level: high|moderate|low>",
    "reasoning": "<brief explanation of decision>"
}
"""
    
    // MARK: - Input State
    struct PhysiologicalState {
        let confidence: Float
        let heartRate: Float
        let hrv: Float
        let hrRMSDD: Float?
        let hrSDNN: Float?
        // MARK: - RF Feature Vector completeness (APP_AUDIT.md M4)
        /// Low-frequency / high-frequency power ratio from HRV spectral analysis
        let lfHfRatio: Float?
        /// Heart rate standard deviation over the detection window
        let hrStd: Float?
        // MARK: -
        let age: Int
        let timeOfDay: Date
        let recentSleepHours: Float?

        /// Recent episode count in last 24 hours
        var recentEpisodeCount: Int = 0

        /// Hours since last episode
        var hoursSinceLastEpisode: Float? = nil
    }
    
    // MARK: - Prompt Construction
    
    /// Builds a complete prompt string for Gemma inference
    static func buildPrompt(from state: PhysiologicalState) -> String {
        var prompt = "USER PHYSIOLOGICAL STATE:\n"
        prompt += "  confidence: \(String(format: "%.2f", state.confidence))\n"
        prompt += "  heart_rate: \(String(format: "%.1f", state.heartRate)) BPM\n"
        prompt += "  hrv: \(String(format: "%.1f", state.hrv)) ms\n"
        
        if let rmsdd = state.hrRMSDD {
            prompt += "  hr_rmssd: \(String(format: "%.1f", rmsdd)) ms\n"
        }
        if let sdnn = state.hrSDNN {
            prompt += "  hr_sdnn: \(String(format: "%.1f", sdnn)) ms\n"
        }
        if let lfHf = state.lfHfRatio {
            prompt += "  lf_hf_ratio: \(String(format: "%.2f", lfHf))\n"
        }
        if let hrStd = state.hrStd {
            prompt += "  hr_std: \(String(format: "%.1f", hrStd)) BPM\n"
        }

        prompt += "  age: \(state.age) years\n"
        prompt += "  time_of_day: \(formatTimeOfDay(state.timeOfDay))\n"
        
        if let sleep = state.recentSleepHours {
            prompt += "  recent_sleep_hours: \(String(format: "%.1f", sleep))\n"
        }
        
        // Context from recent episodes
        if state.recentEpisodeCount > 0 {
            prompt += "\nRECENT CONTEXT:\n"
            prompt += "  episodes_last_24h: \(state.recentEpisodeCount)\n"
            if let hoursSince = state.hoursSinceLastEpisode {
                prompt += "  hours_since_last_episode: \(String(format: "%.1f", hoursSince))\n"
            }
        }
        
        prompt += "\nBased on this state, select the most appropriate intervention."
        prompt += "\nRespond with ONLY valid JSON in the specified format."
        
        return prompt
    }
    
    /// Builds a check-in follow-up prompt after user response
    static func buildCheckInFollowUp(
        originalState: PhysiologicalState,
        userResponse: String
    ) -> String {
        var prompt = "USER CHECK-IN RESPONSE:\n"
        prompt += "\"\(userResponse)\"\n\n"
        prompt += "Original physiological state:\n"
        prompt += "  confidence: \(String(format: "%.2f", originalState.confidence))\n"
        prompt += "  heart_rate: \(String(format: "%.1f", originalState.heartRate)) BPM\n"
        prompt += "  hrv: \(String(format: "%.1f", originalState.hrv)) ms\n"
        
        if let sleep = originalState.recentSleepHours {
            prompt += "  recent_sleep_hours: \(String(format: "%.1f", sleep))\n"
        }
        
        prompt += "\nBased on this response, determine next action:\n"
        prompt += "- If user expresses distress/panic: escalate\n"
        prompt += "- If user confirms they're okay: dismiss\n"
        prompt += "- If unclear: check_in again or use grounding_prompt\n"
        prompt += "\nRespond with ONLY valid JSON in the specified format."
        
        return prompt
    }
    
    /// Builds a prompt for escalation decision
    static func buildEscalationPrompt(
        state: PhysiologicalState,
        escalationReason: String
    ) -> String {
        var prompt = "ESCALATION ASSESSMENT:\n"
        prompt += "  reason: \(escalationReason)\n"
        prompt += "  confidence: \(String(format: "%.2f", state.confidence))\n"
        prompt += "  heart_rate: \(String(format: "%.1f", state.heartRate)) BPM\n"
        prompt += "  hrv: \(String(format: "%.1f", state.hrv)) ms\n"
        prompt += "  age: \(state.age) years\n"
        
        if let sleep = state.recentSleepHours {
            prompt += "  recent_sleep_hours: \(String(format: "%.1f", sleep))\n"
        }
        
        prompt += "\nAssess whether to proceed with escalation or try alternative interventions."
        prompt += "\nRespond with ONLY valid JSON in the specified format."
        
        return prompt
    }
    
    // MARK: - Helpers
    
    private static func formatTimeOfDay(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let timeString = formatter.string(from: date)
        
        let hour = Calendar.current.component(.hour, from: date)
        
        let period: String
        switch hour {
        case 0..<6: period = "night_early"
        case 6..<9: period = "morning"
        case 9..<12: period = "late_morning"
        case 12..<14: period = "midday"
        case 14..<17: period = "afternoon"
        case 17..<21: period = "evening"
        default: period = "night_late"
        }
        
        return "\(timeString) (\(period))"
    }
    
    // MARK: - Pattern Explanation

    /// Builds a prompt for Gemma to explain a trigger correlation pattern to the user
    static func buildPatternExplanationPrompt(for correlation: EpisodeLogger.TriggerCorrelation) -> String {
        var prompt = "PATTERN EXPLANATION REQUEST:\n"
        prompt += "\nI need you to explain this panic trigger pattern in plain, calming language:\n"
        prompt += "\nPattern Type: \(correlation.patternType.displayName)"
        prompt += "\nDescription: \(correlation.patternDescription)"
        prompt += "\nSupporting Episodes: \(correlation.episodeCount)"
        prompt += "\nSupporting Details: \(correlation.supportingDetails)"
        prompt += "\nConfidence: \(correlation.confidenceLabel) (\(String(format: "%.0f", correlation.confidence * 100))%)\n"
        prompt += "\nPlease explain:\n"
        prompt += "1. What this pattern likely means for the user\n"
        prompt += "2. Why it might be contributing to panic episodes\n"
        prompt += "3. One or two simple things the user could consider to reduce episodes matching this pattern\n"
        prompt += "\nKeep the tone calm, supportive, and non-judgmental. Avoid medical jargon."
        prompt += "\nBe concise (3-5 sentences) and end on a reassuring note.\n"

        return prompt
    }

    // MARK: - Conversation History

    /// Simple conversation turn for context
    struct ConversationTurn: Codable {
        let role: String  // "user" or "assistant"
        let content: String
        let timestamp: Date
    }
    
    /// Builds a conversation context string
    static func buildConversationContext(
        turns: [ConversationTurn],
        maxTurns: Int = 5
    ) -> String {
        let recentTurns = turns.suffix(maxTurns)
        var context = "\nCONVERSATION HISTORY:\n"

        for turn in recentTurns {
            let role = turn.role == "user" ? "User" : "Assistant"
            context += "  [\(role)]: \(turn.content.prefix(100))...\n"
        }

        return context
    }

    // MARK: - Task Family B: Journal Correlation Analysis (Daily Companion)

    /// Episode summary entry for journal correlation input
    struct EpisodeSummary: Codable {
        let timestamp: Date
        let durationSeconds: Int
        let peakHR: Float
        let lowestRMSSD: Float?
        let resolution: String
        let calendarTag: String?
        let journalTheme: String?
    }

    /// Calendar event near an episode
    struct CalendarEvent: Codable {
        let title: String
        let timestamp: Date
        let tag: String // "work", "social", "exercise", "therapy", "travel"
    }

    /// Input data for journal correlation analysis
    struct JournalCorrelationInput: Codable {
        let episodesLast30Days: Int
        let peakTimeSlots: [String: Int]  // e.g. ["10pm-1am": 4, "2pm-4pm": 3]
        let avgSleepBeforeEpisode: Float?
        let avgSleepNonEpisodeDays: Float?
        let calendarTagsNearEpisodes: [String: Int]  // e.g. ["work meeting": 4, "travel": 2]
        let journalThemesNearEpisodes: [String]
        let upcomingEvents: [CalendarEvent]
        let recentJournalEntries: [String]
    }

    /// Builds a journal correlation / trigger-identification prompt (Family B)
    /// Gemma's daily companion task: correlate episodes + journal + calendar → trigger patterns
    static func buildJournalCorrelationPrompt(from input: JournalCorrelationInput) -> String {
        var prompt = "You are PanicGuard's daily companion. Review the user's recent history and identify patterns.\n\n"
        prompt += "Episode summary (last 30 days):\n"
        prompt += "- Total episodes: \(input.episodesLast30Days)\n"

        if !input.peakTimeSlots.isEmpty {
            prompt += "- Peak times: "
            prompt += input.peakTimeSlots.map { "\($0.key) (\($0.value) episodes)" }.joined(separator: ", ")
            prompt += "\n"
        }

        if let avgSleepEpisode = input.avgSleepBeforeEpisode {
            prompt += "- Average sleep before episode: \(String(format: "%.0f", avgSleepEpisode)) min\n"
        }
        if let avgSleepNonep = input.avgSleepNonEpisodeDays {
            prompt += "- Average sleep non-episode days: \(String(format: "%.0f", avgSleepNonep)) min\n"
        }

        if !input.calendarTagsNearEpisodes.isEmpty {
            prompt += "- Calendar tags near episodes: "
            prompt += input.calendarTagsNearEpisodes.map { "\"\($0.key)\" (\($0.value))" }.joined(separator: ", ")
            prompt += "\n"
        }

        if !input.journalThemesNearEpisodes.isEmpty {
            prompt += "- Journal themes near episodes: \(input.journalThemesNearEpisodes.joined(separator: ", "))\n"
        }

        if !input.upcomingEvents.isEmpty {
            prompt += "\nUpcoming calendar (next 7 days):\n"
            for event in input.upcomingEvents {
                let formatter = DateFormatter()
                formatter.dateFormat = "MMM d, ha"
                prompt += "- \(formatter.string(from: event.timestamp)): \"\(event.title)\" (\(event.tag))\n"
            }
        }

        if !input.recentJournalEntries.isEmpty {
            prompt += "\nRecent journal entries:\n"
            for (i, entry) in input.recentJournalEntries.prefix(5).enumerated() {
                prompt += "[\(i + 1)] \(entry.prefix(200))\n"
            }
        }

        prompt += """
        \nGenerate:
        1. A correlation report identifying the strongest trigger patterns
        2. A proactive nudge for the highest-risk upcoming calendar event (or say "no high-risk events detected")
        3. A suggested journal prompt to help the user explore a recurring theme
        \nRespond with valid JSON:
        {
            "correlation_report": "<2-3 sentence narrative of the strongest patterns>",
            "proactive_nudge": "<specific, empathetic notification text or null>",
            "journal_prompt": "<1-sentence journal prompt or null>"
        }
        """

        return prompt
    }

    // MARK: - Task Family C: Post-Episode Debrief

    /// Input for post-episode narrative debrief
    struct PostEpisodeDebriefInput: Codable {
        let episodeNumber: Int
        let timestamp: Date
        let peakHR: Float
        let lowestRMSSD: Float?
        let personalRMSDDBaseline: Float?
        let durationSeconds: Int
        let resolution: String  // "user_dismissed", "escalated", "resolved"
        let interventionsDelivered: [String]
        let sleepPriorNight: Float?
        let episodeCountLast7Days: Int
        let journalEntryIfAvailable: String?
    }

    /// Builds a post-episode narrative debrief prompt (Family C)
    /// Generates a compassionate, clinically-useful episode story
    static func buildPostEpisodeDebriefPrompt(from input: PostEpisodeDebriefInput) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy, h:mma"

        var prompt = "Generate a narrative debrief for this episode. Keep it compassionate, factual, and clinically useful.\n\n"
        prompt += "Biometric data:\n"
        prompt += "- Detection time: \(formatter.string(from: input.timestamp))\n"
        prompt += "- Peak HR: \(String(format: "%.0f", input.peakHR)) bpm\n"

        if let lowest = input.lowestRMSSD {
            prompt += "- Lowest RMSSD: \(String(format: "%.0f", lowest)) ms\n"
        }
        if let baseline = input.personalRMSDDBaseline {
            prompt += "- Your personal RMSSD baseline: \(String(format: "%.0f", baseline)) ms\n"
        }

        let minutes = input.durationSeconds / 60
        let seconds = input.durationSeconds % 60
        prompt += "- Duration: \(minutes)m \(seconds)s\n"
        prompt += "- Resolution: \(input.resolution)\n"

        if !input.interventionsDelivered.isEmpty {
            prompt += "- Interventions delivered: \(input.interventionsDelivered.joined(separator: ", "))\n"
        }

        if let sleep = input.sleepPriorNight {
            prompt += "- Sleep prior night: \(String(format: "%.0f", sleep)) min\n"
        }

        prompt += "- Episode count last 7 days: \(input.episodeCountLast7Days)\n"

        if let journal = input.journalEntryIfAvailable, !journal.isEmpty {
            prompt += "\nUser journal entry:\n\"\(journal.prefix(300))\"\n"
        }

        prompt += """
        \nWrite a narrative debrief in this format:
        Episode #\(input.episodeNumber) — [date]
        Duration: [Xm Xs] | Peak HR: [X]bpm | Lowest RMSSD: [X]ms ([above/below] your personal baseline of [X]ms)

        What happened: [2-3 sentences on physiological context, triggers if identifiable]

        What helped: [acknowledge user actions, note recovery trajectory]

        Pattern note: [if 3+ episodes in 7 days or recurring context, suggest discussing with therapist]
        """

        return prompt
    }

    // MARK: - Task Family D: Therapy Report Drafting

    /// Input for weekly therapy report
    struct TherapyReportInput: Codable {
        let weekStart: Date
        let weekEnd: Date
        let episodesThisWeek: [EpisodeSummary]
        let totalEpisodeCount: Int
        let dominantPatterns: [String: Int]  // e.g. ["evening": 3, "work-related": 2]
        let averageSleepThisWeek: Float?
        let journalingActivityThisWeek: Int  // number of entries
        let therapySessionsAttended: Int
        let userNotes: String?
    }

    /// Builds a therapy report drafting prompt (Family D)
    /// Generates a structured weekly summary for the user's therapist
    static func buildTherapyReportPrompt(from input: TherapyReportInput) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"

        let weekRange = "\(formatter.string(from: input.weekStart)) – \(formatter.string(from: input.weekEnd))"

        var prompt = "You are PanicGuard's clinical documentation assistant. Draft a structured weekly summary for the user's therapist.\n\n"
        prompt += "Report period: \(weekRange)\n\n"

        prompt += "Episode log:\n"
        if input.episodesThisWeek.isEmpty {
            prompt += "- No episodes recorded this week.\n"
        } else {
            for ep in input.episodesThisWeek {
                let epFormatter = DateFormatter()
                epFormatter.dateFormat = "EEE, MMM d, h:mma"
                prompt += "- \(epFormatter.string(from: ep.timestamp)): peak HR \(String(format: "%.0f", ep.peakHR)) bpm, "
                if let rmssd = ep.lowestRMSSD { prompt += "lowest RMSSD \(String(format: "%.0f", rmssd)) ms, " }
                prompt += "resolved: \(ep.resolution)\n"
            }
        }

        prompt += "\nSummary statistics:\n"
        prompt += "- Total episodes: \(input.totalEpisodeCount)\n"

        if !input.dominantPatterns.isEmpty {
            prompt += "- Dominant patterns: "
            prompt += input.dominantPatterns.map { "\($0.key) (\($0.value))" }.joined(separator: ", ")
            prompt += "\n"
        }

        if let avgSleep = input.averageSleepThisWeek {
            prompt += "- Average sleep this week: \(String(format: "%.1f", avgSleep)) hours\n"
        }

        prompt += "- Journaling activity: \(input.journalingActivityThisWeek) entries\n"
        prompt += "- Therapy sessions attended: \(input.therapySessionsAttended)\n"

        if let notes = input.userNotes, !notes.isEmpty {
            prompt += "\nUser notes for therapist:\n\"\(notes.prefix(500))\"\n"
        }

        prompt += """
        \nDraft a professional therapy report in this structure:
        ## PanicGuard Weekly Report: [date range]

        ### Episode Summary
        [bullet points on each episode — timing, duration, physiological markers, resolution]

        ### Pattern Observations
        [identify any recurring themes, times of day, trigger categories]

        ### Recommendations for Next Session
        [2-3 bullet points: questions to explore, patterns to discuss, treatment adjustments to consider]

        ### Supporting Data
        - Total episodes this week: N
        - Average sleep: X.X hours
        - Journal entries: N
        - Therapy sessions: N

        Keep the tone clinical but warm. Be specific about physiological findings (HR, RMSSD) when available.
        """

        return prompt
    }
}
