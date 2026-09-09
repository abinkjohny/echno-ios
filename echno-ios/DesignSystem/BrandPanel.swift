import SwiftUI

/// The dark brand artwork that fronts the auth screens.
///
/// This is echno-web's left-hand register panel: a near-black field, a faint
/// amber blueprint grid, two soft amber glows, the headline, and the product
/// highlights. It carries the same brand cues, laid out for the space it gets.
///
/// It adapts rather than shrinking. On iPad, and on iPhone in landscape, it
/// takes a column beside the form and shows everything. On a compact iPhone it
/// becomes a short header — headline and wordmark only — because four feature
/// rows above a ten-field form is a scroll, not a welcome.
struct BrandPanel: View {

    enum Layout {
        /// Full column: wordmark, badge, headline, highlights, trust line.
        case full
        /// Compact header: wordmark and headline only.
        case header
    }

    var layout: Layout = .full

    var body: some View {
        content
    }

    // MARK: Artwork

    /// Two blurred amber radials, matching the web panel's corner glows.
    fileprivate static func glows() -> some View {
        GeometryReader { proxy in
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Echno.brand.opacity(0.30), .clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: proxy.size.width * 0.55
                        )
                    )
                    .frame(width: proxy.size.width * 1.1)
                    .position(x: 0, y: 0)

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color(rgb: 0xEA580C).opacity(0.22), .clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: proxy.size.width * 0.45
                        )
                    )
                    .frame(width: proxy.size.width * 0.9)
                    .position(x: proxy.size.width, y: proxy.size.height)
            }
            .blur(radius: 40)
        }
        .allowsHitTesting(false)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch layout {
        case .full:
            // Fills its column, pushing the wordmark to the top and the trust
            // line to the bottom the way the web panel does.
            VStack(alignment: .leading, spacing: 0) {
                wordmark
                Spacer(minLength: Echno.Space.section)
                VStack(alignment: .leading, spacing: Echno.Space.xl) {
                    tagline
                    headline
                    highlights
                }
                Spacer(minLength: Echno.Space.section)
                trustLine
            }
            .padding(Echno.Space.screen)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

        case .header:
            // Hugs its content. Given a flexible height it would stretch and
            // strand the headline in the middle of an empty field.
            VStack(alignment: .leading, spacing: Echno.Space.xl) {
                wordmark
                headline
            }
            .padding(.horizontal, Echno.Space.xxl)
            .padding(.top, Echno.Space.xl)
            .padding(.bottom, Echno.Space.section)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var wordmark: some View {
        HStack(spacing: Echno.Space.sm) {
            Image(systemName: "cube.transparent.fill")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Echno.brand)
            Text("ECHNO")
                .font(.system(size: 20, weight: .black, design: .default))
                .kerning(2)
                .foregroundStyle(.white)
        }
    }

    private var tagline: some View {
        HStack(spacing: Echno.Space.sm) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 11, weight: .semibold))
            Text("Construction-First Platform")
                .font(.footnote.weight(.medium))
        }
        .foregroundStyle(Echno.brand)
        .padding(.horizontal, Echno.Space.md)
        .padding(.vertical, Echno.Space.sm)
        .background(Echno.brand.opacity(0.10), in: Capsule())
        .overlay(Capsule().stroke(Echno.brand.opacity(0.25), lineWidth: 1))
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: Echno.Space.md) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Build Smarter,")
                    .foregroundStyle(.white)
                Text("Manage Better.")
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(rgb: 0xF59E0B), Color(rgb: 0xEA580C)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            // Semantic styles rather than fixed point sizes: at accessibility
            // text sizes a fixed headline stays put while the body around it
            // grows, which inverts the hierarchy it exists to establish.
            .font((layout == .full ? Font.largeTitle : Font.title).weight(.black))
            .tracking(-0.8)
            .lineLimit(2)
            .minimumScaleFactor(0.6)

            if layout == .full {
                Text(
                    "One platform for attendance, workforce, projects, "
                    + "inventory, and billing — built for the construction industry."
                )
                .font(.callout)
                .foregroundStyle(Color(rgb: 0xA1A1AA))
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var highlights: some View {
        VStack(alignment: .leading, spacing: Echno.Space.lg) {
            ForEach(Highlight.all) { item in
                HStack(alignment: .top, spacing: Echno.Space.md) {
                    Image(systemName: item.symbol)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Echno.brand)
                        .frame(width: 32, height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: Echno.Radius.md)
                                .fill(Echno.brand.opacity(0.10))
                                .stroke(Echno.brand.opacity(0.20), lineWidth: 1)
                        )
                    VStack(alignment: .leading, spacing: Echno.Space.hairline) {
                        Text(item.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color(rgb: 0xF4F4F5))
                        Text(item.detail)
                            .font(.caption)
                            .foregroundStyle(Color(rgb: 0x71717B))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var trustLine: some View {
        HStack(spacing: Echno.Space.md) {
            Image(systemName: "checkmark.shield")
                .font(.caption)
            Text("Enterprise-grade security · GDPR compliant · 99.9% uptime SLA")
                .font(.caption2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Color(rgb: 0x52525C))
    }
}

/// The four product highlights from echno-web's register panel, with lucide
/// icons swapped for their closest SF Symbol.
private struct Highlight: Identifiable {
    let id = UUID()
    let symbol: String
    let title: String
    let detail: String

    static let all = [
        Highlight(
            symbol: "clock",                      // lucide: Clock
            title: "Attendance Tracking",
            detail: "GPS-verified check-ins across every site"
        ),
        Highlight(
            symbol: "person.2",                   // lucide: Users
            title: "Team Management",
            detail: "Roles, hierarchies, and shift scheduling"
        ),
        Highlight(
            symbol: "building.2",                 // lucide: Building2
            title: "Multi-Site Support",
            detail: "Manage all projects from one dashboard"
        ),
        Highlight(
            symbol: "chart.bar",                  // lucide: BarChart3
            title: "Live Analytics",
            detail: "Real-time reports and custom dashboards"
        )
    ]
}

/// The dark brand field: panel colour, blueprint grid and amber glows.
///
/// Separate from ``BrandPanel`` so it can ignore the safe area and bleed under
/// the status bar while the panel's text stays inside it. Bleeding the *content*
/// too is what put the wordmark on top of the clock.
struct BrandBackground: View {
    var body: some View {
        ZStack {
            Echno.panel
            BlueprintGrid()
                .stroke(Echno.brand.opacity(0.28), lineWidth: 1)
                .opacity(0.16)
            BrandPanel.glows()
        }
        .ignoresSafeArea()
    }
}

/// The blueprint grid behind the panel — 60 pt cells, matching the web panel's
/// `background-size: 60px 60px`.
private struct BlueprintGrid: Shape {
    var spacing: CGFloat = 60

    func path(in rect: CGRect) -> Path {
        var path = Path()
        var x = rect.minX
        while x <= rect.maxX {
            path.move(to: CGPoint(x: x, y: rect.minY))
            path.addLine(to: CGPoint(x: x, y: rect.maxY))
            x += spacing
        }
        var y = rect.minY
        while y <= rect.maxY {
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
            y += spacing
        }
        return path
    }
}

#Preview("Full") {
    ZStack { BrandBackground(); BrandPanel(layout: .full) }
        .frame(width: 420, height: 780)
}

#Preview("Header") {
    ZStack { BrandBackground(); BrandPanel(layout: .header) }
        .frame(height: 240)
}
