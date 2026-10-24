// Compile with the core sources plus AppStore.swift, LocalServer.swift and Theme.swift.
// Arguments: RECORDING PRIVATE_LIBRARY. Never put the library or recording in Git.
import Foundation

@main struct ValidateImport {
    @MainActor static func main() async throws {
        guard CommandLine.arguments.count==3 else { throw CANError.invalid("Usage: validate-import RECORDING PRIVATE_LIBRARY") }
        let input = URL(fileURLWithPath:CommandLine.arguments[1])
        let root = URL(fileURLWithPath:CommandLine.arguments[2],isDirectory:true)
        let store = AppStore(root:root)
        guard !store.readOnly else { throw CANError.invalid(store.error ?? "Library unavailable") }
        let vehicle = store.selectedVehicle ?? Vehicle(name:"Imported recording · review vehicle")
        if store.selectedVehicle == nil { try store.saveVehicle(vehicle) }
        let receipt = try store.enqueue(input,vehicleID:vehicle.id)
        await store.processPending()
        while store.processing { try await Task.sleep(nanoseconds:100_000_000) }
        guard let processed = store.state.receipts.first(where:{$0.id==receipt.id}),processed.status == .processed else {
            throw CANError.invalid(store.state.receipts.first(where:{$0.id==receipt.id})?.message ?? "Missing receipt")
        }
        let duplicate = try store.enqueue(input,vehicleID:vehicle.id)
        guard duplicate.id==receipt.id else { throw CANError.invalid("Duplicate created a second receipt") }
        let repo = store.repository!
        guard try FilePreparation.hash(repo.originalURL(receipt))==receipt.contentHash else { throw CANError.invalid("Preserved original changed during processing") }
        let restored = try repo.load()
        let trips = restored.trips.filter { processed.tripIDs.contains($0.id) }
        guard trips.count==processed.tripIDs.count,!trips.isEmpty else { throw CANError.invalid("Trips did not survive library reload") }
        let validationRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:validationRoot,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:validationRoot) }
        let backup = try repo.backup(to:validationRoot),backupRepo = try LibraryRepository(root:backup)
        var interrupted = try backupRepo.load()
        interrupted.trips.removeAll { $0.receiptID==receipt.id }
        interrupted.receipts[interrupted.receipts.firstIndex(where:{$0.id==receipt.id})!].status = .processing
        try backupRepo.save(interrupted)
        let recovered = AppStore(root:backup)
        await recovered.processPending()
        while recovered.processing { try await Task.sleep(nanoseconds:100_000_000) }
        guard recovered.state.receipts.first(where:{$0.id==receipt.id})?.status == .processed,
              recovered.state.trips.filter({$0.receiptID==receipt.id}).count==trips.count,
              try FilePreparation.hash(backupRepo.originalURL(receipt))==receipt.contentHash else { throw CANError.invalid("Interrupted import did not recover from the backup") }
        // Public-safe diagnostics only; no filenames, VINs, timestamps, coordinates or values.
        print("Import validation passed: processed receipt, original hash, duplicate receipt, durable trips, backup and interrupted-import recovery.")
        print("Sessions: \(trips.count); diagnostic responses: \(trips.reduce(0){$0+$1.diagnosticResponseCount}); samples: \(trips.reduce(0){$0+$1.samples.count}); GPS samples: \(trips.reduce(0){$0+$1.coordinates.count}).")
        print("Available signal keys: \(Set(trips.flatMap(\.availableSignals)).map(\.rawValue).sorted().joined(separator:", "))")
    }
}
