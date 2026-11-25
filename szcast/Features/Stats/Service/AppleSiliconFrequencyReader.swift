import Foundation
import IOKit
import Darwin

/// Samples Apple Silicon E/P cluster frequencies via IOReport and pmgr DVFS tables without root.
@MainActor
final class AppleSiliconFrequencyReader {
    private typealias CopyChannelsFn = @convention(c) (
        CFString?, CFString?, UInt64, UInt64, UInt64
    ) -> Unmanaged<CFMutableDictionary>?
    private typealias CreateSubFn = @convention(c) (
        UnsafeMutableRawPointer?,
        CFMutableDictionary,
        UnsafeMutablePointer<Unmanaged<CFMutableDictionary>?>?,
        UInt64,
        CFTypeRef?
    ) -> UnsafeMutableRawPointer?
    private typealias CreateSamplesFn = @convention(c) (
        UnsafeMutableRawPointer?, CFMutableDictionary?, CFTypeRef?
    ) -> Unmanaged<CFDictionary>?
    private typealias CreateDeltaFn = @convention(c) (
        CFDictionary, CFDictionary, CFTypeRef?
    ) -> Unmanaged<CFDictionary>?
    private typealias StateCountFn = @convention(c) (CFDictionary) -> Int32
    private typealias StateNameFn = @convention(c) (CFDictionary, Int32) -> Unmanaged<CFString>?
    private typealias StateResidencyFn = @convention(c) (CFDictionary, Int32) -> Int64
    private typealias ChannelNameFn = @convention(c) (CFDictionary) -> Unmanaged<CFString>?
    private typealias IterateBlock = @convention(block) (CFDictionary) -> Int32
    private typealias IterateFn = @convention(c) (CFDictionary, IterateBlock) -> Void

    private struct API {
        let createSamples: CreateSamplesFn
        let createDelta: CreateDeltaFn
        let stateCount: StateCountFn
        let stateName: StateNameFn
        let stateResidency: StateResidencyFn
        let channelName: ChannelNameFn
        let iterate: IterateFn
    }

    private let eFrequenciesMHz: [Double]
    private let pFrequenciesMHz: [Double]
    private let api: API?
    private let subscription: UnsafeMutableRawPointer?
    private let subscribedChannels: CFMutableDictionary?
    private var previousSample: CFDictionary?

    init() {
        let dvfs = Self.readDVFSFrequencies()
        eFrequenciesMHz = dvfs.efficiency
        pFrequenciesMHz = dvfs.performance

        guard (!eFrequenciesMHz.isEmpty || !pFrequenciesMHz.isEmpty),
              let handle = dlopen("/usr/lib/libIOReport.dylib", RTLD_NOW),
              let copyChannelsSym = dlsym(handle, "IOReportCopyChannelsInGroup"),
              let createSubSym = dlsym(handle, "IOReportCreateSubscription"),
              let createSamplesSym = dlsym(handle, "IOReportCreateSamples"),
              let createDeltaSym = dlsym(handle, "IOReportCreateSamplesDelta"),
              let stateCountSym = dlsym(handle, "IOReportStateGetCount"),
              let stateNameSym = dlsym(handle, "IOReportStateGetNameForIndex"),
              let stateResidencySym = dlsym(handle, "IOReportStateGetResidency"),
              let channelNameSym = dlsym(handle, "IOReportChannelGetChannelName"),
              let iterateSym = dlsym(handle, "IOReportIterate")
        else {
            api = nil
            subscription = nil
            subscribedChannels = nil
            return
        }

        let copyChannels = unsafeBitCast(copyChannelsSym, to: CopyChannelsFn.self)
        let createSub = unsafeBitCast(createSubSym, to: CreateSubFn.self)
        let loadedAPI = API(
            createSamples: unsafeBitCast(createSamplesSym, to: CreateSamplesFn.self),
            createDelta: unsafeBitCast(createDeltaSym, to: CreateDeltaFn.self),
            stateCount: unsafeBitCast(stateCountSym, to: StateCountFn.self),
            stateName: unsafeBitCast(stateNameSym, to: StateNameFn.self),
            stateResidency: unsafeBitCast(stateResidencySym, to: StateResidencyFn.self),
            channelName: unsafeBitCast(channelNameSym, to: ChannelNameFn.self),
            iterate: unsafeBitCast(iterateSym, to: IterateFn.self)
        )

        guard let channels = copyChannels(
            "CPU Stats" as CFString,
            "CPU Complex Performance States" as CFString,
            0, 0, 0
        )?.takeRetainedValue() else {
            api = nil
            subscription = nil
            subscribedChannels = nil
            return
        }

        var subbed: Unmanaged<CFMutableDictionary>?
        guard let sub = createSub(nil, channels, &subbed, 0, nil),
              let subDict = subbed?.takeRetainedValue() else {
            api = nil
            subscription = nil
            subscribedChannels = nil
            return
        }

        api = loadedAPI
        subscription = sub
        subscribedChannels = subDict
        previousSample = loadedAPI.createSamples(sub, subDict, nil)?.takeRetainedValue()
    }

    func sample(
        efficiencyCores: Int,
        performanceCores: Int
    ) -> (allMHz: Int?, efficiencyMHz: Int?, performanceMHz: Int?) {
        guard let api, let subscription, let subscribedChannels,
              let current = api.createSamples(subscription, subscribedChannels, nil)?.takeRetainedValue()
        else {
            return (nil, nil, nil)
        }
        defer { previousSample = current }

        guard let previous = previousSample,
              let delta = api.createDelta(previous, current, nil)?.takeRetainedValue() else {
            return (nil, nil, nil)
        }

        var eSumMHz: Double = 0
        var eSamples: Int = 0
        var pSumMHz: Double = 0
        var pSamples: Int = 0

        api.iterate(delta) { entry in
            let name = api.channelName(entry)?.takeUnretainedValue() as String? ?? ""
            let isEfficiency = name.hasPrefix("ECPU")
            let isPerformance = name.hasPrefix("PCPU")
            guard isEfficiency || isPerformance else { return 0 }

            let table = isEfficiency ? self.eFrequenciesMHz : self.pFrequenciesMHz
            guard let freq = Self.weightedFrequency(entry: entry, table: table, api: api) else {
                return 0
            }
            if isEfficiency {
                eSumMHz += freq
                eSamples += 1
            } else {
                pSumMHz += freq
                pSamples += 1
            }
            return 0
        }

        let eMHz = eSamples > 0 ? Int((eSumMHz / Double(eSamples)).rounded()) : nil
        let pMHz = pSamples > 0 ? Int((pSumMHz / Double(pSamples)).rounded()) : nil

        let allMHz: Int?
        if let e = eMHz, let p = pMHz {
            let eWeight = max(1, efficiencyCores)
            let pWeight = max(1, performanceCores)
            allMHz = Int(((Double(e * eWeight + p * pWeight)) / Double(eWeight + pWeight)).rounded())
        } else {
            allMHz = pMHz ?? eMHz
        }
        return (allMHz, eMHz, pMHz)
    }

    private static func weightedFrequency(entry: CFDictionary, table: [Double], api: API) -> Double? {
        guard !table.isEmpty else { return nil }
        let count = api.stateCount(entry)
        var totalActiveResidency: Double = 0
        var weightedSum: Double = 0
        var activeOrdinal = 0

        for idx in 0..<count {
            let stateName = api.stateName(entry, idx)?.takeUnretainedValue() as String? ?? ""
            let upper = stateName.uppercased()
            if upper.contains("IDLE") || upper.contains("OFF") || upper.contains("DOWN") {
                continue
            }
            let residency = api.stateResidency(entry, idx)
            let stateIndex = parsePStateIndex(stateName) ?? activeOrdinal
            activeOrdinal += 1
            guard residency > 0, stateIndex >= 0, stateIndex < table.count else { continue }
            let r = Double(residency)
            totalActiveResidency += r
            weightedSum += r * table[stateIndex]
        }

        guard totalActiveResidency > 0 else { return nil }
        return weightedSum / totalActiveResidency
    }

    /// Parses indices like `V4P0` -> 4; falls back to sequential ordering if name format differs.
    private static func parsePStateIndex(_ name: String) -> Int? {
        guard name.hasPrefix("V") else { return nil }
        let rest = name.dropFirst()
        let digits = rest.prefix(while: { $0.isNumber })
        return digits.isEmpty ? nil : Int(digits)
    }

    private static func readDVFSFrequencies() -> (efficiency: [Double], performance: [Double]) {
        var efficiency: [Double] = []
        var performance: [Double] = []
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("AppleARMIODevice"),
            &iterator
        ) == KERN_SUCCESS else {
            return ([], [])
        }
        defer { IOObjectRelease(iterator) }

        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            var nameBuffer = [CChar](repeating: 0, count: 128)
            IORegistryEntryGetName(service, &nameBuffer)
            let nameBytes = nameBuffer.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }
            guard String(decoding: nameBytes, as: UTF8.self) == "pmgr" else { continue }

            if let eData = IORegistryEntryCreateCFProperty(
                service, "voltage-states1-sram" as CFString, kCFAllocatorDefault, 0
            )?.takeRetainedValue() as? Data {
                efficiency = decodeVoltageStatesMHz(eData)
            }
            if let pData = IORegistryEntryCreateCFProperty(
                service, "voltage-states5-sram" as CFString, kCFAllocatorDefault, 0
            )?.takeRetainedValue() as? Data {
                performance = decodeVoltageStatesMHz(pData)
            }
            if !efficiency.isEmpty || !performance.isEmpty { break }
        }
        return (efficiency, performance)
    }

    private static func decodeVoltageStatesMHz(_ data: Data) -> [Double] {
        guard data.count >= 8 else { return [] }
        return stride(from: 0, to: data.count - 7, by: 8).compactMap { offset in
            let hz = data.withUnsafeBytes { $0.load(fromByteOffset: offset, as: UInt32.self) }
            guard hz > 0 else { return nil }
            return Double(hz) / 1_000_000.0
        }
    }
}
