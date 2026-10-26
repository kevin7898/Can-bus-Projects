import XCTest
import Network
import Foundation
@testable import CANConnect

private final class LoopbackFixtureState: @unchecked Sendable {
    private let lock = NSLock()
    private var listenerError: NWError?
    private var received: [String] = []
    private var connections: [NWConnection] = []

    func record(error: NWError) { lock.withLock { listenerError = error } }
    func record(command: String) { lock.withLock { received.append(command) } }
    func add(connection: NWConnection) { lock.withLock { connections.append(connection) } }
    func error() -> NWError? { lock.withLock { listenerError } }
    func contains(_ command: String) -> Bool { lock.withLock { received.contains(command) } }
    func cancelConnections() { lock.withLock { connections.forEach { $0.cancel() } } }
}

// A loopback-only protocol fixture, never a hardware acceptance test.
final class ELMTransportTests: XCTestCase {
    @MainActor
    func testTCPIdentificationFragmentedPromptsLiveReadAndDisconnect() async throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host:"127.0.0.1",port:.any)
        let listener = try NWListener(using:parameters)
        let ready = expectation(description:"loopback ELM fixture ready")
        let fixture = LoopbackFixtureState()
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready: ready.fulfill()
            case .failed(let error): fixture.record(error:error); ready.fulfill()
            default: break
            }
        }
        listener.newConnectionHandler = { connection in
            fixture.add(connection:connection); connection.start(queue:.main)
            var buffer = ""
            func receive() {
                connection.receive(minimumIncompleteLength:1,maximumLength:4096) { data,_,complete,error in
                    if let data { buffer += String(decoding:data,as:UTF8.self) }
                    while let end = buffer.firstIndex(of:"\r") {
                        let command = String(buffer[..<end]); buffer = String(buffer[buffer.index(after:end)...]); fixture.record(command:command)
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
        defer { listener.cancel(); fixture.cancelConnections() }
        // A cold hosted simulator can take longer than three seconds to bind.
        // Keep the real TCP exchange mandatory and surface listener failures directly.
        await fulfillment(of:[ready],timeout:15)
        if let listenerError=fixture.error() { throw listenerError }
        let session = ELMWiFiSession(); defer { session.disconnect() }
        let identity = try await session.open(host:"127.0.0.1",port:try XCTUnwrap(listener.port?.rawValue))
        XCTAssertEqual(identity.supportedPIDs,[12,13]); XCTAssertNil(identity.vin)
        let response = try await session.command("010C")
        XCTAssertEqual(OBDDecoder.decode(response,pid:12)?.signals["rpm"],1726)
        XCTAssertTrue(fixture.contains("ATH0")); XCTAssertTrue(fixture.contains("ATCAF1"))
        XCTAssertFalse(fixture.contains("04"))
        session.disconnect()
        do { _ = try await session.command("010C"); XCTFail("Disconnected transport accepted a command") } catch {}
    }
}
