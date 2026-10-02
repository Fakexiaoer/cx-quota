import Foundation

public enum QuotaCountdown {
    public static func text(until date: Date?, now: Date = Date()) -> String {
        guard let date else { return "重置时间未提供" }
        let seconds = max(0, Int(date.timeIntervalSince(now)))
        if seconds == 0 { return "即将重置" }
        let days = seconds / 86_400
        let hours = seconds % 86_400 / 3_600
        let minutes = seconds % 3_600 / 60
        if days > 0 { return "\(days)天\(hours)小时后" }
        if hours > 0 { return "\(hours)小时\(minutes)分后" }
        return "\(max(1, minutes))分钟后"
    }

    public static func compactText(until date: Date?, now: Date = Date()) -> String {
        guard let date else { return "—" }
        let seconds = max(0, Int(date.timeIntervalSince(now)))
        if seconds == 0 { return "NOW" }
        let days = seconds / 86_400
        let hours = seconds % 86_400 / 3_600
        let minutes = seconds % 3_600 / 60
        if days > 0 { return "\(days)D \(hours)H" }
        if hours > 0 { return "\(hours)H \(minutes)M" }
        return "\(max(1, minutes))M"
    }
}

public enum QuotaError: LocalizedError, Sendable {
    case invalidResponse
    case server(String)
    case executableUnavailable
    case timedOut
    case processFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse: "官方 Codex 返回的额度数据无法识别"
        case let .server(message): message
        case .executableUnavailable: "未找到官方 codex 命令"
        case .timedOut: "查询超时"
        case let .processFailed(message): message
        }
    }
}
