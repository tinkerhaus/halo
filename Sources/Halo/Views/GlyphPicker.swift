import SwiftUI
import AppKit

/// One SF Symbols category (from the system manifest) plus the symbols in it.
struct GlyphCategory: Identifiable {
    let id: String        // category key, e.g. "communication"
    let label: String
    let icon: String      // an SF Symbol representing the category
    let symbols: [String]
}

/// The full SF Symbols catalog + Apple's own category grouping. macOS has no
/// *public* enumeration API, so we read the system's symbol manifests at runtime —
/// the picker offers every symbol the OS knows, grouped the way the SF Symbols app
/// groups them. Falls back gracefully if the manifests aren't where we expect.
enum SFSymbolCatalog {
    private static let resourceDir =
        "/System/Library/CoreServices/CoreGlyphs.bundle/Contents/Resources"

    static let all: [String] = {
        if let dict = NSDictionary(contentsOfFile: resourceDir + "/name_availability.plist"),
           let symbols = dict["symbols"] as? [String: Any], !symbols.isEmpty {
            return symbols.keys.sorted()
        }
        return fallback
    }()

    static let categories: [GlyphCategory] = loadCategories()

    private static func loadCategories() -> [GlyphCategory] {
        let allCat = GlyphCategory(id: "all", label: "All", icon: "square.grid.2x2", symbols: all)
        guard let catList = NSArray(contentsOfFile: resourceDir + "/categories.plist") as? [[String: Any]],
              let map = NSDictionary(contentsOfFile: resourceDir + "/symbol_categories.plist") as? [String: [String]]
        else { return [allCat] }

        let valid = Set(all)
        var byCategory: [String: [String]] = [:]
        for (symbol, keys) in map where valid.contains(symbol) {
            for key in keys { byCategory[key, default: []].append(symbol) }
        }

        var result = [allCat]
        for entry in catList {
            guard let key = entry["key"] as? String, key != "all" else { continue }
            let symbols = (byCategory[key] ?? []).sorted()
            guard !symbols.isEmpty else { continue }
            let icon = (entry["icon"] as? String) ?? "square"
            result.append(GlyphCategory(id: key, label: label(for: key), icon: icon, symbols: symbols))
        }
        return result
    }

    private static func label(for key: String) -> String {
        let special: [String: String] = [
            "whatsnew": "What's New", "objectsandtools": "Objects & Tools",
            "textformatting": "Text Formatting", "privacyandsecurity": "Privacy & Security",
            "humanfigures": "Human", "connectivity": "Connectivity",
            "transportation": "Transit", "weatherandnature": "Weather & Nature",
        ]
        if let s = special[key] { return s }
        return key.prefix(1).uppercased() + key.dropFirst()
    }

    /// Used only if the system manifests can't be read — still searchable, just smaller.
    static let fallback: [String] = [
        "circle", "circle.fill", "square", "square.fill", "triangle", "star", "star.fill",
        "heart", "heart.fill", "bolt", "flame", "drop", "leaf", "sparkles",
        "arrow.up", "arrow.down", "arrow.left", "arrow.right", "arrow.clockwise",
        "arrow.uturn.backward", "chevron.up", "chevron.down", "chevron.left", "chevron.right",
        "return", "escape", "delete.left", "command", "option", "control", "shift",
        "magnifyingglass", "plus", "minus", "xmark", "checkmark", "ellipsis", "gearshape",
        "doc", "folder", "tray.and.arrow.down", "square.and.arrow.up", "trash", "pencil",
        "play.fill", "pause.fill", "stop.circle", "mic.fill", "waveform", "house", "bell",
        "person.fill", "paperplane.fill", "calendar", "clock", "globe", "lock.fill",
        "terminal.fill", "keyboard", "macwindow", "questionmark", "exclamationmark.triangle",
    ]
}

/// A compact field showing the current glyph; tapping opens a roomy browser.
struct GlyphPicker: View {
    @Binding var glyph: String
    @State private var showing = false

    var body: some View {
        Button { showing = true } label: {
            HStack(spacing: 8) {
                preview(glyph).frame(width: 22, height: 22)
                Text(glyph.isEmpty ? "Choose a symbol…" : glyph)
                    .font(.system(size: 12, design: .monospaced)).foregroundStyle(.primary).lineLimit(1)
                Spacer()
                Image(systemName: "square.grid.2x2").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .padding(7)
            .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.08), lineWidth: 0.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showing) { GlyphBrowser(glyph: $glyph) }
    }

    private func preview(_ name: String) -> some View {
        let ok = NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
        return Image(systemName: ok ? name : "questionmark").font(.system(size: 15))
            .foregroundStyle(ok ? AnyShapeStyle(.primary) : AnyShapeStyle(.orange))
    }
}

/// A roomy, grouped symbol browser shown as a sheet: a category sidebar on the
/// left, a search field, and a lazy grid of every symbol in the selection.
struct GlyphBrowser: View {
    @Binding var glyph: String
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var category = "all"

    private let columns = [GridItem(.adaptive(minimum: 84), spacing: 8)]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                sidebar.frame(width: 196)
                Divider()
                gridPane
            }
        }
        .frame(width: 780, height: 560)
        .background(Color(red: 0.09, green: 0.10, blue: 0.13))
        .preferredColorScheme(.dark)
        .onExitCommand { dismiss() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search \(SFSymbolCatalog.all.count) symbols…", text: $query)
                .textFieldStyle(.plain).font(.system(size: 14))
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
        }
        .padding(12)
    }

    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(SFSymbolCatalog.categories) { cat in
                    Button { category = cat.id; query = "" } label: {
                        HStack(spacing: 8) {
                            Image(systemName: cat.icon).font(.system(size: 12)).frame(width: 18)
                            Text(cat.label).font(.system(size: 12)).lineLimit(1)
                            Spacer()
                            Text("\(cat.symbols.count)").font(.system(size: 9)).foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 9).padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 6)
                            .fill(category == cat.id && query.isEmpty ? Color.accentColor.opacity(0.25) : .clear))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(category == cat.id && query.isEmpty ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                }
            }
            .padding(8)
        }
    }

    private var gridPane: some View {
        VStack(spacing: 0) {
            if !displayed.isEmpty {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(displayed, id: \.self) { cell($0) }
                    }
                    .padding(12)
                }
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "questionmark.circle").font(.system(size: 28)).foregroundStyle(.tertiary)
                    Text("No symbols match “\(query)”.").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var displayed: [String] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty { return SFSymbolCatalog.all.filter { $0.contains(q) } }
        return SFSymbolCatalog.categories.first { $0.id == category }?.symbols ?? SFSymbolCatalog.all
    }

    private func cell(_ name: String) -> some View {
        Button { glyph = name; dismiss() } label: {
            VStack(spacing: 5) {
                Image(systemName: name).font(.system(size: 22)).frame(height: 26)
                Text(name).font(.system(size: 8)).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
            }
            .frame(width: 80, height: 58)
            .background(RoundedRectangle(cornerRadius: 8)
                .fill(name == glyph ? Color.accentColor.opacity(0.35) : Color.white.opacity(0.05)))
        }
        .buttonStyle(.plain).help(name)
    }
}
