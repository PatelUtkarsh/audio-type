import SwiftUI

struct RecordingOverlay: View {
  let text: String
  @EnvironmentObject var levelMonitor: AudioLevelMonitor

  private var isRecording: Bool {
    text == "Recording..."
  }

  var body: some View {
    HStack(spacing: 8) {
      if isRecording {
        LiveWaveformView(level: levelMonitor.level)
          .frame(width: 44, height: 24)
      } else {
        ThinkingDotsView()
          .frame(width: 40, height: 20)
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .frame(minWidth: 80)
    .background(
      RoundedRectangle(cornerRadius: 10)
        .fill(.ultraThinMaterial)
        .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
    )
  }
}

/// Waveform bars driven by live audio level from the microphone.
struct LiveWaveformView: View {
  var level: Float

  private let barCount = 5
  private let minHeight: CGFloat = 3
  private let maxHeight: CGFloat = 22

  var body: some View {
    HStack(spacing: 3) {
      ForEach(0..<barCount, id: \.self) { index in
        RoundedRectangle(cornerRadius: 1.5)
          .fill(Color.white)
          .frame(width: 3, height: barHeight(for: index))
          .animation(.easeOut(duration: 0.08), value: level)
      }
    }
  }

  private func barHeight(for index: Int) -> CGFloat {
    // Each bar gets a slightly different scale to look organic
    let offsets: [Float] = [0.6, 1.0, 0.8, 0.9, 0.5]
    let scaled = CGFloat(level * offsets[index % offsets.count])
    return max(minHeight, minHeight + (maxHeight - minHeight) * scaled)
  }
}

struct ThinkingDotsView: View {
  @State private var animating = false

  var body: some View {
    HStack(spacing: 6) {
      ForEach(0..<3, id: \.self) { index in
        Circle()
          .fill(Color.white)
          .frame(width: 6, height: 6)
          .scaleEffect(animating ? 1.0 : 0.4)
          .opacity(animating ? 1.0 : 0.3)
          .animation(
            .easeInOut(duration: 0.5)
              .repeatForever(autoreverses: true)
              .delay(Double(index) * 0.2),
            value: animating
          )
      }
    }
    .onAppear {
      animating = true
    }
  }
}
