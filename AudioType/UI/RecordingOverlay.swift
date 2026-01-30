import SwiftUI

struct RecordingOverlay: View {
  let text: String

  private var isRecording: Bool {
    text == "Recording..."
  }

  var body: some View {
    HStack(spacing: 10) {
      if isRecording {
        // Pulsing red dot for recording
        Circle()
          .fill(Color.red)
          .frame(width: 10, height: 10)
      } else {
        // Spinner for processing
        ProgressView()
          .scaleEffect(0.7)
          .frame(width: 10, height: 10)
      }

      Text(isRecording ? "Recording" : "Processing")
        .font(.system(size: 13, weight: .medium))
        .foregroundColor(.primary)
        .fixedSize(horizontal: true, vertical: false)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .frame(minWidth: 140)
    .background(
      RoundedRectangle(cornerRadius: 10)
        .fill(.ultraThinMaterial)
        .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
    )
  }
}
