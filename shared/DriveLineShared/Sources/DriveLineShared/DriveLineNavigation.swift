import Foundation

public enum DriveLineMacDestination: String, CaseIterable, Identifiable, Sendable {
    case today
    case drives
    case fuel
    case signals
    case garage
    case imports
    case server

    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
    public static let primary: [Self] = [.today,.drives,.fuel,.signals,.garage]
    public static let secondary: [Self] = [.imports,.server]
}
