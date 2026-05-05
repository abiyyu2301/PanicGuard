import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @AppStorage("hapticEnabled") private var hapticEnabled = true
    @AppStorage("demoMode") private var demoMode = false
    @AppStorage("autoEscalate") private var autoEscalate = true
    @AppStorage("companionNudgesEnabled") private var companionNudgesEnabled = true
    @AppStorage("nudgeBeforeTriggers") private var nudgeBeforeTriggers = true
    @AppStorage("nudgeWeeklySummary") private var nudgeWeeklySummary = true
    @AppStorage("nudgeJournalReminder") private var nudgeJournalReminder = false
    @State private var contactName: String = ""
    @State private var contactPhone: String = ""
    @State private var contactRelationship: String = ""
    @State private var showingRecalibrate = false

    var body: some View {
        Form {
            Section("Emergency Contact") {
                TextField("Name", text: $contactName)
                TextField("Phone", text: $contactPhone)
                    .keyboardType(.phonePad)
                TextField("Relationship", text: $contactRelationship)

                Button("Save Contact") {
                    saveContact()
                }
            }

            Section("Detection") {
                Button("Re-run Calibration") {
                    showingRecalibrate = true
                }
                .foregroundColor(.blue)

                Toggle("Haptic Feedback", isOn: $hapticEnabled)
            }

            Section("Daily Companion") {
                Toggle("Enable Proactive Nudges", isOn: $companionNudgesEnabled)

                if companionNudgesEnabled {
                    Toggle("Nudge before known triggers", isOn: $nudgeBeforeTriggers)
                    Toggle("Weekly summary reminder", isOn: $nudgeWeeklySummary)
                    Toggle("Daily journal reminder", isOn: $nudgeJournalReminder)

                    Text("Nudges are personalized based on your episode history and calendar events. They only use on-device data.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Section("Escalation") {
                Toggle("Auto-escalate after 5 minutes", isOn: $autoEscalate)

                if !autoEscalate {
                    Text("A confirmation prompt will appear before SMS is sent to your emergency contact.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("An SMS will automatically be sent to your emergency contact after 5 minutes if the episode hasn't resolved.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Section("Demo Mode") {
                Toggle("Demo Mode", isOn: $demoMode)

                Text("Simulates heart rate and HRV data for demonstrations.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Privacy") {
                HStack {
                    Image(systemName: "lock.shield")
                        .foregroundColor(.green)
                    Text("Your data never leaves this device")
                        .font(.subheadline)
                }

                Text("PanicGuard uses on-device processing only. No accounts, no analytics, no cloud sync.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("About") {
                HStack {
                    Text("Version")
                    Spacer()
                    Text("1.0.0")
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("Settings")
        .onAppear {
            loadContact()
        }
        .alert("Re-run Calibration", isPresented: $showingRecalibrate) {
            Button("Cancel", role: .cancel) {}
            Button("Start") {
                // Trigger recalibration
            }
        } message: {
            Text("Please sit still for 5 minutes. This will update your baseline readings.")
        }
    }

    private func loadContact() {
        contactName = UserDefaults.standard.string(forKey: "emergencyContactName") ?? ""
        contactPhone = UserDefaults.standard.string(forKey: "emergencyContactPhone") ?? ""
        contactRelationship = UserDefaults.standard.string(forKey: "emergencyContactRelationship") ?? ""
    }

    private func saveContact() {
        UserDefaults.standard.set(contactName, forKey: "emergencyContactName")
        UserDefaults.standard.set(contactPhone, forKey: "emergencyContactPhone")
        UserDefaults.standard.set(contactRelationship, forKey: "emergencyContactRelationship")
    }
}

#Preview {
    NavigationStack {
        SettingsView()
            .environmentObject(AppState())
    }
}
