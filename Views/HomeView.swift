import SwiftUI

struct HomeView: View {
    @EnvironmentObject var appState: AppState
    @State private var pulseAnimation: Bool = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // MARK: - Status + Vital Signs
                    VStack(spacing: 16) {
                        // Status indicator with pulse
                        VStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(pulseAnimation ? Color.green.opacity(0.3) : Color.green.opacity(0.1))
                                    .frame(width: 24, height: 24)
                                    .scaleEffect(pulseAnimation ? 1.5 : 1.0)
                                    .animation(
                                        .easeInOut(duration: 1.5).repeatForever(autoreverses: true),
                                        value: pulseAnimation
                                    )

                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 12, height: 12)
                            }
                            .onAppear {
                                pulseAnimation = true
                            }

                            Text("Monitoring active")
                                .font(.headline)
                                .foregroundColor(.primary)
                        }

                        // Vital signs display
                        HStack(spacing: 40) {
                            VStack(spacing: 4) {
                                Text("HR")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(appState.currentHeartRate != nil ? "\(Int(appState.currentHeartRate!))" : "--")
                                    .font(.title2)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.primary)
                                Text("bpm")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }

                            VStack(spacing: 4) {
                                Text("HRV")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(appState.currentHRV != nil ? "\(Int(appState.currentHRV!))" : "--")
                                    .font(.title2)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.primary)
                                Text("ms")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                    }
                    .padding(.top, 8)

                    // MARK: - Daily Companion Entry Points
                    VStack(spacing: 12) {
                        Text("Daily Companion")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        // Journal entry — primary CTA
                        NavigationLink(value: AppState.CompanionDestination.journal) {
                            HStack {
                                Image(systemName: "book")
                                    .foregroundColor(.blue)
                                    .frame(width: 28)
                                Text("Journal")
                                    .foregroundColor(.primary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                        }
                        .buttonStyle(.plain)

                        // Trigger patterns with badge
                        NavigationLink(value: AppState.CompanionDestination.patterns) {
                            HStack {
                                Image(systemName: "sparkles")
                                    .foregroundColor(.purple)
                                    .frame(width: 28)
                                Text("Trigger Patterns")
                                    .foregroundColor(.primary)
                                Spacer()
                                if appState.hasNewPatterns {
                                    Circle()
                                        .fill(Color.purple)
                                        .frame(width: 8, height: 8)
                                        .overlay(
                                            Circle()
                                                .stroke(Color.purple.opacity(0.3), lineWidth: 2)
                                                .scaleEffect(1.5)
                                        )
                                }
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                        }
                        .buttonStyle(.plain)

                        // Weekly summary with badge
                        NavigationLink(value: AppState.CompanionDestination.weeklySummary) {
                            HStack {
                                Image(systemName: "doc.text")
                                    .foregroundColor(.orange)
                                    .frame(width: 28)
                                Text("Weekly Summary")
                                    .foregroundColor(.primary)
                                Spacer()
                                if appState.weeklySummaryReady {
                                    Text("Ready")
                                        .font(.caption2)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(Color.orange)
                                        .cornerRadius(8)
                                }
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                        }
                        .buttonStyle(.plain)
                    }

                    // MARK: - Emergency contact
                    if let contactName = UserDefaults.standard.string(forKey: "emergencyContactName"), !contactName.isEmpty {
                        HStack {
                            Image(systemName: "person.crop.circle.badge.exclamationmark")
                                .foregroundColor(.orange)
                            Text("Emergency contact: \(contactName)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    // MARK: - Settings
                    NavigationLink(destination: SettingsView()) {
                        HStack {
                            Image(systemName: "gearshape")
                            Text("Settings")
                        }
                        .foregroundColor(.primary)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                    }
                }
                .padding(24)
            }
            .navigationTitle("PanicGuard")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: AppState.CompanionDestination.self) { destination in
                switch destination {
                case .journal:
                    JournalView()
                case .patterns:
                    TriggerCorrelationView()
                case .weeklySummary:
                    TherapyReportView()
                }
            }
        }
    }
}

// MARK: - Placeholder companion views (stubs until Views/JournalView etc. are implemented)
struct PlaceholderCompanionView: View {
    let title: String
    let icon: String
    let description: String

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text(title)
                .font(.title2)
                .fontWeight(.semibold)
            Text(description)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
        .padding(.top, 48)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        HomeView()
            .environmentObject(AppState())
    }
}
