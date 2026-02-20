import AVFoundation
import Foundation
import Speech
import os.log

// MARK: - Errors

enum AppleSpeechError: Error, LocalizedError {
  case notAvailable
  case notAuthorized
  case recognitionFailed(String)
  case noResult

  var errorDescription: String? {
    switch self {
    case .notAvailable:
      return "Apple Speech recognition is not available on this device."
    case .notAuthorized:
      return "Speech recognition permission not granted. Open Settings to allow."
    case .recognitionFailed(let message):
      return "Speech recognition failed: \(message)"
    case .noResult:
      return "No speech was recognized."
    }
  }
}

// MARK: - Apple Speech Engine

/// On-device speech-to-text using Apple's Speech framework (`SFSpeechRecognizer`).
///
/// This engine requires no API key and works offline when on-device recognition is
/// available (macOS 13+). It acts as the fallback when no Groq API key is configured.
class AppleSpeechEngine: TranscriptionEngine {

  private let logger = Logger(subsystem: "com.audiotype", category: "AppleSpeechEngine")

  /// The sample rate AudioRecorder delivers (16 kHz mono Float32).
  private let inputSampleRate: Double = 16000

  var displayName: String { "Apple Speech" }

  var isAvailable: Bool {
    guard let recognizer = SFSpeechRecognizer() else { return false }
    return recognizer.isAvailable
  }

  /// Whether the platform can ever provide `SFSpeechRecognizer`.
  static var isSupported: Bool {
    SFSpeechRecognizer() != nil
  }

  /// Request speech recognition authorization from the user.
  static func requestAuthorization() async -> Bool {
    await withCheckedContinuation { continuation in
      SFSpeechRecognizer.requestAuthorization { status in
        continuation.resume(returning: status == .authorized)
      }
    }
  }

  /// Current authorization status.
  static var authorizationStatus: SFSpeechRecognizerAuthorizationStatus {
    SFSpeechRecognizer.authorizationStatus()
  }

  // MARK: - TranscriptionEngine

  func transcribe(samples: [Float]) async throws -> String {
    // Check (and request if needed) authorization
    var status = SFSpeechRecognizer.authorizationStatus()
    if status == .notDetermined {
      logger.info("Speech recognition not yet determined, requesting...")
      let granted = await Self.requestAuthorization()
      status = granted ? .authorized : .denied
    }
    guard status == .authorized else {
      logger.error(
        "Speech recognition not authorized, status: \(status.rawValue)"
      )
      throw AppleSpeechError.notAuthorized
    }

    // Resolve locale from user's language preference
    let locale = Self.locale(for: TranscriptionLanguage.current)
    guard let recognizer = SFSpeechRecognizer(locale: locale) else {
      throw AppleSpeechError.notAvailable
    }
    guard recognizer.isAvailable else {
      throw AppleSpeechError.notAvailable
    }

    // Prefer on-device recognition when available (no network needed)
    if recognizer.supportsOnDeviceRecognition {
      logger.info("Using on-device recognition for locale: \(locale.identifier)")
    } else {
      logger.info("On-device not available; will use server-based recognition")
    }

    // Build an audio buffer request and feed the recorded samples
    let request = SFSpeechAudioBufferRecognitionRequest()
    request.shouldReportPartialResults = false
    if recognizer.supportsOnDeviceRecognition {
      request.requiresOnDeviceRecognition = true
    }

    // Convert [Float] → AVAudioPCMBuffer
    let buffer = try Self.pcmBuffer(from: samples, sampleRate: inputSampleRate)
    request.append(buffer)
    request.endAudio()

    // Run recognition — guard against multiple callback invocations
    let text: String = try await withCheckedThrowingContinuation { continuation in
      var hasResumed = false
      recognizer.recognitionTask(with: request) { result, error in
        guard !hasResumed else { return }

        if let error = error {
          hasResumed = true
          let msg = error.localizedDescription
          continuation.resume(
            throwing: AppleSpeechError.recognitionFailed(msg)
          )
          return
        }

        guard let result = result, result.isFinal else { return }
        hasResumed = true
        let text = result.bestTranscription.formattedString
        continuation.resume(returning: text)
      }
    }

    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw AppleSpeechError.noResult
    }

    logger.info("Transcription complete: \(text.prefix(80))…")
    return text
  }

  // MARK: - Helpers

  /// Convert a `[Float]` sample array (mono, given sample rate) into an `AVAudioPCMBuffer`.
  private static func pcmBuffer(
    from samples: [Float], sampleRate: Double
  ) throws -> AVAudioPCMBuffer {
    guard
      let format = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: sampleRate,
        channels: 1,
        interleaved: false
      )
    else {
      throw AppleSpeechError.recognitionFailed("Failed to create audio format")
    }

    let capacity = AVAudioFrameCount(samples.count)
    guard
      let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity)
    else {
      throw AppleSpeechError.recognitionFailed("Failed to create audio buffer")
    }

    buffer.frameLength = AVAudioFrameCount(samples.count)

    guard let channelData = buffer.floatChannelData else {
      throw AppleSpeechError.recognitionFailed("Failed to access channel data")
    }
    samples.withUnsafeBufferPointer { src in
      channelData[0].initialize(from: src.baseAddress!, count: samples.count)
    }

    return buffer
  }

  /// Map the app's `TranscriptionLanguage` to a `Locale` for `SFSpeechRecognizer`.
  private static func locale(for language: TranscriptionLanguage) -> Locale {
    switch language {
    case .auto:
      return Locale.current
    default:
      // SFSpeechRecognizer accepts standard BCP-47 / ISO-639-1 codes
      return Locale(identifier: language.rawValue)
    }
  }
}
