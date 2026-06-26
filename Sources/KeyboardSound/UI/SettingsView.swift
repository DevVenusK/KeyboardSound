import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: Settings
    let onTest: () -> Void

    init(settings: Settings, onTest: @escaping () -> Void) {
        self.settings = settings
        self.onTest = onTest
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("KeyboardSound")
                .font(.headline)

            Picker("스위치", selection: Binding(
                get: { settings.selectedSwitchID },
                set: { id in
                    if let preset = Preset.with(id: id) { settings.selectSwitch(preset) }
                }
            )) {
                ForEach(Preset.all) { preset in
                    Text(preset.name).tag(preset.id)
                }
            }
            .pickerStyle(.segmented)

            slider("볼륨", value: Binding(get: { settings.volume }, set: { settings.volume = $0 }))
            slider("톤",   value: Binding(get: { settings.tone }, set: { settings.tone = $0 }))
            slider("샤프함", value: Binding(get: { settings.sharpness }, set: { settings.sharpness = $0 }))

            Button("테스트 소리", action: onTest)
        }
        .padding(20)
        .frame(width: 320)
    }

    private func slider(_ label: String, value: Binding<Double>) -> some View {
        HStack {
            Text(label).frame(width: 48, alignment: .leading)
            Slider(value: value, in: 0...1)
        }
    }
}
