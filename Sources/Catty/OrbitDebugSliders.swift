// Live-tuning sliders for orbit + scale + spin params. Sits below the
// minimap in the Terminal 3D scene. Mutates the shared OrbitConfigState
// so the RealityKit scene and the map respond in lockstep.
//
// Values are displayed numerically so the user can screenshot a tuned
// configuration and have us bake those numbers in as defaults.

#if os(macOS)
import SwiftUI

struct OrbitDebugSliders: View {
    @Bindable var config: OrbitConfigState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            row("Radius", value: $config.radius, range: 0.6...3.0, format: "%.2f")
            row("Speed", value: $config.rate, range: 0...3.0, format: "%.2f")
            row("Maxwell phase", value: $config.maxwellPhase, range: -.pi...(.pi), format: "%.2f")
            row("Maxwell spin", value: $config.maxwellSpinRate, range: 0...8.0, format: "%.2f")
            row("Maxwell scale", value: $config.maxwellScale, range: 0.0001...0.005, format: "%.4f")
            row("Rat scale", value: $config.ratScale, range: 0.005...0.2, format: "%.3f")
            row("Terminal alpha", value: $config.terminalOpacity, range: 0...1.0, format: "%.2f")
        }
        .padding(12)
        .frame(width: 240)
        .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(.white.opacity(0.15), lineWidth: 1)
        )
    }

    private func row(
        _ label: String,
        value: Binding<Float>,
        range: ClosedRange<Float>,
        format: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
                Spacer()
                Text(String(format: format, value.wrappedValue))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.9))
            }
            Slider(value: value, in: range)
                .controlSize(.mini)
                .tint(.purple)
        }
    }
}
#endif
