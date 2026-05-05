import SwiftUI

struct GroundingPromptView: View {
    @State private var currentStep: Int = 0
    @State private var completedItems: Set<Int> = []
    @State private var showStep: Bool = false
    
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    
    private let prompts: [(count: Int, prompt: String, suffix: String)] = [
        (5, "Name 5 things you can see", "things you can see"),
        (4, "Name 4 things you can touch", "things you can touch"),
        (3, "Name 3 things you can hear", "things you can hear"),
        (2, "Name 2 things you can smell", "things you can smell"),
        (1, "Name 1 thing you can taste", "thing you can taste")
    ]
    
    var body: some View {
        VStack(spacing: 24) {
            Text("Grounding Exercise")
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
            
            Text("Tap each number as you name them")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.7))
            
            Spacer()
            
            if reduceMotion {
                staticContent
            } else {
                animatedContent
            }
            
            Spacer()
            
            progressIndicator
        }
        .padding(.horizontal, 32)
        .onAppear {
            if !reduceMotion {
                showStep = true
            }
        }
    }
    
    @ViewBuilder
    private var staticContent: some View {
        VStack(spacing: 16) {
            ForEach(0..<5, id: \.self) { index in
                HStack(spacing: 12) {
                    Text("\(prompts[index].count)")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(Color(hex: "4ECDC4"))
                        .frame(width: 40, height: 40)
                        .background(Color.white.opacity(0.15))
                        .clipShape(Circle())
                    
                    Text(prompts[index].prompt)
                        .font(.body)
                        .foregroundColor(.white.opacity(0.9))
                    
                    Spacer()
                }
                .padding(.vertical, 8)
            }
        }
    }
    
    @ViewBuilder
    private var animatedContent: some View {
        VStack(spacing: 16) {
            if currentStep < prompts.count {
                let step = prompts[currentStep]
                
                VStack(spacing: 20) {
                    Text(step.prompt)
                        .font(.system(size: 22, weight: .medium, design: .rounded))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
                    
                    HStack(spacing: 16) {
                        ForEach(0..<step.count, id: \.self) { itemIndex in
                            let globalIndex = currentStep * 10 + itemIndex
                            Button(action: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    completedItems.insert(globalIndex)
                                    checkStepCompletion(for: itemIndex, total: step.count)
                                }
                            }) {
                                Text("\(step.count - itemIndex)")
                                    .font(.system(size: 24, weight: .bold, design: .rounded))
                                    .foregroundColor(completedItems.contains(globalIndex) ? .white : Color(hex: "4ECDC4"))
                                    .frame(width: 56, height: 56)
                                    .background(
                                        completedItems.contains(globalIndex)
                                            ? Color(hex: "4ECDC4")
                                            : Color.white.opacity(0.15)
                                    )
                                    .clipShape(Circle())
                                    .scaleEffect(completedItems.contains(globalIndex) ? 1.1 : 1.0)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .id(currentStep)
            } else {
                completedView
            }
        }
        .animation(.easeInOut(duration: 0.4), value: currentStep)
    }
    
    private var completedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(Color(hex: "4ECDC4"))
            
            Text("Well done!")
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
            
            Text("You've completed the grounding exercise")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .transition(.scale.combined(with: .opacity))
    }
    
    private var progressIndicator: some View {
        HStack(spacing: 8) {
            ForEach(0..<5, id: \.self) { index in
                Circle()
                    .fill(index <= currentStep ? Color(hex: "4ECDC4") : Color.white.opacity(0.3))
                    .frame(width: 10, height: 10)
                    .animation(.easeInOut(duration: 0.3), value: currentStep)
            }
        }
    }
    
    private func checkStepCompletion(for itemIndex: Int, total: Int) {
        let stepItems = (0..<total).map { currentStep * 10 + $0 }
        let completedInStep = stepItems.filter { completedItems.contains($0) }.count
        
        if completedInStep == total {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation {
                    currentStep += 1
                }
            }
        }
    }
}

#Preview {
    ZStack {
        Color(hex: "1a1a2e").ignoresSafeArea()
        GroundingPromptView()
    }
}
