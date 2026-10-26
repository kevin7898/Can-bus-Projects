import SwiftUI
import UniformTypeIdentifiers

struct VehicleView: View {
    @EnvironmentObject private var store: AppStore
    @Binding var page: Int
    @State private var fuel = false
    @State private var history = false
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            Text(store.activeVehicle?.isSample == true ? "Sample vehicle snapshot · recorded values" : "\(store.activeVehicle?.title ?? "Vehicle") · \(store.latest?.isSample == true ? "sample recorded values" : "recorded values")").captionStyle()
            PageControl(labels:[store.activeVehicle?.fuel == .electric ? "Energy" : "Fuel",store.activeVehicle?.fuel == .electric ? "Powertrain" : "Engine",store.activeVehicle?.fuel == .diesel ? "DPF" : "Health","Logbook"], selection:$page)
            TabView(selection:$page) {
                Group { if store.activeVehicle?.isSample == true { fuelPage } else { recordedFuel } }.tag(0)
                Group { if store.activeVehicle?.isSample == true { engine } else { recordedEngine } }.tag(1)
                Group { if store.activeVehicle?.fuel == .diesel { dpf } else { health } }.tag(2)
                Group { if store.activeVehicle?.fuel == .electric { energyLog } else { logbook } }.tag(3)
            }.tabViewStyle(.page(indexDisplayMode:.never))
        }.sheet(isPresented:$fuel) { FuelForm() }.sheet(isPresented:$history) { FuelHistory() }
    }
    private var health: some View {
        VStack(alignment:.leading,spacing:17) {
            Text("Vehicle-specific health").font(.system(size:18))
            InfoNote(text:"Health data depends on this vehicle and a compatible diagnostic source. Identification alone does not provide fault codes or manufacturer-specific readings.")
            AppButton(title:"Open Record",secondary:true) { store.selectedTab = .record }
            Spacer(minLength:0)
        }.padding(.top,12)
    }
    private var energyLog: some View {
        VStack(alignment:.leading,spacing:17) {
            Text("Energy log").font(.system(size:18))
            InfoNote(text:"Charging and kWh logging are not available in this build. GPS trips and vehicle profiles work for electric vehicles.")
            Spacer(minLength:0)
        }.padding(.top,12)
    }
    private var recordedFuel: some View {
        VStack(alignment:.leading,spacing:17) {
            HStack { Metric(title:"Estimated range",value:"—",unit:"km"); Metric(title:store.activeVehicle?.fuel == .electric ? "Battery" : "Fuel level",value:store.activeVehicle?.fuel == .electric ? "—" : store.latestRecordedValue("fuelPercent")?.text(0) ?? "—",unit:"%") }.card()
            InfoNote(text:"Range and level need a compatible vehicle data source. GPS alone cannot provide them.")
            if let odo = store.activeVehicle?.odometerKM { DataRow(label:"Starting odometer",value:"\(odo.text(0)) km") }
            if let economy = FuelMath.latestEconomy(store.vehicleFills) { Metric(title:"Last full tank",value:economy.text(),unit:"L/100 km").card() }
            AppButton(title:"Open logbook",secondary:true) { page = 3 }
            Spacer(minLength:0)
        }.padding(.horizontal,1).padding(.top,8)
    }
    private var recordedEngine: some View {
        VStack(alignment:.leading,spacing:16) {
            Text(store.latest?.samples?.isEmpty == false ? "End of recorded drive" : "Waiting for recorded vehicle signals").font(.system(size:17))
            if store.activeVehicle?.fuel != .electric { DataRow(label:"Coolant temperature",value:"\(store.latestRecordedValue("coolantC")?.text(0) ?? "—") °C"); DataRow(label:"Engine speed",value:"\(store.latestRecordedValue("rpm")?.text(0) ?? "—") rpm") }
            DataRow(label:"System voltage",value:"\(store.latestRecordedValue("voltage")?.text(1) ?? "—") V")
            InfoNote(text:"These are the newest saved observations for each signal, even when the latest drive was GPS-only. Open Live for current OBD readings; unsupported signals stay unavailable.")
            if let vehicle = store.activeVehicle, !vehicle.supportedPIDs.isEmpty { Text("\(vehicle.supportedPIDs.count) standard OBD PIDs confirmed during setup").captionStyle() }
            Spacer(minLength:0)
        }.padding(.horizontal,1).padding(.top,8)
    }
    private var fuelPage: some View {
        VStack(alignment:.leading,spacing:13) {
            VStack(alignment:.leading,spacing:13) {
                HStack(alignment:.bottom) { VStack(alignment:.leading,spacing:7) { Text("Estimated range · sample").captionStyle(); HStack(alignment:.firstTextBaseline,spacing:5) { Text("620").font(.system(size:46)); Text("km").foregroundStyle(Palette.muted) } }; Spacer(); VStack(spacing:7) { Image(systemName:"fuelpump").foregroundStyle(Palette.blue); Text("62%").font(.system(size:23)) } }
                GeometryReader { g in Capsule().fill(Palette.border).overlay(alignment:.leading) { Capsule().fill(Palette.blue).frame(width:g.size.width*0.62) } }.frame(height:5)
                HStack { Text("33.9 L remaining"); Spacer(); Text("216,482 km") }.captionStyle()
            }.card()
            VStack(alignment:.leading,spacing:8) { Text("Rolling average · sample 500 km").captionStyle(); HStack(alignment:.firstTextBaseline) { Text("5.4").font(.system(size:36)); Text("L/100 km").font(.system(size:12)).foregroundStyle(Palette.muted) } }
            EconomyChart()
            HStack { Text("500 km ago"); Spacer(); Text("Last drive") }.captionStyle()
            InfoNote(text:"Sample range uses recorded fuel level and rolling economy.")
            Spacer(minLength:0)
        }.padding(.horizontal,1).padding(.top,3)
    }
    private var engine: some View {
        VStack(alignment:.leading,spacing:16) { Text("End of sample drive").font(.system(size:17)); VStack(spacing:0) { DataRow(label:"Coolant temperature",value:"89 °C"); DataRow(label:"Engine speed",value:"812 rpm"); DataRow(label:"Intake air temperature",value:"24 °C"); DataRow(label:"Control module voltage",value:"13.9 V") }; InfoNote(text:"These are sample recorded readings. Open Record to use the current source.",icon:"clock"); AppButton(title:"Open Record",secondary:true) { store.selectedTab = .record }; Spacer(minLength:0) }.padding(.horizontal,1).padding(.top,10)
    }
    private var dpf: some View { RegenSummaryView() }
    private var logbook: some View {
        VStack(alignment:.leading,spacing:18) {
            HStack { Text("Latest fill-up").font(.system(size:17)); Spacer(); Button("History") { history = true }.font(.system(size:11)) }
            if let entry = store.vehicleFills.sorted(by: { $0.date > $1.date }).first {
                VStack(alignment:.leading,spacing:16) { HStack { Text(entry.isSample ? "Fuel · sample" : (store.activeVehicle?.fuel.title ?? "Fuel")); Spacer(); Text(entry.full ? "Full fill" : "Partial fill").foregroundStyle(Palette.muted) }.font(.system(size:12)); HStack { Metric(title:"Added",value:entry.litres.text(),unit:"L"); Metric(title:"Total cost",value:"$\(entry.costCAD.text(2))",unit:"CAD") }; HStack { Text("\(entry.odometerKM.text(0)) km"); Spacer(); Text(entry.date.formatted(date:.abbreviated,time:.omitted)) }.captionStyle() }.card()
            } else { InfoNote(text:"Your fill-ups will appear here.",icon:"fuelpump") }
            if let economy = FuelMath.latestEconomy(store.vehicleFills) { Metric(title:"Last full tank economy",value:economy.text(),unit:"L/100 km").card() }
            InfoNote(text:"Keep full and partial fills together. Economy is calculated between two full fills, including the partial fills between them.",icon:"book.closed")
            AppButton(title:"Log a fill-up",icon:"plus") { fuel = true }
            Spacer(minLength:0)
        }.padding(.horizontal,1).padding(.top,10)
    }
}
struct FuelForm: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var litres = ""
    @State private var cost = ""
    @State private var odometer = ""
    @State private var date = Date()
    @State private var full = true
    @State private var currencyCode="CAD"
    @State private var station=""
    @State private var notes=""
    @State private var receipt:ReceiptAttachment?
    @State private var existingReceipt:DriveLineReceiptMetadata?
    @State private var removeReceipt=false
    @State private var choosingReceipt=false
    @State private var allowCorrection=false
    @State private var error: String?
    private let entryID:UUID?
    init(entry:FuelEntry? = nil) {
        entryID=entry?.id
        _litres=State(initialValue:entry.map { String($0.litres) } ?? "")
        _cost=State(initialValue:entry.map { String($0.costCAD) } ?? "")
        _odometer=State(initialValue:entry.map { String($0.odometerKM) } ?? "")
        _date=State(initialValue:entry?.date ?? Date())
        _full=State(initialValue:entry?.full ?? true)
        _currencyCode=State(initialValue:entry?.currencyCode ?? "CAD")
        _station=State(initialValue:entry?.stationName ?? "")
        _notes=State(initialValue:entry?.notes ?? "")
        _existingReceipt=State(initialValue:entry?.receipt)
    }
    private func number(_ input: String) -> Double? { Double(input.replacingOccurrences(of:",",with:".")) }
    var body: some View {
        SheetShell(title:entryID == nil ? "Add Fuel":"Edit Fuel") {
        field("Fuel added · L",text:$litres)
        Group {
            if dynamicTypeSize.isAccessibilitySize { VStack(alignment:.leading,spacing:18) { field("Total cost",text:$cost);currencyField } }
            else { HStack(alignment:.bottom) { field("Total cost",text:$cost);currencyField.frame(width:90) } }
        }
        field("Odometer · km",text:$odometer)
        VStack(alignment:.leading,spacing:8) {
            if dynamicTypeSize.isAccessibilitySize {
                Text("Date").captionStyle()
                DatePicker("Date",selection:$date,in:...Date(),displayedComponents:[.date,.hourAndMinute]).labelsHidden()
                    .font(.system(size:13)).dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            } else {
                DatePicker("Date",selection:$date,in:...Date(),displayedComponents:[.date,.hourAndMinute]).font(.system(size:13))
            }
        }
        Toggle(full ? "Full fill":"Partial fill",isOn:$full).font(.system(size:14)).accessibilityIdentifier("fuel.full")
        VStack(alignment:.leading,spacing:8) { Text("Station").captionStyle();TextField("Optional station or location",text:$station).accessibilityIdentifier("fuel.station").padding(13).background(Palette.surface,in:RoundedRectangle(cornerRadius:10)) }
        VStack(alignment:.leading,spacing:8) { Text("Notes").captionStyle();TextField("Optional notes",text:$notes,axis:.vertical).lineLimit(2...5).accessibilityIdentifier("fuel.notes").padding(13).background(Palette.surface,in:RoundedRectangle(cornerRadius:10)) }
        VStack(alignment:.leading,spacing:8) {
            HStack { Label(receipt?.metadata.fileName ?? existingReceipt?.fileName ?? "No receipt attached",systemImage:"doc.text").lineLimit(1);Spacer();Button("Choose…") { choosingReceipt=true }.accessibilityIdentifier("fuel.receipt.choose") }
            if receipt != nil || existingReceipt != nil { Toggle("Remove receipt",isOn:$removeReceipt).font(.caption).accessibilityIdentifier("fuel.receipt.remove") }
            Text("Receipt files are stored separately from app state and included in complete exports.").captionStyle()
        }.card()
        Toggle("Allow explicit odometer correction",isOn:$allowCorrection).font(.system(size:13)).accessibilityIdentifier("fuel.odometer-correction")
        InfoNote(text:"Partial fills count toward the next full-tank economy calculation.")
        if let error { Text(error).font(.system(size:12)).foregroundStyle(Palette.red) }
        AppButton(title:"Save fill-up",icon:"checkmark") {
            guard let l = number(litres), let c = number(cost), let o = number(odometer) else { error = "Enter litres, total cost and odometer."; return }
            do { _=try store.saveFill(id:entryID,litres:l,cost:c,currencyCode:currencyCode,odometer:o,full:full,date:date,stationName:station,notes:notes,receipt:receipt,removeReceipt:removeReceipt,allowOdometerCorrection:allowCorrection);dismiss() } catch { self.error = error.localizedDescription }
            }
        }
        .fileImporter(isPresented:$choosingReceipt,allowedContentTypes:[.image,.pdf,.data]) { result in
            do { receipt=try store.prepareReceipt(result.get());removeReceipt=false;error=nil } catch { self.error=error.localizedDescription }
        }
    }
    private var currencyField:some View { VStack(alignment:.leading,spacing:8) { Text("Currency").captionStyle();TextField("CAD",text:$currencyCode).textInputAutocapitalization(.characters).autocorrectionDisabled().accessibilityIdentifier("fuel.currency").padding(13).background(Palette.surface,in:RoundedRectangle(cornerRadius:10)).frame(maxWidth:.infinity,alignment:.leading) } }
    private func field(_ title: String, text: Binding<String>) -> some View { VStack(alignment:.leading,spacing:8) { Text(title).captionStyle(); TextField("0",text:text).keyboardType(.decimalPad).font(.system(size:21)).padding(13).background(Palette.surface,in:RoundedRectangle(cornerRadius:10)) } }
}
struct FuelHistory: View {
    @EnvironmentObject private var store: AppStore
    @State private var editing:FuelEntry?
    var body: some View {
        SheetShell(title:"Fuel logbook") {
            if store.vehicleFills.isEmpty { InfoNote(text:"No fill-ups yet.") }
            ForEach(store.vehicleFills.sorted { $0.date > $1.date }) { entry in Button { if !entry.isSample { editing=entry } } label:{ VStack(alignment:.leading,spacing:8) { Text(entry.date.formatted(date:.abbreviated,time:.shortened)).captionStyle();Text("\(entry.litres.text()) L · \(entry.costCAD.formatted(.currency(code:entry.currencyCode)))");Text("\(entry.odometerKM.text(0)) km · \(entry.full ? "Full" : "Partial")\(entry.isSample ? " · Sample" : " · Tap to edit")").captionStyle() }.frame(maxWidth:.infinity,alignment:.leading).card() }.buttonStyle(.plain) }
        }
        .sheet(item:$editing) { FuelForm(entry:$0) }
    }
}

struct FuelLedgerView:View {
    @EnvironmentObject private var store:AppStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var vehicleID:UUID?
    @State private var dateDays=0
    @State private var adding=false
    @State private var editing:FuelEntry?
    private var cutoff:Date? { dateDays == 0 ? nil:Date().addingTimeInterval(-Double(dateDays)*86_400) }
    private var entries:[FuelEntry] {
        store.state.fills.filter { entry in
            (vehicleID == nil || entry.vehicleID == vehicleID) && (cutoff == nil || entry.date >= cutoff!)
        }.sorted { $0.date > $1.date }
    }
    private var sharedEntries:[DriveLineFuelEntry] {
        entries.compactMap { entry in
            guard let vehicleID=entry.vehicleID else { return nil }
            return DriveLineFuelEntry(id:entry.id,vehicleID:vehicleID,date:entry.date,litresPurchased:entry.litres,totalCost:entry.costCAD,
                currencyCode:entry.currencyCode,odometerKm:entry.odometerKM,isFullFill:entry.full,stationName:entry.stationName,
                notes:entry.notes,receipt:entry.receipt,isSample:entry.isSample)
        }
    }
    private var ledger:[DriveLineFuelLedgerItem] {
        let real=DriveLineJourneyPolicy.fuelLedger(sharedEntries.filter{!$0.isSample})
        let sample=DriveLineJourneyPolicy.fuelLedger(sharedEntries.filter(\.isSample),includeSamples:true)
        return real+sample
    }
    private var trips:[Trip] { store.state.trips.filter { vehicleID == nil || $0.vehicleID == vehicleID } }
    private var tripFuel:[DriveLineTripFuelPoint] { DriveLineJourneyPolicy.tripFuelSeries(trips.map(\.sharedRecording)).filter { cutoff == nil || $0.date >= cutoff! } }
    var body:some View {
        SheetShell(title:"Fuel Ledger") {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment:.leading) { fuelVehiclePicker;fuelDatePicker }
                } else { HStack { fuelVehiclePicker;fuelDatePicker } }
            }
            HStack { Metric(title:"Purchased fuel",value:entries.filter{!$0.isSample}.reduce(0){$0+$1.litres}.text(1),unit:"L");Metric(title:"Recorded fills",value:String(entries.filter{!$0.isSample}.count)) }
            InfoNote(text:"Purchased quantity, full-tank economy, and measured trip fuel are separate evidence series. Sample entries are labelled and excluded from totals.",icon:"checkmark.shield")
            if entries.isEmpty { EmptyStateCard(icon:"fuelpump",title:"No fuel entries match",message:"Log a fill or change the vehicle and date filters. Tank economy appears only after two valid full-fill boundaries.") }
            ForEach(entries) { entry in
                let item=ledger.first(where:{$0.id==entry.id})
                SectionCard(title:entry.stationName ?? "Fuel fill",icon:"fuelpump.fill") {
                    Group {
                        if dynamicTypeSize.isAccessibilitySize {
                            VStack(alignment:.leading,spacing:8) { Text(entry.date.formatted(date:.abbreviated,time:.shortened));StatusPill(state:entry.isSample ? .unavailable:(entry.full ? .ready:.stale),text:entry.isSample ? "Sample":(entry.full ? "Full fill":"Partial fill")) }
                        } else { HStack { Text(entry.date.formatted(date:.abbreviated,time:.shortened));Spacer();StatusPill(state:entry.isSample ? .unavailable:(entry.full ? .ready:.stale),text:entry.isSample ? "Sample":(entry.full ? "Full fill":"Partial fill")) } }
                    }.font(.caption)
                    DataRow(label:"Purchased",value:"\(entry.litres.text(2)) L")
                    DataRow(label:"Cost",value:entry.costCAD.formatted(.currency(code:entry.currencyCode)))
                    DataRow(label:"Cost per litre",value:(item?.costPerLitre).map { $0.formatted(.currency(code:entry.currencyCode))+"/L" } ?? "Unavailable")
                    DataRow(label:"Odometer",value:"\(entry.odometerKM.text(0)) km")
                    DataRow(label:"Tank-to-tank economy",value:(item?.tankEconomyL100Km).map { "\($0.text(2)) L/100 km" } ?? "Insufficient full-fill boundaries")
                    if let receipt=entry.receipt { DataRow(label:"Receipt",value:"\(receipt.fileName) · \(ByteCountFormatter.string(fromByteCount:Int64(receipt.byteCount),countStyle:.file))") }
                    if !entry.isSample { Button("Edit fuel entry") { editing=entry }.accessibilityIdentifier("fuel.edit.\(entry.id.uuidString)") }
                }
            }
            SectionCard(title:"Measured trip fuel",icon:"road.lanes") {
                if tripFuel.isEmpty { InfoNote(text:"No journey has qualifying measured fuel-rate coverage in this selection.") }
                ForEach(tripFuel.suffix(12).reversed()) { point in
                    DataRow(label:point.date.formatted(date:.abbreviated,time:.shortened),value:"\(point.litres.text(2)) L · \(point.source)")
                }
            }
            AppButton(title:"Log a fill-up",icon:"plus") { adding=true }
        }.onAppear { vehicleID=store.state.selectedVehicleID }.sheet(isPresented:$adding) { FuelForm() }.sheet(item:$editing) { FuelForm(entry:$0) }
    }
    private var fuelVehiclePicker:some View { Picker("Vehicle",selection:$vehicleID) { Text("All vehicles").tag(nil as UUID?);ForEach(store.state.vehicles) { Text($0.title).tag(Optional($0.id)) } } }
    private var fuelDatePicker:some View { Picker("Date",selection:$dateDays) { Text("Any date").tag(0);Text("90 days").tag(90);Text("1 year").tag(365) } }
}

#if DEBUG
#Preview("Vehicle data · Sample data") { DriveLineCanvas(tab:.more) }
#endif
