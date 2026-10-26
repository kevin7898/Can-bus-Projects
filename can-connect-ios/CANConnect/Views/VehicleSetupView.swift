import SwiftUI

private struct LegacyVehicleSetupView: View {
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
                Toggle("Validate detected VIN locally",isOn:$lookup).font(.system(size:13))
                Text("DriveLine keeps the VIN on this device and never sends it to a cloud decoder.").captionStyle()
                AppButton(title:"Read connected vehicle",icon:"magnifyingglass") { readScanner() }.disabled(busy)
            }
            VStack(alignment:.leading,spacing:12) {
                Label("Have the VIN?",systemImage:"number").font(.system(size:15))
                field("VIN · optional",placeholder:"17 characters",text:$vin,key:"vehicle.vin")
                AppButton(title:"Validate VIN locally",icon:"checkmark.shield",secondary:true) { lookupVIN() }.disabled(busy || vin.isEmpty)
                Text("Local validation can suggest only a confidently recognized manufacturer and an unambiguous model-year cycle.").captionStyle()
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
            do { let result = try DriveLineVINDecoder.decode(inputVIN,enteredModelYear:Int(year));try Task.checkCancellation();vin=result.normalizedVIN;message="VIN validated locally. Review any suggestions in the current onboarding flow.";page=1 }
            catch is CancellationError {} catch { failure = "VIN validation did not finish. Your entries are kept; continue manually. \(error.localizedDescription)" }
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
                        do { _ = try DriveLineVINDecoder.decode(detected,enteredModelYear:Int(year));try Task.checkCancellation();message="VIN read and validated locally. Review your vehicle details." }
                        catch is CancellationError { return }
                        catch { message = "VIN read successfully, but local validation failed; complete the details manually." }
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
struct VehicleSetupView: View {
    @EnvironmentObject private var store:AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var profile:VehicleProfile
    @State private var stage=0
    @State private var year=""
    @State private var vin=""
    @State private var odometer=""
    @State private var tank=""
    @State private var scannerKind:ScannerConnectionKind = .wifi
    @State private var host=""
    @State private var port="35000"
    @State private var detected:DriveLineVINResult?
    @State private var identity:ScannerIdentity?
    @State private var busy=false
    @State private var failure:String?
    @State private var message:String?
    @State private var work:Task<Void,Never>?
    @State private var scannerSource=true
    @State private var gpsSource=true
    @State private var importSource=true
    private let originalID:UUID

    init(existing:VehicleProfile?=nil) {
        var fixture=VehicleProfile()
        #if DEBUG
        if existing == nil,ProcessInfo.processInfo.arguments.contains("--phase7-onboarding") {
            fixture.nickname="Fictional Jetta";fixture.year=2013;fixture.make="Volkswagen";fixture.model="Jetta";fixture.engine="TDI";fixture.fuel = .diesel
        }
        #endif
        let vehicle=existing ?? fixture
        _profile=State(initialValue:vehicle);originalID=vehicle.id
        _year=State(initialValue:vehicle.year.map(String.init) ?? "")
        _vin=State(initialValue:vehicle.vin ?? "")
        _odometer=State(initialValue:vehicle.odometerKM.map{$0.text(0)} ?? "")
        _tank=State(initialValue:vehicle.tankLitres.map{$0.text()} ?? "")
        let settings=vehicle.scannerConnection
        _scannerKind=State(initialValue:settings?.kind ?? .wifi)
        _host=State(initialValue:settings?.host ?? "")
        _port=State(initialValue:String(settings?.port ?? 35000))
        _scannerSource=State(initialValue:vehicle.configuredSources.contains(.obdScanner) || existing == nil)
        _gpsSource=State(initialValue:vehicle.configuredSources.contains(.phoneGPS) || existing == nil)
        _importSource=State(initialValue:vehicle.configuredSources.contains(.importedArchive) || existing == nil)
        #if DEBUG
        let arguments=ProcessInfo.processInfo.arguments
        if arguments.contains("--phase7-scanner") { _stage=State(initialValue:1) }
        if arguments.contains("--phase7-identify-success"),let evidence=try? DriveLineVINDecoder.decode("3VWAAAAA0EM000001",enteredModelYear:2013,currentYear:2026) {
            _stage=State(initialValue:2);_vin=State(initialValue:evidence.normalizedVIN);_detected=State(initialValue:evidence)
            _identity=State(initialValue:ScannerIdentity(vin:evidence.normalizedVIN,adapter:"SANITIZED FIXTURE",vehicleProtocol:"ISO 15765-4 CAN",supportedPIDs:[12,13],respondingAddress:"7E8",observedAt:Date(timeIntervalSince1970:1_700_000_000)))
        }
        if arguments.contains("--phase7-identify-failure") { _stage=State(initialValue:2);_failure=State(initialValue:"The scanner returned a partial Mode 09 VIN. The manual 2013 draft is unchanged; retry or continue manually.") }
        if arguments.contains("--phase7-finish") { _stage=State(initialValue:3);_scannerSource=State(initialValue:false) }
        #endif
    }

    var body:some View {
        NavigationStack {
            ScrollView { VStack(alignment:.leading,spacing:18) {
                Eyebrow(text:"Stage \(stage+1) of 4")
                Text(["Vehicle","Scanner","Identify","Finish"][stage]).font(.system(size:28))
                Text(stageCopy).font(.system(size:13)).foregroundStyle(Palette.muted)
                PageControl(labels:["Vehicle","Scanner","Identify","Finish"],selection:$stage).disabled(busy)
                Group { switch stage { case 0:vehicleStage;case 1:scannerStage;case 2:identifyStage;default:finishStage } }
                if let message { InfoNote(text:message,icon:"checkmark.circle") }
                if let failure { Text(failure).font(.system(size:12)).foregroundStyle(Palette.red).fixedSize(horizontal:false,vertical:true) }
                HStack {
                    if stage>0 { Button("Back") { stage-=1;failure=nil } .disabled(busy) }
                    Spacer()
                    if stage<3 { AppButton(title:"Continue",icon:"chevron.right") { continueStage() }.disabled(busy) }
                    else { AppButton(title:"Save vehicle",icon:"checkmark") { save() }.disabled(busy).accessibilityIdentifier("onboarding.save") }
                }
            }.padding(20) }
            .accessibilityIdentifier("onboarding.form")
            .background(Palette.background).foregroundStyle(Palette.text)
            .navigationTitle("Vehicle onboarding").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement:.topBarTrailing) { Button("Cancel") { cancel();dismiss() }.disabled(busy) } }
        }.tint(Palette.blue).interactiveDismissDisabled(busy)
            .onDisappear { cancel() }
    }
    private var stageCopy:String { switch stage {
        case 0:return "Enter what you know. Unknown values stay unavailable and can be completed later."
        case 1:return "Choose sources for this vehicle. Scanner settings stay with this stable vehicle profile."
        case 2:return "Use the existing read-only Mode 09 VIN request, then review every local suggestion before it changes your draft."
        default:return "Confirm ownership, sources, and identity evidence. Saving keeps the same vehicle UUID."
    } }
    private var vehicleStage:some View { VStack(alignment:.leading,spacing:14) {
        AppButton(title:"Enter vehicle manually",icon:"square.and.pencil",secondary:true) { scannerSource=false;failure=nil }.accessibilityIdentifier("onboarding.manual")
        Picker("Vehicle class",selection:$profile.kind) { ForEach(VehicleKind.allCases) { Text($0.title).tag($0) } }.pickerStyle(.menu)
        field("Nickname · optional","My vehicle",$profile.nickname,"vehicle.nickname")
        HStack(alignment:.top,spacing:12) { field("Model year · optional","2013",$year,"vehicle.year",.numberPad);field("Manufacturer","Volkswagen",$profile.make,"vehicle.make") }
        field("Model","Jetta",$profile.model,"vehicle.model")
        field("Trim · optional","Unknown",$profile.trim,"vehicle.trim")
        field("Engine · optional","Unknown",$profile.engine,"vehicle.engine")
        field("Transmission · optional","Unknown",$profile.transmission,"vehicle.transmission")
        Picker("Fuel / power",selection:$profile.fuel) { ForEach(FuelKind.allCases) { Text($0.title).tag($0) } }.pickerStyle(.menu)
        Picker("Preferred units",selection:$profile.preferredUnits) { Text("Metric").tag(DriveLineUnitSystem.metric);Text("US customary").tag(DriveLineUnitSystem.usCustomary);Text("Imperial").tag(DriveLineUnitSystem.imperial) }.pickerStyle(.menu)
        HStack(alignment:.top,spacing:12) { field("Odometer · km","Optional",$odometer,"vehicle.odometer",.decimalPad);field("Tank · L","Optional",$tank,"vehicle.tank",.decimalPad) }
    } }
    private var scannerStage:some View { VStack(alignment:.leading,spacing:14) {
        Toggle("iPhone GPS",isOn:$gpsSource).accessibilityIdentifier("onboarding.source.gps")
        Toggle("OBD scanner",isOn:$scannerSource).accessibilityIdentifier("onboarding.source.scanner")
        Toggle("Imported recordings",isOn:$importSource).accessibilityIdentifier("onboarding.source.import")
        if scannerSource {
            Picker("Scanner transport",selection:$scannerKind) { ForEach(ScannerConnectionKind.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented)
            if scannerKind == .wifi {
                field("Local scanner address","192.168.x.x",$host,"scanner.host")
                field("TCP port","35000",$port,"scanner.port",.numberPad)
            } else { InfoNote(text:"DriveLine uses the already paired OBDLink MX+ accessory. Pairing credentials and adapter serials never appear in exported evidence.") }
        }
        Picker("Preferred GPS",selection:$profile.preferredGPS) { Text("Automatic").tag(DriveLineGPSPreference.automatic);Text("iPhone").tag(DriveLineGPSPreference.phone);Text("Imported").tag(DriveLineGPSPreference.imported);Text("Unavailable").tag(DriveLineGPSPreference.unavailable) }.pickerStyle(.menu)
        DataRow(label:"External CAN recorder",value:"Planned · unavailable")
        DataRow(label:"USB / generic BLE scanner",value:"Unavailable")
        DataRow(label:"External GPS",value:"Planned · unavailable")
    } }
    private var identifyStage:some View { VStack(alignment:.leading,spacing:14) {
        field("VIN · optional","17 characters",$vin,"vehicle.vin")
        if scannerSource { AppButton(title:busy ? "Reading VIN…":"Read VIN from scanner",icon:"cpu") { readScanner() }.disabled(busy).accessibilityIdentifier("onboarding.identify.scanner") }
        AppButton(title:"Validate VIN locally",icon:"checkmark.shield",secondary:true) { validateVIN() }.disabled(vin.isEmpty || busy).accessibilityIdentifier("onboarding.identify.local")
        if let detected {
            InfoNote(text:"A complete 17-character VIN was received and validated locally. It stays on this device; screenshots and exported evidence must omit it.",icon:"lock.shield")
            if let suggested=detected.suggestedModelYear {
                VStack(alignment:.leading,spacing:8) {
                    Text("Model-year suggestion").captionStyle()
                    Text("Entered: \(year.isEmpty ? "Unavailable":year)   ·   Detected: \(String(suggested))").font(.system(size:15))
                    HStack { Button("Accept \(String(suggested))") { year=String(suggested);profile.year=suggested;message="Detected model year accepted explicitly." }.accessibilityIdentifier("onboarding.year.accept");Button("Keep \(year.isEmpty ? "entered value":year)") { message="Entered model year retained." }.accessibilityIdentifier("onboarding.year.retain") }
                }.card()
            } else if detected.modelYearIsAmbiguous { InfoNote(text:"VIN model-year code matches multiple 30-year cycles (\(detected.candidateModelYears.map(String.init).joined(separator:", "))). No year was suggested.",icon:"questionmark.circle") }
            if let manufacturer=detected.manufacturer {
                HStack { VStack(alignment:.leading) { Text("Detected manufacturer").captionStyle();Text(manufacturer) };Spacer();Button("Use suggestion") { profile.make=manufacturer } }.card()
            } else { DataRow(label:"Manufacturer",value:"Unavailable · unknown WMI") }
            if let identity {
                DataRow(label:"VIN source",value:"Scanner · Mode 09")
                DataRow(label:"Responding ECU",value:identity.respondingAddress ?? "Unavailable from adapter")
                DataRow(label:"Protocol",value:identity.vehicleProtocol)
                DataRow(label:"Observed",value:identity.observedAt.formatted(date:.abbreviated,time:.standard))
            }
        } else { InfoNote(text:"No VIN evidence has been applied. You can continue with a fully manual profile.") }
    } }
    private var finishStage:some View { VStack(alignment:.leading,spacing:12) {
        SectionCard(title:profile.title,icon:profile.kind.icon) {
            VStack(alignment:.leading,spacing:9) {
                DataRow(label:"Vehicle UUID",value:String(originalID.uuidString.prefix(8))+"…")
                DataRow(label:"Details",value:[year,profile.make,profile.model].filter{!$0.isEmpty}.joined(separator:" "))
                DataRow(label:"Class",value:profile.kind.title)
                DataRow(label:"VIN",value:detected == nil && vin.isEmpty ? "Unavailable":"Stored locally · hidden")
                DataRow(label:"Sources",value:sourceTitles.joined(separator:" · "))
                DataRow(label:"Scanner",value:scannerSource ? scannerKind.title:"Not configured")
                DataRow(label:"Preferred GPS",value:profile.preferredGPS == .phone ? "iPhone":profile.preferredGPS == .imported ? "Imported":profile.preferredGPS == .unavailable ? "Unavailable":"Automatic")
                DataRow(label:"Units",value:profile.preferredUnits == .metric ? "Metric":profile.preferredUnits == .usCustomary ? "US customary":"Imperial")
                DataRow(label:"Transfer",value:store.state.server.address.isEmpty ? "Destination unavailable":"Existing paired Mac destination")
                DataRow(label:"Available now",value:"Manual profile · \(gpsSource ? "GPS · ":"")imports")
                DataRow(label:"Requires configuration",value:scannerSource ? "Scanner validation before recording":"Scanner unavailable")
            }
        }
        InfoNote(text:"Drives, fills, signals, receipts and queued transfers remain owned by this stable vehicle UUID. Cancelling does not change the saved Garage.")
    } }
    private var sourceTitles:[String] { ([DriveLineVehicleSource.manual]+(gpsSource ? [.phoneGPS]:[])+(scannerSource ? [.obdScanner]:[])+(importSource ? [.importedArchive]:[])).map { switch $0 { case .manual:return "Manual";case .phoneGPS:return "GPS";case .obdScanner:return "Scanner";case .importedArchive:return "Imports" } } }
    private func field(_ title:String,_ placeholder:String,_ text:Binding<String>,_ id:String,_ keyboard:UIKeyboardType = .default)->some View {
        VStack(alignment:.leading,spacing:7) { Text(title).captionStyle();TextField(placeholder,text:text).keyboardType(keyboard).textInputAutocapitalization(id.contains("vin") ? .characters:.words).autocorrectionDisabled().padding(12).background(Palette.surface,in:RoundedRectangle(cornerRadius:10)).accessibilityIdentifier(id) }
    }
    private func continueStage() {
        failure=nil
        do {
            if stage==0 { try applyDraftValues(requireIdentity:true) }
            if stage==1 { try prepareScannerSettings() }
            stage=min(3,stage+1)
        } catch { failure=error.localizedDescription }
    }
    private func applyDraftValues(requireIdentity:Bool) throws {
        if !year.isEmpty,Int(year)==nil { throw AppFailure("Check the model year.") }
        profile.year=Int(year)
        func number(_ text:String)throws->Double? { if text.isEmpty{return nil};guard let value=Double(text.replacingOccurrences(of:",",with:".")) else { throw AppFailure("Check odometer and tank size.") };return value }
        profile.odometerKM=try number(odometer);profile.tankLitres=try number(tank)
        _=try profile.validated(requireIdentity:requireIdentity)
    }
    private func prepareScannerSettings() throws {
        profile.configuredSources=[.manual]+(gpsSource ? [.phoneGPS]:[])+(scannerSource ? [.obdScanner]:[])+(importSource ? [.importedArchive]:[])
        guard scannerSource else { profile.scannerConnection=nil;return }
        if scannerKind == .wifi {
            guard let value=UInt16(port),value>0,ELMWiFiSession.isLocalHost(host) else { throw AppFailure("Enter the scanner's private local address and valid TCP port.") }
            profile.scannerConnection=ScannerSettings(host:host.trimmingCharacters(in:.whitespacesAndNewlines),port:value,transport:.wifi)
        } else {
            let existing = profile.scannerConnection?.kind == .obdLinkMXPlus ? profile.scannerConnection : (store.state.scanner.kind == .obdLinkMXPlus ? store.state.scanner:nil)
            guard let existing,existing.accessorySerial?.isEmpty == false else { throw AppFailure("Pair the OBDLink MX+ in More → Connections, then return to onboarding.") }
            profile.scannerConnection=existing
        }
    }
    private func validateVIN() {
        failure=nil
        do { detected=try DriveLineVINDecoder.decode(vin,enteredModelYear:Int(year));vin=detected!.normalizedVIN;message="VIN validated locally. Review suggestions before continuing." }
        catch { detected=nil;failure=error.localizedDescription }
    }
    private func readScanner() {
        failure=nil;message=nil
        do { try prepareScannerSettings() } catch { failure=error.localizedDescription;return }
        guard let settings=profile.scannerConnection else { return }
        busy=true
        work=Task { @MainActor in
            defer { busy=false }
            do {
                let result=try await store.scanner.identify(settings:settings);try Task.checkCancellation()
                identity=result;profile.scannerProtocol=result.vehicleProtocol;profile.supportedPIDs=result.supportedPIDs
                profile.identification=DriveLineVehicleIdentityObservation(source:"Read-only Mode 09 VIN",respondingAddress:result.respondingAddress,protocolName:result.vehicleProtocol,observedAt:result.observedAt)
                profile.identificationSource="Scanner Mode 09 · locally reviewed"
                guard let value=result.vin else { detected=nil;message="The vehicle responded, but no complete VIN was available. Keep the manual draft.";return }
                vin=value;validateVIN()
            } catch is CancellationError {} catch { failure=error.localizedDescription }
        }
    }
    private func save() {
        failure=nil
        do {
            try applyDraftValues(requireIdentity:true);try prepareScannerSettings()
            profile.id=originalID;profile.vin=vin.isEmpty ? nil:try VIN.normalized(vin);profile.isSample=false
            try store.saveVehicle(profile);dismiss()
        } catch { failure=error.localizedDescription }
    }
    private func cancel() { work?.cancel();work=nil;store.scanner.disconnect();busy=false }
}
struct GarageView: View {
    var body: some View { SheetShell(title:"Your vehicles") { GarageDestinationView() } }
}
struct GarageDestinationView: View {
    @EnvironmentObject private var store: AppStore
    @State private var adding = false
    @State private var editing: VehicleProfile?
    @State private var detail:VehicleProfile?
    @State private var fuelLedger=false
    @State private var deleteCandidate:VehicleProfile?
    var body: some View { ScrollView {
        VStack(alignment:.leading,spacing:14) {
        AppButton(title:"Open Fuel Ledger",icon:"fuelpump") { fuelLedger=true }.accessibilityIdentifier("garage.fuel-ledger")
        ForEach(store.state.vehicles.filter{!$0.isArchived}) { vehicle in vehicleCard(vehicle) }
        AppButton(title:"Add a vehicle",icon:"plus") { adding = true }.disabled(store.recording || store.pendingGPS)
            .accessibilityIdentifier("garage.add")
        if store.state.vehicles.contains(where:\.isArchived) {
            Text("Archived vehicles").font(.headline).padding(.top,8)
            ForEach(store.state.vehicles.filter(\.isArchived)) { vehicle in vehicleCard(vehicle) }
        }
        InfoNote(text:"Finish a recording before switching vehicles. Trips, fills and dashboard choices stay with the vehicle they belong to.")
        }.padding(.vertical,4)
    }.sheet(isPresented:$adding) { VehicleSetupView() }.sheet(item:$editing) { VehicleSetupView(existing:$0) }
        .sheet(isPresented:$fuelLedger) { FuelLedgerView() }.sheet(item:$detail) { VehicleDetailView(vehicle:$0) }
        .alert("Delete empty vehicle?",isPresented:Binding(get:{deleteCandidate != nil},set:{if !$0{deleteCandidate=nil}})) {
            Button("Cancel",role:.cancel) { deleteCandidate=nil }
            Button("Delete",role:.destructive) { if let id=deleteCandidate?.id { do { try store.deleteEmptyVehicle(id) } catch { store.error=error.localizedDescription } };deleteCandidate=nil }
        } message:{ Text("Only an empty profile can be deleted. DriveLine never cascades deletion into drives, fills, receipts, imports, or queued transfers.") }
    }
    @ViewBuilder private func vehicleCard(_ vehicle:VehicleProfile)->some View {
        let trips=store.state.trips.filter{$0.vehicleID==vehicle.id && !$0.isSample}
        let fills=store.state.fills.filter{$0.vehicleID==vehicle.id && !$0.isSample}
        let queued=store.state.transfers.filter{$0.vehicle.id==vehicle.id}.count
        let hasData = !trips.isEmpty || !fills.isEmpty || queued>0
        VStack(alignment:.leading,spacing:13) {
            HStack(spacing:12) {
                Image(systemName:vehicle.kind.icon).font(.title2).foregroundStyle(Palette.blue)
                VStack(alignment:.leading,spacing:4) { Text(vehicle.title).font(.system(size:16,weight:.semibold));Text(vehicle.detail.isEmpty ? vehicle.identificationSource:vehicle.detail).captionStyle() }
                Spacer()
                if store.state.selectedVehicleID==vehicle.id { StatusPill(state:.ready,text:"Current") }
                else if vehicle.isArchived { StatusPill(state:.unavailable,text:"Archived") }
            }
            HStack { SourceBadge(source:vehicle.configuredSources.contains(.phoneGPS) ? "GPS configured":"GPS unavailable");SourceBadge(source:vehicle.configuredSources.contains(.obdScanner) ? "Scanner configured":"Scanner unavailable") }
            DataRow(label:"Class / fuel",value:"\(vehicle.kind.title) · \(vehicle.fuel.title)")
            DataRow(label:"VIN",value:vehicle.vin == nil ? "Unavailable":"Stored locally · hidden")
            DataRow(label:"Real history",value:"\(trips.count) drives · \(fills.count) fills")
            DataRow(label:"Last real drive",value:trips.max(by:{$0.startedAt<$1.startedAt})?.startedAt.formatted(date:.abbreviated,time:.shortened) ?? "Unavailable")
            DataRow(label:"Storage footprint",value:storageText(trips:trips,fills:fills))
            DataRow(label:"Transfer queue",value:queued==0 ? "Clear":"\(queued) queued")
            let live = store.state.selectedVehicleID==vehicle.id && store.scanner.connected
            DataRow(label:"Runtime status",value:live ? "Scanner live now":(trips.isEmpty ? "Configured · live unavailable":"Historical data · live unavailable"))
            HStack {
                if vehicle.isArchived { Button("Restore") { perform { try store.setVehicleArchived(vehicle.id,archived:false) } } }
                else { Button("Use vehicle") { perform { try store.chooseVehicle(vehicle.id) } }.disabled(store.recording || store.pendingGPS).accessibilityIdentifier(vehicle.isSample ? "garage.select.sample":"garage.select.\(vehicle.id.uuidString)").accessibilityValue(store.state.selectedVehicleID==vehicle.id ? "Selected":"Not selected") }
                Spacer();Button("Details") { detail=vehicle }
                Button("Edit") { editing=vehicle }.disabled(store.recording || store.pendingGPS)
                Menu { if !vehicle.isArchived { Button("Archive vehicle") { perform { try store.setVehicleArchived(vehicle.id,archived:true) } } };Button("Delete empty profile",role:.destructive) { deleteCandidate=vehicle }.disabled(hasData) } label:{ Image(systemName:"ellipsis.circle").frame(width:44,height:44) }.accessibilityLabel("Vehicle actions")
            }.font(.system(size:12))
        }.card()
    }
    private func storageText(trips:[Trip],fills:[FuelEntry])->String {
        let observations=trips.reduce(0){$0+$1.route.count+($1.samples?.count ?? 0)}
        return "\(observations) observations · \(fills.compactMap(\.receipt).count) receipts"
    }
    private func perform(_ body:()throws->Void) { do { try body() } catch { store.error=error.localizedDescription } }
}
struct VehicleDetailView:View {
    @EnvironmentObject private var store:AppStore
    @Environment(\.dismiss) private var dismiss
    let vehicle:VehicleProfile
    @State private var fuel=false
    @State private var signals=false
    private var trips:[Trip] { store.state.trips.filter{$0.vehicleID==vehicle.id && !$0.isSample} }
    private var fills:[FuelEntry] { store.state.fills.filter{$0.vehicleID==vehicle.id && !$0.isSample} }
    private var transfers:[TransferItem] { store.state.transfers.filter{$0.vehicle.id==vehicle.id} }
    var body:some View { NavigationStack { ScrollView { VStack(alignment:.leading,spacing:14) {
        SectionCard(title:"Identity",icon:vehicle.kind.icon) { VStack(alignment:.leading,spacing:8) { DataRow(label:"Stable UUID",value:vehicle.id.uuidString);DataRow(label:"Vehicle",value:vehicle.detail);DataRow(label:"Class",value:vehicle.kind.title);DataRow(label:"Fuel",value:vehicle.fuel.title);DataRow(label:"VIN",value:vehicle.vin == nil ? "Unavailable":"Stored locally · hidden") } }
        SectionCard(title:"Recording sources",icon:"dot.radiowaves.left.and.right") { VStack(alignment:.leading,spacing:8) { DataRow(label:"Configured",value:vehicle.configuredSources.map(sourceTitle).joined(separator:" · "));DataRow(label:"Preferred GPS",value:gpsTitle);DataRow(label:"Scanner",value:vehicle.scannerConnection == nil ? "Unavailable":(store.state.selectedVehicleID==vehicle.id && store.scanner.connected ? "Live now":"Configured · disconnected")) } }
        SectionCard(title:"Storage and transfer",icon:"externaldrive") { VStack(alignment:.leading,spacing:8) { DataRow(label:"Real data",value:"\(trips.count) drives · \(fills.count) fills");DataRow(label:"Stored observations",value:String(trips.reduce(0){$0+$1.route.count+($1.samples?.count ?? 0)}));DataRow(label:"Transfers",value:transfers.isEmpty ? "None":"\(transfers.count) queued / attempted") } }
        SectionCard(title:"Capabilities",icon:"checkmark.shield") { Text("GPS recording is available when selected. Scanner recording requires a configured and currently connected supported adapter. Imported history remains readable while archived.").captionStyle() }
        HStack { Button("Drives") { select();store.selectedTab = .drives;dismiss() };Button("Fuel") { select();fuel=true };Button("Signals") { select();signals=true };Spacer() }
        if vehicle.isArchived { AppButton(title:"Unarchive vehicle",icon:"arrow.uturn.backward") { perform { try store.setVehicleArchived(vehicle.id,archived:false) };dismiss() } }
        else { AppButton(title:"Archive vehicle",icon:"archivebox",secondary:true) { perform { try store.setVehicleArchived(vehicle.id,archived:true) };dismiss() } }
    }.padding(18) } .navigationTitle(vehicle.title).navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement:.topBarTrailing) { Button("Done") { dismiss() } } } }
        .sheet(isPresented:$fuel) { FuelLedgerView() }.sheet(isPresented:$signals) { SignalsOverviewView() }
    }
    private var gpsTitle:String { switch vehicle.preferredGPS { case .automatic:return "Automatic";case .phone:return "iPhone";case .imported:return "Imported";case .unavailable:return "Unavailable" } }
    private func sourceTitle(_ value:DriveLineVehicleSource)->String { switch value { case .manual:return "Manual";case .phoneGPS:return "iPhone GPS";case .obdScanner:return "OBD scanner";case .importedArchive:return "Imports" } }
    private func select() { if !vehicle.isArchived { try? store.chooseVehicle(vehicle.id) } }
    private func perform(_ body:()throws->Void) { do { try body() } catch { store.error=error.localizedDescription } }
}
