import SwiftUI

enum AppSettingsKey {
    /// Whether creating a todo should offer the assignee sheet straight away.
    static let promptForAssignees = "promptForAssigneesOnNewTodo"
    /// Move completed items to the bottom of their section.
    static let sinkCompletedItems = "sinkCompletedItems"
    static let hasSeeded = "hasSeededSampleData"
}

extension View {
    /// Standard sheet sizing for the small pickers, so they all feel the same.
    func pickerSheet() -> some View {
        presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
    }
}
