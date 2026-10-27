import Foundation

/// Display validity is not permission to integrate or fabricate observations.
public struct DriveLineAcquisitionPolicy: Equatable, Sendable {
    public static let version="driveline.acquisition.v1"
    public var requestID:String?
    public var expectedCadence:TimeInterval?
    public var displayValidity:TimeInterval
    public var signalID:String
    public var unit:String? { DriveLineJourneyPolicy.registeredSignal(signalID)?.unit }
    public var sourceKind:DriveLineSourceKind? { requestID == nil ? nil:.obd }
    public var definitionVersion:String { Self.version }
    public var integrationGap:TimeInterval { DriveLineMetricPolicy.maximumSignalGap }
    public static func signal(_ key:String)->Self {
        let groups:[(String,Double,[String])]=[
            ("0133",60,["barometricKpa"]),("0146",300,["outsideC"]),("012F",30,["fuelPercent"]),
            ("vw.engine",60,["dpfAshML","dpfSootG"]),("vw.dsg",5,["dsgFluidC"]),
            ("010C",0.5,["rpm"]),("010D",0.5,["speedKph"]),("015E",0.5,["fuelRateLph"]),
            ("0170",0.5,["boostAbsoluteKpa","boostCommandedKpa","boostBAbsoluteKpa","boostBCommandedKpa"]),
            ("0178",0.5,["egt1C","egt2C","egt3C","egt4C"]),
            ("017A",0.5,["dpfDifferentialKpa","dpfInletKpa","dpfOutletKpa"]),
            ("018B",3,["dpfRegenActive","dpfRegenType","dpfRegenTrigger","dpfAverageRegenMinutes","dpfAverageRegenKM"]),
            ("0104",0.5,["engineLoad"]),("0110",0.5,["mafGps"]),
            ("0105",3,["coolantC"]),("010B",3,["mapKpa"]),("010F",3,["intakeC"]),
            ("0142",3,["voltage"]),("015C",3,["oilC"])
        ]
        guard let group=groups.first(where:{$0.2.contains(key)}) else {
            return Self(requestID:nil,expectedCadence:nil,displayValidity:10,signalID:key)
        }
        return Self(requestID:group.0,expectedCadence:group.1,displayValidity:group.1 >= 30 ? group.1+15:10,signalID:key)
    }

    /// Union of validity windows, clipped to evidence bounds and explicit
    /// interruption boundaries. These are availability seconds, not samples.
    public static func availabilitySeconds(timestamps:[Date],key:String,start:Date,end:Date,
                                           interruptions:[Date]=[])->Double {
        let validity=signal(key).displayValidity
        let boundaries=interruptions.sorted()
        var upper=start,total=0.0
        for timestamp in timestamps.sorted() where timestamp >= start && timestamp <= end {
            let stop=boundaries.first(where:{$0 > timestamp}) ?? end
            let limit=min(end,stop,timestamp.addingTimeInterval(validity))
            let lower=max(upper,timestamp)
            if limit > lower { total += limit.timeIntervalSince(lower);upper=limit }
        }
        return total
    }
}
