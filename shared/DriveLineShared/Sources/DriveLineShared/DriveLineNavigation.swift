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

public enum DriveLinePhoneDestination: String, CaseIterable, Identifiable, Sendable {
    case today
    case drives
    case fuel
    case record
    case garage
    case more

    public static let primary:[Self] = [.today,.drives,.fuel,.garage,.more]
    public var id:String { rawValue }
    public var title:String { rawValue.capitalized }
}

public enum DriveLinePhoneRoute {
    public static func destination(for url:URL)->DriveLinePhoneDestination? {
        guard url.scheme?.lowercased()=="canconnect" else { return nil }
        return url.host?.lowercased()=="recording" ? .record:nil
    }
}

public enum DriveLineMoreCapability:String,CaseIterable,Sendable {
    case connections
    case transfers
    case serverPairing
    case settings
}
