import Foundation

/// How far along a todo is, given that each assignee ticks their own box.
///
/// A todo with nobody assigned falls back to a single shared flag (`isDoneSolo`) so an
/// item never becomes untickable just because its only assignee was deleted.
public struct CompletionRollup: Equatable, Sendable {
    public let doneCount: Int
    public let totalCount: Int
    public let isDoneSolo: Bool

    public init(doneCount: Int, totalCount: Int, isDoneSolo: Bool) {
        self.doneCount = doneCount
        self.totalCount = totalCount
        self.isDoneSolo = isDoneSolo
    }

    /// True when nobody is assigned, in which case `isDoneSolo` is the source of truth.
    public var isUnassigned: Bool { totalCount == 0 }

    /// Complete only when *every* assignee has ticked.
    public var isComplete: Bool {
        isUnassigned ? isDoneSolo : doneCount == totalCount
    }

    /// Some but not all assignees are done — the state the half-filled glyph represents.
    public var isPartial: Bool {
        !isUnassigned && doneCount > 0 && doneCount < totalCount
    }

    /// Tapping the checkbox should ask *who* finished it only when the answer is ambiguous.
    public var needsCompleterPrompt: Bool { totalCount > 1 }

    /// `"1/2"`, shown as a pill next to the item. Nil when there is nothing to count.
    public var progressText: String? {
        totalCount > 1 ? "\(doneCount)/\(totalCount)" : nil
    }

    /// SF Symbol for the checkbox, following empty → half → full.
    public var symbolName: String {
        if isComplete { return "checkmark.circle.fill" }
        if isPartial { return "circle.lefthalf.filled" }
        return "circle"
    }

    public var fractionComplete: Double {
        if isUnassigned { return isDoneSolo ? 1 : 0 }
        return Double(doneCount) / Double(totalCount)
    }
}
