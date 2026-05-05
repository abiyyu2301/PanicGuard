import CoreHaptics
import UIKit

final class HapticService {
    static let shared = HapticService()
    
    private var engine: CHHapticPatternPlayer?
    private var supportsHaptics: Bool = false
    
    private init() {
        setupHapticEngine()
    }
    
    private func setupHapticEngine() {
        guard CHHapticPattern.capabilitiesForHardware().supportsHaptics else {
            supportsHaptics = false
            print("HapticService: Hardware does not support haptics")
            return
        }
        
        supportsHaptics = true
        
        do {
            let engine = try CHHapticPatternEngine()
            self.engine = try engine.makePlayer(with: CHHapticPattern())
            print("HapticService: Engine initialized successfully")
        } catch {
            print("HapticService: Failed to create haptic engine: \(error.localizedDescription)")
        }
    }
    
    /// Plays a calm, rhythmic haptic pattern: 3 pulses, 0.5s interval, 4x repeat
    /// Not a sharp alarm - designed for gentle reassurance
    func playCalmRhythm() {
        guard supportsHaptics else {
            print("HapticService: Haptics not supported, falling back to UIKit feedback")
            playFallbackFeedback()
            return
        }
        
        do {
            let pattern = try createCalmRhythmPattern()
            let player = try engine?.makePlayer(with: pattern)
            try player?.start(atTime: CHHapticPatternPlayer.currentTime)
            print("HapticService: Calm rhythm started")
        } catch {
            print("HapticService: Failed to play haptic pattern: \(error.localizedDescription)")
            playFallbackFeedback()
        }
    }
    
    /// Creates the 3-pulse, 0.5s interval, 4x repeat pattern
    private func createCalmRhythmPattern() throws -> CHHapticPattern {
        // Pattern: 3 pulses with 0.5s interval, repeated 4 times
        // Total duration per cycle: 3 * 0.1s (pulse) + 2 * 0.4s (intervals) = 1.1s
        // But we want 0.5s between pulse starts: 0.5s * 3 = 1.5s per cycle
        // Actually: pulse (0.1s) + wait (0.4s) + pulse (0.1s) + wait (0.4s) + pulse (0.1s) + wait until repeat
        
        var events: [CHHapticEvent] = []
        
        // Create 4 complete cycles
        for cycle in 0..<4 {
            let cycleOffset = TimeInterval(cycle) * 1.5 // 1.5s per cycle
            
            // Pulse 1
            events.append(CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.6),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.3)
                ],
                relativeTime: cycleOffset
            ))
            
            // Wait 0.4s
            
            // Pulse 2
            events.append(CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.6),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.3)
                ],
                relativeTime: cycleOffset + 0.5
            ))
            
            // Wait 0.4s
            
            // Pulse 3
            events.append(CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.6),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.3)
                ],
                relativeTime: cycleOffset + 1.0
            ))
            
            // Wait 0.5s until next cycle (total 1.5s per cycle)
        }
        
        return try CHHapticPattern(events: events, parameters: [])
    }
    
    /// Plays a single gentle pulse for immediate feedback
    func playGentlePulse() {
        guard supportsHaptics else {
            playFallbackFeedback()
            return
        }
        
        do {
            let event = CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.4),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.2)
                ],
                relativeTime: 0
            )
            
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try engine?.makePlayer(with: pattern)
            try player?.start(atTime: CHHapticPatternPlayer.currentTime)
        } catch {
            print("HapticService: Failed to play gentle pulse: \(error.localizedDescription)")
            playFallbackFeedback()
        }
    }
    
    /// Stops any currently playing haptic pattern
    func stopHaptics() {
        do {
            try engine?.stop()
            print("HapticService: Stopped haptics")
        } catch {
            print("HapticService: Failed to stop haptics: \(error.localizedDescription)")
        }
    }
    
    /// UIKit fallback for devices without CoreHaptics
    private func playFallbackFeedback() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred()
    }
    
    /// Called when intervention is triggered to play the calm rhythm
    func notifyInterventionStarted() {
        playCalmRhythm()
    }
    
    /// Called when intervention is dismissed
    func notifyInterventionDismissed() {
        stopHaptics()
    }
}
