import Foundation
import FinanceCore

enum Money {
    static let scale: Decimal = 1000
    private static let posix = Locale(identifier: "en_US_POSIX")

    static func decimal(_ minor: Int64) -> Decimal {
        Decimal(minor) / scale
    }

    static func minor(_ value: Decimal) -> Int64 {
        var scaled = value * scale
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .plain)
        return NSDecimalNumber(decimal: rounded).int64Value
    }

    /// Parses what the user typed: accepts Arabic digits and `,` or `٫` as the decimal separator.
    static func parse(_ text: String) -> Decimal? {
        let normalized = BankMessageParser.normalizeText(text)
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespaces)
        guard !normalized.isEmpty else {
            return nil
        }
        return Decimal(string: normalized, locale: posix)
    }

    /// Plain editable text, e.g. `13.000`.
    static func editableText(_ value: Decimal) -> String {
        value.formatted(.number.precision(.fractionLength(3)).grouping(.never).locale(posix))
    }
}

extension Decimal {
    func money(_ currency: String = "JOD") -> String {
        "\(formatted(.number.precision(.fractionLength(3)))) \(currency)"
    }

    func signedMoney(_ currency: String = "JOD") -> String {
        if self > 0 {
            return "+" + money(currency)
        }
        if self < 0 {
            return "−" + (-self).money(currency)
        }
        return money(currency)
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
