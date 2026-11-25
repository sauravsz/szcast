import Foundation

@main
struct TranscriptExportTest {
    static func main() throws {
        // Test subword merging + speaker attribution + dual-track merge.
        let words = TranscriptSegmentBuilder.mergeSubwordPieces([
            ("▁Hello", 0.0, 0.24),
            ("▁world", 0.24, 0.56),
            ("▁today", 1.1, 1.44),
            (".", 1.44, 1.52)
        ])
        guard words.map(\.text) == ["Hello", "world", "today", "."] || words.map(\.text) == ["Hello", "world", "today."] else {
            fatalError("Unexpected merged words: \(words.map(\.text))")
        }

        let turns = [
            SpeakerTurn(speaker: "Alice", start: 0.0, end: 0.9),
            SpeakerTurn(speaker: "Bob", start: 1.0, end: 2.0)
        ]
        let built = TranscriptSegmentBuilder.build(words: words, turns: turns, pauseThreshold: 0.5)
        guard built.count == 2, built[0].speaker == "Alice", built[1].speaker == "Bob" else {
            fatalError("Speaker attribution failed: \(built)")
        }

        let record = TranscriptRecord(
            kind: .meeting,
            title: "Q4 Planning & Review <Alpha>",
            duration: 125.0,
            text: "Hello world today.",
            summary: "Discussed Q4 milestones.",
            actionItems: ["Ship export suite"],
            decisions: ["Support 8 formats"],
            segments: built
        )

        // 1. TXT
        let txt = String(decoding: try TranscriptExporter.exportData(record, format: .txt), as: UTF8.self)
        guard txt.contains("Alice:") && txt.contains("Bob:") else { fatalError("TXT missing speakers") }

        // 2. MD
        let md = String(decoding: try TranscriptExporter.exportData(record, format: .md), as: UTF8.self)
        guard md.contains("# Q4 Planning") && md.contains("## Action Items") else { fatalError("MD failed") }

        // 3. SRT
        let srt = String(decoding: try TranscriptExporter.exportData(record, format: .srt), as: UTF8.self)
        guard srt.contains("00:00:00,000 -->") && srt.contains("[Alice]") else { fatalError("SRT failed") }

        // 4. VTT
        let vtt = String(decoding: try TranscriptExporter.exportData(record, format: .vtt), as: UTF8.self)
        guard vtt.hasPrefix("WEBVTT") && vtt.contains("<v Alice>") else { fatalError("VTT failed") }

        // 5. JSON
        let json = try TranscriptExporter.exportData(record, format: .json)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(TranscriptRecord.self, from: json)
        guard decoded.id == record.id && decoded.title == record.title else { fatalError("JSON roundtrip failed") }

        // 6. DAPT XML (W3C TTML DAPT 1.0)
        let dapt = String(decoding: try TranscriptExporter.exportData(record, format: .dapt), as: UTF8.self)
        guard dapt.contains("daptm:represents=\"audio.dialogue\""),
            dapt.contains("ttm:agent=\"#spk_1\""),
            dapt.contains("&lt;Alpha&gt;")
        else { fatalError("DAPT XML failed: \(dapt)") }

        // 7. DOCX OOXML ZIP archive (PK\x03\x04 local header + valid ZIP structure via Zlib)
        let docx = try TranscriptExporter.exportData(record, format: .docx)
        guard docx.count > 200, docx.starts(with: [0x50, 0x4B, 0x03, 0x04]) else {
            fatalError("DOCX ZIP header invalid")
        }
        let tempDocx = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID()).docx")
        defer { try? FileManager.default.removeItem(at: tempDocx) }
        try docx.write(to: tempDocx)
        let unzipProc = Process()
        unzipProc.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        unzipProc.arguments = ["-t", tempDocx.path]
        unzipProc.standardOutput = FileHandle.nullDevice
        unzipProc.standardError = FileHandle.nullDevice
        try unzipProc.run()
        unzipProc.waitUntilExit()
        guard unzipProc.terminationStatus == 0 else {
            fatalError("DOCX failed unzip -t integrity check")
        }

        // 8. PDF vector document
        let pdf = try TranscriptExporter.exportData(record, format: .pdf) {
            TranscriptPDFExporter.render(record: $0)
        }
        let pdfStr = String(decoding: pdf.prefix(8), as: UTF8.self)
        guard pdfStr.hasPrefix("%PDF-"), pdf.count > 500 else {
            fatalError("PDF header invalid")
        }

        print("All 8 TranscriptExporter formats passed")
    }
}
