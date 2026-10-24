import Foundation

struct LocalStore {
    let url: URL
    init(url: URL? = nil) {
        self.url = url ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("CANConnect/state.json")
    }
    func load() throws -> StoredState? {
        guard FileManager.default.fileExists(atPath:url.path) else { return nil }
        var state = try JSONDecoder().decode(StoredState.self, from:Data(contentsOf:url))
        guard (1...3).contains(state.schemaVersion) else { throw AppFailure("This saved data needs a newer app. Your file has been preserved.") }
        state.migrateVehicles()
        return state
    }
    func save(_ state: StoredState) throws {
        try FileManager.default.createDirectory(at:url.deletingLastPathComponent(), withIntermediateDirectories:true)
        let data = try JSONEncoder().encode(state)
        try data.write(to:url, options:[.atomic, .completeFileProtectionUnlessOpen])
    }
}
