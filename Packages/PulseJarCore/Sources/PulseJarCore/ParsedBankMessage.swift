import Foundation

/// A bank SMS turned into structured data. Amounts are always positive; `direction` says which way the money moved.
public struct ParsedBankMessage: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// Card or POS purchase (`حركة شراء <merchant>`).
        case purchase(merchant: String)
        /// CliQ payment sent to someone (`حركة كليك` + `إلى:`).
        case cliqOut(to: String)
        /// CliQ payment received from someone (`حركة كليك` + `من:`).
        case cliqIn(from: String)
        /// Salary received (`تحويل راتب كليك`).
        case salary(from: String)
        /// A previous outgoing payment was returned (`عكس دفعة CliQ من <name>`).
        case reversal(from: String)
        /// Money left `account` in an internal transfer (`حركة تحويل` + `من حساب:`).
        case transferOut
        /// Money arrived in `account` from an internal transfer (`حركة تحويل` + `إلى حساب:`).
        case transferIn
        /// Has an amount but a format we don't know yet.
        case unrecognized
    }

    public enum Direction: Equatable, Sendable {
        case moneyOut, moneyIn, unknown
    }

    public var kind: Kind
    public var amount: Decimal
    public var currency: String
    /// Masked account number exactly as the bank writes it, e.g. `1600*1380`.
    public var account: String?
    public var date: Date
    /// Balance of `account` after this transaction, as reported by the bank.
    public var balance: Decimal?
    public var rawText: String

    public init(kind: Kind, amount: Decimal, currency: String, account: String?, date: Date, balance: Decimal?, rawText: String) {
        self.kind = kind
        self.amount = amount
        self.currency = currency
        self.account = account
        self.date = date
        self.balance = balance
        self.rawText = rawText
    }

    public var direction: Direction {
        switch kind {
        case .purchase, .cliqOut, .transferOut:
            return .moneyOut
        case .cliqIn, .salary, .reversal, .transferIn:
            return .moneyIn
        case .unrecognized:
            return .unknown
        }
    }

    /// The other party: merchant for purchases, person or company for CliQ.
    public var counterparty: String? {
        switch kind {
        case .purchase(let name), .cliqOut(let name), .cliqIn(let name), .salary(let name), .reversal(let name):
            return name.isEmpty ? nil : name
        case .transferOut, .transferIn, .unrecognized:
            return nil
        }
    }

    /// Stable identity used to ignore the same SMS arriving twice.
    public var fingerprint: String {
        let kindCode: String
        switch kind {
        case .purchase: kindCode = "purchase"
        case .cliqOut: kindCode = "cliqOut"
        case .cliqIn: kindCode = "cliqIn"
        case .salary: kindCode = "salary"
        case .reversal: kindCode = "reversal"
        case .transferOut: kindCode = "transferOut"
        case .transferIn: kindCode = "transferIn"
        case .unrecognized: kindCode = "unrecognized"
        }
        return [
            kindCode,
            account ?? "-",
            "\(amount)",
            String(Int(date.timeIntervalSince1970)),
            (counterparty ?? "").uppercased(),
        ].joined(separator: "|")
    }
}
