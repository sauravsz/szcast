import Foundation
import Vision
import AppKit

@main
@MainActor
struct ScreenCaptureTests {
    static var failures = 0
    static var passes = 0

    static func main() {
        testScreenCaptureResultModel()
        testURLDetection()
        testDisplaySummaryFormatting()
        testCommandIntegration()

        print("ScreenCaptureTests: \(passes) passed, \(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }

    static func testScreenCaptureResultModel() {
        let textResult = ScreenCaptureResult(kind: .text("Hello World"), rawText: "Hello World")
        expect(textResult.rawText == "Hello World", "rawText is Hello World")
        if case .text(let t) = textResult.kind {
            expect(t == "Hello World", "kind is .text")
        } else {
            expect(false, "expected kind to be .text")
        }

        let qrResult = ScreenCaptureResult(kind: .qrCode(payload: "https://szcast.vercel.app"), rawText: "https://szcast.vercel.app")
        expect(qrResult.rawText == "https://szcast.vercel.app", "qr rawText matches")
        if case .qrCode(let p) = qrResult.kind {
            expect(p == "https://szcast.vercel.app", "kind is .qrCode")
        } else {
            expect(false, "expected kind to be .qrCode")
        }

        // Equatable
        let same = ScreenCaptureResult(kind: .text("Hello World"), rawText: "Hello World")
        expect(textResult == same, "ScreenCaptureResult conforms to Equatable")
    }

    static func testURLDetection() {
        let validURL1 = ScreenCaptureResult(kind: .text("https://szcast.vercel.app"), rawText: "https://szcast.vercel.app")
        expect(validURL1.isURL, "https://szcast.vercel.app is detected as URL")

        let validURL2 = ScreenCaptureResult(kind: .qrCode(payload: "http://localhost:8080/api"), rawText: "http://localhost:8080/api")
        expect(validURL2.isURL, "http://localhost:8080/api is detected as URL")

        let invalidURL = ScreenCaptureResult(kind: .text("Just some regular text captured from screen"), rawText: "Just some regular text captured from screen")
        expect(!invalidURL.isURL, "plain text is not detected as URL")

        let partial = ScreenCaptureResult(kind: .text("not_a_url"), rawText: "not_a_url")
        expect(!partial.isURL, "single word without scheme is not URL")
    }

    static func testDisplaySummaryFormatting() {
        let qr = ScreenCaptureResult(kind: .qrCode(payload: "https://example.com"), rawText: "https://example.com")
        expect(qr.displaySummary == "QR Code: https://example.com", "qr displaySummary format")

        let shortText = ScreenCaptureResult(kind: .text("Short snippet"), rawText: "Short snippet")
        expect(shortText.displaySummary == "Short snippet", "short text is not truncated")

        let longString = "This is a very long recognized text string that definitely exceeds sixty characters in total length"
        let longResult = ScreenCaptureResult(kind: .text(longString), rawText: longString)
        expect(longResult.displaySummary.count == 60, "long text summary is capped to 60 chars")
        expect(longResult.displaySummary.hasSuffix("..."), "long text summary ends with ellipsis")
    }

    static func testCommandIntegration() {
        expect(CommandID.captureScreenText.name == "Capture Screen Text (OCR)", "command name")
        expect(CommandID.captureScreenText.sfSymbol == "text.viewfinder", "command symbol")
        expect(CommandID.scanQRCode.name == "Scan QR Code", "qr command name")
        expect(CommandID.scanQRCode.sfSymbol == "qrcode.viewfinder", "qr command symbol")

        expect(CommandID.captureScreenText.hotKeyAction == .command(.captureScreenText), "has hotKeyAction")
        expect(CommandID.scanQRCode.hotKeyAction == .command(.scanQRCode), "has hotKeyAction")

        let ocrTerms = CommandID.captureScreenText.boostedTerms
        expect(ocrTerms.contains("ocr") && ocrTerms.contains("screen text"), "boosted search terms for OCR")

        let qrTerms = CommandID.scanQRCode.boostedTerms
        expect(qrTerms.contains("qr") && qrTerms.contains("barcode"), "boosted search terms for QR")
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
