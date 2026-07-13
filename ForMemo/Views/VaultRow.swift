

import SwiftUI
import SwiftData

struct VaultRow: View {

    let item: VaultItem

    private var subtitle: String {
        if !item.username.isEmpty { return item.username }
        if !item.email.isEmpty { return item.email }
        if !item.website.isEmpty { return item.website }
        return String(localized: "No username")
    }

    private var isPasswordExpired: Bool {
        guard let expiry = item.passwordExpiresAt else { return false }
        return expiry < .now
    }

    var body: some View {
        HStack(spacing: 14) {

            Image(systemName: item.icon.rawValue)
                .font(.title3)
                .foregroundStyle(item.color.swiftUIColor)
                .frame(width: 42, height: 42)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(item.title)
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    if item.favorite {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                    }
                }

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                HStack(spacing: 6) {
                    Text(item.category.localizedTitle)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.thinMaterial, in: Capsule())

                    if isPasswordExpired {
                        Label(String(localized: "Expired"), systemImage: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
            }

            Spacer(minLength: 8)


        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.title), \(subtitle)")
        .accessibilityHint(
            isPasswordExpired
            ? String(localized: "Password expired")
            : (item.favorite
                ? String(localized: "Favorite credential")
                : "")
        )
    }
}
