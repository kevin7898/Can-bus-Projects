import SwiftUI
import Charts

struct DrivesDestinationView:View {
    @State private var comparison=false
    var body:some View {
        VStack(alignment:.leading,spacing:14) {
            HStack {
                Picker("Drives mode",selection:$comparison) {
                    Text("Ledger").tag(false)
                    Text("Compare").tag(true)
                }.pickerStyle(.segmented).frame(width:220).accessibilityIdentifier("mac.drives.mode")
                Spacer()
                if comparison { Label("Compare uses the same preserved recordings",systemImage:"rectangle.split.2x1").foregroundStyle(Theme.secondaryText) }
            }.font(.system(size:11))
            if comparison { CompareView() } else { TripsView() }
        }
    }
}

struct FuelDestinationView:View {
    @EnvironmentObject private var store:AppStore
    @State private var dateDays=0
    @State private var selectedFuelID:UUID?
    private var cutoff:Date? { dateDays == 0 ? nil:Date().addingTimeInterval(-Double(dateDays)*86_400) }
    var entries:[FuelEntry] { store.state.fuelEntries.filter { $0.vehicleID==store.state.selectedVehicleID && (cutoff == nil || $0.date >= cutoff!) }.sorted { $0.date>$1.date } }
    var sharedEntries:[DriveLineFuelEntry] { entries.map { DriveLineFuelEntry(id:$0.id,vehicleID:$0.vehicleID,date:$0.date,litresPurchased:$0.litresPurchased,totalCost:$0.totalCost,currencyCode:$0.currencyCode,odometerKm:$0.odometerKm,isFullFill:$0.isFullFill,stationName:$0.stationName,notes:$0.notes,receipt:$0.receipt,isSample:$0.isDemo) } }
    var ledger:[DriveLineFuelLedgerItem] {
        let real=DriveLineJourneyPolicy.fuelLedger(sharedEntries.filter{!$0.isSample})
        let sample=DriveLineJourneyPolicy.fuelLedger(sharedEntries.filter(\.isSample),includeSamples:true)
        return real+sample
    }
    var tripFuel:[DriveLineTripFuelPoint] { DriveLineJourneyPolicy.tripFuelSeries(store.vehicleTrips.map(\.sharedRecording)).filter { cutoff == nil || $0.date >= cutoff! } }
    var realEntries:[FuelEntry] { entries.filter{!$0.isDemo} }
    var monthEntries:[FuelEntry] { realEntries.filter { Calendar.current.isDate($0.date,equalTo:Date(),toGranularity:.month) } }
    var selectedEntry:FuelEntry? { entries.first(where:{$0.id==selectedFuelID}) ?? entries.first }
    var monthSpend:String {
        let groups=Dictionary(grouping:monthEntries,by:{$0.currencyCode})
        guard !groups.isEmpty else { return "—" }
        return groups.sorted{$0.key<$1.key}.map { code,values in values.reduce(0){$0+$1.totalCost}.formatted(.currency(code:code)) }.joined(separator:" + ")
    }
    var body:some View {
        VStack(alignment:.leading,spacing:14) {
            HStack {
                Picker("Date",selection:$dateDays) { Text("Any date").tag(0);Text("90 days").tag(90);Text("1 year").tag(365) }.frame(width:150)
                Text("Vehicle: \(store.selectedVehicle?.name ?? "None")").foregroundStyle(Theme.secondaryText)
                Spacer()
                Text("\(entries.filter{!$0.isDemo}.reduce(0){$0+$1.litresPurchased}.formatted(.number.precision(.fractionLength(1)))) L purchased · \(entries.filter{!$0.isDemo}.count) real fills").monospacedDigit()
            }.font(.system(size:11)).accessibilityIdentifier("mac.fuel.filters")
            Text("Purchased quantity, full-tank economy, and measured trip fuel are separate evidence series. Sample entries are labelled and excluded from totals.").font(.system(size:11)).foregroundStyle(Theme.secondaryText)
            HStack(spacing:14) {
                MetricTile(title:"This month",value:"\(monthEntries.count)",unit:"fills",showsFreshness:false)
                MetricTile(title:"Purchased",value:number(monthEntries.reduce(0){$0+$1.litresPurchased}),unit:"L",showsFreshness:false)
                MetricTile(title:"Spend by currency",value:monthSpend,unit:"recorded total",showsFreshness:false)
            }.accessibilityIdentifier("mac.fuel.month-summary")
            if entries.isEmpty {
                EmptyStateCard(icon:"fuelpump",title:"No fuel entries match",message:"Imported and transferred fills for this vehicle appear here. Tank economy requires two valid full-fill boundaries.")
            } else {
                HStack(alignment:.top,spacing:14) {
                    Panel(title:"Fuel ledger · \(entries.count) fills",icon:"fuelpump") {
                        ForEach(entries) { entry in
                            let item=ledger.first(where:{$0.id==entry.id})
                            Button { selectedFuelID=entry.id } label:{ VStack(alignment:.leading,spacing:8) {
                                HStack(spacing:12) {
                                    Image(systemName:"fuelpump.fill").foregroundStyle(Theme.fuelAttention)
                                    VStack(alignment:.leading,spacing:4) { Text(entry.stationName ?? "Fuel fill").font(.system(size:12,weight:.semibold));Text(entry.date.formatted(date:.abbreviated,time:.shortened)).font(.system(size:10)).foregroundStyle(Theme.secondaryText) }
                                    Spacer()
                                    StatusPill(state:entry.isDemo ? .unavailable:(entry.isFullFill ? .healthy:.stale),text:entry.isDemo ? "Sample":(entry.isFullFill ? "Full fill":"Partial fill"))
                                    Text("\(number(entry.litresPurchased)) L purchased").monospacedDigit()
                                    Text(entry.totalCost.formatted(.currency(code:entry.currencyCode))).monospacedDigit()
                                }
                                HStack(spacing:18) {
                                    KeyValue(label:"Cost / litre",value:(item?.costPerLitre).map { $0.formatted(.currency(code:entry.currencyCode))+"/L" } ?? "Unavailable")
                                    KeyValue(label:"Odometer",value:"\(number(entry.odometerKm)) km")
                                    KeyValue(label:"Tank economy",value:(item?.tankEconomyL100Km).map { "\(number($0)) L/100 km" } ?? "Insufficient data")
                                    if let receipt=entry.receipt { Label("\(receipt.fileName) · \(ByteCountFormatter.string(fromByteCount:Int64(receipt.byteCount),countStyle:.file))",systemImage:"doc.text").foregroundStyle(Theme.healthy) }
                                }.font(.system(size:10))
                            }.padding(13).background(entry.id==selectedEntry?.id ? Theme.cobalt.opacity(0.10):Color.clear) }.buttonStyle(.plain).accessibilityIdentifier("mac.fuel.entry.\(entry.id.uuidString)")
                            Divider().overlay(Theme.border)
                        }
                    }
                    VStack(spacing:14) {
                        Panel(title:"Tank-to-tank economy · full-fill boundaries",icon:"chart.xyaxis.line") {
                            let points=ledger.filter{$0.tankEconomyL100Km != nil}
                            if points.isEmpty { Text("Insufficient full-fill boundaries in this selection.").foregroundStyle(Theme.secondaryText).padding(14) }
                            else { Chart(points) { item in LineMark(x:.value("Date",item.entry.date),y:.value("L/100 km",item.tankEconomyL100Km!)).foregroundStyle(Theme.fuelAttention);PointMark(x:.value("Date",item.entry.date),y:.value("L/100 km",item.tankEconomyL100Km!)).foregroundStyle(Theme.fuelAttention) }.frame(height:180).padding(14) }
                            Text("Source: purchased litres between two recorded full fills divided by odometer distance. Partial fills inside the boundary are included.").font(.system(size:9)).foregroundStyle(Theme.secondaryText).padding(.horizontal,14).padding(.bottom,12)
                        }
                        Panel(title:"Measured trip fuel · journey series",icon:"road.lanes") {
                            if tripFuel.isEmpty { Text("No journey meets the measured fuel-rate coverage policy.").foregroundStyle(Theme.secondaryText).padding(14) }
                            else { Chart(tripFuel) { point in BarMark(x:.value("Date",point.date),y:.value("Litres",point.litres)).foregroundStyle(Theme.cobalt) }.frame(height:170).padding(14) }
                            Text("Source: qualifying recorded fuel-rate observations. This is not purchased fill quantity.").font(.system(size:9)).foregroundStyle(Theme.secondaryText).padding(.horizontal,14).padding(.bottom,12)
                        }
                        Panel(title:"Purchased cost · recorded currency",icon:"creditcard") {
                            if realEntries.isEmpty { Text("No purchased-cost entries in this selection.").foregroundStyle(Theme.secondaryText).padding(14) }
                            else { Chart(realEntries) { entry in BarMark(x:.value("Date",entry.date),y:.value("Cost",entry.totalCost)).foregroundStyle(Theme.fuelAttention) }.frame(height:140).padding(14) }
                            Text("Amounts retain their recorded currency and are never converted or summed across currencies.").font(.system(size:9)).foregroundStyle(Theme.secondaryText).padding(.horizontal,14).padding(.bottom,12)
                        }
                        if let entry=selectedEntry {
                            Panel(title:"Selected fill and receipt",icon:"doc.text.magnifyingglass") {
                                VStack(alignment:.leading,spacing:10) {
                                    KeyValue(label:"Station",value:entry.stationName ?? "Unavailable")
                                    KeyValue(label:"Notes",value:entry.notes ?? "Unavailable")
                                    if let receipt=entry.receipt {
                                        KeyValue(label:"Receipt",value:receipt.fileName)
                                        KeyValue(label:"Media",value:receipt.mediaType)
                                        KeyValue(label:"Integrity",value:store.receiptURL(receipt)==nil ? "Metadata preserved · file missing":"SHA-256 verified · file available")
                                        Button("Open receipt") { store.openReceipt(receipt) }.disabled(store.receiptURL(receipt)==nil).accessibilityIdentifier("mac.fuel.open-receipt")
                                    } else { Text("No receipt attached to this fill.").foregroundStyle(Theme.secondaryText) }
                                }.padding(14)
                            }
                        }
                    }.frame(minWidth:360)
                }
            }
        }.onAppear { selectedFuelID=selectedFuelID ?? entries.first?.id }
    }
}
