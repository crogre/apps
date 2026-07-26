import Foundation
import SwiftData

extension ModelContainer {
    static let tallySchema = Schema([
        Document.self,
        Block.self,
        Person.self,
        Assignment.self,
    ])

    /// The app's store. `inMemory` backs previews and tests.
    static func tally(inMemory: Bool = false) -> ModelContainer {
        let configuration = ModelConfiguration(schema: tallySchema, isStoredInMemoryOnly: inMemory)
        do {
            return try ModelContainer(for: tallySchema, configurations: configuration)
        } catch {
            // A store that cannot be opened is unrecoverable at launch. Falling back to
            // memory keeps the app usable for the session and makes the failure obvious in
            // the log rather than as a silent crash on a user's device.
            assertionFailure("Could not open the Tally store: \(error)")
            let fallback = ModelConfiguration(schema: tallySchema, isStoredInMemoryOnly: true)
            // swiftlint:disable:next force_try
            return try! ModelContainer(for: tallySchema, configurations: fallback)
        }
    }
}
