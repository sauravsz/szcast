import Foundation

enum TranscriptExportFormat: String, CaseIterable, Identifiable, Sendable {
    case txt
    case md
    case srt
    case vtt
    case json
    case dapt
    case pdf
    case docx

    var id: String { rawValue }
    var fileExtension: String { rawValue }

    var displayName: String {
        switch self {
        case .txt: "Plain Text (.txt)"
        case .md: "Markdown (.md)"
        case .srt: "SubRip Subtitles (.srt)"
        case .vtt: "WebVTT Subtitles (.vtt)"
        case .json: "JSON (.json)"
        case .dapt: "W3C DAPT XML (.dapt)"
        case .pdf: "PDF Document (.pdf)"
        case .docx: "Word Document (.docx)"
        }
    }
}

enum TranscriptExporter {
    static func exportData(
        _ record: TranscriptRecord,
        format: TranscriptExportFormat,
        pdfRenderer: ((TranscriptRecord) -> Data)? = nil
    ) throws -> Data {
        switch format {
        case .txt:
            return Data(renderPlainText(record).utf8)
        case .md:
            return Data(renderMarkdown(record).utf8)
        case .srt:
            return Data(renderSRT(record).utf8)
        case .vtt:
            return Data(renderVTT(record).utf8)
        case .json:
            return try renderJSON(record)
        case .dapt:
            return Data(renderDAPT(record).utf8)
        case .docx:
            return try renderDOCX(record)
        case .pdf:
            if let pdfRenderer { return pdfRenderer(record) }
            throw CocoaError(.coderInvalidValue)
        }
    }

    static func renderPlainText(_ record: TranscriptRecord) -> String {
        let segments = effectiveSegments(for: record)
        let includeSpeakers = hasSpeakerLabels(segments)
        if segments.isEmpty { return record.text }
        return segments.map { segment in
            let stamp = "[\(TranscriptTimeFormat.formatClock(segment.start))]"
            if includeSpeakers, !segment.speaker.isEmpty {
                return "\(stamp) \(segment.speaker): \(segment.text)"
            }
            return segments.count > 1 ? "\(stamp) \(segment.text)" : segment.text
        }.joined(separator: "\n")
    }

    static func renderMarkdown(_ record: TranscriptRecord) -> String {
        var lines = ["# \(record.title)", ""]
        let dateString = ISO8601DateFormatter().string(from: record.createdAt)
        lines.append("- **Source**: \(record.kind.label)")
        lines.append("- **Date**: \(dateString)")
        lines.append("- **Duration**: \(TranscriptTimeFormat.formatClock(record.duration))")
        if let sourceURL = record.sourceURL, !sourceURL.isEmpty {
            lines.append("- **Origin**: \(sourceURL)")
        }
        if !record.speakerNames.isEmpty {
            lines.append("- **Speakers**: \(record.speakerNames.joined(separator: ", "))")
        }
        lines.append("")

        let cleanSummary = record.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanSummary.isEmpty {
            lines += ["## Summary", "", cleanSummary, ""]
        }
        if !record.actionItems.isEmpty {
            lines += ["## Action Items", ""]
            lines += record.actionItems.map { "- [ ] \($0)" }
            lines.append("")
        }
        if !record.decisions.isEmpty {
            lines += ["## Decisions", ""]
            lines += record.decisions.map { "- \($0)" }
            lines.append("")
        }

        lines += ["## Transcript", ""]
        let segments = effectiveSegments(for: record)
        for segment in segments {
            let stamp = "`\(TranscriptTimeFormat.formatClock(segment.start))`"
            if !segment.speaker.isEmpty {
                lines.append("\(stamp) **\(segment.speaker):** \(segment.text)")
            } else {
                lines.append("\(stamp) \(segment.text)")
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    static func renderSRT(_ record: TranscriptRecord) -> String {
        let cues = subtitleCues(for: record)
        let includeSpeakers = hasSpeakerLabels(cues)
        var out = [String]()
        for (index, cue) in cues.enumerated() {
            let start = TranscriptTimeFormat.formatSRT(cue.start)
            let end = TranscriptTimeFormat.formatSRT(max(cue.end, cue.start + 0.25))
            let body = (includeSpeakers && !cue.speaker.isEmpty) ? "[\(cue.speaker)] \(cue.text)" : cue.text
            out.append("\(index + 1)\n\(start) --> \(end)\n\(body)")
        }
        return out.joined(separator: "\n\n") + (out.isEmpty ? "" : "\n")
    }

    static func renderVTT(_ record: TranscriptRecord) -> String {
        let cues = subtitleCues(for: record)
        let includeSpeakers = hasSpeakerLabels(cues)
        var lines = ["WEBVTT", ""]
        for (index, cue) in cues.enumerated() {
            let start = TranscriptTimeFormat.formatVTT(cue.start)
            let end = TranscriptTimeFormat.formatVTT(max(cue.end, cue.start + 0.25))
            let body = (includeSpeakers && !cue.speaker.isEmpty)
                ? "<v \(cue.speaker)>\(cue.text)"
                : cue.text
            lines.append("\(index + 1)")
            lines.append("\(start) --> \(end)")
            lines.append(body)
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    static func renderJSON(_ record: TranscriptRecord) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(record)
    }

    /// W3C Dubbing and Audio Description Profiles of TTML2 (DAPT 1.0) XML representation.
    static func renderDAPT(_ record: TranscriptRecord) -> String {
        let segments = effectiveSegments(for: record)
        var speakerIDs = [String: String]()
        var agentNodes = [String]()
        for segment in segments {
            let name = segment.speaker.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, speakerIDs[name] == nil else { continue }
            let agentID = "spk_\(speakerIDs.count + 1)"
            speakerIDs[name] = agentID
            agentNodes.append("""
                    <ttm:agent xml:id="\(agentID)" type="person">
                      <ttm:name type="full">\(xmlEscape(name))</ttm:name>
                    </ttm:agent>
                """)
        }

        var paragraphs = [String]()
        for segment in segments {
            let begin = TranscriptTimeFormat.formatISO8601Duration(segment.start)
            let end = TranscriptTimeFormat.formatISO8601Duration(max(segment.end, segment.start + 0.1))
            let agentAttr: String
            if let agentID = speakerIDs[segment.speaker.trimmingCharacters(in: .whitespacesAndNewlines)] {
                agentAttr = " ttm:agent=\"#\(agentID)\""
            } else {
                agentAttr = ""
            }
            paragraphs.append(
                "        <p begin=\"\(begin)\" end=\"\(end)\"\(agentAttr)>\(xmlEscape(segment.text))</p>"
            )
        }

        return """
            <?xml version="1.0" encoding="UTF-8"?>
            <tt xml:lang="en" xmlns="http://www.w3.org/ns/ttml"
                xmlns:ttm="http://www.w3.org/ns/ttml#metadata"
                xmlns:daptm="http://www.w3.org/ns/ttml/profile/dapt#metadata"
                daptm:represents="audio.dialogue">
              <head>
                <metadata>
                  <ttm:title>\(xmlEscape(record.title))</ttm:title>
            \(agentNodes.joined(separator: "\n"))
                </metadata>
              </head>
              <body>
                <div>
            \(paragraphs.joined(separator: "\n"))
                </div>
              </body>
            </tt>
            """
    }

    static func renderDOCX(_ record: TranscriptRecord) throws -> Data {
        let segments = effectiveSegments(for: record)
        var bodyParagraphs = [
            docxParagraph(record.title, bold: true, sizeHalfPoints: 32, spacingAfter: 120),
            docxParagraph(
                "\(record.kind.label)  |  \(TranscriptTimeFormat.formatClock(record.duration))",
                bold: false, sizeHalfPoints: 18, colorHex: "666666", spacingAfter: 200
            )
        ]

        let cleanSummary = record.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanSummary.isEmpty {
            bodyParagraphs.append(docxParagraph("Summary", bold: true, sizeHalfPoints: 24, spacingAfter: 80))
            bodyParagraphs.append(docxParagraph(cleanSummary, bold: false, sizeHalfPoints: 22, spacingAfter: 160))
        }
        if !record.actionItems.isEmpty {
            bodyParagraphs.append(docxParagraph("Action Items", bold: true, sizeHalfPoints: 24, spacingAfter: 80))
            for item in record.actionItems {
                bodyParagraphs.append(docxParagraph("• \(item)", bold: false, sizeHalfPoints: 22, spacingAfter: 60))
            }
        }
        if !record.decisions.isEmpty {
            bodyParagraphs.append(docxParagraph("Decisions", bold: true, sizeHalfPoints: 24, spacingAfter: 80))
            for item in record.decisions {
                bodyParagraphs.append(docxParagraph("• \(item)", bold: false, sizeHalfPoints: 22, spacingAfter: 60))
            }
        }

        bodyParagraphs.append(docxParagraph("Transcript", bold: true, sizeHalfPoints: 24, spacingAfter: 100))
        for segment in segments {
            let stamp = "[\(TranscriptTimeFormat.formatClock(segment.start))]"
            let header = segment.speaker.isEmpty ? stamp : "\(stamp) \(segment.speaker)"
            bodyParagraphs.append(docxParagraph(header, bold: true, sizeHalfPoints: 20, colorHex: "4F46E5", spacingAfter: 40))
            bodyParagraphs.append(docxParagraph(segment.text, bold: false, sizeHalfPoints: 22, spacingAfter: 140))
        }

        let documentXML = """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
              <w:body>
                \(bodyParagraphs.joined(separator: "\n    "))
                <w:sectPr><w:pgSz w:w="12240" w:h="15840"/></w:sectPr>
              </w:body>
            </w:document>
            """

        let contentTypesXML = """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
              <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
              <Default Extension="xml" ContentType="application/xml"/>
              <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
            </Types>
            """

        let relsXML = """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
              <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
            </Relationships>
            """

        let docRelsXML = """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"/>
            """

        return try ZipArchiveBuilder.build(entries: [
            ("[Content_Types].xml", Data(contentTypesXML.utf8)),
            ("_rels/.rels", Data(relsXML.utf8)),
            ("word/_rels/document.xml.rels", Data(docRelsXML.utf8)),
            ("word/document.xml", Data(documentXML.utf8))
        ])
    }

    // MARK: - Helpers

    private static func effectiveSegments(for record: TranscriptRecord) -> [TranscriptSegment] {
        if !record.segments.isEmpty { return record.segments }
        let trimmed = record.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return [TranscriptSegment(speaker: "", text: trimmed, start: 0, end: max(1, record.duration))]
    }

    private static func subtitleCues(for record: TranscriptRecord) -> [TranscriptSegment] {
        let base = effectiveSegments(for: record)
        var result = [TranscriptSegment]()
        for seg in base {
            if !seg.words.isEmpty && seg.words.count > 12 {
                result += TranscriptSegmentBuilder.build(
                    words: seg.words,
                    turns: seg.speaker.isEmpty ? [] : [SpeakerTurn(speaker: seg.speaker, start: seg.start, end: seg.end)],
                    maxSegmentWords: 12,
                    pauseThreshold: 0.7
                )
            } else {
                result.append(seg)
            }
        }
        return result
    }

    private static func hasSpeakerLabels(_ segments: [TranscriptSegment]) -> Bool {
        segments.contains { !$0.speaker.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private static func docxParagraph(
        _ text: String, bold: Bool, sizeHalfPoints: Int, colorHex: String? = nil, spacingAfter: Int
    ) -> String {
        let colorTag = colorHex.map { "<w:color w:val=\"\($0)\"/>" } ?? ""
        let boldTag = bold ? "<w:b/>" : ""
        return """
            <w:p>
              <w:pPr><w:spacing w:after="\(spacingAfter)"/></w:pPr>
              <w:r>
                <w:rPr>\(boldTag)<w:sz w:val="\(sizeHalfPoints)"/>\(colorTag)</w:rPr>
                <w:t xml:space="preserve">\(xmlEscape(text))</w:t>
              </w:r>
            </w:p>
            """
    }

    private static func xmlEscape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}

private enum ZipArchiveBuilder {
    static func build(entries: [(name: String, data: Data)]) throws -> Data {
        var archive = Data()
        var centralDirectory = Data()

        for (name, uncompressed) in entries {
            let nameData = Data(name.utf8)
            let crc = Zlib.crc32(uncompressed)
            let compressed = try Zlib.deflateRaw(uncompressed)
            let offset = UInt32(archive.count)

            appendUInt32(&archive, 0x0403_4B50)
            appendUInt16(&archive, 20)
            appendUInt16(&archive, 0x0800)
            appendUInt16(&archive, 8)
            appendUInt16(&archive, 0)
            appendUInt16(&archive, 0)
            appendUInt32(&archive, crc)
            appendUInt32(&archive, UInt32(compressed.count))
            appendUInt32(&archive, UInt32(uncompressed.count))
            appendUInt16(&archive, UInt16(nameData.count))
            appendUInt16(&archive, 0)
            archive.append(nameData)
            archive.append(compressed)

            appendUInt32(&centralDirectory, 0x0201_4B50)
            appendUInt16(&centralDirectory, 20)
            appendUInt16(&centralDirectory, 20)
            appendUInt16(&centralDirectory, 0x0800)
            appendUInt16(&centralDirectory, 8)
            appendUInt16(&centralDirectory, 0)
            appendUInt16(&centralDirectory, 0)
            appendUInt32(&centralDirectory, crc)
            appendUInt32(&centralDirectory, UInt32(compressed.count))
            appendUInt32(&centralDirectory, UInt32(uncompressed.count))
            appendUInt16(&centralDirectory, UInt16(nameData.count))
            appendUInt16(&centralDirectory, 0)
            appendUInt16(&centralDirectory, 0)
            appendUInt16(&centralDirectory, 0)
            appendUInt16(&centralDirectory, 0)
            appendUInt32(&centralDirectory, 0)
            appendUInt32(&centralDirectory, offset)
            centralDirectory.append(nameData)
        }

        let centralOffset = UInt32(archive.count)
        archive.append(centralDirectory)
        appendUInt32(&archive, 0x0605_4B50)
        appendUInt16(&archive, 0)
        appendUInt16(&archive, 0)
        appendUInt16(&archive, UInt16(entries.count))
        appendUInt16(&archive, UInt16(entries.count))
        appendUInt32(&archive, UInt32(centralDirectory.count))
        appendUInt32(&archive, centralOffset)
        appendUInt16(&archive, 0)
        return archive
    }

    private static func appendUInt16(_ data: inout Data, _ value: UInt16) {
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }

    private static func appendUInt32(_ data: inout Data, _ value: UInt32) {
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }
}
