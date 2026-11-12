import SwiftUI

// Jiza's own iOS 16-compatible visual design tokens and reusable workspace components.
// Inspired by the token-driven approach of open-source SwiftUI design systems;
// no third-party source or runtime dependency is copied into the app.
enum JizaStyle {
    static let background = Color(red: 0.035, green: 0.055, blue: 0.10)
    static let surface = Color(red: 0.085, green: 0.11, blue: 0.18)
    static let elevated = Color(red: 0.115, green: 0.15, blue: 0.23)
    static let mint = Color(red: 0.29, green: 0.91, blue: 0.68)
    static let blue = Color(red: 0.41, green: 0.67, blue: 1.0)
    static let violet = Color(red: 0.67, green: 0.52, blue: 1.0)
    static let secondary = Color(red: 0.69, green: 0.75, blue: 0.84)
}

struct JizaWorkspaceBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [JizaStyle.background, Color(red: 0.08, green: 0.09, blue: 0.18)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            Circle()
                .fill(JizaStyle.blue.opacity(0.13))
                .frame(width: 270, height: 270)
                .blur(radius: 70)
                .offset(x: 160, y: -310)
            Circle()
                .fill(JizaStyle.violet.opacity(0.10))
                .frame(width: 240, height: 240)
                .blur(radius: 65)
                .offset(x: -170, y: 240)
        }
        .allowsHitTesting(false)
    }
}

struct JizaWorkspaceIntro: View {
    let eyebrow: String
    let title: String
    let detail: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .bold))
                Text(eyebrow.uppercased())
                    .tracking(2)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
            }
            .foregroundStyle(JizaStyle.mint)
            Text(title)
                .font(.system(size: 31, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.8)
            Text(detail)
                .font(.system(size: 14))
                .foregroundStyle(JizaStyle.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 12)
    }
}

struct JizaWorkspaceCard: View {
    let title: String
    let detail: String
    let symbol: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(color.opacity(0.14))
                        .frame(width: 62, height: 62)
                    Image(systemName: symbol)
                        .font(.system(size: 27, weight: .medium))
                        .foregroundStyle(color)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundStyle(JizaStyle.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 4)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(color)
                    .frame(width: 28, height: 28)
                    .background(color.opacity(0.14), in: Circle())
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(JizaStyle.surface, in: RoundedRectangle(cornerRadius: 22))
            .overlay {
                RoundedRectangle(cornerRadius: 22)
                    .strokeBorder(.white.opacity(0.09), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title + ". " + detail)
    }
}

struct JizaWorkspaceNote: View {
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lock.shield.fill")
                .foregroundStyle(JizaStyle.mint)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(JizaStyle.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(JizaStyle.elevated.opacity(0.7),
                    in: RoundedRectangle(cornerRadius: 16))
    }
}
