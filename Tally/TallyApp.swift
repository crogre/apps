import SwiftData
import SwiftUI

@main
struct TallyApp: App {
    private let container = ModelContainer.tally()

    var body: some Scene {
        WindowGroup {
            DocumentListView()
                .task {
                    // Opening on an empty screen makes it hard to tell what the app is
                    // for, so the first launch gets the packing list.
                    SampleData.seedIfEmpty(container.mainContext)
                }
        }
        .modelContainer(container)
    }
}
