import Foundation

struct FuelOdometerObservation: Codable, Equatable, Sendable {
    var vehicleID: UUID
    var valueKm: Double
    var observedAt: Date
    var sourceIdentifier: String
    var recordingID: UUID?
    var isTrusted: Bool
    var definitionID:String? = nil
    var definitionVersion:String? = nil
    var controllerFingerprint:String? = nil
    var validationStatus:String? = nil

    var isValid: Bool {
        valueKm.isFinite && (0...10_000_000).contains(valueKm) &&
        observedAt.timeIntervalSince1970.isFinite && !sourceIdentifier.isEmpty
    }

    var provenance: DriveLineOdometerProvenance {
        var value=DriveLineOdometerProvenance(valueKm:valueKm,observedAt:observedAt,
            sourceIdentifier:sourceIdentifier,recordingID:recordingID,sourceType:.scanned)
        value.definitionID=definitionID;value.definitionVersion=definitionVersion
        value.controllerFingerprint=controllerFingerprint;value.validationStatus=validationStatus
        return value
    }
    func requiresReview(comparedWith previous:FuelOdometerObservation?) ->Bool {
        guard let previous,previous.vehicleID == vehicleID,observedAt > previous.observedAt else { return false }
        let hours=observedAt.timeIntervalSince(previous.observedAt)/3600
        return valueKm < previous.valueKm || valueKm-previous.valueKm > max(5,hours*300)
    }
}

enum FuelOdometerPrefillPolicy {
    static let currentMaximumAge: TimeInterval = 15 * 60
    static let storedMaximumAge: TimeInterval = 180 * 86_400

    static func choose(vehicleID: UUID, current: FuelOdometerObservation?,
                       stored: [FuelOdometerObservation], fills: [FuelEntry],
                       now: Date) -> DriveLineOdometerProvenance? {
        func accepted(_ item:FuelOdometerObservation,maximumAge:TimeInterval)->Bool {
            item.vehicleID == vehicleID && item.isTrusted && item.isValid &&
            (0...maximumAge).contains(now.timeIntervalSince(item.observedAt))
        }
        let previous=stored.filter { accepted($0,maximumAge:storedMaximumAge) }.max(by:{$0.observedAt<$1.observedAt})
        if let current, accepted(current,maximumAge:currentMaximumAge),!current.requiresReview(comparedWith:previous) { return current.provenance }
        if let latest=stored.filter({ accepted($0,maximumAge:storedMaximumAge) }).max(by:{$0.observedAt<$1.observedAt}) {
            return latest.provenance
        }
        guard let fill=fills.filter({ $0.vehicleID == vehicleID && !$0.isSample &&
            $0.odometerKM.isFinite && $0.odometerKM >= 0 }).max(by:{$0.date<$1.date}) else { return nil }
        return DriveLineOdometerProvenance(valueKm:fill.odometerKM,observedAt:fill.date,
            sourceIdentifier:"fuel-entry:\(fill.id.uuidString)",sourceType:.fuelEntry)
    }
}

struct FuelStationSuggestion: Equatable, Sendable {
    var stationName: String?
    var stationAddress: String
    var observedAt: Date
    var sourceIdentifier: String = "core-location.reverse-geocode"
}

enum FuelLocationFailure: Error, Equatable, Sendable {
    case permissionDenied
    case restricted
    case timeout
    case offline
    case unavailable
    case noResult

    var message:String {
        switch self {
        case .permissionDenied:return "Location permission is off. Enter the station manually or enable it in Settings."
        case .restricted:return "Location is restricted on this iPhone. Enter the station manually."
        case .timeout:return "The current location timed out. You can retry or enter the station manually."
        case .offline:return "Address lookup is offline. You can retry later or enter the station manually."
        case .unavailable:return "A sufficiently accurate current location is unavailable."
        case .noResult:return "No street address was found for the current location."
        }
    }
}

@MainActor
protocol FuelLocationProviding: AnyObject {
    func currentStation() async throws -> FuelStationSuggestion
}

enum FuelStationPrefillPolicy {
    @MainActor static func resolve(using provider:any FuelLocationProviding) async ->Result<FuelStationSuggestion,FuelLocationFailure> {
        do { return .success(try await provider.currentStation()) }
        catch let failure as FuelLocationFailure { return .failure(failure) }
        catch { return .failure(.unavailable) }
    }
}

/// Testable editing state. Async prefill results may mutate only pristine
/// fields; typing or explicitly clearing a field permanently claims it for the
/// user during this form session.
struct FuelFormDraft: Equatable {
    var odometerText: String
    var stationName: String
    var stationAddress: String
    var odometerProvenance: DriveLineOdometerProvenance?
    var stationProvenance: DriveLineStationProvenance?
    private(set) var odometerIsPristine: Bool
    private(set) var stationIsPristine: Bool

    init(entry:FuelEntry? = nil) {
        odometerText=entry.map { String($0.odometerKM) } ?? ""
        stationName=entry?.stationName ?? ""
        stationAddress=entry?.stationAddress ?? ""
        odometerProvenance=entry?.odometerProvenance
        stationProvenance=entry?.stationProvenance
        odometerIsPristine=entry == nil
        stationIsPristine=entry == nil
    }

    mutating func userChangedOdometer(_ text:String) {
        odometerText=text;odometerIsPristine=false;odometerProvenance=nil
    }
    mutating func userChangedStationName(_ text:String) {
        stationName=text;stationIsPristine=false;stationProvenance=nil
    }
    mutating func userChangedStationAddress(_ text:String) {
        stationAddress=text;stationIsPristine=false;stationProvenance=nil
    }
    mutating func applyOdometer(_ provenance:DriveLineOdometerProvenance?) {
        guard odometerIsPristine,odometerText.isEmpty,let provenance else { return }
        odometerText=provenance.valueKm.formatted(.number.grouping(.never).precision(.fractionLength(0...1)))
        odometerProvenance=provenance
    }
    mutating func applyStation(_ suggestion:FuelStationSuggestion) {
        guard stationIsPristine,stationName.isEmpty,stationAddress.isEmpty else { return }
        stationName=suggestion.stationName ?? ""
        stationAddress=suggestion.stationAddress
        stationProvenance=DriveLineStationProvenance(observedAt:suggestion.observedAt,
            sourceIdentifier:suggestion.sourceIdentifier,sourceType:.currentLocation)
    }
    mutating func clearStation() {
        stationName="";stationAddress="";stationIsPristine=false;stationProvenance=nil
    }
    mutating func prepareForLocationRefresh() {
        stationName="";stationAddress="";stationIsPristine=true;stationProvenance=nil
    }
}
