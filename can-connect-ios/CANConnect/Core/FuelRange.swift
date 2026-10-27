import Foundation

/// Fuel and speed are integrated only over intersecting, bounded observations
/// from the same ECU and clock epoch. Idle fuel is retained. No tank-level
/// deltas, trip-total extrapolation, or bridging of disconnected periods.
struct RollingFuelWindow:Equatable,Sendable {
    struct Bin:Equatable,Sendable { var km:Double;var litres:Double }
    private(set) var bins:[Bin]=[]
    var km:Double { bins.reduce(0) { $0+$1.km } }
    var litres:Double { bins.reduce(0) { $0+$1.litres } }
    var economy:Double? { km >= 1 && litres > 0 ? 100*litres/km:nil }
    mutating func append(km:Double,litres:Double) {
        guard km.isFinite,litres.isFinite,km >= 0,litres >= 0 else { return }
        if let last=bins.last,last.km+km <= 1 {
            bins[bins.count-1].km += km;bins[bins.count-1].litres += litres
        } else { bins.append(.init(km:km,litres:litres)) }
        var excess=self.km-500
        while excess > 0.0000001,!bins.isEmpty {
            if bins[0].km <= excess { excess -= bins.removeFirst().km }
            else {
                // Fractionally trim the oldest <=1 km bin, never a whole trip.
                let fraction=(bins[0].km-excess)/bins[0].km
                bins[0].km *= fraction;bins[0].litres *= fraction;excess=0
            }
        }
    }
    func appending(_ newer:Self)->Self {
        var result=self
        for bin in newer.bins { result.append(km:bin.km,litres:bin.litres) }
        return result
    }
    func range(fuel:Double?,reserve:Double)->Double? {
        guard let fuel,fuel.isFinite,fuel >= 0,reserve.isFinite,reserve >= 0,let economy else { return nil }
        return max(0,fuel-reserve)*100/economy
    }
}

struct MatchedFuelCollector {
    private struct Point { var time:Double;var value:Double;var source:String;var epoch:UUID? }
    private struct Segment {
        var a:Point;var b:Point
        func integral(_ start:Double,_ end:Double)->Double {
            let span=b.time-a.time
            let x=a.value+(b.value-a.value)*(start-a.time)/span
            let y=a.value+(b.value-a.value)*(end-a.time)/span
            return (x+y)/2*(end-start)/3600
        }
    }
    private var speed:Point?,fuel:Point?
    private var speeds:[Segment]=[],fuels:[Segment]=[]
    private(set) var window=RollingFuelWindow()
    mutating func interrupt() { speed=nil;fuel=nil;speeds=[];fuels=[] }
    mutating func accept(_ sample:OBDSample) {
        guard sample.isValid else { interrupt();return }
        for key in ["speedKph","fuelRateLph"] {
            guard let value=sample.signals[key] else { continue }
            let point=Point(time:sample.monotonicTime ?? sample.timestamp.timeIntervalSince1970,value:value,source:sample.responseHeader ?? "obd",epoch:sample.clockEpoch)
            let previous=key == "speedKph" ? speed:fuel
            guard value.isFinite,value >= 0,(key != "speedKph" || value <= DriveLineMetricPolicy.maximumPlausibleSpeedKph) else { interrupt();continue }
            if let p=previous {
                let seconds=point.time-p.time
                if seconds > 0,seconds <= 10,p.source == point.source,p.epoch == point.epoch {
                    if key == "speedKph" { speeds.append(.init(a:p,b:point)) } else { fuels.append(.init(a:p,b:point)) }
                } else { interrupt() }
            }
            if key == "speedKph" { speed=point } else { fuel=point }
            while let s=speeds.first,let f=fuels.first {
                let start=max(s.a.time,f.a.time),end=min(s.b.time,f.b.time)
                if end > start,s.a.source == f.a.source,s.a.epoch == f.a.epoch {
                    window.append(km:s.integral(start,end),litres:f.integral(start,end))
                }
                if s.b.time <= f.b.time { speeds.removeFirst() }
                if f.b.time <= s.b.time { fuels.removeFirst() }
            }
            // A missing counterpart cannot grow memory without bound.
            speeds.removeAll { point.time-$0.b.time > 10 }
            fuels.removeAll { point.time-$0.b.time > 10 }
        }
    }
}

actor FuelRangeHistory {
    static let shared=FuelRangeHistory()
    private var cached:[UUID:(Trip,RollingFuelWindow)]=[:]
    func window(trips:[Trip],vehicleID:UUID) throws -> RollingFuelWindow {
        var result=RollingFuelWindow()
        let selected=trips.filter { !$0.isSample && $0.vehicleID == vehicleID }.sorted { $0.startedAt < $1.startedAt }
        for trip in selected {
            try Task.checkCancellation()
            let window:RollingFuelWindow
            if let entry=cached[trip.id],entry.0 == trip { window=entry.1 }
            else {
                var collector=MatchedFuelCollector()
                var interruptions=(trip.acquisitionInterruptions ?? []).sorted()[...]
                for sample in (trip.samples ?? []).sorted(by:{$0.timestamp < $1.timestamp}) {
                    while let boundary=interruptions.first,boundary <= sample.timestamp { collector.interrupt();interruptions=interruptions.dropFirst() }
                    collector.accept(sample)
                }
                window=collector.window;cached[trip.id]=(trip,window)
            }
            result=result.appending(window)
        }
        let retained=Set(trips.map(\.id));cached=cached.filter { retained.contains($0.key) }
        return result
    }
}
