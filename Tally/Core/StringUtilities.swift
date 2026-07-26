import Foundation

extension String {
    func trimmingTrailingWhitespace() -> String {
        var result = self
        while let last = result.last, last.isWhitespace {
            result.removeLast()
        }
        return result
    }

    var isBlank: Bool {
        allSatisfy(\.isWhitespace)
    }
}
