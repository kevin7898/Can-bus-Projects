import Foundation

enum VehicleKind: String, Codable, CaseIterable, Identifiable {
    case car, pickup, motorcycle, heavyTruck, van, other
    var id: String { rawValue }
    var title: String { switch self { case .car:return "Passenger car";case .pickup:return "Light truck";case .motorcycle:return "Motorcycle";case .heavyTruck:return "Heavy truck";case .van:return "Van";case .other:return "Other" } }
    var icon: String { switch self { case .motorcycle: return "motorcycle"; case .pickup: return "truck.pickup.side"; case .heavyTruck:return "truck.box";case .van: return "bus"; default: return "car.side" } }
    var shared:DriveLineVehicleClass { switch self { case .car:return .passengerCar;case .pickup:return .lightTruck;case .motorcycle:return .motorcycle;case .heavyTruck:return .heavyTruck;case .van:return .van;case .other:return .other } }
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
    var identification: DriveLineVehicleIdentityObservation?
    var preferredUnits: DriveLineUnitSystem = .metric
    var preferredGPS: DriveLineGPSPreference = .automatic
    var configuredSources: [DriveLineVehicleSource] = [.manual,.phoneGPS]
    var isArchived = false
    var archivedAt: Date?
    var isSample = false
    var dashboard = Preferences()
    init() {}
    var title: String {
        if !nickname.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty { return nickname }
        let name = [year.map(String.init),make,model].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator:" ")
        return name.isEmpty ? "Vehicle" : name
    }
    var detail: String { [year.map(String.init),make,model,trim].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator:" ") }
    static var sample: Self {
        var v = Self(); v.nickname = "Fictional Jetta"; v.year = 2013; v.make = "Volkswagen"; v.model = "Jetta"; v.engine = "TDI"; v.fuel = .diesel; v.odometerKM = 216482; v.tankLitres = 55; v.isSample = true; v.identificationSource = "Sanitized debug fixture"; return v
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

    private enum CodingKeys:String,CodingKey {
        case id,nickname,year,make,model,trim,engine,transmission,kind,fuel,vin,odometerKM,tankLitres
        case scannerProtocol,scannerConnection,supportedPIDs,identificationSource,identification,preferredUnits
        case preferredGPS,configuredSources,isArchived,archivedAt,isSample,dashboard
    }
    init(from decoder:Decoder) throws {
        let values=try decoder.container(keyedBy:CodingKeys.self)
        id=try values.decodeIfPresent(UUID.self,forKey:.id) ?? UUID()
        nickname=try values.decodeIfPresent(String.self,forKey:.nickname) ?? ""
        year=try values.decodeIfPresent(Int.self,forKey:.year)
        make=try values.decodeIfPresent(String.self,forKey:.make) ?? ""
        model=try values.decodeIfPresent(String.self,forKey:.model) ?? ""
        trim=try values.decodeIfPresent(String.self,forKey:.trim) ?? ""
        engine=try values.decodeIfPresent(String.self,forKey:.engine) ?? ""
        transmission=try values.decodeIfPresent(String.self,forKey:.transmission) ?? ""
        kind=try values.decodeIfPresent(VehicleKind.self,forKey:.kind) ?? .car
        fuel=try values.decodeIfPresent(FuelKind.self,forKey:.fuel) ?? .unknown
        vin=try values.decodeIfPresent(String.self,forKey:.vin)
        odometerKM=try values.decodeIfPresent(Double.self,forKey:.odometerKM)
        tankLitres=try values.decodeIfPresent(Double.self,forKey:.tankLitres)
        scannerProtocol=try values.decodeIfPresent(String.self,forKey:.scannerProtocol)
        scannerConnection=try values.decodeIfPresent(ScannerSettings.self,forKey:.scannerConnection)
        supportedPIDs=try values.decodeIfPresent([Int].self,forKey:.supportedPIDs) ?? []
        identificationSource=try values.decodeIfPresent(String.self,forKey:.identificationSource) ?? "Manual entry"
        identification=try values.decodeIfPresent(DriveLineVehicleIdentityObservation.self,forKey:.identification)
        preferredUnits=try values.decodeIfPresent(DriveLineUnitSystem.self,forKey:.preferredUnits) ?? .metric
        preferredGPS=try values.decodeIfPresent(DriveLineGPSPreference.self,forKey:.preferredGPS) ?? .automatic
        configuredSources=try values.decodeIfPresent([DriveLineVehicleSource].self,forKey:.configuredSources) ?? [.manual,.phoneGPS]
        isArchived=try values.decodeIfPresent(Bool.self,forKey:.isArchived) ?? false
        archivedAt=try values.decodeIfPresent(Date.self,forKey:.archivedAt)
        isSample=try values.decodeIfPresent(Bool.self,forKey:.isSample) ?? false
        dashboard=try values.decodeIfPresent(Preferences.self,forKey:.dashboard) ?? Preferences()
    }
}
enum VIN {
    static func normalized(_ input: String) throws -> String {
        do { return try DriveLineVINDecoder.normalized(input) }
        catch { throw AppFailure(error.localizedDescription+" You can leave VIN blank for manual setup.") }
    }
}
struct ScannerIdentity {
    var vin: String?
    var adapter: String
    var vehicleProtocol: String
    var supportedPIDs: [Int]
    var respondingAddress: String? = nil
    var observedAt: Date = Date()
}

struct VehicleOnboardingReview:Equatable {
    let original:VehicleProfile
    private(set) var draft:VehicleProfile
    private(set) var detected:DriveLineVINResult?
    private(set) var retainedEnteredYear=false

    init(_ profile:VehicleProfile) { original=profile;draft=profile }
    mutating func receive(vin:String,identity:ScannerIdentity?) throws {
        let evidence=try DriveLineVINDecoder.decode(vin,enteredModelYear:draft.year)
        detected=evidence;draft.vin=evidence.normalizedVIN
        if let identity {
            draft.scannerProtocol=identity.vehicleProtocol;draft.supportedPIDs=identity.supportedPIDs
            draft.identification=DriveLineVehicleIdentityObservation(source:"Read-only Mode 09 VIN",respondingAddress:identity.respondingAddress,protocolName:identity.vehicleProtocol,observedAt:identity.observedAt)
        }
    }
    mutating func acceptSuggestedYear() {
        guard let year=detected?.suggestedModelYear else { return }
        draft.year=year;retainedEnteredYear=false
    }
    mutating func retainEnteredYear() { draft.year=original.year;retainedEnteredYear=true }
    mutating func acceptSuggestedManufacturer() {
        guard let manufacturer=detected?.manufacturer else { return }
        draft.make=manufacturer
    }
    func cancelledProfile()->VehicleProfile { original }
    func completedProfile()->VehicleProfile { var value=draft;value.id=original.id;return value }
}

extension StoredState {
    private enum Keys: String, CodingKey { case schemaVersion, regenTrackingStartedAt, trips, fills, preferences, draft, vehicles, selectedVehicleID, onboardingCompleted, scanner, server, transfers, journeyAnnotations }
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
        journeyAnnotations = try c.decodeIfPresent([String:DriveLineJourneyAnnotation].self,forKey:.journeyAnnotations) ?? [:]
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
        if schemaVersion < 4 { schemaVersion = 4 }
        if selectedVehicleID == nil || !vehicles.contains(where:{$0.id == selectedVehicleID}) { selectedVehicleID = vehicles.first?.id }
        if let selectedVehicleID,
           let index=vehicles.firstIndex(where:{$0.id==selectedVehicleID}),
           vehicles[index].scannerConnection == nil,
           (!scanner.host.isEmpty || scanner.accessorySerial?.isEmpty == false) {
            vehicles[index].scannerConnection=scanner
            if !vehicles[index].configuredSources.contains(.obdScanner) { vehicles[index].configuredSources.append(.obdScanner) }
        }
    }
}
