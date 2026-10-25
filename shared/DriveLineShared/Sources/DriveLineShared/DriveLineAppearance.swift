import Foundation

public enum DriveLineAppearance: String, CaseIterable, Codable, Identifiable, Sendable {
    case system
    case light
    case dark

    public static let storageKey = "driveline.appearance"
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    public func resolved(systemIsDark: Bool) -> DriveLineResolvedAppearance {
        switch self {
        case .system: systemIsDark ? .dark : .light
        case .light: .light
        case .dark: .dark
        }
    }
}

public enum DriveLineResolvedAppearance: String, Equatable, Sendable {
    case light
    case dark
}

public struct DriveLineAppearanceStore {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var selection: DriveLineAppearance {
        get {
            guard let rawValue = defaults.string(forKey: DriveLineAppearance.storageKey),
                  let value = DriveLineAppearance(rawValue: rawValue) else { return .system }
            return value
        }
        nonmutating set { defaults.set(newValue.rawValue, forKey: DriveLineAppearance.storageKey) }
    }
}
