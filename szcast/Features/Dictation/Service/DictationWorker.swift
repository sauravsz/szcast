import Foundation
import Synchronization

final class DictationWorker: Sendable {
    private let process: Process
    private let input: FileHandle
    private let output: FileHandle
    private let exit: ProcessExit
    private let queue = DispatchQueue(label: "com.sauravsz.szcast.dictation-worker", qos: .userInitiated)

    init(executable: URL = DictationWorker.executable, arguments: [String] = []) throws {
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.qualityOfService = .userInitiated
        guard fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1) == 0 else {
            throw POSIXError(.EIO)
        }
        self.exit = try process.runObservingExit()
        self.process = process
        self.input = input.fileHandleForWriting
        self.output = output.fileHandleForReading
        try? input.fileHandleForReading.close()
        try? output.fileHandleForWriting.close()
    }

    static var executable: URL {
        Bundle.main.bundleURL.appending(
            path: "Contents/Helpers/\(executableName).app/Contents/MacOS/\(executableName)")
    }

    private static var executableName: String {
        #if DEBUG
            "szcast Dev Dictation"
        #else
            "szcast Dictation"
        #endif
    }

    func transcribe(
        _ samples: [Float], request: DictationWire.Request,
        onReady: @escaping @MainActor @Sendable () -> Void
    ) async throws -> String {
        try await transcribeTimed(samples, request: request, onReady: onReady).text
    }

    func transcribeTimed(
        _ samples: [Float], request: DictationWire.Request,
        onReady: @escaping @MainActor @Sendable () -> Void
    ) async throws -> TimedTranscript {
        try Task.checkCancellation()
        let validCount = samples.count == request.sampleCount && (
            request.prewarmOnly
                ? samples.isEmpty
                : (1...DictationWire.maximumSamples).contains(samples.count)
        )
        guard validCount else {
            throw DictationWire.Failure.unavailable
        }
        // Cold CoreML/ANE specialization can exceed 60s on first load; only bound inference once `.ready` arrives.
        let prepareTimeoutSeconds = 240
        let inferenceTimeoutSeconds = 60 + samples.count / DictationWire.sampleRate * 2
        let prepareDeadline = Task.detached(priority: .utility) {
            do { try await Task.sleep(for: .seconds(prepareTimeoutSeconds)) } catch { return }
            self.terminate()
        }
        let inferenceDeadline = Mutex<Task<Void, Never>?>(nil)
        defer {
            prepareDeadline.cancel()
            inferenceDeadline.withLock { $0?.cancel() }
        }
        return try await withTaskCancellationHandler {
            let responses = AsyncThrowingStream<DictationWire.Response, Error>(
                bufferingPolicy: .bufferingOldest(2)
            ) { continuation in
                queue.async {
                    do {
                        try DictationWire.write(request, to: self.input)
                        guard
                            let ready = try DictationWire.read(
                                DictationWire.Response.self, from: self.output),
                            ready.id == request.id, ready.status == .ready
                        else {
                            throw DictationWire.Failure.unavailable
                        }
                        prepareDeadline.cancel()
                        inferenceDeadline.withLock { slot in
                            slot = Task.detached(priority: .utility) {
                                do { try await Task.sleep(for: .seconds(inferenceTimeoutSeconds)) } catch { return }
                                self.terminate()
                            }
                        }
                        continuation.yield(ready)
                        if !samples.isEmpty {
                            try samples.withUnsafeBytes { try self.input.write(contentsOf: $0) }
                        }
                        guard
                            let result = try DictationWire.read(
                                DictationWire.Response.self, from: self.output),
                            result.id == request.id, result.status == .result
                        else {
                            throw DictationWire.Failure.unavailable
                        }
                        continuation.yield(result)
                        continuation.finish()
                    } catch {
                        self.terminate()
                        continuation.finish(throwing: error)
                    }
                }
            }
            var finalResponse: DictationWire.Response?
            for try await response in responses {
                if response.status == .ready { await onReady() }
                if response.status == .result { finalResponse = response }
            }
            try Task.checkCancellation()
            guard let finalResponse else { throw DictationWire.Failure.unavailable }
            return TimedTranscript(
                text: finalResponse.text,
                words: finalResponse.words,
                segments: finalResponse.segments
            )
        } onCancel: {
            self.terminate()
        }
    }

    var isRunning: Bool {
        process.isRunning
    }

    func terminate() {
        if process.isRunning { process.terminate() }
    }

    func stop() async {
        terminate()
        await withCheckedContinuation { continuation in
            queue.async {
                self.exit.wait()
                try? self.input.close()
                try? self.output.close()
                continuation.resume()
            }
        }
    }
}
