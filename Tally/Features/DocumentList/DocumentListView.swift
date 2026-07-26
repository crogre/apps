import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct DocumentListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Document.updatedAt, order: .reverse) private var documents: [Document]

    @State private var path: [Document] = []
    @State private var searchText = ""
    @State private var documentPendingDeletion: Document?
    @State private var showingImporter = false
    @State private var importError: String?
    /// One piece of state for every sheet: stacking several `.sheet` modifiers on the same
    /// view is a well-known way to end up with one of them silently never presenting.
    @State private var sheet: ListSheet?

    private enum ListSheet: Identifiable {
        case newFrom(Document)
        case people
        case settings

        var id: String {
            switch self {
            case let .newFrom(document): return "newFrom-\(document.id)"
            case .people: return "people"
            case .settings: return "settings"
            }
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if documents.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .navigationTitle("Notes")
            .searchable(text: $searchText, prompt: "Search notes")
            .toolbar { toolbar }
            .navigationDestination(for: Document.self) { document in
                DocumentEditorView(document: document)
            }
            .sheet(item: $sheet) { destination in
                switch destination {
                case let .newFrom(source):
                    NewFromDocumentSheet(source: source) { newDocument in
                        path.append(newDocument)
                    }
                case .people:
                    NavigationStack { PeopleManagerView() }
                case .settings:
                    NavigationStack { SettingsView() }
                }
            }
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: [.plainText, UTType("net.daringfireball.markdown") ?? .plainText],
                allowsMultipleSelection: true,
                onCompletion: importFiles
            )
            .alert("Could not import", isPresented: Binding(
                get: { importError != nil },
                set: { if !$0 { importError = nil } }
            )) {
                Button("OK", role: .cancel) { importError = nil }
            } message: {
                Text(verbatim: importError ?? "")
            }
            .confirmationDialog(
                "Delete “\(documentPendingDeletion?.displayTitle ?? "")”?",
                isPresented: Binding(
                    get: { documentPendingDeletion != nil },
                    set: { if !$0 { documentPendingDeletion = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let document = documentPendingDeletion {
                        context.delete(document)
                    }
                    documentPendingDeletion = nil
                }
                Button("Cancel", role: .cancel) { documentPendingDeletion = nil }
            } message: {
                Text("This cannot be undone.")
            }
        }
    }

    // MARK: - Content

    private var list: some View {
        List {
            if templates.isEmpty {
                Section { notesRows }
            } else {
                Section("Templates") {
                    ForEach(templates) { row($0) }
                }
                Section("Notes") { notesRows }
            }
        }
    }

    @ViewBuilder
    private var notesRows: some View {
        if others.isEmpty {
            Text("No notes yet")
                .foregroundStyle(.secondary)
        } else {
            ForEach(others) { row($0) }
        }
    }

    private func row(_ document: Document) -> some View {
        NavigationLink(value: document) {
            DocumentRow(document: document)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                documentPendingDeletion = document
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading) {
            Button {
                sheet = .newFrom(document)
            } label: {
                Label("New from this", systemImage: "doc.on.doc")
            }
            .tint(.accentColor)
        }
        .contextMenu {
            DocumentActionsMenu(
                document: document,
                onUseAsTemplate: { sheet = .newFrom(document) },
                onDelete: { documentPendingDeletion = document }
            )
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No notes yet", systemImage: "checklist")
        } description: {
            Text("Create a note, then add todos and assign them to the people who need to do them.")
        } actions: {
            Button("New Note", action: createDocument)
                .buttonStyle(.borderedProminent)
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Menu {
                Button {
                    sheet = .people
                } label: {
                    Label("People", systemImage: "person.2")
                }
                Button {
                    showingImporter = true
                } label: {
                    Label("Import Markdown…", systemImage: "square.and.arrow.down")
                }
                Button {
                    sheet = .settings
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button(action: createDocument) {
                Label("New Note", systemImage: "square.and.pencil")
            }
        }
    }

    // MARK: - Data

    private var visibleDocuments: [Document] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return documents }
        return documents.filter { document in
            document.title.localizedCaseInsensitiveContains(query)
                || document.orderedBlocks.contains { $0.text.localizedCaseInsensitiveContains(query) }
                || document.distinctPeople.contains { $0.name.localizedCaseInsensitiveContains(query) }
        }
    }

    private var templates: [Document] { visibleDocuments.filter(\.isTemplate) }
    private var others: [Document] { visibleDocuments.filter { !$0.isTemplate } }

    /// Imported files keep their people: `@Alma` is matched against the Almas you already
    /// have rather than creating a second one.
    private func importFiles(_ result: Result<[URL], Error>) {
        do {
            var imported: Document?
            for url in try result.get() {
                let needsScope = url.startAccessingSecurityScopedResource()
                defer { if needsScope { url.stopAccessingSecurityScopedResource() } }

                let text = try String(contentsOf: url, encoding: .utf8)
                let fallback = url.deletingPathExtension().lastPathComponent
                let draft = MarkdownParser.document(from: text, fallbackTitle: fallback)
                imported = DocumentMaterializer.makeDocument(from: draft, in: context)
            }
            if let imported { path.append(imported) }
        } catch {
            importError = error.localizedDescription
        }
    }

    private func createDocument() {
        let document = Document(title: "")
        context.insert(document)
        // A note always has at least one line to type into.
        DocumentMaterializer.append([BlockDraft(kind: .paragraph)], to: document, in: context)
        path.append(document)
    }
}

/// Shared between the list's context menu and the editor's ⋯ menu.
struct DocumentActionsMenu: View {
    let document: Document
    var onUseAsTemplate: () -> Void
    var onDelete: () -> Void

    var body: some View {
        Button {
            onUseAsTemplate()
        } label: {
            Label("New from this…", systemImage: "doc.on.doc")
        }

        Button {
            DocumentMaterializer.resetCompletion(in: document)
        } label: {
            Label("Reset all checkboxes", systemImage: "arrow.counterclockwise")
        }

        Button {
            document.isTemplate.toggle()
            document.touch()
        } label: {
            Label(
                document.isTemplate ? "Remove from Templates" : "Pin to Templates",
                systemImage: document.isTemplate ? "pin.slash" : "pin"
            )
        }

        ShareLink(item: document.markdown) {
            Label("Share as Markdown", systemImage: "square.and.arrow.up")
        }

        Divider()

        Button(role: .destructive, action: onDelete) {
            Label("Delete", systemImage: "trash")
        }
    }
}

#Preview {
    DocumentListView()
        .modelContainer(SampleData.previewContainer())
}
