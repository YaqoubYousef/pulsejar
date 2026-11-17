import SwiftUI

/// The family palette shared by every app (see design/BRAND.md).
enum Brand {
    static let night = Color(red: 0x13 / 255, green: 0x20 / 255, blue: 0x2E / 255)
    static let clay = Color(red: 0xC8 / 255, green: 0x64 / 255, blue: 0x3B / 255)
    static let sand = Color(red: 0xE9 / 255, green: 0xD3 / 255, blue: 0xB4 / 255)
    static let blend = Color(red: 0xD8 / 255, green: 0x9C / 255, blue: 0x78 / 255)
    static let cream = Color(red: 0xF3 / 255, green: 0xE9 / 255, blue: 0xDC / 255)
    static let maker = "made by Yaqoub"
}

/// The maker's seal: two raised-arm figures (YY, two sides of one person) in sand and clay,
/// holding the eight-point star in the colour made of both. Drawn from design/brand/seal.svg.
struct MakerSeal: View {
    var size: CGFloat = 44

    var body: some View {
        Canvas { context, canvas in
            let unit = canvas.width / 100

            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: (50 + (x - 50) * 0.78) * unit, y: (53 + (y - 53) * 0.78) * unit)
            }

            let tile = Path(
                roundedRect: CGRect(x: 4 * unit, y: 4 * unit, width: 92 * unit, height: 92 * unit),
                cornerRadius: 21 * unit,
                style: .continuous
            )
            context.fill(tile, with: .color(Brand.night))

            let figureStyle = StrokeStyle(lineWidth: 8.5 * 0.78 * unit, lineCap: .round, lineJoin: .round)

            func figure(outer: CGPoint, joint: CGPoint, inner: CGPoint, foot: CGPoint) -> Path {
                var path = Path()
                path.move(to: outer)
                path.addLine(to: joint)
                path.addLine(to: inner)
                path.move(to: joint)
                path.addLine(to: foot)
                return path
            }

            let left = figure(outer: point(8, 32), joint: point(24, 54), inner: point(40, 32), foot: point(24, 78))
            let right = figure(outer: point(92, 32), joint: point(76, 54), inner: point(60, 32), foot: point(76, 78))
            context.stroke(left, with: .color(Brand.sand), style: figureStyle)
            context.stroke(right, with: .color(Brand.clay), style: figureStyle)

            func star(radius: CGFloat) -> Path {
                var path = Path()
                for rotation in [0.0, 45.0] {
                    let corners = (0..<4).map { index -> CGPoint in
                        let angle = (rotation + 90 * Double(index)) * .pi / 180
                        return point(50 + radius * CGFloat(cos(angle)), 27 + radius * CGFloat(sin(angle)))
                    }
                    path.addLines(corners)
                    path.closeSubpath()
                }
                return path
            }

            context.fill(star(radius: 10.5), with: .color(Brand.night))
            let starShape = star(radius: 8)
            context.fill(starShape, with: .color(Brand.blend))
            context.stroke(starShape, with: .color(Brand.blend), style: StrokeStyle(lineWidth: 1.2 * 0.78 * unit, lineJoin: .round))
        }
        .frame(width: size, height: size)
        .accessibilityLabel(Brand.maker)
    }
}

/// Shown for a moment after launch. The jar sits exactly where the system launch screen draws it,
/// so the hand-off is seamless; the title and the maker's seal fade in with it.
struct SplashView: View {
    var body: some View {
        ZStack {
            Brand.night.ignoresSafeArea()

            Image("LaunchMark")
                .overlay(alignment: .bottom) {
                    Text("PulseJar")
                        .font(.title.bold())
                        .foregroundStyle(Brand.cream)
                        .fixedSize()
                        .offset(y: 56)
                }

            VStack {
                Spacer()
                HStack(spacing: 8) {
                    MakerSeal(size: 22)
                    Text(Brand.maker)
                        .font(.footnote)
                        .foregroundStyle(Brand.cream.opacity(0.6))
                }
                .padding(.bottom, 24)
            }
        }
    }
}

/// The signature at the bottom of Settings.
struct MakerFooter: View {
    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    var body: some View {
        VStack(spacing: 6) {
            MakerSeal(size: 44)
                .padding(.bottom, 4)
            Text("PulseJar \(version)")
            Text(Brand.maker)
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }
}
