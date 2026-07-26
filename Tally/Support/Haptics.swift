import UIKit

/// Ticking a box should feel like ticking a box.
enum Haptics {
    /// One person ticked their own box, but the item is not finished yet.
    static func tick() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// The last assignee ticked and the whole item is done.
    static func itemCompleted() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func untick() {
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.5)
    }
}
