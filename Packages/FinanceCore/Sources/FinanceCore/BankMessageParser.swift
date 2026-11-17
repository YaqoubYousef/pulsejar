import Foundation

/// Parses Jordanian bank SMS messages (Arabic labels, Latin names) into `ParsedBankMessage`.
public enum BankMessageParser {
    private enum Key {
        static let amount: Set<String> = ["المبلغ", "مبلغ"]
        static let account: Set<String> = ["حساب", "الحساب"]
        static let to: Set<String> = ["الى", "الي"]
        static let from: Set<String> = ["من"]
        static let date: Set<String> = ["تاريخ", "التاريخ"]
        static let balance: Set<String> = ["الرصيد", "رصيد"]
        static let fromAccount: Set<String> = ["من حساب", "من الحساب"]
        static let toAccount: Set<String> = ["الى حساب", "الي حساب", "الى الحساب"]

        static let all: Set<String> = amount.union(account).union(to).union(from).union(date)
            .union(balance).union(fromAccount).union(toAccount)
    }

    private static let posix = Locale(identifier: "en_US_POSIX")
    private static let bankTimeZone = TimeZone(identifier: "Asia/Amman") ?? TimeZone.current
    private static let dateFormats = [
        "dd/MM/yyyy HH:mm:ss", "d/M/yyyy HH:mm:ss",
        "dd/MM/yyyy HH:mm", "d/M/yyyy HH:mm",
        "dd-MM-yyyy HH:mm:ss", "yyyy-MM-dd HH:mm:ss",
        "dd/MM/yyyy", "d/M/yyyy",
    ]

    /// Parses one message. Returns nil when the text has no amount (not a transaction message).
    /// - Parameter receivedAt: used only when the message has no date line.
    public static func parse(_ text: String, receivedAt: Date = Date()) -> ParsedBankMessage? {
        let lines = normalizeText(text)
            .components(separatedBy: .newlines)
            .map(collapseSpaces)
            .filter { !$0.isEmpty }

        var header: String?
        var fields: [String: String] = [:]
        for line in lines {
            if let field = splitField(line), Key.all.contains(field.key) || header != nil {
                if fields[field.key] == nil {
                    fields[field.key] = field.value
                }
            } else if header == nil {
                header = line
            }
        }

        guard let amountText = value(in: fields, for: Key.amount),
              let money = parseMoney(amountText)
        else {
            return nil
        }
        let amount = money.value
        let currency = money.currency

        let headerText = header ?? ""
        let normalizedHeader = normalizeArabic(headerText)
        let toName = value(in: fields, for: Key.to).map(collapseSpaces)
        let fromName = value(in: fields, for: Key.from).map(collapseSpaces)
        var account = value(in: fields, for: Key.account).map(cleanAccountMask)

        let kind: ParsedBankMessage.Kind
        if normalizedHeader.contains("عكس") {
            kind = .reversal(from: reversalName(in: headerText) ?? fromName ?? toName ?? "")
        } else if normalizedHeader.contains("راتب") {
            kind = .salary(from: fromName ?? "")
        } else if normalizedHeader.contains("شراء") {
            kind = .purchase(merchant: merchantName(in: headerText) ?? toName ?? "Purchase")
        } else if let fromAccount = value(in: fields, for: Key.fromAccount) {
            account = cleanAccountMask(fromAccount)
            kind = .transferOut
        } else if let toAccount = value(in: fields, for: Key.toAccount) {
            account = cleanAccountMask(toAccount)
            kind = .transferIn
        } else if let toName {
            kind = .cliqOut(to: toName)
        } else if let fromName {
            kind = .cliqIn(from: fromName)
        } else {
            kind = .unrecognized
        }

        let date = value(in: fields, for: Key.date).flatMap(parseDate) ?? receivedAt
        let balance = value(in: fields, for: Key.balance).flatMap(parseMoney)?.value

        return ParsedBankMessage(
            kind: kind,
            amount: amount,
            currency: currency ?? "JOD",
            account: account,
            date: date,
            balance: balance,
            rawText: lines.joined(separator: "\n")
        )
    }

    /// Splits pasted text holding several messages. A new message starts at a blank line,
    /// or at a title line (no known `label:`) that follows field lines.
    public static func splitMessages(_ text: String) -> [String] {
        var messages: [[String]] = []
        var current: [String] = []
        var currentHasFields = false

        for rawLine in normalizeText(text).components(separatedBy: .newlines) {
            let line = collapseSpaces(rawLine)
            if line.isEmpty {
                if !current.isEmpty {
                    messages.append(current)
                    current = []
                    currentHasFields = false
                }
                continue
            }
            let isField = splitField(line).map { Key.all.contains($0.key) } ?? false
            if !isField, currentHasFields {
                messages.append(current)
                current = []
                currentHasFields = false
            }
            current.append(line)
            if isField {
                currentHasFields = true
            }
        }
        if !current.isEmpty {
            messages.append(current)
        }
        return messages.map { $0.joined(separator: "\n") }
    }

    /// Parses every message in pasted text, oldest first. Unparseable chunks are skipped.
    public static func parseMany(_ text: String, receivedAt: Date = Date()) -> [ParsedBankMessage] {
        splitMessages(text)
            .compactMap { parse($0, receivedAt: receivedAt) }
            .sorted { $0.date < $1.date }
    }

    /// Removes invisible direction marks and converts Arabic-Indic digits and separators to ASCII.
    public static func normalizeText(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x200B...0x200F, 0x202A...0x202E, 0x2066...0x2069, 0xFEFF, 0x061C, 0x0640:
                continue
            case 0x00A0, 0x202F:
                scalars.append(" ")
            case 0x0660...0x0669:
                scalars.append(Unicode.Scalar(scalar.value - 0x0660 + 0x30)!)
            case 0x06F0...0x06F9:
                scalars.append(Unicode.Scalar(scalar.value - 0x06F0 + 0x30)!)
            case 0x066B:
                scalars.append(".")
            case 0x066C:
                scalars.append(",")
            case 0xFF1A:
                scalars.append(":")
            default:
                scalars.append(scalar)
            }
        }
        return String(scalars)
    }

    /// Parses an amount such as `13.000 JOD` or `1,250.500`. Returns the value and the currency code if present.
    public static func parseMoney(_ text: String) -> (value: Decimal, currency: String?)? {
        let cleaned = normalizeText(text).replacingOccurrences(of: ",", with: "")
        guard let numberRange = cleaned.range(of: #"[0-9]+(\.[0-9]+)?"#, options: .regularExpression),
              let value = Decimal(string: String(cleaned[numberRange]), locale: posix)
        else {
            return nil
        }
        let currency = cleaned.range(of: #"[A-Z]{3}"#, options: .regularExpression).map { String(cleaned[$0]) }
        return (value, currency)
    }

    public static func parseDate(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = posix
        formatter.timeZone = bankTimeZone
        formatter.isLenient = false
        let value = collapseSpaces(text)
        for format in dateFormats {
            formatter.dateFormat = format
            if let date = formatter.date(from: value) {
                return date
            }
        }
        return nil
    }

    // MARK: - Helpers

    private static func splitField(_ line: String) -> (key: String, value: String)? {
        guard let colon = line.firstIndex(of: ":") else {
            return nil
        }
        let key = normalizeArabic(collapseSpaces(String(line[..<colon])))
        let value = collapseSpaces(String(line[line.index(after: colon)...]))
        guard !key.isEmpty else {
            return nil
        }
        return (key, value)
    }

    private static func value(in fields: [String: String], for keys: Set<String>) -> String? {
        for key in keys {
            if let value = fields[key], !value.isEmpty {
                return value
            }
        }
        return nil
    }

    /// `عكس دفعة CliQ من NAME` → `NAME`; `عكس حركة شراء SHOP` → `SHOP`.
    private static func reversalName(in header: String) -> String? {
        if let range = header.range(of: " من ", options: .backwards) {
            let name = collapseSpaces(String(header[range.upperBound...]))
            return name.isEmpty ? nil : name
        }
        return merchantName(in: header)
    }

    /// `حركة شراء HAMADA - HAI NAZZAL AMMAN JO` → `HAMADA - HAI NAZZAL AMMAN JO`.
    private static func merchantName(in header: String) -> String? {
        guard let range = header.range(of: "شراء") else {
            return nil
        }
        let name = collapseSpaces(String(header[range.upperBound...]))
        return name.isEmpty ? nil : name
    }

    private static func cleanAccountMask(_ text: String) -> String {
        text.filter { !$0.isWhitespace }
    }

    private static func collapseSpaces(_ text: String) -> String {
        text.split(whereSeparator: { $0 == " " || $0 == "\t" }).joined(separator: " ")
    }

    /// Treats أ إ آ as ا so `إلى` and `الى` match.
    private static func normalizeArabic(_ text: String) -> String {
        String(text.map { "أإآ".contains($0) ? "ا" : $0 })
    }
}
