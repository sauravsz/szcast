import CoreAudio
import Foundation

@MainActor
final class AudioDeviceService {
    static let shared = AudioDeviceService()

    func outputDevices() -> [AudioDevice] {
        devices().filter { $0.isOutput }
    }

    func inputDevices() -> [AudioDevice] {
        devices().filter { $0.isInput }
    }

    func defaultOutputDevice() -> AudioDevice? {
        defaultDevice(scope: kAudioObjectPropertyScopeGlobal, selector: kAudioHardwarePropertyDefaultOutputDevice)
    }

    func defaultInputDevice() -> AudioDevice? {
        defaultDevice(scope: kAudioObjectPropertyScopeGlobal, selector: kAudioHardwarePropertyDefaultInputDevice)
    }

    @discardableResult
    func setDefaultOutputDevice(_ deviceID: AudioDeviceID) -> Bool {
        setDefaultDevice(deviceID, selector: kAudioHardwarePropertyDefaultOutputDevice)
    }

    @discardableResult
    func setDefaultInputDevice(_ deviceID: AudioDeviceID) -> Bool {
        setDefaultDevice(deviceID, selector: kAudioHardwarePropertyDefaultInputDevice)
    }

    func cycleNextOutputDevice() -> AudioDevice? {
        let outputs = outputDevices()
        guard outputs.count > 1, let current = defaultOutputDevice() else {
            return outputs.first
        }
        if let idx = outputs.firstIndex(where: { $0.id == current.id }) {
            let nextIndex = (idx + 1) % outputs.count
            let next = outputs[nextIndex]
            setDefaultOutputDevice(next.id)
            return next
        } else if let first = outputs.first {
            setDefaultOutputDevice(first.id)
            return first
        }
        return nil
    }

    func cycleNextInputDevice() -> AudioDevice? {
        let inputs = inputDevices()
        guard inputs.count > 1, let current = defaultInputDevice() else {
            return inputs.first
        }
        if let idx = inputs.firstIndex(where: { $0.id == current.id }) {
            let nextIndex = (idx + 1) % inputs.count
            let next = inputs[nextIndex]
            setDefaultInputDevice(next.id)
            return next
        } else if let first = inputs.first {
            setDefaultInputDevice(first.id)
            return first
        }
        return nil
    }

    private func devices() -> [AudioDevice] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr, size > 0 else {
            return []
        }

        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceIDs) == noErr else {
            return []
        }

        let defaultOut = defaultOutputDevice()?.id
        let defaultIn = defaultInputDevice()?.id

        var results: [AudioDevice] = []
        for devID in deviceIDs {
            guard let name = deviceName(devID), !name.isEmpty else { continue }
            let uid = deviceUID(devID) ?? "\(devID)"
            let isOut = hasStreams(devID, scope: kAudioDevicePropertyScopeOutput)
            let isIn = hasStreams(devID, scope: kAudioDevicePropertyScopeInput)
            if !isOut && !isIn { continue }

            let isDef = (isOut && devID == defaultOut) || (isIn && devID == defaultIn)
            results.append(AudioDevice(id: devID, name: name, uid: uid, isInput: isIn, isOutput: isOut, isDefault: isDef))
        }
        return results
    }

    private func defaultDevice(scope: AudioObjectPropertyScope, selector: AudioObjectPropertySelector) -> AudioDevice? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var devID = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &devID) == noErr,
              devID != kAudioObjectUnknown,
              let name = deviceName(devID) else {
            return nil
        }
        let uid = deviceUID(devID) ?? "\(devID)"
        return AudioDevice(
            id: devID,
            name: name,
            uid: uid,
            isInput: selector == kAudioHardwarePropertyDefaultInputDevice,
            isOutput: selector == kAudioHardwarePropertyDefaultOutputDevice,
            isDefault: true
        )
    }

    private func setDefaultDevice(_ deviceID: AudioDeviceID, selector: AudioObjectPropertySelector) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var devID = deviceID
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, size, &devID)
        return status == noErr
    }

    private func deviceName(_ deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &name)
        return status == noErr ? (name?.takeRetainedValue() as String?) : nil
    }

    private func deviceUID(_ deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var uid: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &uid)
        return status == noErr ? (uid?.takeRetainedValue() as String?) : nil
    }

    private func hasStreams(_ deviceID: AudioDeviceID, scope: AudioObjectPropertyScope) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size)
        return status == noErr && size > 0
    }
}
