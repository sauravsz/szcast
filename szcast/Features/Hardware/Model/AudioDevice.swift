import CoreAudio
import Foundation

struct AudioDevice: Identifiable, Hashable, Sendable {
    let id: AudioDeviceID
    let name: String
    let uid: String
    let isInput: Bool
    let isOutput: Bool
    let isDefault: Bool
}
