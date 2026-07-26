import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppSettingsKey.promptForAssignees) private var promptModeRaw = AssigneePromptMode.firstInNote.rawValue

    private var promptMode: AssigneePromptMode {
        AssigneePromptMode(rawValue: promptModeRaw) ?? .firstInNote
    }

    var body: some View {
        Form {
            Section {
                Picker("Ask who it's for", selection: $promptModeRaw) {
                    ForEach(AssigneePromptMode.allCases) { mode in
                        Text(mode.title).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text("New to-dos")
            } footer: {
                Text(promptMode.explanation)
            }

            Section {
                LabeledContent("Markdown", value: "@name, @name✓")
            } header: {
                Text("Sharing")
            } footer: {
                Text("Notes share as plain markdown. People are written after the item, and a check mark marks the ones who are already done — so a half-packed shared item survives the round trip.")
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
    }
}

#Preview {
    NavigationStack { SettingsView() }
}
