import XCTest
@testable import PulseJarCore

final class BankMessageParserTests: XCTestCase {
    private func decimal(_ text: String) -> Decimal {
        Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))!
    }

    private func ammanComponents(_ date: Date) -> DateComponents {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Amman")!
        return calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
    }

    private func parse(_ text: String) throws -> ParsedBankMessage {
        try XCTUnwrap(BankMessageParser.parse(text))
    }

    func testCliqPaymentToPerson() throws {
        let message = try parse("""
        حركة كليك
        المبلغ: 13.000 JOD
        حساب: 1600*1380
        إلى: MOHAMMAD AHMAD MOHAMMAD HUSSEIN
        تاريخ: 16/11/2026 00:53:33
        الرصيد: 418.531 JOD
        """)

        XCTAssertEqual(message.kind, .cliqOut(to: "MOHAMMAD AHMAD MOHAMMAD HUSSEIN"))
        XCTAssertEqual(message.direction, .moneyOut)
        XCTAssertEqual(message.amount, decimal("13"))
        XCTAssertEqual(message.currency, "JOD")
        XCTAssertEqual(message.account, "1600*1380")
        XCTAssertEqual(message.balance, decimal("418.531"))

        let components = ammanComponents(message.date)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 11)
        XCTAssertEqual(components.day, 16)
        XCTAssertEqual(components.hour, 0)
        XCTAssertEqual(components.minute, 53)
        XCTAssertEqual(components.second, 33)
    }

    func testPurchaseTakesMerchantFromTitle() throws {
        let message = try parse("""
        حركة شراء HAMADA - HAI NAZZAL AMMAN JO
        المبلغ: 1.200 JOD
        حساب: 1600*1380
        تاريخ: 14/11/2026 10:51:20
        الرصيد: 496.531 JOD
        """)

        XCTAssertEqual(message.kind, .purchase(merchant: "HAMADA - HAI NAZZAL AMMAN JO"))
        XCTAssertEqual(message.direction, .moneyOut)
        XCTAssertEqual(message.amount, decimal("1.2"))
        XCTAssertEqual(message.balance, decimal("496.531"))
    }

    func testReversalWithBalanceMissingCurrency() throws {
        let message = try parse("""
        عكس دفعة CliQ من MOHAMMAD MAHMOUD MOSA GAITH
        المبلغ: 4.500 JOD
        حساب: 1600*1380
        تاريخ: 14/11/2026 00:51:05
        الرصيد: 502.231
        """)

        XCTAssertEqual(message.kind, .reversal(from: "MOHAMMAD MAHMOUD MOSA GAITH"))
        XCTAssertEqual(message.direction, .moneyIn)
        XCTAssertEqual(message.balance, decimal("502.231"))
    }

    func testSalary() throws {
        let message = try parse("""
        تحويل راتب كليك
        المبلغ: 425.000 JOD
        حساب: 1600*1380
        من: EXEPTION SOFT
        تاريخ: 11/11/2026 19:57:13
        الرصيد: 662.581
        """)

        XCTAssertEqual(message.kind, .salary(from: "EXEPTION SOFT"))
        XCTAssertEqual(message.amount, decimal("425"))
    }

    func testTransferHalvesUseTheirOwnAccounts() throws {
        let outgoing = try parse("""
        حركة تحويل
        المبلغ: 5.000 JOD
        من حساب: 1600*1380
        تاريخ: 07/11/2026 00:34:16
        الرصيد: 254.872 JOD
        """)
        let incoming = try parse("""
        حركة تحويل
        المبلغ: 5.000 JOD
        إلى حساب: 1601*1380
        تاريخ: 07/11/2026 00:34:16
        الرصيد: 5.000 JOD
        """)

        XCTAssertEqual(outgoing.kind, .transferOut)
        XCTAssertEqual(outgoing.account, "1600*1380")
        XCTAssertEqual(outgoing.balance, decimal("254.872"))
        XCTAssertEqual(incoming.kind, .transferIn)
        XCTAssertEqual(incoming.account, "1601*1380")
        XCTAssertEqual(incoming.balance, decimal("5"))
        XCTAssertEqual(outgoing.date, incoming.date)
        XCTAssertNotEqual(outgoing.fingerprint, incoming.fingerprint)
    }

    func testCliqReceivedWithTrailingSpaces() throws {
        let message = try parse("حركة كليك \nالمبلغ: 7.000 JOD\nحساب: 1600*1380\nمن: AWAS ABD-AL-HAKIM BAJES AHMAD\nتاريخ: 30/10/2026 22:47:58 \nالرصيد: 384.022 JOD")

        XCTAssertEqual(message.kind, .cliqIn(from: "AWAS ABD-AL-HAKIM BAJES AHMAD"))
        XCTAssertEqual(message.direction, .moneyIn)
        XCTAssertEqual(ammanComponents(message.date).second, 58)
    }

    func testDirectionMarksAndArabicDigits() throws {
        let message = try parse("\u{200F}حركة كليك\n\u{200F}المبلغ: ١٣٫٥٠٠ JOD\nحساب: 1600*1380\nالى: SOMEONE\nتاريخ: ١٦/١١/٢٠٢٦ ٠٠:٥٣:٣٣")

        XCTAssertEqual(message.kind, .cliqOut(to: "SOMEONE"))
        XCTAssertEqual(message.amount, decimal("13.5"))
        XCTAssertNil(message.balance)
        XCTAssertEqual(ammanComponents(message.date).day, 16)
    }

    func testTextWithoutAmountIsNotABankMessage() {
        XCTAssertNil(BankMessageParser.parse("Your verification code is 123456"))
        XCTAssertNil(BankMessageParser.parse(""))
    }

    func testSameMessageHasSameFingerprint() throws {
        let text = "حركة كليك\nالمبلغ: 13.000 JOD\nحساب: 1600*1380\nإلى: A B\nتاريخ: 16/11/2026 00:53:33"
        XCTAssertEqual(try parse(text).fingerprint, try parse(text).fingerprint)
    }

    func testSplitsPastedMessagesWithAndWithoutBlankLines() {
        let pasted = """
        حركة كليك
        المبلغ: 13.000 JOD
        حساب: 1600*1380
        إلى: MOHAMMAD AHMAD MOHAMMAD HUSSEIN
        تاريخ: 16/11/2026 00:53:33
        الرصيد: 418.531 JOD
        حركة شراء HAMADA - HAI NAZZAL AMMAN JO
        المبلغ: 1.200 JOD
        حساب: 1600*1380
        تاريخ: 14/11/2026 10:51:20
        الرصيد: 496.531 JOD

        عكس دفعة CliQ من MOHAMMAD MAHMOUD MOSA GAITH
        المبلغ: 4.500 JOD
        حساب: 1600*1380
        تاريخ: 14/11/2026 00:51:05
        الرصيد: 502.231
        """

        let parsed = BankMessageParser.parseMany(pasted)

        XCTAssertEqual(parsed.count, 3)
        XCTAssertEqual(parsed.first?.kind, .reversal(from: "MOHAMMAD MAHMOUD MOSA GAITH"), "sorted oldest first")
        XCTAssertEqual(parsed.last?.kind, .cliqOut(to: "MOHAMMAD AHMAD MOHAMMAD HUSSEIN"))
    }
}
