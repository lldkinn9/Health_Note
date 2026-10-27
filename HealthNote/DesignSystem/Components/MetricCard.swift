import SwiftUI

/// 数値指標カード（太字丸ゴシック・文字切れ防止レイアウト）
public struct MetricCard: View {
    public let title: String
    public let value: String
    public let unit: String
    public let icon: String
    public let iconColor: Color
    public var subtitle: String? = nil

    public init(
        title: String,
        value: String,
        unit: String,
        icon: String,
        iconColor: Color,
        subtitle: String? = nil
    ) {
        self.title = title
        self.value = value
        self.unit = unit
        self.icon = icon
        self.iconColor = iconColor
        self.subtitle = subtitle
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(iconColor)

                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundColor(.primary)
                    .preventTruncation(minScale: 0.65)

                Text(unit)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(.secondary)
            }

            if let subtitle = subtitle {
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard()
    }
}
