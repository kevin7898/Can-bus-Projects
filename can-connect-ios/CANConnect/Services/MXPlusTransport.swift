import Foundation
import ExternalAccessory
import Combine

// OBDLink MX+ is an MFi Bluetooth Classic accessory, not a Core Bluetooth BLE UART.
// Protocol documented by https://github.com/Cornucopia-Swift/CornucopiaStreams
@MainActor
enum MXPlusAccessory {
    static let protocolName = "com.obdlink"
    static func matches(name: String, model: String, protocols: [String]) -> Bool {
        let identity = (name + " " + model).uppercased()
        return protocols.contains(protocolName) && (identity.contains("MX+") || identity.contains("MX201"))
    }
    static var connected: [EAAccessory] {
        EAAccessoryManager.shared().connectedAccessories.filter {
            $0.isConnected && matches(name:$0.name,model:$0.modelNumber,protocols:$0.protocolStrings)
        }
    }
    static func select(serial: String?) throws -> EAAccessory {
        let accessories = connected
        if let serial, !serial.isEmpty {
            guard let match = accessories.first(where:{$0.serialNumber == serial}) else {
                throw AppFailure("The selected MX+ is unavailable. Check its power and iPhone Bluetooth pairing, then refresh the accessory list.")
            }
            return match
        }
        guard accessories.count == 1, let accessory = accessories.first else {
            throw AppFailure(accessories.isEmpty ? "No authenticated OBDLink MX+ is connected. Pair it in iPhone Settings → Bluetooth, close other OBD apps, then refresh." : "Several MX+ adapters are connected. Choose the adapter before connecting.")
        }
        return accessory
    }
}

@MainActor
final class MXPlusAccessories: ObservableObject {
    struct Item: Identifiable {
        var id: Int
        var name: String
        var serial: String
    }
    @Published private(set) var items: [Item] = []
    @Published private(set) var showingPicker = false
    @Published private(set) var pickerMessage: String?
    private var observations: [NSObjectProtocol] = []
    init() {
        EAAccessoryManager.shared().registerForLocalNotifications()
        for name in [Notification.Name.EAAccessoryDidConnect, .EAAccessoryDidDisconnect] {
            observations.append(NotificationCenter.default.addObserver(forName:name,object:nil,queue:.main) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            })
        }
        refresh()
    }
    deinit { observations.forEach(NotificationCenter.default.removeObserver) }
    func refresh() {
        items = MXPlusAccessory.connected.map { Item(id:$0.connectionID,name:$0.name,serial:$0.serialNumber) }
    }
    func showPicker() {
        guard !showingPicker else { return }
        showingPicker = true; pickerMessage = nil
        // Discovery names can differ from the authenticated accessory identity.
        // Show all compatible iAP accessories; refresh still validates MX+ and com.obdlink.
        EAAccessoryManager.shared().showBluetoothAccessoryPicker(withNameFilter:nil) { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                self.showingPicker = false; self.refresh()
                if self.items.isEmpty {
                    self.pickerMessage = error == nil ? "Waiting for MX+ authentication. Refresh in a few seconds." : "MX+ pairing did not finish. You can pair or reconnect in iPhone Settings → Bluetooth, then refresh."
                }
            }
        }
    }
}

// Thin boundary around Apple's streams permits deterministic fragmented-read,
// short-write, timeout and disconnect tests without pretending to test the adapter.
@MainActor
protocol AccessoryStreams: AnyObject {
    var onEvent: ((Stream.Event) -> Void)? { get set }
    var isOpen: Bool { get }
    var hasBytes: Bool { get }
    var hasSpace: Bool { get }
    func open()
    func read() throws -> Data
    func write(_ bytes: Data) throws -> Int
    func close()
}

@MainActor
final class MXPlusStreams: NSObject, AccessoryStreams, @preconcurrency StreamDelegate {
    var onEvent: ((Stream.Event) -> Void)?
    private var session: EASession?
    private let input: InputStream
    private let output: OutputStream
    init(accessory: EAAccessory) throws {
        guard let session = EASession(accessory:accessory,forProtocol:MXPlusAccessory.protocolName),
              let input = session.inputStream, let output = session.outputStream else {
            throw AppFailure("iOS could not open the MX+ session. Close other OBD apps and reconnect. If it persists, the app may need OBDLink manufacturer authorization.")
        }
        self.session = session; self.input = input; self.output = output
        super.init()
    }
    var isOpen: Bool { input.streamStatus == .open && output.streamStatus == .open }
    var hasBytes: Bool { input.hasBytesAvailable }
    var hasSpace: Bool { output.hasSpaceAvailable }
    func open() {
        input.delegate = self; output.delegate = self
        input.schedule(in:.main,forMode:.common); output.schedule(in:.main,forMode:.common)
        input.open(); output.open()
    }
    func read() throws -> Data {
        var bytes = [UInt8](repeating:0,count:4096)
        let count = input.read(&bytes,maxLength:bytes.count)
        guard count >= 0 else { throw input.streamError ?? AppFailure("MX+ input failed.") }
        return Data(bytes.prefix(count))
    }
    func write(_ bytes: Data) throws -> Int {
        let count = bytes.withUnsafeBytes { raw -> Int in
            guard let address = raw.bindMemory(to:UInt8.self).baseAddress else { return 0 }
            return output.write(address,maxLength:bytes.count)
        }
        guard count >= 0 else { throw output.streamError ?? AppFailure("MX+ output failed.") }
        return count
    }
    func stream(_ aStream: Stream, handle eventCode: Stream.Event) { onEvent?(eventCode) }
    func close() {
        onEvent = nil
        input.delegate = nil; output.delegate = nil
        input.close(); output.close()
        input.remove(from:.main,forMode:.common); output.remove(from:.main,forMode:.common)
        // Release iOS's protocol ownership now, before another connection starts.
        session = nil
    }
}

@MainActor
final class ELMAccessoryChannel {
    private let streams: AccessoryStreams
    private let timeoutNanoseconds: UInt64
    private let drainOnCancellation: Bool
    var reusable: Bool { ready && streams.isOpen }
    private var opening: CheckedContinuation<Void,Error>?
    private var waiting: CheckedContinuation<String,Error>?
    private var deadline: Task<Void,Never>?
    private var ready = false
    private var buffer = Data()
    private var outgoing = Data()
    private var pendingCommand = ""
    init(streams: AccessoryStreams, timeoutNanoseconds: UInt64 = 12_000_000_000, drainOnCancellation: Bool = false) {
        self.streams = streams; self.timeoutNanoseconds = timeoutNanoseconds; self.drainOnCancellation = drainOnCancellation
    }
    func open() async throws {
        try Task.checkCancellation()
        guard !ready, opening == nil else { throw AppFailure("MX+ session is already opening or open.") }
        streams.onEvent = { [weak self] event in self?.receive(event) }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                opening = continuation; armTimeout(); streams.open()
                if streams.isOpen { didOpen() }
            }
        } onCancel: { Task { @MainActor [weak self] in
            guard let self, !self.drainOnCancellation else { return }
            self.disconnect()
        } }
        try Task.checkCancellation()
    }
    func command(_ text: String) async throws -> String {
        try Task.checkCancellation()
        guard ready, waiting == nil else { throw AppFailure("MX+ connection is unavailable or a command is already pending.") }
        guard !text.isEmpty, text.count <= 16, text.allSatisfy({$0.isASCII && ($0.isLetter || $0.isNumber)}) else { throw AppFailure("Invalid scanner command.") }
        buffer.removeAll(keepingCapacity:true); pendingCommand = text
        outgoing = Data((text+"\r").utf8)
        let reply: String = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                waiting = continuation; armTimeout()
                do { try flushOutput() } catch { fail(error) }
            }
        } onCancel: { Task { @MainActor [weak self] in
            guard let self, !self.drainOnCancellation else { return }
            self.disconnect()
        } }
        // A canceled read drains through its prompt before a new request may start.
        try Task.checkCancellation()
        return reply
    }
    private func didOpen() {
        guard let pending = opening, streams.isOpen else { return }
        opening = nil; ready = true; deadline?.cancel(); pending.resume()
    }
    private func receive(_ event: Stream.Event) {
        if event.contains(.errorOccurred) || event.contains(.endEncountered) {
            fail(AppFailure("The MX+ disconnected. Check power, Bluetooth pairing and ignition, then reconnect.")); return
        }
        if event.contains(.openCompleted) { didOpen() }
        do {
            if event.contains(.hasSpaceAvailable) { try flushOutput() }
            if event.contains(.hasBytesAvailable) {
                while streams.hasBytes {
                    let data = try streams.read()
                    if data.isEmpty { break }
                    guard buffer.count + data.count <= 64_000 else { throw AppFailure("The MX+ response exceeded 64 KB.") }
                    buffer.append(data)
                    while let end = buffer.firstIndex(of:0x3E) {
                        let response = String(decoding:buffer[..<end],as:UTF8.self)
                        buffer.removeSubrange(...end)
                        guard let pending = waiting, outgoing.isEmpty else { continue }
                        let normalized = response.uppercased().replacingOccurrences(of:pendingCommand,with:"").trimmingCharacters(in:.whitespacesAndNewlines)
                        let configuration = pendingCommand.hasPrefix("AT") && !["ATI","ATDP","ATZ"].contains(pendingCommand)
                        if !normalized.isEmpty && (!configuration || ["OK","?","ERROR"].contains(where:normalized.contains)) {
                            waiting = nil; deadline?.cancel(); pending.resume(returning:response)
                        }
                    }
                }
            }
        } catch { fail(error) }
    }
    private func flushOutput() throws {
        while !outgoing.isEmpty && streams.hasSpace {
            let written = try streams.write(outgoing)
            guard written >= 0, written <= outgoing.count else { throw AppFailure("Invalid MX+ stream write.") }
            if written == 0 { break }
            outgoing.removeFirst(written)
        }
    }
    private func armTimeout() {
        deadline?.cancel()
        deadline = Task { [weak self, timeoutNanoseconds] in
            try? await Task.sleep(nanoseconds:timeoutNanoseconds)
            guard !Task.isCancelled else { return }
            guard let self else { return }
            let phase = self.opening != nil ? "opening the Bluetooth stream" : "waiting for \(self.pendingCommand)"
            self.fail(AppFailure("MX+ timed out \(phase). Check power, Bluetooth pairing and ignition, and close other OBD apps."))
        }
    }
    private func fail(_ error: Error) {
        ready = false; deadline?.cancel(); deadline = nil
        let start = opening; opening = nil
        let request = waiting; waiting = nil
        outgoing.removeAll(); buffer.removeAll(); streams.close()
        start?.resume(throwing:error); request?.resume(throwing:error)
    }
    func disconnect() { fail(CancellationError()) }
}

// MFi session ownership is separate from acquisition. Reopening the MX+ iAP data
// port immediately after cancellation can leave a paired adapter silent. Keep one
// accessory channel and drain an in-flight reply before restarting identification.
@MainActor
private enum MXPlusSharedSession {
    static var connectionID: Int?
    static var channel: ELMAccessoryChannel?
    static func acquire(_ accessory: EAAccessory) throws -> ELMAccessoryChannel {
        if connectionID == accessory.connectionID, let channel, channel.reusable { return channel }
        close()
        let streams = try MXPlusStreams(accessory:accessory)
        let created = ELMAccessoryChannel(streams:streams,drainOnCancellation:true)
        connectionID = accessory.connectionID; channel = created
        return created
    }
    static func discard(_ failed: ELMAccessoryChannel) {
        if channel === failed { close() }
    }
    static func close() {
        channel?.disconnect(); channel = nil; connectionID = nil
    }
}

@MainActor
final class ELMMXPlusSession: ScannerTransport {
    private let serial: String?
    private var channel: ELMAccessoryChannel?
    private let journal: ScannerJournal?
    private let restoreCANDefaults: Bool
    init(serial: String?, journal: ScannerJournal? = nil, restoreCANDefaults: Bool = false) {
        self.serial = serial; self.journal = journal; self.restoreCANDefaults = restoreCANDefaults
    }
    static func closeForegroundSession() { MXPlusSharedSession.close() }
    func open(host: String, port: UInt16) async throws -> ScannerIdentity {
        disconnect()
        do {
            let accessory = try MXPlusAccessory.select(serial:serial)
            let connection = try MXPlusSharedSession.acquire(accessory); channel = connection
            if !connection.reusable {
                journal?.append(command:"SESSION",reply:"Opening Bluetooth streams")
                try await connection.open()
            } else { journal?.append(command:"SESSION",reply:"Reusing Bluetooth session") }
            return try await ELMIdentification.read(restoreCANDefaults:restoreCANDefaults,command:command)
        } catch {
            journal?.append(command:"ERROR",reply:error.localizedDescription)
            if !(error is CancellationError), let channel { MXPlusSharedSession.discard(channel) }
            disconnect(); throw error
        }
    }
    func command(_ text: String) async throws -> String {
        guard let channel else { throw AppFailure("Connect the OBDLink MX+ first.") }
        do {
            let reply = try await channel.command(text)
            journal?.append(command:text,reply:reply)
            return reply
        } catch {
            if !(error is CancellationError) { MXPlusSharedSession.discard(channel) }
            throw error
        }
    }
    // Stop this acquisition while keeping the iAP channel reusable.
    // Transport errors close the underlying session; app switching preserves it.
    func disconnect() { channel = nil }
}
