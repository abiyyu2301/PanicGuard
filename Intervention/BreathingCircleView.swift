import SwiftUI

struct BreathingCircleView: View {
    @State private var scale: CGFloat = 0.4
    @State private var currentPhase: BreathPhase = .inhale
    @State private var cycleCount: Int = 0
    
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    
    private let totalCycles = 4
    private let phaseDuration: TimeInterval = 4.0
    
    enum BreathPhase: String {
        case inhale = "Breathe In"
        case holdIn = "Hold"
        case exhale = "Breathe Out"
        case holdOut = "Hold"
    }
    
    var body: some View {
        VStack(spacing: 32) {
            Text(currentPhase.rawValue)
                .font(.system(size: 28, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.9))
                .animation(reduceMotion ? .none : .easeInOut(duration: 0.3), value: currentPhase)
            
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(hex: "4ECDC4").opacity(0.8),
                                Color(hex: "45B7AF").opacity(0.6),
                                Color(hex: "1a1a2e").opacity(0.3)
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 150
                        )
                    )
                    .frame(width: 250, height: 250)
                    .scaleEffect(scale)
                    .animation(
                        reduceMotion ? .none : .easeInOut(duration: phaseDuration),
                        value: scale
                    )
                
                Circle()
                    .stroke(Color.white.opacity(0.3), lineWidth: 2)
                    .frame(width: 260, height: 260)
                    .scaleEffect(scale)
                    .animation(
                        reduceMotion ? .none : .easeInOut(duration: phaseDuration),
                        value: scale
                    )
            }
            
            Text("Cycle \(cycleCount + 1) of \(totalCycles)")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.7))
        }
        .onAppear {
            if !reduceMotion {
                startBreathingAnimation()
            } else {
                scale = 1.0
                currentPhase = .inhale
            }
        }
    }
    
    private func startBreathingAnimation() {
        func runCycle() {
            guard cycleCount < totalCycles else { return }
            
            // Inhale: 0.4 -> 1.0
            currentPhase = .inhale
            withAnimation(.easeInOut(duration: phaseDuration)) {
                scale = 1.0
            }
            
            // Hold after inhale
            DispatchQueue.main.asyncAfter(deadline: .now() + phaseDuration) {
                currentPhase = .holdIn
            }
            
            // Exhale: 1.0 -> 0.4
            DispatchQueue.main.asyncAfter(deadline: .now() + phaseDuration * 2) {
                currentPhase = .exhale
                withAnimation(.easeInOut(duration: phaseDuration)) {
                    scale = 0.4
                }
            }
            
            // Hold after exhale, then next cycle
            DispatchQueue.main.asyncAfter(deadline: .now() + phaseDuration * 3) {
                currentPhase = .holdOut
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + phaseDuration * 4) {
                cycleCount += 1
                runCycle()
            }
        }
        
        runCycle()
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

#Preview {
    ZStack {
        Color(hex: "1a1a2e").ignoresSafeArea()
        BreathingCircleView()
    }
}
