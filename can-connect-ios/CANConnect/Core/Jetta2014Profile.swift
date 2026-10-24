import Foundation

// Confirmed user profile. All live reads remain advertised standard Mode 01.
// VW/DSG service 22 candidates returned NO DATA on the physical MX+ acceptance run.
enum Jetta2014Profile {
    static func matches(_ vehicle: VehicleProfile) -> Bool {
        !vehicle.isSample && vehicle.year == 2014 &&
        ["volkswagen","vw"].contains(vehicle.make.lowercased()) && vehicle.model.lowercased() == "jetta" &&
        (vehicle.fuel == .diesel || vehicle.engine.uppercased().contains("TDI")) && vehicle.transmission.uppercased().contains("DSG")
    }

}

// Bounded local hardware evidence, never sent to GitHub or included in transfers.
// Includes rejected/unsupported replies so unavailable signals can be diagnosed.
@MainActor
final class ScannerJournal {
    private struct Exchange: Codable { var timestamp: Date; var command: String; var reply: String }
    private var entries: [Exchange] = []
    private let url: URL?
    private let eventsURL: URL?
    private var events: [Exchange] = []
    init(directory: URL? = nil) {
        let root = directory ?? (try? FileManager.default.url(for:.applicationSupportDirectory,in:.userDomainMask,appropriateFor:nil,create:true)
            .appendingPathComponent("CANConnect"))
        url = root?.appendingPathComponent("scanner-diagnostics.json")
        eventsURL = root?.appendingPathComponent("scanner-events.json")
        if let eventsURL, let data = try? Data(contentsOf:eventsURL),
           let saved = try? JSONDecoder().decode([Exchange].self,from:data) {
            events = Array(saved.suffix(256))
        }
        append(command:"SESSION",reply:"Preparing scanner connection")
    }
    func append(command: String, reply: String) {
        let entry = Exchange(timestamp:Date(),command:command,reply:reply)
        entries.append(entry)
        if ["SESSION","VW","ERROR"].contains(command) {
            events.append(entry)
            if events.count > 256 { events.removeFirst(events.count-256) }
            if let eventsURL, let data = try? JSONEncoder().encode(events) {
                try? FileManager.default.createDirectory(at:eventsURL.deletingLastPathComponent(),withIntermediateDirectories:true)
                try? data.write(to:eventsURL,options:[.atomic,.completeFileProtectionUntilFirstUserAuthentication])
            }
        }
        if entries.count > 512 { entries.removeFirst(entries.count-512) }
        guard let url, let data = try? JSONEncoder().encode(entries) else { return }
        try? FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
        try? data.write(to:url,options:[.atomic,.completeFileProtectionUntilFirstUserAuthentication])
    }
}
