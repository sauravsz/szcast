import CoreGraphics
import CoreText
import Foundation

enum TranscriptPDFExporter {
    static func render(record: TranscriptRecord) -> Data {
        let pageSize = CGSize(width: 612, height: 792)
        let margin: CGFloat = 48
        let contentRect = CGRect(
            x: margin, y: margin, width: pageSize.width - margin * 2, height: pageSize.height - margin * 2)

        let data = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
            let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
        else { return Data() }

        let attributed = buildAttributedText(record: record)
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        var currentIndex = 0
        let totalLength = attributed.length

        while currentIndex < totalLength {
            context.beginPDFPage(nil)
            let path = CGMutablePath()
            path.addRect(contentRect)
            let frame = CTFramesetterCreateFrame(
                framesetter, CFRange(location: currentIndex, length: 0), path, nil)
            CTFrameDraw(frame, context)
            let visible = CTFrameGetVisibleStringRange(frame)
            context.endPDFPage()
            guard visible.length > 0 else { break }
            currentIndex += visible.length
        }

        context.closePDF()
        return data as Data
    }

    private static func buildAttributedText(record: TranscriptRecord) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let titleFont = CTFontCreateWithName("HelveticaNeue-Bold" as CFString, 18, nil)
        let headingFont = CTFontCreateWithName("HelveticaNeue-Bold" as CFString, 12, nil)
        let metaFont = CTFontCreateWithName("HelveticaNeue" as CFString, 10, nil)
        let bodyFont = CTFontCreateWithName("HelveticaNeue" as CFString, 11, nil)
        let muted = CGColor(gray: 0.4, alpha: 1)
        let ink = CGColor(gray: 0.1, alpha: 1)

        func append(_ string: String, font: CTFont, color: CGColor) {
            out.append(NSAttributedString(string: string, attributes: [
                kCTFontAttributeName as NSAttributedString.Key: font,
                kCTForegroundColorAttributeName as NSAttributedString.Key: color
            ]))
        }

        append("\(record.title)\n", font: titleFont, color: ink)
        let dateString = ISO8601DateFormatter().string(from: record.createdAt)
        append(
            "\(record.kind.label)  |  \(TranscriptTimeFormat.formatClock(record.duration))  |  \(dateString)\n\n",
            font: metaFont,
            color: muted
        )

        if !record.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            append("Summary\n", font: headingFont, color: ink)
            append("\(record.summary)\n\n", font: bodyFont, color: ink)
        }
        if !record.actionItems.isEmpty {
            append("Action Items\n", font: headingFont, color: ink)
            for item in record.actionItems { append("• \(item)\n", font: bodyFont, color: ink) }
            append("\n", font: bodyFont, color: ink)
        }
        if !record.decisions.isEmpty {
            append("Decisions\n", font: headingFont, color: ink)
            for item in record.decisions { append("• \(item)\n", font: bodyFont, color: ink) }
            append("\n", font: bodyFont, color: ink)
        }

        append("Transcript\n\n", font: headingFont, color: ink)
        if record.segments.isEmpty {
            append(record.text, font: bodyFont, color: ink)
        } else {
            for segment in record.segments {
                let ts = "[\(TranscriptTimeFormat.formatClock(segment.start))]"
                let label = segment.speaker.isEmpty ? ts : "\(ts) \(segment.speaker)"
                append("\(label)\n", font: headingFont, color: muted)
                append("\(segment.text)\n\n", font: bodyFont, color: ink)
            }
        }
        return out
    }
}
