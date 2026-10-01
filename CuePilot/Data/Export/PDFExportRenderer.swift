import UIKit

/// Lays out an `ExportDocument` as a paginated US-Letter PDF with UIKit text drawing.
final class PDFExportRenderer: ExportRendering {
    private let pageSize = CGSize(width: 612, height: 792)
    private let margin: CGFloat = 44

    private enum Ink {
        static let midnight = UIColor(red: 0x14 / 255, green: 0x2B / 255, blue: 0x69 / 255, alpha: 1)
        static let red = UIColor(red: 0xE7 / 255, green: 0x47 / 255, blue: 0x43 / 255, alpha: 1)
        static let yellow = UIColor(red: 0xFF / 255, green: 0xDC / 255, blue: 0x58 / 255, alpha: 1)
        static let paper = UIColor(red: 0xFF / 255, green: 0xF8 / 255, blue: 0xEB / 255, alpha: 1)
        static let text = UIColor(red: 0x18 / 255, green: 0x24 / 255, blue: 0x3D / 255, alpha: 1)
        static let muted = UIColor(red: 0x63 / 255, green: 0x70 / 255, blue: 0x8C / 255, alpha: 1)
        static let rule = UIColor(red: 0xE6 / 255, green: 0xDC / 255, blue: 0xC6 / 255, alpha: 1)
    }

    func pdf(for document: ExportDocument) throws -> Data {
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: "\(document.kindTitle) — \(document.title)",
            kCGPDFContextCreator as String: "Cue Pilot"
        ]
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize), format: format)
        return renderer.pdfData { context in
            var layout = PageLayout(context: context, pageSize: pageSize, margin: margin, footer: document.footer)
            layout.beginPage()
            drawHeader(document, layout: &layout)
            for section in document.sections {
                drawSection(section, layout: &layout)
            }
            layout.finishPage()
        }
    }

    func csv(for table: ExportTable) -> Data {
        func escape(_ value: String) -> String {
            let needsQuotes = value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r")
            let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
            return needsQuotes ? "\"\(escaped)\"" : escaped
        }
        var lines = [table.columns.map(escape).joined(separator: ",")]
        lines += table.rows.map { $0.map(escape).joined(separator: ",") }
        // UTF-8 BOM so spreadsheet apps pick the right encoding.
        return Data([0xEF, 0xBB, 0xBF]) + Data(lines.joined(separator: "\r\n").utf8)
    }

    // MARK: Drawing

    private func drawHeader(_ document: ExportDocument, layout: inout PageLayout) {
        let bandHeight: CGFloat = 92
        let band = CGRect(x: 0, y: 0, width: pageSize.width, height: bandHeight)
        Ink.midnight.setFill()
        UIRectFill(band)
        Ink.red.setFill()
        UIRectFill(CGRect(x: 0, y: bandHeight, width: pageSize.width, height: 5))
        Ink.yellow.setFill()
        UIBezierPath(ovalIn: CGRect(x: pageSize.width - margin - 18, y: 26, width: 18, height: 18)).fill()

        draw(document.kindTitle.uppercased(), in: CGRect(x: margin, y: 22, width: 400, height: 16),
             font: .systemFont(ofSize: 10, weight: .bold), color: Ink.yellow, kern: 1.4)
        draw(document.title, in: CGRect(x: margin, y: 40, width: pageSize.width - margin * 2 - 30, height: 40),
             font: .systemFont(ofSize: 24, weight: .bold), color: .white)
        layout.y = bandHeight + 22

        layout.paragraph(document.sourceLine, font: .systemFont(ofSize: 11, weight: .semibold), color: Ink.text)
        for line in document.metaLines {
            layout.paragraph(line, font: .systemFont(ofSize: 10), color: Ink.muted, spacing: 3)
        }
        layout.y += 10
    }

    private func drawSection(_ section: ExportSection, layout: inout PageLayout) {
        layout.ensure(46)
        layout.y += 8
        draw(section.heading.uppercased(), in: CGRect(x: margin, y: layout.y, width: layout.contentWidth, height: 14),
             font: .systemFont(ofSize: 10, weight: .heavy), color: Ink.red, kern: 1.1)
        layout.y += 17
        Ink.rule.setFill()
        UIRectFill(CGRect(x: margin, y: layout.y, width: layout.contentWidth, height: 1))
        layout.y += 8

        for paragraph in section.paragraphs {
            layout.paragraph(paragraph, font: .systemFont(ofSize: 11), color: Ink.text, spacing: 6)
        }
        for bullet in section.bullets {
            layout.paragraph("•  " + bullet, font: .systemFont(ofSize: 10.5), color: Ink.text, spacing: 4)
        }
        if let table = section.table {
            drawTable(table, layout: &layout)
        }
        layout.y += 6
    }

    private func drawTable(_ table: ExportTable, layout: inout PageLayout) {
        let columns = table.columns
        guard !columns.isEmpty else { return }
        let weights = table.weights.count == columns.count ? table.weights : Array(repeating: 1, count: columns.count)
        let totalWeight = weights.reduce(0, +)
        let widths = weights.map { CGFloat($0 / totalWeight) * layout.contentWidth }
        let padding: CGFloat = 5
        let headerFont = UIFont.systemFont(ofSize: 9, weight: .bold)
        let bodyFont = UIFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .regular)
        let boldFont = UIFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .bold)

        func drawHeaderRow() {
            let height: CGFloat = 20
            Ink.midnight.setFill()
            UIBezierPath(roundedRect: CGRect(x: margin, y: layout.y, width: layout.contentWidth, height: height), cornerRadius: 4).fill()
            var x = margin
            for (index, title) in columns.enumerated() {
                draw(title, in: CGRect(x: x + padding, y: layout.y + 5, width: widths[index] - padding * 2, height: 12),
                     font: headerFont, color: .white)
                x += widths[index]
            }
            layout.y += height
        }

        layout.ensure(44)
        drawHeaderRow()
        for (rowIndex, row) in table.rows.enumerated() {
            let emphasized = table.emphasizedRows.contains(rowIndex)
            let font = emphasized ? boldFont : bodyFont
            let heights = row.enumerated().map { index, value -> CGFloat in
                guard index < widths.count else { return 0 }
                return textHeight(value, width: widths[index] - padding * 2, font: font)
            }
            let rowHeight = max(18, (heights.max() ?? 12) + 8)
            if layout.ensure(rowHeight) {
                drawHeaderRow()
            }
            if emphasized {
                Ink.yellow.withAlphaComponent(0.35).setFill()
                UIRectFill(CGRect(x: margin, y: layout.y, width: layout.contentWidth, height: rowHeight))
            } else if rowIndex % 2 == 1 {
                Ink.paper.setFill()
                UIRectFill(CGRect(x: margin, y: layout.y, width: layout.contentWidth, height: rowHeight))
            }
            var x = margin
            for (index, value) in row.enumerated() where index < widths.count {
                draw(value, in: CGRect(x: x + padding, y: layout.y + 4, width: widths[index] - padding * 2, height: rowHeight - 6),
                     font: font, color: Ink.text)
                x += widths[index]
            }
            Ink.rule.setFill()
            UIRectFill(CGRect(x: margin, y: layout.y + rowHeight - 0.5, width: layout.contentWidth, height: 0.5))
            layout.y += rowHeight
        }
        layout.y += 6
    }

    private func textHeight(_ text: String, width: CGFloat, font: UIFont) -> CGFloat {
        let rect = (text as NSString).boundingRect(
            with: CGSize(width: max(10, width), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font],
            context: nil
        )
        return ceil(rect.height)
    }

    private func draw(_ text: String, in rect: CGRect, font: UIFont, color: UIColor, kern: CGFloat = 0) {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byWordWrapping
        (text as NSString).draw(
            with: rect,
            options: [.usesLineFragmentOrigin, .usesFontLeading, .truncatesLastVisibleLine],
            attributes: [.font: font, .foregroundColor: color, .kern: kern, .paragraphStyle: style],
            context: nil
        )
    }

    /// Tracks the vertical cursor and starts new pages as needed.
    private struct PageLayout {
        let context: UIGraphicsPDFRendererContext
        let pageSize: CGSize
        let margin: CGFloat
        let footer: String
        var y: CGFloat = 0
        var pageNumber = 0

        var contentWidth: CGFloat { pageSize.width - margin * 2 }
        private var bottomLimit: CGFloat { pageSize.height - margin - 26 }

        init(context: UIGraphicsPDFRendererContext, pageSize: CGSize, margin: CGFloat, footer: String) {
            self.context = context
            self.pageSize = pageSize
            self.margin = margin
            self.footer = footer
        }

        mutating func beginPage() {
            context.beginPage()
            // Opaque page so the document never shows through as a dark/transparent sheet in viewers.
            UIColor.white.setFill()
            UIRectFill(CGRect(origin: .zero, size: pageSize))
            pageNumber += 1
            y = margin
        }

        mutating func finishPage() {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 8),
                .foregroundColor: Ink.muted
            ]
            let footerRect = CGRect(x: margin, y: pageSize.height - margin + 4, width: contentWidth - 50, height: 22)
            (footer as NSString).draw(with: footerRect, options: [.usesLineFragmentOrigin], attributes: attributes, context: nil)
            ("\(pageNumber)" as NSString).draw(
                at: CGPoint(x: pageSize.width - margin - 10, y: pageSize.height - margin + 4), withAttributes: attributes
            )
        }

        /// Starts a new page if `height` doesn't fit. Returns true when a page break happened.
        @discardableResult
        mutating func ensure(_ height: CGFloat) -> Bool {
            guard y + height > bottomLimit else { return false }
            finishPage()
            beginPage()
            return true
        }

        mutating func paragraph(_ text: String, font: UIFont, color: UIColor, spacing: CGFloat = 4) {
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
            let pieces = Self.split(text, attributes: attributes, width: contentWidth, maxHeight: 220)
            for (index, piece) in pieces.enumerated() {
                let height = Self.measure(piece, attributes: attributes, width: contentWidth)
                ensure(height)
                (piece as NSString).draw(
                    with: CGRect(x: margin, y: y, width: contentWidth, height: height + 2),
                    options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes, context: nil
                )
                y += height + (index == pieces.count - 1 ? spacing : 1)
            }
        }

        private static func measure(_ text: String, attributes: [NSAttributedString.Key: Any], width: CGFloat) -> CGFloat {
            ceil((text as NSString).boundingRect(
                with: CGSize(width: width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes, context: nil
            ).height)
        }

        /// Breaks long text into pieces that each fit on a page, so nothing is drawn past the margin.
        private static func split(_ text: String, attributes: [NSAttributedString.Key: Any], width: CGFloat, maxHeight: CGFloat) -> [String] {
            var result: [String] = []
            for line in text.components(separatedBy: "\n") {
                if measure(line, attributes: attributes, width: width) <= maxHeight {
                    result.append(line)
                    continue
                }
                var current = ""
                for word in line.split(separator: " ") {
                    let candidate = current.isEmpty ? String(word) : current + " " + word
                    if !current.isEmpty, measure(candidate, attributes: attributes, width: width) > maxHeight {
                        result.append(current)
                        current = String(word)
                    } else {
                        current = candidate
                    }
                }
                if !current.isEmpty { result.append(current) }
            }
            return result.isEmpty ? [""] : result
        }
    }
}

final class Studio {
    lazy var vault: Vault = Booth()
    lazy var scout: Scout = Spotter()
    lazy var feed: Feed = Broadcaster()
    lazy var usher: Usher = Doorman()
}
