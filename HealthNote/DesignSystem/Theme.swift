import SwiftUI

// MARK: - App Design System & Colors
public enum AppTheme {
    // MARK: - Colors
    public static let emerald = Color(red: 16/255, green: 185/255, blue: 129/255) // #10B981
    public static let emeraldDark = Color(red: 5/255, green: 150/255, blue: 105/255)
    public static let emeraldLight = Color(red: 209/255, green: 250/255, blue: 229/255)

    // PFC Balance Colors
    public static let proteinColor = Color(red: 6/255, green: 182/255, blue: 212/255) // Cyan #06B6D4
    public static let fatColor = Color(red: 245/255, green: 158/255, blue: 11/255)    // Amber/Yellow #F59E0B
    public static let carbsColor = Color(red: 16/255, green: 185/255, blue: 129/255)  // Mint/Emerald #10B981

    // Calorie Colors
    public static let calorieIntake = Color.orange
    public static let calorieBurn = Color.green
    public static let calorieNet = Color.blue

    // Widget & Dark Card Backgrounds
    public static let deepNavy = Color(red: 15/255, green: 23/255, blue: 42/255) // #0F172A (Slate 900)
    public static let deepNavySurface = Color(red: 30/255, green: 41/255, blue: 59/255) // Slate 800
    public static let cardBorderSubtle = Color.white.opacity(0.08)

    // Action Button Gradient (Indigo ~ Purple)
    public static let actionGradient = LinearGradient(
        colors: [Color.indigo, Color.purple],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // Emerald Brand Gradient
    public static let emeraldGradient = LinearGradient(
        colors: [emerald, emeraldDark],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // MARK: - Dimensions & Radius
    public static let cardCornerRadius: CGFloat = 18
    public static let buttonCornerRadius: CGFloat = 14
    public static let smallCornerRadius: CGFloat = 10

    // MARK: - Shadows
    public static let cardShadowColor = Color.black.opacity(0.05)
    public static let cardShadowRadius: CGFloat = 8
    public static let cardShadowY: CGFloat = 4
}

// MARK: - View Modifiers for Robust Layout
public struct CardModifier: ViewModifier {
    public var cornerRadius: CGFloat = AppTheme.cardCornerRadius
    public var backgroundColor: Color = Color(.secondarySystemGroupedBackground)

    public func body(content: Content) -> some View {
        content
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: AppTheme.cardShadowColor, radius: AppTheme.cardShadowRadius, x: 0, y: AppTheme.cardShadowY)
    }
}

public struct PreventTruncationModifier: ViewModifier {
    public var minimumScaleFactor: CGFloat = 0.7

    public func body(content: Content) -> some View {
        content
            .lineLimit(1)
            .minimumScaleFactor(minimumScaleFactor)
    }
}

public extension View {
    func appCard(
        cornerRadius: CGFloat = AppTheme.cardCornerRadius,
        backgroundColor: Color = Color(.secondarySystemGroupedBackground)
    ) -> some View {
        modifier(CardModifier(cornerRadius: cornerRadius, backgroundColor: backgroundColor))
    }

    /// 数字やタイトルの文字切れ（...）を防止するModifier
    func preventTruncation(minScale: CGFloat = 0.7) -> some View {
        modifier(PreventTruncationModifier(minimumScaleFactor: minScale))
    }

    /// 数値用太字丸ゴシックフォント
    func roundedMetricFont(size: CGFloat, weight: Font.Weight = .black) -> some View {
        self.font(.system(size: size, weight: weight, design: .rounded))
    }
}
