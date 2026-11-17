import SwiftUI

/// Soft warm color fields behind every screen. Liquid Glass refracts what's beneath it, so a flat background would make it read as plain gray.
struct AmbientBackground: View {
    var body: some View {
        ZStack {
            Theme.background
            blob(Theme.glowA, size: 520, x: -0.35, y: -0.38)
            blob(Theme.glowB, size: 460, x: 0.45, y: -0.05)
            blob(Theme.glowC, size: 560, x: -0.25, y: 0.45)
        }
        .ignoresSafeArea()
    }

    private func blob(_ color: Color, size: CGFloat, x: CGFloat, y: CGFloat) -> some View {
        GeometryReader { geometry in
            Circle()
                .fill(color)
                .frame(width: size, height: size)
                .blur(radius: 90)
                .position(x: geometry.size.width * (0.5 + x), y: geometry.size.height * (0.5 + y))
        }
    }
}
