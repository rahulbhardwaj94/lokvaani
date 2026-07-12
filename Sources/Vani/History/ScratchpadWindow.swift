import SwiftUI
import AppKit

// MARK: - Store

/// Multi-note scratchpad persistence (scratchpad.json). Notes are the tabs;
/// the single-note text from the first scratchpad version migrates in.
@MainActor
final class ScratchpadStore: ObservableObject {
    static let shared = ScratchpadStore()

    struct Note: Identifiable, Codable, Equatable {
        var id = UUID()
        var text = ""

        var title: String {
            let firstLine = text
                .split(separator: "\n", omittingEmptySubsequences: true)
                .first.map(String.init)?
                .trimmingCharacters(in: .whitespaces) ?? ""
            return firstLine.isEmpty ? "Untitled" : String(firstLine.prefix(22))
        }
    }

    @Published var notes: [Note] = [] {
        didSet { save() }
    }
    @Published var currentID: UUID?

    private let fileURL: URL

    private init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Vani")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appending(path: "scratchpad.json")
        notes = (try? JSONDecoder().decode([Note].self, from: Data(contentsOf: fileURL))) ?? []

        // Migrate the v1 single-note scratchpad.
        let legacy = UserDefaults.standard.string(forKey: "scratchpadText") ?? ""
        if notes.isEmpty, !legacy.isEmpty {
            notes = [Note(text: legacy)]
            UserDefaults.standard.removeObject(forKey: "scratchpadText")
        }
        if notes.isEmpty { notes = [Note()] }
        currentID = notes.first?.id
    }

    var currentText: Binding<String> {
        Binding(
            get: { [weak self] in
                guard let self, let id = self.currentID,
                      let note = self.notes.first(where: { $0.id == id }) else { return "" }
                return note.text
            },
            set: { [weak self] newValue in
                guard let self, let id = self.currentID,
                      let index = self.notes.firstIndex(where: { $0.id == id }) else { return }
                self.notes[index].text = newValue
            }
        )
    }

    func newNote() {
        let note = Note()
        notes.append(note)
        currentID = note.id
    }

    func close(_ id: UUID) {
        notes.removeAll { $0.id == id }
        if notes.isEmpty { notes = [Note()] }
        if currentID == id || currentID == nil { currentID = notes.last?.id }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(notes) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}

// MARK: - View

struct ScratchpadView: View {
    @ObservedObject private var store = ScratchpadStore.shared
    @AppStorage("scratchpadFontSize") private var fontSize = 15.0
    @State private var searching = false
    @State private var query = ""
    @State private var copied = false

    private var visibleNotes: [ScratchpadStore.Note] {
        guard searching, !query.isEmpty else { return store.notes }
        return store.notes.filter {
            $0.text.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            VStack(spacing: 0) {
                topBar
                editor
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.separator, lineWidth: 0.5))
    }

    private var sidebar: some View {
        VStack(spacing: 18) {
            Image(systemName: "waveform")
                .font(.system(size: 15, weight: .semibold))
                .padding(.top, 18)
            Button { store.newNote() } label: {
                Image(systemName: "square.and.pencil")
            }
            .help("New note")
            Button {
                searching.toggle()
                if !searching { query = "" }
            } label: {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(searching ? Color.accentColor : .secondary)
            }
            .help("Search notes")
            Spacer()
            Button {
                fontSize = fontSize >= 18 ? 13 : fontSize + 2.5
            } label: {
                Image(systemName: "textformat.size")
            }
            .help("Text size")
            .padding(.bottom, 16)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .font(.system(size: 14))
        .frame(width: 44)
    }

    private var topBar: some View {
        HStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(visibleNotes) { note in
                        TabChip(
                            title: note.title,
                            selected: note.id == store.currentID,
                            select: { store.currentID = note.id },
                            close: { store.close(note.id) }
                        )
                    }
                    Button { store.newNote() } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 2)
                }
            }
            if searching {
                TextField("Search…", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 130)
            }
            Button { ScratchpadWindow.shared.toggleExpand() } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
            }
            .help("Expand")
            Button { ScratchpadWindow.shared.hide() } label: {
                Image(systemName: "xmark")
            }
            .help("Close")
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .frame(height: 46)
        .contentShape(Rectangle())
    }

    private var editor: some View {
        ZStack(alignment: .bottomTrailing) {
            TextEditor(text: store.currentText)
                .font(.system(size: fontSize))
                .scrollContentBackground(.hidden)
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
                .padding([.horizontal, .bottom], 10)

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(store.currentText.wrappedValue, forType: .string)
                copied = true
                Task {
                    try? await Task.sleep(for: .seconds(1.4))
                    copied = false
                }
            } label: {
                Label(copied ? "Copied" : "Copy",
                      systemImage: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(.black))
            }
            .buttonStyle(.plain)
            .disabled(store.currentText.wrappedValue.isEmpty)
            .opacity(store.currentText.wrappedValue.isEmpty ? 0.35 : 1)
            .padding(24)
        }
    }
}

private struct TabChip: View {
    let title: String
    let selected: Bool
    let select: () -> Void
    let close: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 5) {
            Text(title)
                .font(.system(size: 12.5, weight: selected ? .medium : .regular))
                .lineLimit(1)
            if hovering || selected {
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                }
                .buttonStyle(.borderless)
            }
        }
        .foregroundStyle(selected ? .primary : .secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(selected ? AnyShapeStyle(.quaternary.opacity(0.6)) : AnyShapeStyle(.clear))
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: select)
        .onHover { hovering = $0 }
    }
}

// MARK: - Window

/// Borderless windows refuse key status by default; the scratchpad needs it
/// so its text view can take focus and receive the dictation paste.
private final class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class ScratchpadWindow {
    static let shared = ScratchpadWindow()
    private var window: NSWindow?
    private var savedFrame: NSRect?

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: ScratchpadView())
            let win = KeyableWindow(
                contentRect: NSRect(x: 0, y: 0, width: 560, height: 440),
                styleMask: [.borderless, .resizable],
                backing: .buffered,
                defer: false
            )
            win.contentViewController = hosting
            win.isOpaque = false
            win.backgroundColor = .clear
            win.hasShadow = true
            win.isMovableByWindowBackground = true
            win.isReleasedWhenClosed = false
            win.center()
            window = win
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func hide() {
        window?.orderOut(nil)
    }

    /// Toggle between the compact size and a large working size.
    func toggleExpand() {
        guard let window, let screen = window.screen ?? NSScreen.main else { return }
        if let saved = savedFrame {
            window.setFrame(saved, display: true, animate: true)
            savedFrame = nil
        } else {
            savedFrame = window.frame
            let visible = screen.visibleFrame
            let target = NSRect(
                x: visible.midX - visible.width * 0.35,
                y: visible.midY - visible.height * 0.4,
                width: visible.width * 0.7,
                height: visible.height * 0.8
            )
            window.setFrame(target, display: true, animate: true)
        }
    }
}
