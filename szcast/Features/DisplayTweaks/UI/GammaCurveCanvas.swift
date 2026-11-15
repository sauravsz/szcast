import SwiftUI

struct GammaCurveCanvas: View {
    let redTable: [Float]
    let greenTable: [Float]
    let blueTable: [Float]

    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            let pad: CGFloat = 8
            let gw = w - pad * 2
            let gh = h - pad * 2

            // Background surface
            let bgRect = CGRect(origin: .zero, size: size)
            context.fill(Path(roundedRect: bgRect, cornerRadius: 6), with: .color(Color(nsColor: .windowBackgroundColor).opacity(0.8)))

            // Inner graph frame
            let graphRect = CGRect(x: pad, y: pad, width: gw, height: gh)
            context.stroke(Path(graphRect), with: .color(.secondary.opacity(0.3)), lineWidth: 0.5)

            // Grid lines (quarter steps)
            for step in 1...3 {
                let frac = CGFloat(step) / 4.0
                let x = pad + gw * frac
                let y = pad + gh * (1.0 - frac)

                var vLine = Path()
                vLine.move(to: CGPoint(x: x, y: pad))
                vLine.addLine(to: CGPoint(x: x, y: pad + gh))
                context.stroke(vLine, with: .color(.secondary.opacity(0.15)), lineWidth: 0.5)

                var hLine = Path()
                hLine.move(to: CGPoint(x: pad, y: y))
                hLine.addLine(to: CGPoint(x: pad + gw, y: y))
                context.stroke(hLine, with: .color(.secondary.opacity(0.15)), lineWidth: 0.5)
            }

            // Diagonal baseline reference (dashed)
            var diag = Path()
            diag.move(to: CGPoint(x: pad, y: pad + gh))
            diag.addLine(to: CGPoint(x: pad + gw, y: pad))
            context.stroke(diag, with: .color(.secondary.opacity(0.25)), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

            // Transfer Curves
            if redTable.count == 256 {
                drawCurve(table: redTable, color: Color.red.opacity(0.85), in: graphRect, context: &context)
            }
            if greenTable.count == 256 {
                drawCurve(table: greenTable, color: Color.green.opacity(0.85), in: graphRect, context: &context)
            }
            if blueTable.count == 256 {
                drawCurve(table: blueTable, color: Color.blue.opacity(0.85), in: graphRect, context: &context)
            }
        }
        .frame(height: 120)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func drawCurve(table: [Float], color: Color, in rect: CGRect, context: inout GraphicsContext) {
        var path = Path()
        for i in 0..<table.count {
            let xFrac = CGFloat(i) / 255.0
            let yFrac = CGFloat(min(1.0, max(0.0, table[i])))
            let x = rect.minX + rect.width * xFrac
            let y = rect.maxY - rect.height * yFrac
            if i == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        context.stroke(path, with: .color(color), lineWidth: 1.5)
    }
}
