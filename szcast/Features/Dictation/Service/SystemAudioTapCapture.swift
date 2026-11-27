import AudioToolbox
import CoreAudio
import Foundation

/// System audio capture via macOS CoreAudio Process Tap (`NSAudioCaptureUsageDescription`, no Screen Recording TCC).
@MainActor
final class SystemAudioTapCapture {
    private final class State: @unchecked Sendable {
        let queue = DispatchQueue(label: "com.sauravsz.szcast.system-audio-tap")
        var samples: [Float] = []
        var isActive = false
        var tapID = AudioObjectID(kAudioObjectUnknown)
        var aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
        var procID: AudioDeviceIOProcID?
        var sourceSampleRate: Double = 48_000
        var sourceChannels: Int = 2
        var phase: Double = 0
        var lastSample: Float = 0

        func installIOProc(on aggregateID: AudioObjectID) -> OSStatus {
            var newProcID: AudioDeviceIOProcID?
            let status = AudioDeviceCreateIOProcIDWithBlock(&newProcID, aggregateID, queue) {
                _, inInputData, _, _, _ in
                self.appendBufferList(inInputData)
            }
            if status == noErr {
                procID = newProcID
                isActive = true
            }
            return status
        }

        func appendBufferList(_ bufferListPtr: UnsafePointer<AudioBufferList>) {
            guard isActive else { return }
            let list = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: bufferListPtr))
            guard let first = list.first, let rawData = first.mData else { return }
            let channels = max(1, Int(first.mNumberChannels))
            let totalFloats = Int(first.mDataByteSize) / MemoryLayout<Float>.size
            let frameCount = list.count > 1 ? totalFloats : (totalFloats / channels)
            guard frameCount > 0 else { return }

            var mono = [Float](repeating: 0, count: frameCount)
            if list.count > 1 {
                for buf in list {
                    guard let ptr = buf.mData else { continue }
                    let floats = ptr.assumingMemoryBound(to: Float.self)
                    let scale = 1.0 / Float(list.count)
                    for i in 0..<frameCount { mono[i] += floats[i] * scale }
                }
            } else {
                let floats = rawData.assumingMemoryBound(to: Float.self)
                let scale = 1.0 / Float(channels)
                for frame in 0..<frameCount {
                    var sum: Float = 0
                    for ch in 0..<channels { sum += floats[frame * channels + ch] }
                    mono[frame] = sum * scale
                }
            }

            let step = sourceSampleRate / Double(DictationWire.sampleRate)
            guard step > 0 else { return }
            while Int(phase) < frameCount {
                let idx = Int(phase)
                let frac = Float(phase - Double(idx))
                let s0 = idx == 0 ? lastSample : mono[idx - 1]
                let s1 = mono[idx]
                samples.append(s0 + (s1 - s0) * frac)
                phase += step
            }
            phase -= Double(frameCount)
            lastSample = mono[frameCount - 1]
        }
    }

    private var state: State?
    private(set) var isCapturing = false

    func start() async throws {
        guard !isCapturing else { return }
        let s = State()
        let myPID = ProcessInfo.processInfo.processIdentifier
        let excludedObjects = Self.translatePIDsToProcessObjects([myPID])
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: excludedObjects)
        description.muteBehavior = .unmuted
        description.isPrivate = true

        var tapID = AudioObjectID(kAudioObjectUnknown)
        let tapStatus = AudioHardwareCreateProcessTap(description, &tapID)
        guard tapStatus == noErr, tapID != AudioObjectID(kAudioObjectUnknown) else {
            throw NSError(
                domain: NSOSStatusErrorDomain, code: Int(tapStatus),
                userInfo: [NSLocalizedDescriptionKey: "CoreAudio Process Tap unavailable (\(tapStatus))"]
            )
        }
        s.tapID = tapID

        guard let tapUUID = Self.tapUID(for: tapID),
            let outputUID = Self.defaultOutputDeviceUID()
        else {
            AudioHardwareDestroyProcessTap(tapID)
            throw NSError(domain: NSOSStatusErrorDomain, code: -1)
        }

        let aggregateDict: [String: Any] = [
            kAudioAggregateDeviceNameKey: "szcast System Audio Tap",
            kAudioAggregateDeviceUIDKey: "com.sauravsz.szcast.tap.\(UUID().uuidString)",
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapUIDKey: tapUUID,
                    kAudioSubTapDriftCompensationKey: true
                ]
            ]
        ]

        var aggregateID = AudioObjectID(kAudioObjectUnknown)
        let aggStatus = AudioHardwareCreateAggregateDevice(aggregateDict as CFDictionary, &aggregateID)
        guard aggStatus == noErr, aggregateID != AudioObjectID(kAudioObjectUnknown) else {
            AudioHardwareDestroyProcessTap(tapID)
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(aggStatus))
        }
        s.aggregateDeviceID = aggregateID

        if let format = Self.tapStreamFormat(for: tapID) {
            s.sourceSampleRate = format.mSampleRate > 0 ? format.mSampleRate : 48_000
            s.sourceChannels = max(1, Int(format.mChannelsPerFrame))
        }

        let ioStatus = s.installIOProc(on: aggregateID)
        guard ioStatus == noErr, let procID = s.procID else {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            AudioHardwareDestroyProcessTap(tapID)
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(ioStatus))
        }

        let startStatus = AudioDeviceStart(aggregateID, procID)
        guard startStatus == noErr else {
            s.isActive = false
            AudioDeviceDestroyIOProcID(aggregateID, procID)
            AudioHardwareDestroyAggregateDevice(aggregateID)
            AudioHardwareDestroyProcessTap(tapID)
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(startStatus))
        }

        self.state = s
        isCapturing = true
    }

    func stop() -> [Float] {
        isCapturing = false
        guard let s = state else { return [] }
        self.state = nil
        let collected = s.queue.sync { () -> [Float] in
            s.isActive = false
            return s.samples
        }
        if let procID = s.procID, s.aggregateDeviceID != AudioObjectID(kAudioObjectUnknown) {
            AudioDeviceStop(s.aggregateDeviceID, procID)
            AudioDeviceDestroyIOProcID(s.aggregateDeviceID, procID)
        }
        if s.aggregateDeviceID != AudioObjectID(kAudioObjectUnknown) {
            AudioHardwareDestroyAggregateDevice(s.aggregateDeviceID)
        }
        if s.tapID != AudioObjectID(kAudioObjectUnknown) {
            AudioHardwareDestroyProcessTap(s.tapID)
        }
        return collected
    }

    private static func translatePIDsToProcessObjects(_ pids: [pid_t]) -> [AudioObjectID] {
        var result = [AudioObjectID]()
        for var pid in pids {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var objID = AudioObjectID(kAudioObjectUnknown)
            var size = UInt32(MemoryLayout<AudioObjectID>.size)
            let status = AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject), &address,
                UInt32(MemoryLayout<pid_t>.size), &pid, &size, &objID
            )
            if status == noErr, objID != AudioObjectID(kAudioObjectUnknown) {
                result.append(objID)
            }
        }
        return result
    }

    private static func tapUID(for tapID: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var uidRef: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &uidRef) == noErr,
            let uid = uidRef?.takeRetainedValue() as String?
        else { return nil }
        return uid
    }

    private static func tapStreamFormat(for tapID: AudioObjectID) -> AudioStreamBasicDescription? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var asbd = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        guard AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &asbd) == noErr else {
            return nil
        }
        return asbd
    }

    private static func defaultOutputDeviceUID() -> String? {
        var devAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var devSize = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &devAddress, 0, nil, &devSize, &deviceID
        ) == noErr, deviceID != AudioObjectID(kAudioObjectUnknown) else { return nil }

        var uidAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var uidRef: Unmanaged<CFString>?
        var uidSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(deviceID, &uidAddress, 0, nil, &uidSize, &uidRef) == noErr,
            let uid = uidRef?.takeRetainedValue() as String?
        else { return nil }
        return uid
    }
}
