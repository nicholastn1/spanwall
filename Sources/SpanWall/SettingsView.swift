import SwiftUI
import AppKit
import ServiceManagement
import UniformTypeIdentifiers

/// Bridges the SwiftUI settings panel to the `WallpaperController` (source of truth).
/// All access happens on the main thread (menu actions / SwiftUI body).
final class SettingsViewModel: ObservableObject {
    private let controller: WallpaperController

    @Published var contentLabel = ""
    @Published var spanEnabled = true
    @Published var bezelPoints = 0.0
    @Published var launchAtLogin = false
    @Published var screenCount = 0
    @Published var spanScreenCount = 0

    init(controller: WallpaperController) {
        self.controller = controller
        refresh()
    }

    func refresh() {
        contentLabel = controller.contentLabel
        spanEnabled = controller.spanEnabled
        bezelPoints = controller.bezelPoints
        launchAtLogin = SMAppService.mainApp.status == .enabled
        screenCount = controller.screenCount
        spanScreenCount = controller.spanScreenCount
    }

    func pickVideo() { pick([.movie, .video, .quickTimeMovie, .mpeg4Movie]) { controller.chooseVideo(path: $0.path) } }
    func pickImage() { pick([.image]) { controller.chooseImage(path: $0.path) } }
    func useTestPattern() { controller.useTestPattern(); refresh() }

    private func pick(_ types: [UTType], _ then: (URL) -> Void) {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = types
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url { then(url); refresh() }
    }

    func setSpan(_ on: Bool) { spanEnabled = on; controller.setSpanEnabled(on); refresh() }
    func previewBezel(_ pts: Double) { bezelPoints = pts }               // live label only
    func commitBezel() { controller.setBezelPoints(bezelPoints); refresh() } // apply on release

    func setLaunchAtLogin(_ on: Bool) {
        let service = SMAppService.mainApp
        do { if on { try service.register() } else { try service.unregister() } }
        catch { NSLog("SpanWall: launch-at-login toggle failed: \(error.localizedDescription)") }
        launchAtLogin = service.status == .enabled
    }

    func openRepo() { if let url = URL(string: AppInfo.repoURL) { NSWorkspace.shared.open(url) } }
    func quit() { NSApp.terminate(nil) }
}

struct SettingsView: View {
    @ObservedObject var vm: SettingsViewModel

    var body: some View {
        Form {
            Section("Conteúdo") {
                LabeledContent("Atual", value: vm.contentLabel)
                HStack {
                    Button("Escolher vídeo…") { vm.pickVideo() }
                    Button("Escolher imagem…") { vm.pickImage() }
                    Button("Padrão de teste") { vm.useTestPattern() }
                }
            }

            Section("Layout") {
                Toggle("Estender pelos monitores (span)",
                       isOn: Binding(get: { vm.spanEnabled }, set: { vm.setSpan($0) }))
                HStack {
                    Text("Bezel")
                    Slider(value: Binding(get: { vm.bezelPoints }, set: { vm.previewBezel($0) }),
                           in: 0...200,
                           onEditingChanged: { editing in if !editing { vm.commitBezel() } })
                    Text("\(Int(vm.bezelPoints)) pt").monospacedDigit().frame(width: 54, alignment: .trailing)
                }
                LabeledContent("Monitores", value: "\(vm.screenCount)  ·  no span: \(vm.spanScreenCount)")
            }

            Section("Sistema") {
                Toggle("Iniciar no login",
                       isOn: Binding(get: { vm.launchAtLogin }, set: { vm.setLaunchAtLogin($0) }))
                LabeledContent("Versão", value: AppInfo.version)
                HStack {
                    Button("GitHub") { vm.openRepo() }
                    Spacer()
                    Button("Sair do SpanWall") { vm.quit() }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 508)
    }
}
