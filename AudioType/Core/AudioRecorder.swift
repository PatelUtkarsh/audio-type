import AVFoundation
import os.log

class AudioRecorder {
  private let audioEngine = AVAudioEngine()
  private var audioBuffer: [Float] = []
  private let bufferLock = NSLock()
  private var isRecording = false

  private let logger = Logger(subsystem: "com.audiotype", category: "AudioRecorder")

  // Whisper requires 16kHz mono audio
  private let targetSampleRate: Double = 16000

  init() {
    // Pre-allocate buffer for ~30 seconds of audio at 16kHz
    audioBuffer.reserveCapacity(Int(targetSampleRate * 30))
  }

  func startRecording() throws {
    guard !isRecording else {
      logger.warning("Already recording")
      return
    }

    // Clear previous buffer
    bufferLock.lock()
    audioBuffer.removeAll(keepingCapacity: true)
    bufferLock.unlock()

    let inputNode = audioEngine.inputNode
    let inputFormat = inputNode.outputFormat(forBus: 0)

    logger.info("Input format: \(inputFormat.sampleRate)Hz, \(inputFormat.channelCount) channels")

    // Create format for Whisper (16kHz mono)
    guard
      let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: targetSampleRate,
        channels: 1,
        interleaved: false
      )
    else {
      throw AudioRecorderError.formatCreationFailed
    }

    // Create converter if sample rates differ
    let converter: AVAudioConverter?
    if inputFormat.sampleRate != targetSampleRate || inputFormat.channelCount != 1 {
      converter = AVAudioConverter(from: inputFormat, to: targetFormat)
      if converter == nil {
        logger.error("Failed to create audio converter")
        throw AudioRecorderError.converterCreationFailed
      }
    } else {
      converter = nil
    }

    // Install tap on input node
    inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
      self?.processAudioBuffer(buffer, converter: converter, targetFormat: targetFormat)
    }

    // Start audio engine
    audioEngine.prepare()
    try audioEngine.start()

    isRecording = true
    logger.info("Recording started")
  }

  func stopRecording() -> [Float]? {
    guard isRecording else {
      logger.warning("Not recording")
      return nil
    }

    // Stop and remove tap
    audioEngine.inputNode.removeTap(onBus: 0)
    audioEngine.stop()

    isRecording = false

    // Return captured samples
    bufferLock.lock()
    let samples = audioBuffer
    bufferLock.unlock()

    logger.info(
      "Recording stopped, captured \(samples.count) samples (\(Double(samples.count) / self.targetSampleRate, format: .fixed(precision: 2))s)"
    )

    return samples.isEmpty ? nil : samples
  }

  private func processAudioBuffer(
    _ buffer: AVAudioPCMBuffer, converter: AVAudioConverter?, targetFormat: AVAudioFormat
  ) {
    var samplesArray: [Float]

    if let converter = converter {
      // Need to convert to target format
      let frameCount = AVAudioFrameCount(
        Double(buffer.frameLength) * targetSampleRate / buffer.format.sampleRate
      )

      guard
        let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCount)
      else {
        logger.error("Failed to create converted buffer")
        return
      }

      var error: NSError?
      let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
        outStatus.pointee = .haveData
        return buffer
      }

      converter.convert(to: convertedBuffer, error: &error, withInputFrom: inputBlock)

      if let error = error {
        logger.error("Conversion error: \(error.localizedDescription)")
        return
      }

      guard let channelData = convertedBuffer.floatChannelData else { return }
      samplesArray = Array(
        UnsafeBufferPointer(start: channelData[0], count: Int(convertedBuffer.frameLength)))
    } else {
      // Already in correct format
      guard let channelData = buffer.floatChannelData else { return }
      samplesArray = Array(
        UnsafeBufferPointer(start: channelData[0], count: Int(buffer.frameLength)))
    }

    // Append to buffer
    bufferLock.lock()
    audioBuffer.append(contentsOf: samplesArray)
    bufferLock.unlock()
  }
}

enum AudioRecorderError: Error, LocalizedError {
  case formatCreationFailed
  case converterCreationFailed
  case engineStartFailed

  var errorDescription: String? {
    switch self {
    case .formatCreationFailed:
      return "Failed to create audio format"
    case .converterCreationFailed:
      return "Failed to create audio converter"
    case .engineStartFailed:
      return "Failed to start audio engine"
    }
  }
}
