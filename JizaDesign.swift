import SwiftUI

enum JizaPalette {
    static let cobalt = Color(red: 49 / 255, green: 91 / 255, blue: 235 / 255)
    static let accent = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 145 / 255, green: 179 / 255, blue: 1, alpha: 1)
            : UIColor(red: 49 / 255, green: 91 / 255, blue: 235 / 255, alpha: 1)
    })
    static let background = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 16 / 255, green: 24 / 255, blue: 44 / 255, alpha: 1)
            : UIColor(red: 239 / 255, green: 243 / 255, blue: 1, alpha: 1)
    })
    static let surface = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 25 / 255, green: 36 / 255, blue: 61 / 255, alpha: 1)
            : .white
    })
}

struct JizaSurface: ViewModifier {
    var radius: CGFloat = 24
    var interactive = false
    func body(content: Content) -> some View {
        content.modifier(JizaGlassSurface(radius: radius, interactive: interactive))
    }
}

struct JizaBackdrop: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        ZStack {
            JizaPalette.background
            if !reduceTransparency {
                RadialGradient(colors: [JizaPalette.cobalt.opacity(scheme == .dark ? 0.45 : 0.18), .clear],
                               center: .topTrailing, startRadius: 0, endRadius: 480)
            }
        }
    }
}

struct JizaPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.75), value: configuration.isPressed)
    }
}
