import Foundation

/// The kinds of line a document can be made of.
///
/// Raw values are what gets persisted, so they must stay stable across releases even if
/// the case names are refactored.
public enum BlockKind: String, Codable, Sendable, CaseIterable {
    case heading1 = "h1"
    case heading2 = "h2"
    case heading3 = "h3"
    case paragraph = "p"
    case bullet = "ul"
    case todo = "todo"
    case divider = "hr"

    /// Kinds that carry a leading marker and so should be continued when the user presses
    /// return at the end of the line.
    public var continuesOnReturn: Bool {
        switch self {
        case .bullet, .todo: return true
        case .heading1, .heading2, .heading3, .paragraph, .divider: return false
        }
    }

    /// Only todos can have people assigned to them.
    public var acceptsAssignees: Bool { self == .todo }

    /// Kinds that can be nested underneath one another.
    public var acceptsIndent: Bool {
        switch self {
        case .bullet, .todo: return true
        default: return false
        }
    }

    /// Blocks with no text of their own.
    public var isTextless: Bool { self == .divider }

    public var headingLevel: Int? {
        switch self {
        case .heading1: return 1
        case .heading2: return 2
        case .heading3: return 3
        default: return nil
        }
    }

    public static func heading(level: Int) -> BlockKind {
        switch level {
        case ...1: return .heading1
        case 2: return .heading2
        default: return .heading3
        }
    }
}
