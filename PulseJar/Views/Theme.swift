import SwiftUI
import UIKit

// MARK: - Colours

/// App colours. Dark mode is the primary look; light mode follows the same roles.
enum Theme {
    /// Screen background: deep night in dark mode, system grouped grey in light mode.
    static let background = Color(light: 0xF2F2F7, dark: 0x0C151E)
    /// Rows and cards sitting on `background`.
    static let card = Color(light: 0xFFFFFF, dark: 0x16222F)
    /// The balance card. Night in light mode, lifted night in dark mode so it doesn't vanish.
    static let hero = Color(light: 0x13202E, dark: 0x1D2E40)
    /// Clay, a little brighter in dark mode for contrast.
    static let accent = Color(light: 0xC8643B, dark: 0xE27B50)
    static let accentSoft = Color(light: 0xC8643B, dark: 0xE27B50).opacity(0.16)
    /// Money coming in.
    static let positive = Color(light: 0x2E9E4F, dark: 0x5DC97C)
    /// Neutral icon backgrounds (transfers, adjustments, "More").
    static let neutralSoft = Color(light: 0x8E8E93, dark: 0x8E9AA6).opacity(0.18)
    static let neutral = Color(light: 0x5B6470, dark: 0xA3AEB9)
}

extension Color {
    /// A colour that switches with the interface style.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

// MARK: - Appearance setting

enum Appearance: String, CaseIterable, Identifiable {
    case dark, system, light

    static let storageKey = "appearance"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dark: return "Dark"
        case .system: return "Match iPhone"
        case .light: return "Light"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .dark: return .dark
        case .system: return nil
        case .light: return .light
        }
    }
}

// MARK: - List styling

extension View {
    /// Themed background for a List, Form or ScrollView.
    func themedBackground() -> some View {
        scrollContentBackground(.hidden)
            .background(Theme.background)
    }

    /// Themed row background. Apply to each Section of a themed List or Form.
    func cardRows() -> some View {
        listRowBackground(Theme.card)
    }
}

// MARK: - Money

/// An amount with the fils drawn smaller than the dinars, e.g. 1,284.350
struct MoneyText: View {
    let amount: Decimal
    var signed = false
    var showsCurrency = false
    var currency = "JOD"
    /// Point size of the dinars. Defaults to the body text size.
    var size: CGFloat = UIFont.preferredFont(forTextStyle: .body).pointSize
    var weight: Font.Weight = .regular
    var filsScale: CGFloat = 0.72

    private var parts: (sign: String, whole: String, fraction: String) {
        let sign: String
        if signed && amount > 0 {
            sign = "+"
        } else if amount < 0 {
            sign = "−"
        } else {
            sign = ""
        }
        let text = abs(amount).formatted(.number.precision(.fractionLength(3)))
        let separator = Locale.current.decimalSeparator ?? "."
        if let range = text.range(of: separator, options: .backwards) {
            return (sign, String(text[..<range.lowerBound]), String(text[range.lowerBound...]))
        }
        return (sign, text, "")
    }

    var body: some View {
        let parts = parts
        let whole = Text(parts.sign + parts.whole)
            .font(.system(size: size, weight: weight))
        let fraction = Text(parts.fraction)
            .font(.system(size: size * filsScale, weight: weight))
        let unit = Text(showsCurrency ? " \(currency)" : "")
            .font(.system(size: max(11, size * 0.5), weight: .semibold))
            .foregroundColor(.secondary)
        (whole + fraction + unit)
            .monospacedDigit()
            .lineLimit(1)
            .accessibilityLabel(amount.spokenMoney(signed: signed))
    }
}

extension Decimal {
    /// "minus 9 dinars 750 fils": how VoiceOver should read an amount.
    func spokenMoney(signed: Bool = false) -> String {
        let minor = Money.minor(abs(self))
        let dinars = minor / 1000
        let fils = minor % 1000
        var text = ""
        if self < 0 {
            text = "minus "
        } else if signed && self > 0 {
            text = "plus "
        }
        text += "\(dinars) \(dinars == 1 ? "dinar" : "dinars")"
        if fils != 0 {
            text += " \(fils) fils"
        }
        return text
    }
}

// MARK: - Icons

/// A round tinted icon used in rows, cards and grids.
struct IconBadge: View {
    let systemName: String
    var tint: Color = Theme.accent
    var size: CGFloat = 34
    var filled = false

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.42, weight: .medium))
            .foregroundStyle(filled ? Color.white : tint)
            .frame(width: size, height: size)
            .background(filled ? tint : tint.opacity(0.16), in: Circle())
            .accessibilityHidden(true)
    }
}

// MARK: - Empty states

/// Empty state with the PulseJar jar instead of a generic symbol.
struct BrandEmptyState: View {
    let title: String
    let message: String

    var body: some View {
        ContentUnavailableView {
            VStack(spacing: 12) {
                Image("LaunchMark")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 72)
                    .accessibilityHidden(true)
                Text(title)
            }
        } description: {
            Text(message)
        }
    }
}

// MARK: - Haptics

@MainActor
enum Haptics {
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

// MARK: - Keyboard

/// Closes the keyboard when the user taps anywhere except another text field.
///
/// Installed once on each window. The tap still reaches whatever was tapped (buttons, rows, pickers),
/// it just also ends editing.
@MainActor
enum KeyboardDismissal {
    private static let delegate = Delegate()

    static func install() {
        // Only the app's own windows: the keyboard lives in a higher-level window, and taps on keys
        // must never close it.
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .filter { $0.windowLevel == .normal }
        for window in windows where !(window.gestureRecognizers ?? []).contains(where: { $0.name == "PulseJarKeyboardDismissal" }) {
            let tap = UITapGestureRecognizer(target: delegate, action: #selector(Delegate.handleTap(_:)))
            tap.name = "PulseJarKeyboardDismissal"
            tap.cancelsTouchesInView = false
            tap.delaysTouchesBegan = false
            tap.delaysTouchesEnded = false
            tap.delegate = delegate
            window.addGestureRecognizer(tap)
        }
    }

    private final class Delegate: NSObject, UIGestureRecognizerDelegate {
        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            recognizer.view?.endEditing(true)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            // Taps on a text field or text view move focus there instead of closing the keyboard.
            var view = touch.view
            while let current = view {
                if current is UITextField || current is UITextView {
                    return false
                }
                view = current.superview
            }
            return true
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }
}
