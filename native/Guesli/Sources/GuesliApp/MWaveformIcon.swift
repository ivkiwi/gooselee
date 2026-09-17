import SwiftUI
import GuesliCore

/// Center-aligned waveform bars with a sinusoidal two-peak envelope
/// that naturally suggests the letter "M". Uses |sin(πx)| over two
/// half-cycles so the peaks emerge organically, like a real audio signal.
struct MWaveformIcon: View {
    var barCount: Int = 9
    var spacing: CGFloat = 1.5

    // Symmetric M-envelope: two peaks with a valley in the center.
    // Each subset is symmetric around the middle bar.
    private static let presets: [Int: [CGFloat]] = [
        5:  [0.85, 1.0, 0.35, 1.0, 0.85],
        7:  [0.45, 0.85, 1.0, 0.35, 1.0, 0.85, 0.45],
        9:  [0.45, 0.65, 0.90, 1.0, 0.45, 1.0, 0.90, 0.65, 0.45],
        11: [0.25, 0.50, 0.80, 1.0, 0.65, 0.30, 0.65, 1.0, 0.80, 0.50, 0.25],
        13: [0.30, 0.50, 0.75, 0.95, 1.0, 0.65, 0.30, 0.65, 1.0, 0.95, 0.75, 0.50, 0.30],
    ]

    private var multipliers: [CGFloat] {
        Self.presets[barCount] ?? Self.presets[9]!
    }

    var body: some View {
        GeometryReader { geo in
            let mults = multipliers
            let count = mults.count
            let totalSpacing = spacing * CGFloat(count - 1)
            let barWidth = (geo.size.width - totalSpacing) / CGFloat(count)
            let cornerRadius = barWidth / 2

            HStack(alignment: .center, spacing: spacing) {
                ForEach(0..<count, id: \.self) { i in
                    let barHeight = max(geo.size.height * mults[i], barWidth)
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .frame(width: barWidth, height: barHeight)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
        }
    }
}
