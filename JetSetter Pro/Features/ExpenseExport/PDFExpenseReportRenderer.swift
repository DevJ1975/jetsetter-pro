// File: Features/ExpenseExport/PDFExpenseReportRenderer.swift
//
// Generates a multi-page 8.5×11 PDF expense report using UIGraphicsPDFRenderer.
// Page 1: hero header + summary + line-item table. Subsequent pages: receipt
// OCR text for each expense (one per page) so approvers can audit.

import Foundation
import UIKit
import PDFKit

enum PDFExpenseReportRenderer {

    static func render(trip: Trip?, expenses: [Expense]) -> Data {
        let pageWidth: CGFloat = 612    // 8.5 inch * 72 dpi
        let pageHeight: CGFloat = 792   // 11 inch * 72 dpi
        let bounds = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)

        return renderer.pdfData { context in
            // ── Page 1 ────────────────────────────────────────────────────
            context.beginPage()
            drawHeader(ctx: context.cgContext, page: bounds, trip: trip, expenses: expenses)
            drawSummary(ctx: context.cgContext, page: bounds, trip: trip, expenses: expenses)
            drawLineItems(ctx: context.cgContext, page: bounds, expenses: expenses)
            drawFooter(ctx: context.cgContext, page: bounds, pageNumber: 1)

            // ── Receipt audit pages ─────────────────────────────────────────
            var pageIdx = 2
            for expense in expenses where (expense.receiptText?.isEmpty == false) {
                context.beginPage()
                drawReceiptAudit(ctx: context.cgContext, page: bounds, expense: expense)
                drawFooter(ctx: context.cgContext, page: bounds, pageNumber: pageIdx)
                pageIdx += 1
            }
        }
    }

    // MARK: - Page 1 sections

    private static let margin: CGFloat = 40

    private static func drawHeader(ctx: CGContext, page: CGRect, trip: Trip?, expenses: [Expense]) {
        let title = trip?.name ?? "Expense Report"
        let subtitle: String = {
            if let trip {
                let f = DateFormatter(); f.dateStyle = .medium
                return "\(trip.destination)  ·  \(f.string(from: trip.startDate)) – \(f.string(from: trip.endDate))"
            }
            return "Submitted \(Date().formatted(date: .long, time: .omitted))"
        }()

        // Hero gradient bar
        let heroRect = CGRect(x: 0, y: 0, width: page.width, height: 110)
        let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                UIColor(red: 0.231, green: 0.620, blue: 0.941, alpha: 1).cgColor, // accent blue
                UIColor(red: 0.482, green: 0.247, blue: 0.749, alpha: 1).cgColor  // violet
            ] as CFArray,
            locations: [0, 1]
        )!
        ctx.saveGState()
        ctx.addRect(heroRect)
        ctx.clip()
        ctx.drawLinearGradient(gradient,
                                start: CGPoint(x: 0, y: 0),
                                end: CGPoint(x: page.width, y: heroRect.maxY),
                                options: [])
        ctx.restoreGState()

        // Title text
        title.draw(at: CGPoint(x: margin, y: 36),
                   withAttributes: [
                       .font: UIFont.systemFont(ofSize: 26, weight: .bold),
                       .foregroundColor: UIColor.white
                   ])
        subtitle.draw(at: CGPoint(x: margin, y: 72),
                      withAttributes: [
                          .font: UIFont.systemFont(ofSize: 11, weight: .medium),
                          .foregroundColor: UIColor.white.withAlphaComponent(0.85)
                      ])

        // "EXPENSE REPORT" label, top-right
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 9, weight: .black),
            .foregroundColor: UIColor.white.withAlphaComponent(0.7),
            .kern: 2.5
        ]
        let label = NSAttributedString(string: "JETSETTER PRO  ·  EXPENSE REPORT", attributes: labelAttrs)
        let labelSize = label.size()
        label.draw(at: CGPoint(x: page.width - margin - labelSize.width, y: 42))
    }

    private static func drawSummary(ctx: CGContext, page: CGRect, trip: Trip?, expenses: [Expense]) {
        let y: CGFloat = 140

        // Per-currency subtotals — summing raw amounts across currencies would
        // misrepresent the total, so group first and present each separately.
        let totalsByCurrency = Dictionary(grouping: expenses, by: { $0.currency })
            .map { (currency: $0.key, amount: $0.value.reduce(0) { $0 + $1.amount }) }
            .sorted { $0.currency < $1.currency }
        let totalString = totalsByCurrency.isEmpty
            ? "USD 0.00"
            : totalsByCurrency.map { String(format: "%@ %.2f", $0.currency, $0.amount) }.joined(separator: "  ·  ")

        let totalLabel = NSAttributedString(
            string: "TOTAL",
            attributes: [
                .font: UIFont.systemFont(ofSize: 9, weight: .black),
                .foregroundColor: UIColor.darkGray,
                .kern: 1.5
            ]
        )
        // A single currency still gets the large hero figure; mixed currencies
        // step down a size so the "·"-joined breakdown fits on one line.
        let totalFontSize: CGFloat = totalsByCurrency.count > 1 ? 20 : 32
        let totalValue = NSAttributedString(
            string: totalString,
            attributes: [
                .font: UIFont.monospacedDigitSystemFont(ofSize: totalFontSize, weight: .bold),
                .foregroundColor: UIColor.black
            ]
        )
        let countLabel = NSAttributedString(
            string: "\(expenses.count) item\(expenses.count == 1 ? "" : "s")",
            attributes: [
                .font: UIFont.systemFont(ofSize: 12, weight: .medium),
                .foregroundColor: UIColor.darkGray
            ]
        )
        totalLabel.draw(at: CGPoint(x: margin, y: y))
        totalValue.draw(at: CGPoint(x: margin, y: y + 14))
        countLabel.draw(at: CGPoint(x: margin, y: y + 58))

        // Category subtotals on the right — also grouped by currency so a
        // category spanning two currencies shows one line per currency.
        let byCategoryCurrency = Dictionary(grouping: expenses) {
            CategoryCurrencyKey(category: $0.category, currency: $0.currency)
        }
        var rowY: CGFloat = y + 14
        for (key, items) in byCategoryCurrency.sorted(by: { $0.value.reduce(0) { $0 + $1.amount } > $1.value.reduce(0) { $0 + $1.amount } }) {
            let subtotal = items.reduce(0) { $0 + $1.amount }
            let line = NSAttributedString(
                string: String(format: "%@ %.2f  %@", key.currency, subtotal, key.category.displayName),
                attributes: [
                    .font: UIFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
                    .foregroundColor: UIColor.darkGray
                ]
            )
            let size = line.size()
            line.draw(at: CGPoint(x: page.width - margin - size.width, y: rowY))
            rowY += 16
            if rowY > y + 72 { break }
        }
    }

    /// Grouping key so category subtotals never mix currencies.
    private struct CategoryCurrencyKey: Hashable {
        let category: ExpenseCategory
        let currency: String
    }

    private static func drawLineItems(ctx: CGContext, page: CGRect, expenses: [Expense]) {
        let startY: CGFloat = 240
        var y = startY

        // Header row
        let headerAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 9, weight: .black),
            .foregroundColor: UIColor.darkGray,
            .kern: 1.5
        ]
        NSAttributedString(string: "DATE", attributes: headerAttrs).draw(at: CGPoint(x: margin, y: y))
        NSAttributedString(string: "MERCHANT", attributes: headerAttrs).draw(at: CGPoint(x: margin + 80, y: y))
        NSAttributedString(string: "CATEGORY", attributes: headerAttrs).draw(at: CGPoint(x: margin + 320, y: y))
        NSAttributedString(string: "AMOUNT", attributes: headerAttrs).draw(at: CGPoint(x: page.width - margin - 60, y: y))

        y += 14
        ctx.setStrokeColor(UIColor.lightGray.cgColor)
        ctx.setLineWidth(0.5)
        ctx.move(to: CGPoint(x: margin, y: y))
        ctx.addLine(to: CGPoint(x: page.width - margin, y: y))
        ctx.strokePath()

        y += 10

        let dateF = DateFormatter()
        dateF.dateFormat = "MMM d"

        let textAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 11),
            .foregroundColor: UIColor.black
        ]
        let amountAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: UIColor.black
        ]

        for expense in expenses.sorted(by: { $0.date < $1.date }) {
            if y > page.height - 80 { break }   // leave room for footer
            dateF.string(from: expense.date).draw(at: CGPoint(x: margin, y: y), withAttributes: textAttrs)
            (expense.merchant as NSString).draw(
                in: CGRect(x: margin + 80, y: y, width: 230, height: 14),
                withAttributes: textAttrs
            )
            expense.category.displayName.draw(at: CGPoint(x: margin + 320, y: y), withAttributes: textAttrs)
            let amount = String(format: "%@ %.2f", expense.currency, expense.amount) as NSString
            let amountStr = NSAttributedString(string: amount as String, attributes: amountAttrs)
            let amountSize = amountStr.size()
            amountStr.draw(at: CGPoint(x: page.width - margin - amountSize.width, y: y))
            y += 18
        }
    }

    private static func drawReceiptAudit(ctx: CGContext, page: CGRect, expense: Expense) {
        let h = NSAttributedString(
            string: "RECEIPT AUDIT",
            attributes: [
                .font: UIFont.systemFont(ofSize: 9, weight: .black),
                .foregroundColor: UIColor.darkGray,
                .kern: 1.5
            ]
        )
        h.draw(at: CGPoint(x: margin, y: 60))

        let merchant = NSAttributedString(
            string: "\(expense.merchant)",
            attributes: [
                .font: UIFont.systemFont(ofSize: 18, weight: .bold),
                .foregroundColor: UIColor.black
            ]
        )
        merchant.draw(at: CGPoint(x: margin, y: 78))

        let f = DateFormatter(); f.dateStyle = .full
        let meta = NSAttributedString(
            string: "\(f.string(from: expense.date))  ·  \(String(format: "%@ %.2f", expense.currency, expense.amount))  ·  \(expense.category.displayName)",
            attributes: [
                .font: UIFont.systemFont(ofSize: 11),
                .foregroundColor: UIColor.darkGray
            ]
        )
        meta.draw(at: CGPoint(x: margin, y: 106))

        if let raw = expense.receiptText, !raw.isEmpty {
            let body = NSAttributedString(
                string: raw,
                attributes: [
                    .font: UIFont.monospacedSystemFont(ofSize: 10, weight: .regular),
                    .foregroundColor: UIColor.black
                ]
            )
            body.draw(in: CGRect(
                x: margin, y: 140,
                width: page.width - 2 * margin,
                height: page.height - 200
            ))
        }
    }

    private static func drawFooter(ctx: CGContext, page: CGRect, pageNumber: Int) {
        let footer = NSAttributedString(
            string: "Generated by JetSetter Pro  ·  Page \(pageNumber)",
            attributes: [
                .font: UIFont.systemFont(ofSize: 9, weight: .medium),
                .foregroundColor: UIColor.lightGray
            ]
        )
        let size = footer.size()
        footer.draw(at: CGPoint(
            x: (page.width - size.width) / 2,
            y: page.height - 30
        ))
    }
}
