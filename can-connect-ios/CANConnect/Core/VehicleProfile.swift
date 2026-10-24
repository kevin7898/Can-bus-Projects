import Foundation

enum VehicleKind: String, Codable, CaseIterable, Identifiable {
    case car, pickup, motorcycle, van, other
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var icon: String { switch self { case .motorcycle: return "motorcycle"; case .pickup: return "truck.pickup.side"; case .van: return "bus"; default: return "car.side" } }
}
enum FuelKind: String, Codable, CaseIterable, Identifiable {
    case unknown, gasoline, diesel, electric, hybrid, other
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}
struct VehicleProfile: Codable, Identifiable, Equatable {
    var id = UUID()
    var nickname = ""
    var year: Int?
    var make = ""
    var model = ""
    var trim = ""
    var engine = ""
    var transmission = ""
    var kind: VehicleKind = .car
    var fuel: FuelKind = .unknown
    var vin: String?
    var odometerKM: Double?
    var tankLitres: Double?
    var scannerProtocol: String?
    var scannerConnection: ScannerSettings?
    var supportedPIDs: [Int] = []
    var identificationSource = "Manual entry"
    var isSample = false
    var dashboard = Preferences()
    var title: String {
        if !nickname.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty { return nickname }
        let name = [year.map(String.init),make,model].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator:" ")
        return name.isEmpty ? "Vehicle" : name
    }
    var detail: String { [year.map(String.init),make,model,trim].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator:" ") }
    static var sample: Self {
        var v = Self(); v.nickname = "Sample Jetta"; v.year = 2014; v.make = "Volkswagen"; v.model = "Jetta"; v.engine = "2.0 TDI"; v.transmission = "DSG"; v.fuel = .diesel; v.odometerKM = 216482; v.tankLitres = 55; v.isSample = true; v.identificationSource = "Bundled sample"; return v
    }
    func validated(requireIdentity: Bool = true) throws -> Self {
        var value = self
        value.nickname = nickname.trimmingCharacters(in:.whitespacesAndNewlines)
        value.make = make.trimmingCharacters(in:.whitespacesAndNewlines)
        value.model = model.trimmingCharacters(in:.whitespacesAndNewlines)
        guard (!requireIdentity || (!value.make.isEmpty && !value.model.isEmpty)), value.make.count <= 80, value.model.count <= 80, value.nickname.count <= 80 else { throw AppFailure("Enter the make and model, or a shorter vehicle name.") }
        if let year { guard (1886...(Calendar.current.component(.year,from:Date())+2)).contains(year) else { throw AppFailure("Check the model year.") } }
        if let vin, !vin.isEmpty { value.vin = try VIN.normalized(vin) } else { value.vin = nil }
        if let odometerKM { guard odometerKM.isFinite && odometerKM >= 0 else { throw AppFailure("Check the odometer.") } }
        if let tankLitres { guard tankLitres.isFinite && tankLitres > 0 && tankLitres <= 2000 else { throw AppFailure("Check the tank capacity.") } }
        return value
    }
}
enum VIN {
    static func normalized(_ input: String) throws -> String {
        let value = input.uppercased().filter { !$0.isWhitespace }
        let allowed = Set("ABCDEFGHJKLMNPRSTUVWXYZ0123456789")
        guard value.count == 17, value.allSatisfy({allowed.contains($0)}) else { throw AppFailure("A standard VIN has 17 letters and numbers, without I, O or Q. You can leave VIN blank for manual setup.") }
        return value
    }
}
struct ScannerIdentity {
    var vin: String?
    var adapter: String
    var vehicleProtocol: String
    var supportedPIDs: [Int]
}

extension StoredState {
    private enum Keys: String, CodingKey { case schemaVersion, regenTrackingStartedAt, trips, fills, preferences, draft, vehicles, selectedVehicleID, onboardingCompleted, scanner, server, transfers }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy:Keys.self)
        schemaVersion = try c.decodeIfPresent(Int.self,forKey:.schemaVersion) ?? 1
        regenTrackingStartedAt = try c.decodeIfPresent(Date.self,forKey:.regenTrackingStartedAt)
        trips = try c.decodeIfPresent([Trip].self,forKey:.trips) ?? []
        fills = try c.decodeIfPresent([FuelEntry].self,forKey:.fills) ?? []
        preferences = try c.decodeIfPresent(Preferences.self,forKey:.preferences) ?? Preferences()
        scanner = try c.decodeIfPresent(ScannerSettings.self,forKey:.scanner) ?? ScannerSettings()
        server = try c.decodeIfPresent(ServerSettings.self,forKey:.server) ?? ServerSettings()
        transfers = try c.decodeIfPresent([TransferItem].self,forKey:.transfers) ?? []
        draft = try c.decodeIfPresent(RecordingDraft.self,forKey:.draft)
        vehicles = try c.decodeIfPresent([VehicleProfile].self,forKey:.vehicles) ?? []
        selectedVehicleID = try c.decodeIfPresent(UUID.self,forKey:.selectedVehicleID)
        onboardingCompleted = try c.decodeIfPresent(Bool.self,forKey:.onboardingCompleted) ?? false
    }
    mutating func migrateVehicles() {
        if schemaVersion == 1 {
            if !trips.isEmpty || !fills.isEmpty || draft != nil {
                let sampleOnly = trips.allSatisfy(\.isSample) && fills.allSatisfy(\.isSample) && draft == nil
                var vehicle = sampleOnly ? VehicleProfile.sample : VehicleProfile()
                if !sampleOnly { vehicle.nickname = "Previous vehicle"; vehicle.identificationSource = "Previous app data · review details" }
                vehicle.dashboard = preferences
                vehicles = [vehicle]; selectedVehicleID = vehicle.id
                for i in trips.indices { trips[i].vehicleID = vehicle.id }
                for i in fills.indices { fills[i].vehicleID = vehicle.id }
                draft?.vehicleID = vehicle.id
            }
            schemaVersion = 2
        }
        schemaVersion = 3
        if selectedVehicleID == nil || !vehicles.contains(where:{$0.id == selectedVehicleID}) { selectedVehicleID = vehicles.first?.id }
    }
}
