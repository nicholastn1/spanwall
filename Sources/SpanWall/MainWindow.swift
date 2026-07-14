import SwiftUI
import AppKit
import ServiceManagement
import UniformTypeIdentifiers

enum MainSection: String, CaseIterable, Identifiable {
    case catalog = "Catalog"
    case settings = "Settings"
    case about = "About"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .catalog: return "square.grid.2x2"
        case .settings: return "gearshape"
        case .about: return "info.circle"
        }
    }
}

/// Drives the main window: wallpaper library + settings, backed by the controller.
final class MainViewModel: ObservableObject {
    let controller: WallpaperController
    let library: WallpaperLibrary

    @Published var section: MainSection? = .catalog
    @Published var currentPath: String?
    @Published var spanEnabled = true
    @Published var bezelMM = 0.0
    @Published var fit: ContentFit = .fill
    @Published var launchAtLogin = false
    @Published var screenInfo = ""

    init(controller: WallpaperController, library: WallpaperLibrary) {
        self.controller = controller
        self.library = library
        refresh()
    }

    func refresh() {
        currentPath = controller.currentMediaPath
        spanEnabled = controller.spanEnabled
        bezelMM = controller.bezelMillimeters
        fit = controller.fit
        launchAtLogin = SMAppService.mainApp.status == .enabled
        screenInfo = "\(controller.screenCount) displays · \(controller.spanScreenCount) spanned"
    }

    // Catalog
    func importFiles() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .image]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.message = "Import videos or images into your library"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls { library.import(from: url) }
    }

    func apply(_ item: WallpaperItem) {
        controller.apply(item)
        currentPath = controller.currentMediaPath
    }

    func delete(_ item: WallpaperItem) {
        library.delete(item)
        if currentPath == item.url.path { useTestPattern() }
    }

    func isCurrent(_ item: WallpaperItem) -> Bool { currentPath == item.url.path }
    func useTestPattern() { controller.useTestPattern(); refresh() }

    // Settings
    func setSpan(_ on: Bool) { spanEnabled = on; controller.setSpanEnabled(on) }
    func setFit(_ f: ContentFit) { fit = f; controller.setFit(f) }
    /// Live drag: re-offset in place without persisting on every tick.
    func previewBezelMM(_ v: Double) { bezelMM = v; controller.setBezelMillimeters(v, persist: false) }
    /// Drag ended: persist the final value.
    func commitBezelMM() { controller.setBezelMillimeters(bezelMM, persist: true) }
    func setLaunchAtLogin(_ on: Bool) {
        let svc = SMAppService.mainApp
        do { if on { try svc.register() } else { try svc.unregister() } }
        catch { NSLog("SpanWall: launch-at-login failed: \(error.localizedDescription)") }
        launchAtLogin = svc.status == .enabled
    }
    func openRepo() { if let u = URL(string: AppInfo.repoURL) { NSWorkspace.shared.open(u) } }
    func quit() { NSApp.terminate(nil) }
}

struct MainWindowView: View {
    @ObservedObject var vm: MainViewModel

    var body: some View {
        NavigationSplitView {
            List(MainSection.allCases, selection: $vm.section) { section in
                Label(section.rawValue, systemImage: section.icon).tag(section)
            }
            .navigationSplitViewColumnWidth(min: 168, ideal: 184, max: 220)
        } detail: {
            switch vm.section ?? .catalog {
            case .catalog: CatalogView(vm: vm, library: vm.library)
            case .settings: SettingsSection(vm: vm)
            case .about: AboutSection(vm: vm)
            }
        }
        .frame(minWidth: 720, minHeight: 460)
        .toolbar {
            ToolbarItem {
                Button { vm.useTestPattern() } label: { Label("Test pattern", systemImage: "ruler") }
            }
            ToolbarItem {
                Button { vm.importFiles() } label: { Label("Import…", systemImage: "plus") }
            }
        }
        .onAppear { vm.refresh() }
    }
}

private struct CatalogView: View {
    @ObservedObject var vm: MainViewModel
    @ObservedObject var library: WallpaperLibrary

    private let columns = [GridItem(.adaptive(minimum: 220), spacing: 20)]

    var body: some View {
        ScrollView {
            if library.items.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 44)).foregroundStyle(.secondary)
                    Text("Library is empty").font(.title3.bold())
                    Text("Import a video or image to get started.").foregroundStyle(.secondary)
                    Button("Import…") { vm.importFiles() }.padding(.top, 4)
                }
                .frame(maxWidth: .infinity).padding(.top, 90)
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                    ForEach(library.items) { item in
                        WallpaperCard(item: item,
                                      thumbnail: library.thumbnail(for: item),
                                      isCurrent: vm.isCurrent(item),
                                      apply: { vm.apply(item) },
                                      delete: { vm.delete(item) })
                    }
                }
                .padding(20)
            }
        }
        .navigationTitle("Catalog")
    }
}

private struct WallpaperCard: View {
    let item: WallpaperItem
    let thumbnail: NSImage?
    let isCurrent: Bool
    let apply: () -> Void
    let delete: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            // Color.clear + aspectRatio pins the thumbnail to a uniform 16:9 box the
            // exact width of the grid cell; the image fills it via .overlay and is
            // clipped, so a wide (ultrawide) source can never spill into a neighbour.
            Color.clear
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .overlay {
                    if let thumbnail {
                        Image(nsImage: thumbnail).resizable().scaledToFill()
                    } else {
                        ZStack {
                            Color.black.opacity(0.25)
                            Image(systemName: item.isVideo ? "film" : "photo")
                                .font(.largeTitle).foregroundStyle(.secondary)
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .stroke(isCurrent ? Color.accentColor : Color.secondary.opacity(0.25),
                            lineWidth: isCurrent ? 3 : 1))
                .overlay(alignment: .topLeading) {
                    if item.isVideo {
                        Image(systemName: "play.circle.fill")
                            .padding(6).foregroundStyle(.white).shadow(radius: 2)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if isCurrent {
                        Image(systemName: "checkmark.circle.fill")
                            .padding(6).foregroundStyle(Color.accentColor).background(.white, in: Circle()).padding(4)
                    }
                }

            Text(item.name).font(.caption).lineLimit(1).truncationMode(.middle)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture(perform: apply)
        .contextMenu {
            Button("Apply", action: apply)
            Button("Remove from library", role: .destructive, action: delete)
        }
    }
}

private struct SettingsSection: View {
    @ObservedObject var vm: MainViewModel
    var body: some View {
        Form {
            Section("Layout") {
                Toggle("Span across displays",
                       isOn: Binding(get: { vm.spanEnabled }, set: { vm.setSpan($0) }))
                Picker("Fit", selection: Binding(get: { vm.fit }, set: { vm.setFit($0) })) {
                    Text("Fill").tag(ContentFit.fill)
                    Text("Fit").tag(ContentFit.fit)
                    Text("Stretch").tag(ContentFit.stretch)
                }.pickerStyle(.segmented)
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("Bezel")
                        Slider(value: Binding(get: { vm.bezelMM }, set: { vm.previewBezelMM($0) }),
                               in: 0...40, onEditingChanged: { if !$0 { vm.commitBezelMM() } })
                        Text("\(vm.bezelMM, specifier: "%.1f") mm").monospacedDigit().frame(width: 62, alignment: .trailing)
                    }
                    Text("Physical gap between displays. Drag while watching the seam.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                LabeledContent("Displays", value: vm.screenInfo)
            }
            Section("System") {
                Toggle("Launch at login",
                       isOn: Binding(get: { vm.launchAtLogin }, set: { vm.setLaunchAtLogin($0) }))
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
    }
}

private struct AboutSection: View {
    @ObservedObject var vm: MainViewModel
    var body: some View {
        VStack(spacing: 14) {
            if let icon = NSApp.applicationIconImage {
                Image(nsImage: icon).resizable().frame(width: 96, height: 96)
            }
            Text(AppInfo.displayName).font(.title.bold())
            Text("Version \(AppInfo.version)").foregroundStyle(.secondary)
            Text("One wallpaper (image or video) that spans across your displays.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary).padding(.horizontal, 40)
            HStack {
                Button("GitHub") { vm.openRepo() }
                Button("Quit SpanWall") { vm.quit() }
            }.padding(.top, 6)
            Spacer()
        }
        .padding(.top, 48)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("About")
    }
}
