import AppKit
import Foundation
import Vision

@MainActor
final class ScreenCaptureService {
    static let shared = ScreenCaptureService()

    enum Mode: Sendable {
        case textOCR
        case qrCode
        case any
    }

    private var isCapturing = false

    /// Interactive crosshair screen capture to clipboard without temporary files on disk
    func capture(
        mode: Mode = .any,
        showMessage: (@MainActor (String) -> Void)? = nil,
        completion: (@MainActor (ScreenCaptureResult?) -> Void)? = nil
    ) {
        guard !isCapturing else { return }
        isCapturing = true

        Task.detached { [weak self] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            process.arguments = ["-i", "-c"] // interactive selection straight to clipboard

            do {
                try process.run()
                process.waitUntilExit()

                guard process.terminationStatus == 0 else {
                    await MainActor.run {
                        self?.isCapturing = false
                        completion?(nil)
                    }
                    return
                }

                // Read image from pasteboard
                let imageResult = await MainActor.run { () -> CGImage? in
                    guard let image = NSImage(pasteboard: .general) else { return nil }
                    return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
                }

                guard let cgImage = imageResult else {
                    await MainActor.run {
                        self?.isCapturing = false
                        completion?(nil)
                    }
                    return
                }

                let result = try await Self.processImage(cgImage, mode: mode)

                await MainActor.run {
                    self?.isCapturing = false
                    if let result {
                        // Put recognized text into pasteboard
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(result.rawText, forType: .string)

                        // Show HUD
                        let charCount = result.rawText.count
                        let message = result.isURL
                            ? String(localized: "Scanned URL (\(result.rawText))")
                            : String(localized: "Copied \(charCount) character\(charCount == 1 ? "" : "s") to clipboard")
                        showMessage?(message)

                        completion?(result)
                    } else {
                        showMessage?(String(localized: "No text or QR code detected"))
                        completion?(nil)
                    }
                }
            } catch {
                await MainActor.run {
                    self?.isCapturing = false
                    completion?(nil)
                }
            }
        }
    }

    nonisolated static func processImage(_ image: CGImage, mode: Mode) async throws -> ScreenCaptureResult? {
        let handler = VNImageRequestHandler(cgImage: image, options: [:])

        // 1. If QR code or any mode, check barcodes first
        if mode == .qrCode || mode == .any {
            let barcodeRequest = VNDetectBarcodesRequest()
            barcodeRequest.symbologies = [.qr, .aztec, .dataMatrix, .code128, .ean13]
            try handler.perform([barcodeRequest])

            if let results = barcodeRequest.results, let first = results.first, let payload = first.payloadStringValue, !payload.isEmpty {
                return ScreenCaptureResult(kind: .qrCode(payload: payload), rawText: payload)
            }
        }

        // 2. OCR text detection
        if mode == .textOCR || mode == .any {
            let textRequest = VNRecognizeTextRequest()
            textRequest.recognitionLevel = .accurate
            textRequest.usesLanguageCorrection = true
            try handler.perform([textRequest])

            if let observations = textRequest.results, !observations.isEmpty {
                // Sort vertically top to bottom (VN coordinates: origin is bottom-left)
                let sorted = observations.sorted { obs1, obs2 in
                    obs1.boundingBox.origin.y > obs2.boundingBox.origin.y
                }
                let recognizedLines = sorted.compactMap { $0.topCandidates(1).first?.string }
                let text = recognizedLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    return ScreenCaptureResult(kind: .text(text), rawText: text)
                }
            }
        }

        return nil
    }
}
