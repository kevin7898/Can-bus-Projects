import Foundation

// Compiled alongside the production iOS client sources by validate_mac_transfer.py.
// All profiles, samples and credentials in this probe are synthetic.
@main struct MacTransferProbe {
    static func main() async throws {
        let address = CommandLine.arguments[1]
        let client = try MacServerClient(address:address,token:ProcessInfo.processInfo.environment["CAN_CONNECT_TEST_TOKEN"]!)
        _ = try await client.health()
        var vehicle = VehicleProfile(); vehicle.make = "Synthetic"; vehicle.model = "Transfer fixture"
        let remoteID = try await client.resolve(vehicle)
        guard try await client.resolve(vehicle) == remoteID else { fatalError("Vehicle resolution is not stable") }
        let start = Date(timeIntervalSince1970:1_792_757_200.123456)
        var draft = RecordingDraft(vehicleID:vehicle.id,source:.scanner,startedAt:start,updatedAt:start)
        for second in [0.0,1.0] { draft.accept(OBDDecoder.decode("41 0C 1A F8",pid:12,at:start.addingTimeInterval(second))!) }
        let scannerTrip = draft.trip(endedAt:start.addingTimeInterval(2))
        let gpsTrip = Trip(vehicleID:vehicle.id,name:"Synthetic GPS transfer",startedAt:start,duration:2,distanceKM:0.01,source:.phoneGPS,isSample:false,route:[RoutePoint(latitude:49.1,longitude:-123.9,timestamp:start,accuracy:5,speed:10),RoutePoint(latitude:49.1001,longitude:-123.9,timestamp:start.addingTimeInterval(1),accuracy:5,speed:10)])
        for trip in [scannerTrip,gpsTrip] {
            var item = TransferItem(tripID:trip.id,name:trip.name,endpoint:address,vehicle:vehicle,payload:try MacRecording.encode(trip))
            item.remoteVehicleID = remoteID
            let first = try await client.receipt(for:item); item.receiptID = first.id
            var processed: MacReceipt? = nil
            for _ in 0..<80 {
                let receipt = try await client.receipt(for:item)
                if receipt.status == "processed" { processed = receipt; break }
                if receipt.status == "failed" { fatalError("Mac import failed") }
                try await Task.sleep(nanoseconds:100_000_000)
            }
            guard let receipt = processed, let tripID = receipt.tripIDs.first else { fatalError("No processing acknowledgment") }
            item.receiptID = nil
            let duplicate = try await client.receipt(for:item)
            guard duplicate.id == receipt.id else { fatalError("Identical retry created a duplicate receipt") }
            let raw = try await client.request("GET",path:"v1/trips/\(tripID.uuidString)")
            let json = try JSONSerialization.jsonObject(with:raw) as! [String:Any]
            let samples = json["samples"] as! [[String:Any]]
            guard samples.count == 2 else { fatalError("Unexpected sample count") }
            if trip.source == .scanner {
                guard (samples[0]["signals"] as? [String:Double])?["rpm"] == 1726 else { fatalError("OBD value changed") }
            } else {
                guard samples[0]["latitude"] as? Double == 49.1, (samples[0]["signals"] as? [String:Double])?.isEmpty == true else { fatalError("GPS provenance changed") }
            }
        }
        print("Production iOS client → native Mac service passed: health, vehicle resolution, scanner/GPS uploads, hash-validated receipts, processing, exact-byte retry deduplication and trip retrieval.")
    }
}
