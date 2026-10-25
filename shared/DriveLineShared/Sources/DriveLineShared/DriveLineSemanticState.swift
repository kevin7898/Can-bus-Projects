import Foundation

public enum DriveLineSemanticState:String,CaseIterable,Identifiable,Sendable {
    case healthy
    case stale
    case unavailable
    case queued
    case recording

    public var id:String { rawValue }
    public var title:String { rawValue.capitalized }
    public var icon:String {
        switch self {
        case .healthy:"checkmark.circle.fill"
        case .stale:"clock.badge.exclamationmark"
        case .unavailable:"minus.circle"
        case .queued:"arrow.up.circle"
        case .recording:"record.circle.fill"
        }
    }
}
