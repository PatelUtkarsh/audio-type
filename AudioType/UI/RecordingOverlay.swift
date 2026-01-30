import SwiftUI

struct RecordingOverlay: View {
  let text: String

  var body: some View {
    HStack(spacing: 12) {
      if text == "Recording..." {
        Circle()
          .fill(Color.red)
          .frame(width: 12, height: 12)
          .overlay(
            Circle()
              .stroke(Color.red.opacity(0.5), lineWidth: 2)
              .scaleEffect(1.5)
              .opacity(0.8)
          )
      } else {
        ProgressView()
          .scaleEffect(0.8)
      }

      Text(text)
        .font(.system(size: 14, weight: .medium))
        .foregroundColor(.primary)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .background(
      RoundedRectangle(cornerRadius: 10)
        .fill(.ultraThinMaterial)
        .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
    )
  }
}
