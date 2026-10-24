import XCTest
import Network
@testable import CANConnect

// A loopback-only protocol fixture, never a hardware acceptance test.
final class ELMTransportTests: XCTestCase {
    @MainActor
    func testTCPIdentificationFragmentedPromptsLiveReadAndDisconnect() async throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host:"127.0.0.1",port:.any)
        let listener = try NWListener(using:parameters)
        let ready = expectation(description:"loopback ELM fixture ready")
        var received: [String] = []
        var connections: [NWConnection] = []
        listener.stateUpdateHandler = { state in if case .ready = state { ready.fulfill() } }
        listener.newConnectionHandler = { connection in
            connections.append(connection); connection.start(queue:.main)
            var buffer = ""
            func receive() {
                connection.receive(minimumIncompleteLength:1,maximumLength:4096) { data,_,complete,error in
                    if let data { buffer += String(decoding:data,as:UTF8.self) }
                    while let end = buffer.firstIndex(of:"\r") {
                        let command = String(buffer[..<end]); buffer = String(buffer[buffer.index(after:end)...]); received.append(command)
                        let response: String
                        switch command {
                        case "ATI": response = "ELM327 TEST FIXTURE\r"
                        case "ATDP": response = "ISO 15765-4 CAN\r"
                        case "0902": response = "NO DATA\r"
                        case "0100": response = "41 00 00 18 00 00\r"
                        case "010C": response = "41 0C 1A F8\r"
                        default: response = "OK\r"
                        }
                        // Send the prompt separately to exercise receive buffering across packets.
                        connection.send(content:Data(response.utf8),completion:.contentProcessed { _ in
                            connection.send(content:Data(">".utf8),completion:.contentProcessed {_ in})
                        })
                    }
                    if !complete && error == nil { receive() }
                }
            }
            receive()
        }
        listener.start(queue:.main)
        defer { listener.cancel(); connections.forEach {$0.cancel()} }
        await fulfillment(of:[ready],timeout:3)
        let session = ELMWiFiSession(); defer { session.disconnect() }
        let identity = try await session.open(host:"127.0.0.1",port:try XCTUnwrap(listener.port?.rawValue))
        XCTAssertEqual(identity.supportedPIDs,[12,13]); XCTAssertNil(identity.vin)
        let response = try await session.command("010C")
        XCTAssertEqual(OBDDecoder.decode(response,pid:12)?.signals["rpm"],1726)
        XCTAssertTrue(received.contains("ATH0")); XCTAssertTrue(received.contains("ATCAF1"))
        XCTAssertFalse(received.contains("04"))
        session.disconnect()
        do { _ = try await session.command("010C"); XCTFail("Disconnected transport accepted a command") } catch {}
    }
}
