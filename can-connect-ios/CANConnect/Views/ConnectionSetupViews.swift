import SwiftUI

struct ScannerConnectionView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var host = ""
    @State private var port = ""
    @State private var failure: String?
    var body: some View { SheetShell(title:"Wi-Fi scanner") {
        InfoNote(text:"Join your ELM327 adapter's Wi-Fi and turn on ignition. This connection records standard OBD readings for the selected vehicle. Bluetooth/MFi and raw CAN are unavailable.")
        DataRow(label:"Vehicle",value:store.activeVehicle?.title ?? "Choose a vehicle")
        InfoNote(text:"Confirm that this is the connected vehicle. If both profiles provide VINs, they must match. Without a VIN, verify the vehicle yourself before connecting.")
        TextField("Scanner address",text:$host).textInputAutocapitalization(.never).autocorrectionDisabled().textFieldStyle(.roundedBorder).accessibilityIdentifier("connection.host")
        TextField("TCP port",text:$port).keyboardType(.numberPad).textFieldStyle(.roundedBorder).accessibilityIdentifier("connection.port")
        if let failure { Text(failure).foregroundStyle(Palette.red).font(.system(size:13)) }
        InfoNote(text:store.scanner.status)
        AppButton(title:"Connect selected vehicle",icon:"antenna.radiowaves.left.and.right") {
            do {
                guard let tcp = UInt16(port) else { throw AppFailure("Enter a TCP port from 1 to 65535.") }
                try store.connectScanner(host:host,port:tcp); store.selectedTab = .live; dismiss()
            } catch { failure = error.localizedDescription }
        }.disabled(store.recording || store.pendingGPS)
        if store.scanner.connected || store.scanner.connecting {
            AppButton(title:"Disconnect scanner",secondary:true) { store.scanner.disconnect() }.disabled(store.recording)
        }
        InfoNote(text:"Keep the app visible for scanner recordings. Leaving the app saves the recording and disconnects the scanner. GPS recording can continue with the phone locked.")
    }.onAppear { host = store.activeVehicle?.scannerConnection?.host ?? store.state.scanner.host; port = String(store.activeVehicle?.scannerConnection?.port ?? store.state.scanner.port) } }
}

struct ServerConnectionView: View {
    @EnvironmentObject private var store: AppStore
    @State private var address = ""
    @State private var token = ""
    @State private var busy = false
    @State private var message: String?
    @State private var work: Task<Void,Never>?
    var body: some View { SheetShell(title:"Mac server") {
        InfoNote(text:"Start the native Mac app's Server and enable its local-network access. Use its private address and copy its pairing token. Your phone must be able to reach that network.")
        TextField("http://mac-mini.local:8765",text:$address).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL).textFieldStyle(.roundedBorder).accessibilityIdentifier("server.address")
        SecureField("Pairing token (blank keeps saved token)",text:$token).textInputAutocapitalization(.never).autocorrectionDisabled().textFieldStyle(.roundedBorder).accessibilityIdentifier("server.token")
        Text("The token is saved in this iPhone's Keychain. HTTP uses your trusted private LAN without encryption; use HTTPS if your server provides it.").captionStyle()
        if let message { InfoNote(text:message) }
        AppButton(title:busy ? "Checking…" : "Pair & test server",icon:"desktopcomputer") {
            busy = true; message = nil
            work = Task {
                defer { busy = false }
                do { try await store.configureServer(address:address,token:token); token = ""; message = store.serverStatus }
                catch is CancellationError {} catch { message = error.localizedDescription }
            }
        }.disabled(busy || store.transferring)
        InfoNote(text:"Recordings stay on this iPhone through queued, failed and completed transfers. The Mac verifies the source bytes and returns a processing receipt. Transfers can be retried from Connect → Transfers.")
    }.onAppear { address = store.state.server.address }.onDisappear { work?.cancel(); token = "" } }
}
struct TransferQueueView: View {
    @EnvironmentObject private var store: AppStore
    var body: some View { SheetShell(title:"Transfer queue") {
        if store.state.transfers.isEmpty { InfoNote(text:"No recordings queued. Sample recordings are excluded. Pair your server, then send recordings from Transfers.") }
        ForEach(store.state.transfers.reversed()) { item in
            VStack(alignment:.leading,spacing:8) {
                Text(item.name).font(.system(size:16))
                Text(item.status.rawValue == "awaitingReceipt" ? "Awaiting Mac processing" : item.status.rawValue.capitalized).foregroundStyle(item.status == .complete ? Palette.green : Palette.blue)
                Text(item.message).captionStyle()
                Text(item.endpoint).captionStyle()
            }.card()
        }
        AppButton(title:store.transferring ? "Transferring…" : "Retry / check receipts",icon:"arrow.clockwise") { Task { await store.sendQueued() } }.disabled(store.transferring)
    } }
}
