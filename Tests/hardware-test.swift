import Foundation
import CoreAudio
import AppKit

@main
@MainActor
struct HardwareTests {
    static var failures = 0
    static var passes = 0

    static func main() {
        testAudioDeviceModel()
        testDisplayBrightnessCalculations()
        testHardwareActions()

        print("HardwareTests: \(passes) passed, \(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }

    static func testAudioDeviceModel() {
        let outDev = AudioDevice(
            id: 42,
            name: "MacBook Pro Speakers",
            uid: "BuiltInSpeakerDevice",
            isInput: false,
            isOutput: true,
            isDefault: true
        )
        expect(outDev.id == 42, "id is 42")
        expect(outDev.name == "MacBook Pro Speakers", "name is MacBook Pro Speakers")
        expect(outDev.uid == "BuiltInSpeakerDevice", "uid matches")
        expect(outDev.isOutput && !outDev.isInput, "is output device")
        expect(outDev.isDefault, "is default device")

        let inDev = AudioDevice(
            id: 84,
            name: "MacBook Pro Microphone",
            uid: "BuiltInMicrophoneDevice",
            isInput: true,
            isOutput: false,
            isDefault: false
        )
        expect(inDev.isInput && !inDev.isOutput, "is input device")
        expect(!inDev.isDefault, "not default device")

        // Equatable / Hashable
        let copy = AudioDevice(
            id: 42,
            name: "MacBook Pro Speakers",
            uid: "BuiltInSpeakerDevice",
            isInput: false,
            isOutput: true,
            isDefault: true
        )
        expect(outDev == copy, "AudioDevice conforms to Equatable")
        expect(Set([outDev, copy]).count == 1, "AudioDevice conforms to Hashable")
    }

    static func testDisplayBrightnessCalculations() {
        // Test clamping logic in brightness adjustment
        func clampBrightness(_ level: Float) -> Float {
            max(0.0, min(1.0, level))
        }

        func stepBrightness(current: Float, delta: Float) -> Float {
            clampBrightness(current + delta)
        }

        expect(clampBrightness(1.5) == 1.0, "clamp upper bound to 1.0")
        expect(clampBrightness(-0.5) == 0.0, "clamp lower bound to 0.0")
        expect(clampBrightness(0.75) == 0.75, "keep in-range brightness")

        expect(abs(stepBrightness(current: 0.5, delta: 0.1) - 0.6) < 0.001, "step up by 0.1")
        expect(abs(stepBrightness(current: 0.5, delta: -0.1) - 0.4) < 0.001, "step down by 0.1")
        expect(stepBrightness(current: 0.95, delta: 0.1) == 1.0, "step up clamps to 1.0")
        expect(stepBrightness(current: 0.05, delta: -0.1) == 0.0, "step down clamps to 0.0")
    }

    static func testHardwareActions() {
        let catalog = SystemActionCatalog.all
        let hardwareIDs: [SystemAction.ID] = [
            .switchAudioOutput,
            .switchAudioInput,
            .brightnessUp,
            .brightnessDown,
            .brightness50,
            .brightness100
        ]

        for id in hardwareIDs {
            let action = catalog.first { $0.id == id }
            expect(action != nil, "action \(id.rawValue) exists in catalog")
            if let action {
                expect(!action.name.isEmpty, "action \(id.rawValue) has non-empty name")
                expect(!action.sfSymbol.isEmpty, "action \(id.rawValue) has non-empty symbol")
                expect(action.confirmation == .none, "action \(id.rawValue) requires no confirmation")
            }
        }
    }

    static func expect(_ condition: Bool, _ label: String) {
        if condition {
            passes += 1
        } else {
            failures += 1
            print("FAIL  \(label)")
        }
    }
}
