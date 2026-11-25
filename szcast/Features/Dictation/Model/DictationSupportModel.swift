import Foundation

enum DictationSupportModel: String, CaseIterable, Identifiable, Codable, Sendable {
    case sileroVAD = "silero-vad"
    case speakerDiarization = "speaker-diarization"

    var id: Self { self }

    var title: String {
        switch self {
        case .sileroVAD: String(localized: "Silero VAD v6")
        case .speakerDiarization: String(localized: "Speaker Diarization")
        }
    }

    var summary: String {
        switch self {
        case .sileroVAD:
            String(localized: "CoreML voice activity detection for silence trimming and long-audio chunking.")
        case .speakerDiarization:
            String(localized: "Offline speaker segmentation and WeSpeaker embeddings for multi-speaker labeling.")
        }
    }

    var folderName: String {
        switch self {
        case .sileroVAD: "silero-vad-coreml"
        case .speakerDiarization: "speaker-diarization-coreml"
        }
    }

    var possibleFolderNames: [String] { [folderName] }

    var components: Set<String> {
        switch self {
        case .sileroVAD:
            return ["silero-vad-unified-256ms-v6.2.1.mlmodelc"]
        case .speakerDiarization:
            return [
                "Segmentation.mlmodelc",
                "FBank.mlmodelc",
                "Embedding.mlmodelc",
                "PLDA.mlmodelc"
            ]
        }
    }

    var requiredFiles: Set<String> { components }

    var repository: String {
        switch self {
        case .sileroVAD: "FluidInference/silero-vad-coreml"
        case .speakerDiarization: "FluidInference/speaker-diarization-coreml"
        }
    }

    var revision: String {
        switch self {
        case .sileroVAD: "b419383c55c110e2c9271fa6ee0ea83d03c70d96"
        case .speakerDiarization: "7eab74f3463c736418d0eb10296261ae581146c9"
        }
    }

    var approximateInstalledMegabytes: Int {
        switch self {
        case .sileroVAD: 2
        case .speakerDiarization: 28
        }
    }
}
