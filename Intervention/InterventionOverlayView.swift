import SwiftUI

struct InterventionOverlayView: View {
    @ObservedObject var interventionService = InterventionService.shared
    
    var body: some View {
        ZStack {
            Color(hex: "1a1a2e")
                .ignoresSafeArea()
                .opacity(0.95)
            
            VStack(spacing: 0) {
                headerSection
                    .padding(.top, 60)
                
                Spacer()
                
                contentSection
                    .padding(.horizontal, 24)
                
                Spacer()
                
                footerSection
                    .padding(.horizontal, 32)
                    .padding(.bottom, 48)
            }
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }
    
    private var headerSection: some View {
        VStack(spacing: 8) {
            Text(interventionTitle)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
            
            Text(interventionSubtitle)
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(.white.opacity(0.6))
        }
    }
    
    @ViewBuilder
    private var contentSection: some View {
        switch interventionService.currentIntervention {
        case .breathingExercise:
            BreathingCircleView()
        case .groundingPrompt:
            GroundingPromptView()
        case .hapticRhythm:
            HapticRhythmView()
        case .checkIn:
            CheckInView()
        case .escalate, .dismiss, .none:
            EmptyView()
        }
    }
    
    private var footerSection: some View {
        VStack(spacing: 16) {
            if interventionService.currentIntervention != .checkIn {
                ImOkayButton()
            }
            
            progressBar
        }
    }
    
    private var progressBar: some View {
        VStack(spacing: 8) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.2))
                        .frame(height: 8)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(hex: "4ECDC4"))
                        .frame(width: geometry.size.width * interventionService.interventionProgress, height: 8)
                        .animation(.linear(duration: 0.5), value: interventionService.interventionProgress)
                }
            }
            .frame(height: 8)
            
            Text("\(Int(interventionService.interventionProgress * 100))% complete")
                .font(.caption)
                .foregroundColor(.white.opacity(0.5))
        }
    }
    
    private var interventionTitle: String {
        switch interventionService.currentIntervention {
        case .breathingExercise:
            return "Breathing Exercise"
        case .groundingPrompt:
            return "Grounding Exercise"
        case .hapticRhythm:
            return "Haptic Rhythm"
        case .checkIn:
            return "Check In"
        case .escalate, .dismiss, .none:
            return ""
        }
    }
    
    private var interventionSubtitle: String {
        switch interventionService.currentIntervention {
        case .breathingExercise:
            let cycle = min(Int(interventionService.interventionProgress * 4) + 1, 4)
            return "Breathing exercise — \(cycle) of 4 cycles"
        case .groundingPrompt:
            return "Focus on your senses"
        case .hapticRhythm:
            return "Follow the haptic pattern"
        case .checkIn:
            return "Please respond when ready"
        case .escalate, .dismiss, .none:
            return ""
        }
    }
}

struct HapticRhythmView: View {
    @State private var isPulsing: Bool = false
    
    var body: some View {
        VStack(spacing: 32) {
            Text("Feel the Rhythm")
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
            
            Image(systemName: "waveform.path")
                .font(.system(size: 80))
                .foregroundColor(Color(hex: "4ECDC4"))
                .scaleEffect(isPulsing ? 1.2 : 0.8)
                .animation(
                    .easeInOut(duration: 0.5)
                        .repeatForever(autoreverses: true),
                    value: isPulsing
                )
            
            Text("Your Apple Watch will pulse\nin a calm, rhythmic pattern")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .onAppear {
            isPulsing = true
        }
    }
}

struct CheckInView: View {
    @State private var responseText: String = ""
    @FocusState private var isTextFieldFocused: Bool
    
    var body: some View {
        VStack(spacing: 32) {
            Text("Are you okay?")
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
            
            Text("If you need help, please respond.\nOtherwise, tap \"I'm Okay\" below.")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
            
            TextField("Type your response...", text: $responseText)
                .textFieldStyle(.plain)
                .padding()
                .background(Color.white.opacity(0.1))
                .cornerRadius(12)
                .foregroundColor(.white)
                .focused($isTextFieldFocused)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal)
    }
}

#Preview {
    InterventionOverlayView()
}
