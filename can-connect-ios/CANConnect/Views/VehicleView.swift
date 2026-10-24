import SwiftUI

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
            AppButton(title:"Open Live",secondary:true) { store.selectedTab = .live }
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
            HStack { Metric(title:"Estimated range",value:"—",unit:"km"); Metric(title:store.activeVehicle?.fuel == .electric ? "Battery" : "Fuel level",value:store.activeVehicle?.fuel == .electric ? "—" : store.latest?.recordedValue("fuelPercent")?.text(0) ?? "—",unit:"%") }.card()
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
            if store.activeVehicle?.fuel != .electric { DataRow(label:"Coolant temperature",value:"\(store.latest?.recordedValue("coolantC")?.text(0) ?? "—") °C"); DataRow(label:"Engine speed",value:"\(store.latest?.recordedValue("rpm")?.text(0) ?? "—") rpm") }
            DataRow(label:"System voltage",value:"\(store.latest?.recordedValue("voltage")?.text(1) ?? "—") V")
            InfoNote(text:"These are saved readings from the latest drive, when available. Open Live for current OBD readings; unsupported signals stay unavailable.")
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
        VStack(alignment:.leading,spacing:16) { Text("End of sample drive").font(.system(size:17)); VStack(spacing:0) { DataRow(label:"Coolant temperature",value:"89 °C"); DataRow(label:"Engine speed",value:"812 rpm"); DataRow(label:"Intake air temperature",value:"24 °C"); DataRow(label:"Control module voltage",value:"13.9 V") }; InfoNote(text:"These are sample recorded readings. Open Live to use the current source.",icon:"clock"); AppButton(title:"Open Live",secondary:true) { store.selectedTab = .live }; Spacer(minLength:0) }.padding(.horizontal,1).padding(.top,10)
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
    @State private var litres = ""
    @State private var cost = ""
    @State private var odometer = ""
    @State private var date = Date()
    @State private var full = true
    @State private var error: String?
    private func number(_ input: String) -> Double? { Double(input.replacingOccurrences(of:",",with:".")) }
    var body: some View { SheetShell(title:"Log a fill-up") {
        field("Fuel added · L",text:$litres)
        field("Total cost · CAD",text:$cost)
        field("Odometer · km",text:$odometer)
        DatePicker("Date",selection:$date,in:...Date(),displayedComponents:[.date,.hourAndMinute]).font(.system(size:13))
        Toggle("Full tank",isOn:$full).font(.system(size:14))
        InfoNote(text:"Partial fills count toward the next full-tank economy calculation.")
        if let error { Text(error).font(.system(size:12)).foregroundStyle(Palette.red) }
        AppButton(title:"Save fill-up",icon:"checkmark") {
            guard let l = number(litres), let c = number(cost), let o = number(odometer) else { error = "Enter litres, total cost and odometer."; return }
            do { try store.addFill(litres:l,cost:c,odometer:o,full:full,date:date); dismiss() } catch { self.error = error.localizedDescription }
        }
    } }
    private func field(_ title: String, text: Binding<String>) -> some View { VStack(alignment:.leading,spacing:8) { Text(title).captionStyle(); TextField("0",text:text).keyboardType(.decimalPad).font(.system(size:21)).padding(13).background(Palette.surface,in:RoundedRectangle(cornerRadius:10)) } }
}
struct FuelHistory: View {
    @EnvironmentObject private var store: AppStore
    var body: some View { SheetShell(title:"Fuel logbook") {
        if store.vehicleFills.isEmpty { InfoNote(text:"No fill-ups yet.") }
        ForEach(store.vehicleFills.sorted { $0.date > $1.date }) { entry in VStack(alignment:.leading,spacing:8) { Text(entry.date.formatted(date:.abbreviated,time:.shortened)).captionStyle(); Text("\(entry.litres.text()) L · $\(entry.costCAD.text(2)) CAD"); Text("\(entry.odometerKM.text(0)) km · \(entry.full ? "Full" : "Partial")\(entry.isSample ? " · Sample" : "")").captionStyle() }.frame(maxWidth:.infinity,alignment:.leading).card() }
    } }
}
