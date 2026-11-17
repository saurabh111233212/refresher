import SwiftUI

/// Warns two days before the free-signing install lapses, so reinstalling happens at a desk rather than in a queue.
struct ExpiryBanner: View {
    @Environment(AppModel.self) private var model
    static let warningWindow: TimeInterval = 2 * 24 * 60 * 60

    var body: some View {
        if let expiry = model.installExpiry, expiry.timeIntervalSinceNow < Self.warningWindow {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "clock.badge.exclamationmark")
                    .font(.title3)
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text(expiry > .now ? "Refresher expires \(expiry.formatted(.relative(presentation: .named)))" : "This install has expired")
                        .font(.subheadline.weight(.semibold))
                    Text("Plug the phone into your Mac and ask Claude to reinstall Refresher. Your progress carries over.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .glassEffect(.regular.tint(Theme.accent.opacity(0.15)), in: RoundedRectangle(cornerRadius: 22))
        }
    }
}
