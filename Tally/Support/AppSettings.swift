import SwiftUI

enum AppSettingsKey {
    /// How eagerly creating a to-do should offer the assignee sheet. Stores the raw value
    /// of `AssigneePromptMode`.
    static let promptForAssignees = "promptForAssigneesOnNewTodo"
}

extension View {
    /// Standard sheet sizing for the small pickers, so they all feel the same.
    func pickerSheet() -> some View {
        presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
    }
}
