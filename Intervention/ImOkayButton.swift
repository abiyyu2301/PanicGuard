import SwiftUI
import AVFoundation

struct ImOkayButton: View {
    @ObservedObject var interventionService = InterventionService.shared
    @State private var isPressed: Bool = false
    
    private let buttonHeight: CGFloat = 88
    
    var body: some View {
        Button(action: handleTap) {
            HStack(spacing: 16) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 32))
                
                Text("I'm Okay")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: buttonHeight)
            .background(
                LinearGradient(
                    colors: [
                        Color(hex: "4ECDC4"),
                        Color(hex: "45B7AF")
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: buttonHeight / 2))
            .shadow(color: Color(hex: "4ECDC4").opacity(0.4), radius: 12, x: 0, y: 6)
            .scaleEffect(isPressed ? 0.96 : 1.0)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("I'm Okay - dismisses intervention")
        .accessibilityHint("Double tap to confirm you are okay and dismiss the current exercise")
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    withAnimation(.easeInOut(duration: 0.1)) {
                        isPressed = true
                    }
                }
                .onEnded { _ in
                    withAnimation(.easeInOut(duration: 0.1)) {
                        isPressed = false
                    }
                }
        )
    }
    
    private func handleTap() {
        speakConfirmation()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            interventionService.dismissIntervention()
        }
    }
    
    private func speakConfirmation() {
        let utterance = AVSpeechUtterance(string: "Got it. Glad you're okay.")
        utterance.rate = 0.5
        utterance.pitchMultiplier = 1.0
        utterance.volume = 0.8
        
        let synthesizer = AVSpeechSynthesizer()
        synthesizer.speak(utterance)
    }
}

#Preview {
    ZStack {
        Color(hex: "1a1a2e").ignoresSafeArea()
        VStack {
            Spacer()
            ImOkayButton()
                .padding(.horizontal, 32)
                .padding(.bottom, 48)
        }
    }
}
