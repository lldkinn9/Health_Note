import SwiftUI

/// PFCバランスを3色（シアン/イエロー/ミント）のプログレスバーとグラム数で可視化するコンポーネント
public struct PFCBalanceView: View {
    public let protein: Double
    public let fat: Double
    public let carbs: Double
    public var targetProtein: Double? = nil
    public var targetFat: Double? = nil
    public var targetCarbs: Double? = nil
    public var compact: Bool = false

    public init(
        protein: Double,
        fat: Double,
        carbs: Double,
        targetProtein: Double? = nil,
        targetFat: Double? = nil,
        targetCarbs: Double? = nil,
        compact: Bool = false
    ) {
        self.protein = protein
        self.fat = fat
        self.carbs = carbs
        self.targetProtein = targetProtein
        self.targetFat = targetFat
        self.targetCarbs = targetCarbs
        self.compact = compact
    }

    private var totalGrams: Double {
        protein + fat + carbs
    }

    private var pRatio: CGFloat {
        guard totalGrams > 0 else { return 0.33 }
        return CGFloat(protein / totalGrams)
    }

    private var fRatio: CGFloat {
        guard totalGrams > 0 else { return 0.33 }
        return CGFloat(fat / totalGrams)
    }

    private var cRatio: CGFloat {
        guard totalGrams > 0 else { return 0.34 }
        return CGFloat(carbs / totalGrams)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 10) {
            // 3色セグメントバー
            GeometryReader { geo in
                HStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(AppTheme.proteinColor)
                        .frame(width: max(4, geo.size.width * pRatio))

                    RoundedRectangle(cornerRadius: 3)
                        .fill(AppTheme.fatColor)
                        .frame(width: max(4, geo.size.width * fRatio))

                    RoundedRectangle(cornerRadius: 3)
                        .fill(AppTheme.carbsColor)
                        .frame(width: max(4, geo.size.width * cRatio))
                }
            }
            .frame(height: compact ? 6 : 8)
            .clipShape(Capsule())

            // グラム数表記
            HStack(spacing: compact ? 8 : 14) {
                pfcItem(label: "P", grams: protein, target: targetProtein, color: AppTheme.proteinColor)
                pfcItem(label: "F", grams: fat, target: targetFat, color: AppTheme.fatColor)
                pfcItem(label: "C", grams: carbs, target: targetCarbs, color: AppTheme.carbsColor)
            }
        }
    }

    @ViewBuilder
    private func pfcItem(label: String, grams: Double, target: Double?, color: Color) -> some View {
        HStack(spacing: 3) {
            Circle()
                .fill(color)
                .frame(width: compact ? 6 : 8, height: compact ? 6 : 8)

            Text(label)
                .font(.system(size: compact ? 11 : 12, weight: .bold, design: .rounded))
                .foregroundColor(.secondary)

            Text("\(Int(grams))g")
                .font(.system(size: compact ? 12 : 14, weight: .black, design: .rounded))
                .foregroundColor(.primary)
                .preventTruncation(minScale: 0.8)
        }
    }
}
