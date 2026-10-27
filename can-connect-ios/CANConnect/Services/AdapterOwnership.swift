import Foundation

/// Process-wide lease: onboarding and recording cannot open the same physical
/// endpoint concurrently, even when they use different facade instances.
@MainActor
enum AdapterOwnership {
    private static var owners:[String:UUID]=[:]
    static func acquire(_ key:String,owner:UUID) throws {
        guard owners[key] == nil || owners[key] == owner else { throw AppFailure("This adapter is already in use by DriveLine. Stop the current session first.") }
        owners[key]=owner
    }
    static func release(_ key:String,owner:UUID) { if owners[key] == owner { owners.removeValue(forKey:key) } }
}
