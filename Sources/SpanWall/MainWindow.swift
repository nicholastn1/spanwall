import SwiftUI
import AppKit
import ServiceManagement
import UniformTypeIdentifiers

enum MainSection: String, CaseIterable, Identifiable {
    case catalog = "Catálogo"
    case settings = "Configurações"
    case about = "Sobre"
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
    @Published var bezelPoints = 0.0
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
        bezelPoints = controller.bezelPoints
        fit = controller.fit
        launchAtLogin = SMAppService.mainApp.status == .enabled
        screenInfo = "\(controller.screenCount) telas · \(controller.spanScreenCount) no span"
    }

    // Catalog
    func importFiles() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .image]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.message = "Importe vídeos ou imagens para a sua biblioteca"
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
    func previewBezel(_ v: Double) { bezelPoints = v }
    func commitBezel() { controller.setBezelPoints(bezelPoints) }
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
                Button { vm.useTestPattern() } label: { Label("Padrão de teste", systemImage: "ruler") }
            }
            ToolbarItem {
                Button { vm.importFiles() } label: { Label("Importar…", systemImage: "plus") }
            }
        }
        .onAppear { vm.refresh() }
    }
}

private struct CatalogView: View {
    @ObservedObject var vm: MainViewModel
    @ObservedObject var library: WallpaperLibrary

    private let columns = [GridItem(.adaptive(minimum: 200, maximum: 260), spacing: 16)]

    var body: some View {
        ScrollView {
            if library.items.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 44)).foregroundStyle(.secondary)
                    Text("Biblioteca vazia").font(.title3.bold())
                    Text("Importe um vídeo ou imagem para começar.").foregroundStyle(.secondary)
                    Button("Importar…") { vm.importFiles() }.padding(.top, 4)
                }
                .frame(maxWidth: .infinity).padding(.top, 90)
            } else {
                LazyVGrid(columns: columns, spacing: 16) {
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
        .navigationTitle("Catálogo")
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
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.25))
                if let thumbnail {
                    Image(nsImage: thumbnail).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: item.isVideo ? "film" : "photo").font(.largeTitle).foregroundStyle(.secondary)
                }
            }
            .frame(height: 118)
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
        .contentShape(Rectangle())
        .onTapGesture(perform: apply)
        .contextMenu {
            Button("Aplicar", action: apply)
            Button("Remover da biblioteca", role: .destructive, action: delete)
        }
    }
}

private struct SettingsSection: View {
    @ObservedObject var vm: MainViewModel
    var body: some View {
        Form {
            Section("Layout") {
                Toggle("Estender pelos monitores (span)",
                       isOn: Binding(get: { vm.spanEnabled }, set: { vm.setSpan($0) }))
                Picker("Ajuste", selection: Binding(get: { vm.fit }, set: { vm.setFit($0) })) {
                    Text("Preencher").tag(ContentFit.fill)
                    Text("Ajustar").tag(ContentFit.fit)
                    Text("Esticar").tag(ContentFit.stretch)
                }.pickerStyle(.segmented)
                HStack {
                    Text("Bezel")
                    Slider(value: Binding(get: { vm.bezelPoints }, set: { vm.previewBezel($0) }),
                           in: 0...200, onEditingChanged: { if !$0 { vm.commitBezel() } })
                    Text("\(Int(vm.bezelPoints)) pt").monospacedDigit().frame(width: 54, alignment: .trailing)
                }
                LabeledContent("Monitores", value: vm.screenInfo)
            }
            Section("Sistema") {
                Toggle("Iniciar no login",
                       isOn: Binding(get: { vm.launchAtLogin }, set: { vm.setLaunchAtLogin($0) }))
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Configurações")
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
            Text("Versão \(AppInfo.version)").foregroundStyle(.secondary)
            Text("Um wallpaper (imagem ou vídeo) que se estende pelos seus monitores.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary).padding(.horizontal, 40)
            HStack {
                Button("GitHub") { vm.openRepo() }
                Button("Sair do SpanWall") { vm.quit() }
            }.padding(.top, 6)
            Spacer()
        }
        .padding(.top, 48)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Sobre")
    }
}
