import Foundation

/// Ordering for blocks inside a document.
///
/// Blocks carry a `Double` position rather than an array index so that inserting a line in
/// the middle of a long note is a single write instead of renumbering everything below it.
/// Repeated splitting halves the gap each time, so `needsRenormalisation` watches for the
/// point where doubles run out of room and the whole document gets renumbered.
public enum FractionalIndex {
    /// Spacing used when appending to the end of a document.
    public static let step: Double = 1

    /// Smallest gap we are willing to subdivide. Doubles have ~15 significant digits; this
    /// leaves a wide margin before neighbouring positions could collide.
    public static let minimumGap: Double = 1e-9

    /// A position that sorts between `before` and `after`.
    ///
    /// - `before == nil` means "insert at the very top", `after == nil` means "append".
    public static func between(_ before: Double?, _ after: Double?) -> Double {
        switch (before, after) {
        case let (.some(a), .some(b)):
            return a + (b - a) / 2
        case let (.some(a), .none):
            return a + step
        case let (.none, .some(b)):
            return b - step
        case (.none, .none):
            return 0
        }
    }

    /// Position for appending after the last block of a document.
    public static func append(after positions: [Double]) -> Double {
        (positions.max().map { $0 + step }) ?? 0
    }

    /// True when any two adjacent positions have grown too close to safely subdivide, or
    /// when duplicates have crept in.
    public static func needsRenormalisation(_ positions: [Double]) -> Bool {
        let sorted = positions.sorted()
        guard sorted.count > 1 else { return false }
        for (a, b) in zip(sorted, sorted.dropFirst()) where b - a < minimumGap {
            return true
        }
        return false
    }

    /// Evenly spaced positions preserving the current order: `0, 1, 2, …`
    public static func renormalised(count: Int) -> [Double] {
        guard count > 0 else { return [] }
        return (0..<count).map { Double($0) * step }
    }
}
