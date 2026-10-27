import SwiftUI

/// 未保存の変更がある時のみ画面下部にふわっと現れるフローティング保存バー
public struct FloatingSaveBar: View {
    public let isVisible: Bool
    public let onSave: () -> Void
    public let onDiscard: (() -> Void)?

    @State private var isPulsing: Bool = false

    public init(
        isVisible: Bool,
        onSave: @escaping () -> Void,
        onDiscard: (() -> Void)? = nil
    ) {
        self.isVisible = isVisible
        self.onSave = onSave
        self.onDiscard = onDiscard
    }

    public var body: some View {
        if isVisible {
            HStack(spacing: 12) {
                // パルス点滅インジケーター ＆ ステータステキスト
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(Color.orange.opacity(0.3))
                            .frame(width: 14, height: 14)
                            .scaleEffect(isPulsing ? 1.6 : 1.0)
                            .opacity(isPulsing ? 0.0 : 1.0)

                        Circle()
                            .fill(Color.orange)
                            .frame(width: 8, height: 8)
                    }

                    Text("未保存の変更があります")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.primary)
                        .preventTruncation(minScale: 0.8)
                }

                Spacer()

                // 破棄ボタン（指定されている場合）
                if let onDiscard = onDiscard {
                    Button(action: {
                        let generator = UIImpactFeedbackGenerator(style: .light)
                        generator.impactOccurred()
                        onDiscard()
                    }) {
                        Text("破棄")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                    }
                }

                // 保存実行ボタン
                Button(action: {
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                    onSave()
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14, weight: .bold))
                        Text("保存する")
                            .font(.system(size: 13, weight: .black, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(AppTheme.emeraldGradient)
                    .clipShape(Capsule())
                    .shadow(color: AppTheme.emerald.opacity(0.3), radius: 6, x: 0, y: 3)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .shadow(color: Color.black.opacity(0.12), radius: 16, x: 0, y: 6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(AppTheme.cardBorderSubtle, lineWidth: 1)
                    )
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 1.2)
                    .repeatForever(autoreverses: false)
                ) {
                    isPulsing = true
                }
            }
        }
    }
}
