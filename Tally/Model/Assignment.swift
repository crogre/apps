import Foundation
import SwiftData

/// One person's stake in one todo.
///
/// This is a join record rather than a plain list of people on the block, because each
/// assignee ticks their *own* box — "2 pairs of socks" assigned to two kids is done when
/// both of them have packed, and we want to know who finished when.
@Model
final class Assignment {
    var id: UUID = UUID()
    /// `nil` until this person has ticked their own box.
    var completedAt: Date?
    /// Position within the block's chip row, so the order does not shuffle between launches.
    var order: Int = 0

    var block: Block?
    var person: Person?

    init(person: Person?, order: Int = 0, completedAt: Date? = nil) {
        self.id = UUID()
        self.person = person
        self.order = order
        self.completedAt = completedAt
    }

    var isDone: Bool {
        get { completedAt != nil }
        set { completedAt = newValue ? (completedAt ?? .now) : nil }
    }

    var personName: String { person?.name ?? "" }
}
