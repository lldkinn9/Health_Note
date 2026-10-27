import Foundation
import SwiftData

public enum ChatRole: String, Codable {
    case user = "user"
    case assistant = "assistant"
    case system = "system"
}

/// AIアドバイザーとのチャットメッセージ履歴
/// SwiftData + CloudKit 同期準拠
@Model
public final class AdvisorChatMessage {
    public var id: UUID = UUID()
    public var timestamp: Date = Date()
    public var roleRaw: String = ChatRole.user.rawValue
    public var content: String = ""
    public var isError: Bool = false

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        role: ChatRole = .user,
        content: String,
        isError: Bool = false
    ) {
        self.id = id
        self.timestamp = timestamp
        self.roleRaw = role.rawValue
        self.content = content
        self.isError = isError
    }

    public var role: ChatRole {
        get { ChatRole(rawValue: roleRaw) ?? .user }
        set { roleRaw = newValue.rawValue }
    }

    public var isUser: Bool {
        role == .user
    }
}
