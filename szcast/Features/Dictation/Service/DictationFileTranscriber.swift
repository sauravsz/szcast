import AVFoundation
import Foundation
import OSLog

public enum DictationFileTranscriber {
    private static let logger = Logger(subsystem: "com.sauravsz.szcast", category: "FileTranscriber")

    public enum TranscribeError: LocalizedError {
        case fileNotFound
        case noAudioTrack
        case unableToRead
        case decodingFailed(String)

        public var errorDescription: String? {
            switch self {
            case .fileNotFound:
                return String(localized: "Audio/video file not found.")
            case .noAudioTrack:
                return String(localized: "No audio track found in the selected file.")
            case .unableToRead:
                return String(localized: "Unable to read audio data from the file.")
            case .decodingFailed(let reason):
                return String(localized: "Failed to decode audio: \(reason)")
            }
        }
    }

    /// Decodes any audio or video container file into standard 16kHz 1-channel 32-bit float linear PCM samples.
    public static func extractSamples(from fileURL: URL) async throws -> [Float] {
        let asset = AVURLAsset(url: fileURL, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard let track = audioTracks.first else {
            throw TranscribeError.noAudioTrack
        }

        let reader = try AVAssetReader(asset: asset)
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMIsBigEndianKey: false
        ]

        let trackOutput = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        trackOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(trackOutput) else {
            throw TranscribeError.unableToRead
        }
        reader.add(trackOutput)

        guard reader.startReading() else {
            throw TranscribeError.decodingFailed(reader.error?.localizedDescription ?? "Failed to start asset reader.")
        }

        var samples: [Float] = []
        samples.reserveCapacity(16000 * 60 * 3)

        while reader.status == .reading {
            guard let sampleBuffer = trackOutput.copyNextSampleBuffer() else { break }
            guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }

            var length = 0
            var dataPointer: UnsafeMutablePointer<Int8>?
            let status = CMBlockBufferGetDataPointer(
                blockBuffer,
                atOffset: 0,
                lengthAtOffsetOut: nil,
                totalLengthOut: &length,
                dataPointerOut: &dataPointer
            )

            guard status == kCMBlockBufferNoErr, let dataPointer, length > 0 else { continue }

            let floatCount = length / MemoryLayout<Float>.size
            dataPointer.withMemoryRebound(to: Float.self, capacity: floatCount) { buffer in
                samples.append(contentsOf: UnsafeBufferPointer(start: buffer, count: floatCount))
            }
        }

        if reader.status == .failed {
            throw TranscribeError.decodingFailed(reader.error?.localizedDescription ?? "Reading aborted.")
        }

        return samples
    }
}
