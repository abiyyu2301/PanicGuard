import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var appState: AppState
    @State private var currentStep: Int = 0
    @State private var contact = EmergencyContact.placeholder
    @State private var isCalibrating = false
    @State private var calibrationProgress: Double = 0.0

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Progress indicator
                HStack(spacing: 8) {
                    ForEach(0..<5) { index in
                        Circle()
                            .fill(index <= currentStep ? Color.blue : Color.gray.opacity(0.3))
                            .frame(width: 8, height: 8)
                    }
                }
                .padding(.top)

                TabView(selection: $currentStep) {
                    welcomeStep.tag(0)
                    healthKitStep.tag(1)
                    calibrationStep.tag(2)
                    contactStep.tag(3)
                    doneStep.tag(4)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut, value: currentStep)

                // Navigation buttons
                HStack {
                    if currentStep > 0 {
                        Button("Back") {
                            withAnimation {
                                currentStep -= 1
                            }
                        }
                        .foregroundColor(.secondary)
                    }

                    Spacer()

                    if currentStep < 4 {
                        Button(currentStep == 2 && isCalibrating ? "Calibrating..." : "Next") {
                            handleNext()
                        }
                        .disabled(currentStep == 2 && isCalibrating)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
    }

    // MARK: - Steps
    private var welcomeStep: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "heart.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.blue)
            Text("Welcome to PanicGuard")
                .font(.title)
                .fontWeight(.bold)
            Text("PanicGuard runs entirely on your phone. Your data never leaves your device.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
    }

    private var healthKitStep: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "heart.text.square.fill")
                .font(.system(size: 80))
                .foregroundColor(.red)
            Text("Connect Health Data")
                .font(.title)
                .fontWeight(.bold)
            Text("PanicGuard needs access to your heart rate and heart rate variability data from Apple Health.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Allow HealthKit Access") {
                Task {
                    await HealthKitService.shared.requestAuthorization()
                }
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
    }

    private var calibrationStep: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 80))
                .foregroundColor(.green)
            Text("Calibrate Baseline")
                .font(.title)
                .fontWeight(.bold)
            Text("Please sit still for 5 minutes while we measure your resting heart rate and HRV.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            if isCalibrating {
                ProgressView(value: calibrationProgress)
                    .progressViewStyle(.linear)
                    .frame(width: 200)

                Text("\(Int(calibrationProgress * 100))% complete")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
    }

    private var contactStep: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 80))
                .foregroundColor(.orange)
            Text("Emergency Contact")
                .font(.title)
                .fontWeight(.bold)
            Text("If we can't reach you, we'll contact this person.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            VStack(spacing: 16) {
                TextField("Name", text: $contact.name)
                    .textFieldStyle(.roundedBorder)
                TextField("Phone", text: $contact.phone)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.phonePad)
                TextField("Relationship", text: $contact.relationship)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(.horizontal, 32)

            Spacer()
        }
    }

    private var doneStep: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 80))
                .foregroundColor(.green)
            Text("You're Protected")
                .font(.title)
                .fontWeight(.bold)
            Text("PanicGuard is now monitoring your well-being. We're here when you need us.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
    }

    // MARK: - Actions
    private func handleNext() {
        if currentStep == 2 {
            startCalibration()
        } else if currentStep < 4 {
            withAnimation {
                currentStep += 1
            }
        } else {
            saveContact()
            appState.completeOnboarding()
        }
    }

    private func startCalibration() {
        isCalibrating = true
        calibrationProgress = 0.0

        // Simulate calibration
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
            DispatchQueue.main.async {
                calibrationProgress += 0.0033 // ~5 min / 0.1s intervals
                if calibrationProgress >= 1.0 {
                    timer.invalidate()
                    isCalibrating = false
                    DetectionEngine.shared.calibrateBaseline(
                        heartRate: Double.random(in: 65...75),
                        hrv: Double.random(in: 40...50)
                    )
                    currentStep = 3
                }
            }
        }
    }

    private func saveContact() {
        UserDefaults.standard.set(contact.name, forKey: "emergencyContactName")
        UserDefaults.standard.set(contact.phone, forKey: "emergencyContactPhone")
        UserDefaults.standard.set(contact.relationship, forKey: "emergencyContactRelationship")
    }
}

#Preview {
    OnboardingView()
        .environmentObject(AppState())
}
