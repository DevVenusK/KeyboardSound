import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var settings: Settings
    @ObservedObject var sampleStore: CustomSampleStore
    let onTest: () -> Void

    init(settings: Settings, sampleStore: CustomSampleStore, onTest: @escaping () -> Void) {
        self.settings = settings
        self.sampleStore = sampleStore
        self.onTest = onTest
    }

    private var isCustom: Bool { settings.selectedSwitchID == Preset.customID }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("KeyboardSound")
                .font(.headline)

            Picker("스위치", selection: Binding(
                get: { settings.selectedSwitchID },
                set: { id in
                    if id == Preset.customID {
                        settings.selectCustom()
                    } else if let preset = Preset.with(id: id) {
                        settings.selectSwitch(preset)
                    }
                }
            )) {
                ForEach(Preset.all) { preset in
                    Text(preset.name).tag(preset.id)
                }
                Text("커스텀").tag(Preset.customID)
            }
            .pickerStyle(.segmented)

            if isCustom {
                customSection
            } else {
                synthSection
            }
        }
        .padding(20)
        .frame(width: 320)
    }

    private var customSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button("파일 선택…", action: pickFile)
                Text(sampleStore.fileName ?? "선택된 파일 없음")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            slider("볼륨", value: Binding(get: { settings.volume }, set: { settings.volume = $0 }))
            Button("테스트 소리", action: onTest)
        }
    }

    private var synthSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            slider("볼륨", value: Binding(get: { settings.volume }, set: { settings.volume = $0 }))
            slider("톤",   value: Binding(get: { settings.tone }, set: { settings.tone = $0 }))
            slider("샤프함", value: Binding(get: { settings.sharpness }, set: { settings.sharpness = $0 }))
            slider("무게",  value: Binding(get: { settings.weight }, set: { settings.weight = $0 }))
            slider("울림",  value: Binding(get: { settings.ring }, set: { settings.ring = $0 }))

            HStack {
                Button("테스트 소리", action: onTest)
                Button("값 초기화") { settings.resetCurrentSwitch() }
            }
        }
    }

    private func pickFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try sampleStore.importFile(url)
        } catch {
            let alert = NSAlert()
            alert.messageText = "오디오 파일을 불러올 수 없습니다"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    private func slider(_ label: String, value: Binding<Double>) -> some View {
        HStack {
            Text(label).frame(width: 48, alignment: .leading)
            Slider(value: value, in: 0...1)
        }
    }
}
