#if DEBUG
import Foundation

/// Command-matched synthetic response model for the existing UI. Available only
/// in the isolated --ui-testing --obd-replay launch path; never auto-selected.
@MainActor
final class TelemetryReplayTransport:ScannerTransport {
    private var openState=false
    private let ignitionOnly:Bool
    init(ignitionOnly:Bool=false) { self.ignitionOnly=ignitionOnly }
    func open(host:String,port:UInt16) async throws -> ScannerIdentity {
        openState=true
        return ScannerIdentity(vin:nil,adapter:"SYNTHETIC REPLAY",vehicleProtocol:"ISO CAN",supportedPIDs:[12,13,94])
    }
    func command(_ text:String) async throws -> String {
        guard openState else { throw CancellationError() }
        try await Task.sleep(for:.milliseconds(24))
        switch text {
        case "ATDPN":return "A6"
        case "0100":return "7E8 06 41 00 00 18 00 01"
        case "0120":return "7E8 06 41 20 00 00 00 01"
        case "0140":return "7E8 06 41 40 00 00 00 04"
        case "010C":return ignitionOnly ? "7E8 04 41 0C 00 00":"7E8 04 41 0C 1A F8"
        case "010D":return ignitionOnly ? "7E8 03 41 0D 00":"7E8 03 41 0D 3C"
        case "015E":return "7E8 04 41 5E 00 64"
        case "0902":return "NO DATA"
        default:
            guard text.hasPrefix("AT") else { throw TelemetryFailure.invalidRequest }
            return "OK"
        }
    }
    func disconnect() { openState=false }
}
#endif
