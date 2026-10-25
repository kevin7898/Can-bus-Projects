import SwiftUI

struct VehicleSetupView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var profile: VehicleProfile
    @State private var page: Int
    @State private var vin: String
    @State private var year = ""
    @State private var odometer = ""
    @State private var tank = ""
    @State private var host = ""
    @State private var port = ""
    @State private var wifi = false
    @State private var lookup = false
    @State private var busy = false
    @State private var message: String?
    @State private var failure: String?
    @State private var work: Task<Void,Never>?
    @State private var scanner = ELMWiFiSession()
    @FocusState private var focusedField: String?
    init(existing: VehicleProfile? = nil) {
        let vehicle = existing ?? VehicleProfile()
        _profile = State(initialValue:vehicle); _page = State(initialValue:existing == nil ? 0 : 1)
        _vin = State(initialValue:vehicle.vin ?? "")
        _year = State(initialValue:vehicle.year.map(String.init) ?? "")
        _odometer = State(initialValue:vehicle.odometerKM.map {$0.text(0)} ?? "")
        _tank = State(initialValue:vehicle.tankLitres.map {$0.text()} ?? "")
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:19) {
                    Eyebrow(text:page == 0 ? "Your garage starts here" : "Review your vehicle")
                    Text(page == 0 ? "Make it your vehicle." : profile.title == "Vehicle" ? "A few details, then you're ready." : profile.title).font(.system(size:28))
                    Text(page == 0 ? "Cars, trucks and motorcycles. Each gets its own recordings, fuel log and dashboard." : "Check the suggested details and add anything the scanner or VIN could not tell us.").font(.system(size:13)).foregroundStyle(Palette.muted)
                    PageControl(labels:["Identify","Review & save"],selection:$page).disabled(busy)
                    if page == 0 { identification.disabled(busy) } else { review.disabled(busy) }
                    if let message { InfoNote(text:message,icon:"checkmark.circle") }
                    if let failure { Text(failure).font(.system(size:12)).foregroundStyle(Palette.red).fixedSize(horizontal:false,vertical:true) }
                    if busy { HStack { ProgressView(); Text("Reading vehicle details…").captionStyle(); Spacer(); Button("Cancel") { cancel() } }.padding(.vertical,10) }
                }.padding(20)
            }.accessibilityIdentifier("onboarding.form").scrollDismissesKeyboard(.immediately).background(Palette.background).foregroundStyle(Palette.text)
                .navigationTitle("Vehicle setup").navigationBarTitleDisplayMode(.inline)
                .toolbar { if store.state.onboardingCompleted { ToolbarItem(placement:.topBarTrailing) { Button("Cancel") { cancel(); dismiss() } } } }
                .toolbarBackground(Palette.surface,for:.navigationBar).toolbarBackground(.visible,for:.navigationBar)
        }.tint(Palette.blue)
            .interactiveDismissDisabled(!store.state.onboardingCompleted || busy)
            .onDisappear { cancel() }
            .onChange(of:page) { _,_ in focusedField = nil }
    }
    private var identification: some View {
        VStack(alignment:.leading,spacing:15) {
            Button { wifi.toggle(); failure = nil } label: { choice("Read from a scanner",detail:"Wi-Fi ELM327 · VIN, protocol and supported PIDs",icon:"cpu") }.buttonStyle(.plain).accessibilityIdentifier("onboarding.scanner")
            if wifi {
                InfoNote(text:"Join the adapter's Wi-Fi and turn the ignition on. Enter its address and port. For OBDLink MX+, enter your vehicle manually, then choose Bluetooth in Connect → CAN recorder.")
                field("Scanner address",placeholder:"e.g. 192.168.0.10",text:$host,key:"scanner.host")
                field("TCP port",placeholder:"From adapter instructions",text:$port,key:"scanner.port",keyboard:.numberPad)
                Toggle("Look up VIN details with NHTSA",isOn:$lookup).font(.system(size:13))
                Text("When enabled, the detected VIN is sent to NHTSA to suggest vehicle details. Review them before saving.").captionStyle()
                AppButton(title:"Read connected vehicle",icon:"magnifyingglass") { readScanner() }.disabled(busy)
            }
            VStack(alignment:.leading,spacing:12) {
                Label("Have the VIN?",systemImage:"number").font(.system(size:15))
                field("VIN · optional",placeholder:"17 characters",text:$vin,key:"vehicle.vin")
                AppButton(title:"Look up VIN",icon:"magnifyingglass",secondary:true) { lookupVIN() }.disabled(busy || vin.isEmpty)
                Text("VIN is shared with NHTSA only when you choose lookup. You can also enter details offline.").captionStyle()
            }.card()
            AppButton(title:"Enter vehicle manually",icon:"square.and.pencil",secondary:true) { page = 1; failure = nil }.disabled(busy).accessibilityIdentifier("onboarding.manual")
            if !store.state.onboardingCompleted { Button("Try the sample dashboard") { do { try store.useSampleVehicle(); dismiss() } catch { failure = error.localizedDescription } }.font(.system(size:13)).frame(maxWidth:.infinity).padding(.top,6) }
        }
    }
    private var review: some View {
        VStack(alignment:.leading,spacing:16) {
            Picker("Vehicle type",selection:$profile.kind) { ForEach(VehicleKind.allCases) { Text($0.title).tag($0) } }.pickerStyle(.menu)
            field("Nickname · optional",placeholder:"My vehicle",text:$profile.nickname,key:"vehicle.nickname")
            HStack(alignment:.top,spacing:12) { field("Year · optional",placeholder:"Year",text:$year,key:"vehicle.year",keyboard:.numberPad); field("Make",placeholder:"Manufacturer",text:$profile.make,key:"vehicle.make") }
            field("Model",placeholder:"Vehicle model",text:$profile.model,key:"vehicle.model")
            field("Trim · optional",placeholder:"Trim",text:$profile.trim,key:"vehicle.trim")
            field("Engine · optional",placeholder:"Engine or motor",text:$profile.engine,key:"vehicle.engine")
            field("Transmission · optional",placeholder:"Transmission",text:$profile.transmission,key:"vehicle.transmission")
            Picker("Fuel / power",selection:$profile.fuel) { ForEach(FuelKind.allCases) { Text($0.title).tag($0) } }.pickerStyle(.menu)
            field("VIN · optional",placeholder:"17 characters",text:$vin,key:"vehicle.reviewVIN")
            HStack(alignment:.top,spacing:12) { field("Odometer · km",placeholder:"Optional",text:$odometer,key:"vehicle.odometer",keyboard:.decimalPad); field("Tank size · L",placeholder:"Optional",text:$tank,key:"vehicle.tank",keyboard:.decimalPad) }
            InfoNote(text:"Odometer and tank size often need manual entry. Unknown values stay unavailable.")
            if let protocolName = profile.scannerProtocol, !protocolName.isEmpty { DataRow(label:"Detected protocol",value:protocolName) }
            if !profile.supportedPIDs.isEmpty { InfoNote(text:"\(profile.supportedPIDs.count) standard OBD PIDs confirmed. Make-specific signals such as DPF data still need compatible decoders.",icon:"checkmark.circle") }
            if let existing = existingVIN {
                AppButton(title:"Use existing vehicle: \(existing.title)",icon:existing.kind.icon) { do { try store.chooseVehicle(existing.id); dismiss() } catch { failure = error.localizedDescription } }
            } else {
                AppButton(title:"Save vehicle",icon:"checkmark") { save() }.disabled(busy).accessibilityIdentifier("onboarding.save")
            }
        }
    }
    private var existingVIN: VehicleProfile? { guard let normalized = try? VIN.normalized(vin) else { return nil }; return store.state.vehicles.first {$0.id != profile.id && $0.vin == normalized} }
    private func choice(_ title: String, detail: String, icon: String) -> some View { HStack(spacing:13) { Image(systemName:icon).font(.system(size:25)).foregroundStyle(Palette.blue); VStack(alignment:.leading,spacing:6) { Text(title).font(.system(size:16)); Text(detail).captionStyle() }; Spacer(); Image(systemName:"chevron.right").font(.system(size:11)).foregroundStyle(Palette.muted) }.foregroundStyle(Palette.text).card() }
    private func field(_ title: String, placeholder: String, text: Binding<String>, key: String, keyboard: UIKeyboardType = .default) -> some View {
        VStack(alignment:.leading,spacing:7) { Text(title).captionStyle(); TextField(placeholder,text:text).keyboardType(keyboard).textInputAutocapitalization(key.contains("VIN") || key == "vehicle.vin" ? .characters : .words).autocorrectionDisabled().submitLabel(.done).onSubmit { focusedField = nil }.focused($focusedField,equals:key).padding(12).font(.system(size:15)).background(Palette.surface,in:RoundedRectangle(cornerRadius:10)).accessibilityIdentifier(key) }
    }
    private func apply(_ suggested: VehicleProfile) {
        profile.make = suggested.make; profile.model = suggested.model; profile.trim = suggested.trim; profile.engine = suggested.engine; profile.transmission = suggested.transmission; profile.kind = suggested.kind; profile.fuel = suggested.fuel
        profile.year = suggested.year; year = suggested.year.map(String.init) ?? ""; profile.identificationSource = suggested.identificationSource
    }
    private func lookupVIN() {
        failure = nil; message = nil
        guard (try? VIN.normalized(vin)) != nil else { failure = "Enter a standard 17-character VIN, or continue manually."; return }
        busy = true
        let inputVIN = vin
        work = Task { @MainActor in
            defer { busy = false }
            do { let result = try await VINLookup().decode(inputVIN); try Task.checkCancellation(); vin = result.vehicle.vin ?? inputVIN; apply(result.vehicle); message = result.partial ? "Partial VIN match. Review and complete the details." : "VIN details found. Review before saving."; page = 1 }
            catch is CancellationError {} catch { failure = "VIN lookup did not finish. Your entries are kept; continue manually. \(error.localizedDescription)" }
        }
    }
    private func readScanner() {
        guard let tcpPort = UInt16(port), tcpPort > 0 else { failure = "Enter the adapter's TCP port."; return }
        failure = nil; message = nil; busy = true
        let address = host.trimmingCharacters(in:.whitespacesAndNewlines)
        let session = ELMWiFiSession(); scanner = session
        work = Task { @MainActor in
            defer { busy = false }
            do {
                let identity = try await session.identify(host:address,port:tcpPort); try Task.checkCancellation()
                profile.scannerConnection = ScannerSettings(host:address,port:tcpPort)
                profile.scannerProtocol = identity.vehicleProtocol; profile.supportedPIDs = identity.supportedPIDs; profile.identificationSource = "Scanner identification · \(identity.adapter)"
                if let detected = identity.vin {
                    vin = detected
                    if lookup {
                        do { let result = try await VINLookup().decode(detected); try Task.checkCancellation(); apply(result.vehicle); profile.identificationSource = "Scanner VIN + NHTSA suggestions" }
                        catch is CancellationError { return }
                        catch { message = "VIN read successfully. Online lookup was unavailable; complete the details manually." }
                    } else { message = "VIN read successfully. Review your vehicle details." }
                } else { message = "Vehicle responded, but no VIN was available. Complete the details manually." }
                page = 1
            } catch is CancellationError {} catch { failure = error.localizedDescription }
        }
    }
    private func save() {
        focusedField = nil
        do {
            if !year.isEmpty && Int(year) == nil { throw AppFailure("Check the model year.") }
            profile.year = Int(year); profile.vin = vin.isEmpty ? nil : vin
            func number(_ text: String) throws -> Double? { if text.isEmpty { return nil }; guard let n = Double(text.replacingOccurrences(of:",",with:".")) else { throw AppFailure("Check odometer and tank size.") }; return n }
            profile.odometerKM = try number(odometer); profile.tankLitres = try number(tank)
            profile.isSample = false
            if profile.identificationSource == "Bundled sample" { profile.identificationSource = "Manual entry" }
            try store.saveVehicle(profile); dismiss()
        } catch { failure = error.localizedDescription }
    }
    private func cancel() { focusedField = nil; work?.cancel(); work = nil; scanner.disconnect(); busy = false }
}
struct GarageView: View {
    var body: some View { SheetShell(title:"Your vehicles") { GarageDestinationView() } }
}
struct GarageDestinationView: View {
    @EnvironmentObject private var store: AppStore
    @State private var adding = false
    @State private var editing: VehicleProfile?
    @State private var fuelLedger=false
    var body: some View { ScrollView {
        VStack(alignment:.leading,spacing:14) {
        AppButton(title:"Open Fuel Ledger",icon:"fuelpump") { fuelLedger=true }.accessibilityIdentifier("garage.fuel-ledger")
        ForEach(store.state.vehicles) { vehicle in VStack(alignment:.leading,spacing:13) {
            HStack(spacing:12) { Image(systemName:vehicle.kind.icon).foregroundStyle(Palette.blue); VStack(alignment:.leading,spacing:4) { Text(vehicle.title).font(.system(size:16)); Text(vehicle.detail.isEmpty ? vehicle.identificationSource : vehicle.detail).captionStyle() }; Spacer(); if store.state.selectedVehicleID == vehicle.id { Image(systemName:"checkmark.circle.fill").foregroundStyle(Palette.blue) } }
            HStack { Button("Use vehicle") { do { try store.chooseVehicle(vehicle.id) } catch { store.error = error.localizedDescription } }
                    .disabled(store.recording || store.pendingGPS)
                    .accessibilityIdentifier(vehicle.isSample ? "garage.select.sample" : "garage.select.\(vehicle.id.uuidString)")
                    .accessibilityValue(store.state.selectedVehicleID == vehicle.id ? "Selected" : "Not selected")
                Spacer(); Button("Edit details") { editing = vehicle }.disabled(store.recording || store.pendingGPS) }.font(.system(size:12))
        }.card() }
        AppButton(title:"Add a vehicle",icon:"plus") { adding = true }.disabled(store.recording || store.pendingGPS)
        InfoNote(text:"Finish a recording before switching vehicles. Trips, fills and dashboard choices stay with the vehicle they belong to.")
        }.padding(.vertical,4)
    }.sheet(isPresented:$adding) { VehicleSetupView() }.sheet(item:$editing) { VehicleSetupView(existing:$0) }
        .sheet(isPresented:$fuelLedger) { FuelLedgerView() } }
}
