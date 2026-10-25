import SwiftUI
import UniformTypeIdentifiers

struct OverviewView:View {
    @EnvironmentObject var store:AppStore
    @State private var viewport = MapViewport()
    @State private var expanded = false
    @State private var corridor:Trip?
    @State private var customizing = false
    @State private var dragged:UUID?
    @State private var availableWidth:CGFloat = 0
    var body:some View {
        VStack(spacing:14) {
            HStack(alignment:.top,spacing:14) {
                VStack(spacing:14) {
                    Grid(horizontalSpacing:10,verticalSpacing:10) {
                        ForEach(Array(widgetRows.enumerated()),id:\.offset) { _,widgets in
                            GridRow { ForEach(widgets) { widget in metric(widget).gridCellColumns(widget.columns) }; if widgets.reduce(0,{$0+$1.columns})<4 { Color.clear.gridCellColumns(4-widgets.reduce(0,{$0+$1.columns})) } }
                        }
                    }
                    HStack {
                        Picker("Period",selection:Binding(get:{store.preferences.periodDays},set:{days in store.changePreferences{$0.periodDays = days}})) { Text("7 days").tag(7);Text("30 days").tag(30);Text("All time").tag(0) }.pickerStyle(.segmented).frame(width:260)
                        Spacer()
                        Button { customizing.toggle() } label: { Label(customizing ? "Done" : "Customize",systemImage:customizing ? "checkmark" : "slider.horizontal.3") }
                    }
                    if customizing { customization }
                    if store.preferences.mapFirst { mapSection; if !expanded { recentTrips } } else { if !expanded { recentTrips }; mapSection }
                }.frame(maxWidth:.infinity,alignment:.top)
                if availableWidth>1000 { inspector.frame(width:235) }
            }
            if availableWidth<=1000 { inspector }
        }.background {
            GeometryReader { geometry in
                Color.clear.onAppear { availableWidth = geometry.size.width }
                    .onChange(of:geometry.size.width) { _,width in availableWidth = width }
            }
        }
            .onAppear { viewport = store.preferences.map }
            .onChange(of:store.state.selectedVehicleID) { _,_ in viewport = store.preferences.map; corridor = nil }
            .onChange(of:viewport) { _,value in store.setMap(value) }
    }
    var widgetRows:[[SummaryWidget]] {
        var rows:[[SummaryWidget]] = [],row:[SummaryWidget] = [],used = 0
        for widget in store.preferences.widgets {
            if used+widget.columns>4 { rows.append(row);row = [];used = 0 }
            row.append(widget);used += widget.columns
        }
        if !row.isEmpty { rows.append(row) };return rows
    }
    func metric(_ widget:SummaryWidget) -> some View {
        VStack(alignment:.leading,spacing:9) {
            HStack { Text(widget.kind.title).font(.system(size:11)).foregroundStyle(Theme.muted);Spacer();if customizing { Menu { ForEach(SummaryKind.allCases,id:\.self) { kind in Button(kind.title) { update(widget.id){$0.kind = kind} } };Divider();ForEach(1...4,id:\.self) { size in Button("Width: \(size) columns") { update(widget.id){$0.columns = size} } };Button(widget.rows==1 ? "Make taller" : "Make compact") { update(widget.id){$0.rows = $0.rows==1 ? 2:1} };Button("Remove",role:.destructive) { store.changePreferences { $0.widgets.removeAll{$0.id==widget.id} } } } label:{Image(systemName:"ellipsis")} } }
            Text(summary(widget.kind)).font(.system(size:25,weight:.medium,design:.monospaced)).minimumScaleFactor(0.7).lineLimit(1)
            Text(widget.kind == .economy ? "Only drives with recorded fuel coverage" : "Recorded data · selected period").font(.system(size:10)).foregroundStyle(Theme.muted).lineLimit(2)
        }.padding(13).frame(maxWidth:.infinity,minHeight:CGFloat(95*widget.rows),alignment:.leading).background(Theme.panel).clipShape(RoundedRectangle(cornerRadius:8)).overlay(RoundedRectangle(cornerRadius:8).stroke(customizing ? Theme.blue:Theme.line))
            .onDrag { dragged = widget.id; return NSItemProvider(object:widget.id.uuidString as NSString) }
            .onDrop(of:[UTType.text],isTargeted:nil) { _ in
                guard customizing,let from = dragged,from != widget.id else { return false }
                store.changePreferences { p in guard let i = p.widgets.firstIndex(where:{$0.id==from}),let j = p.widgets.firstIndex(where:{$0.id==widget.id}) else { return };let value = p.widgets.remove(at:i);p.widgets.insert(value,at:min(j,p.widgets.count)) };dragged = nil;return true
            }
    }
    func update(_ id:UUID,_ body:(inout SummaryWidget)->Void) { store.changePreferences { p in if let i = p.widgets.firstIndex(where:{$0.id==id}) { body(&p.widgets[i]) } } }
    func summary(_ kind:SummaryKind) -> String {
        let trips = store.realFilteredTrips
        switch kind {
        case .distance: let d = trips.compactMap(\.distanceKm);return d.isEmpty ? "— km" : number(d.reduce(0,+),digits:0)+" km"
        case .economy:
            let usable = trips.filter{$0.economyL100 != nil};let km = usable.compactMap(\.distanceKm).reduce(0,+),fuel = usable.compactMap(\.fuelUsedL).reduce(0,+)
            return (km>0 ? number(fuel/km*100) : "—")+" L/100"
        case .drives:return String(trips.count)
        case .duration:return duration(trips.reduce(0){$0+$1.duration})
        }
    }
    var customization:some View {
        HStack { Text("Drag cards to reorder. Use each card menu to change its reading or size.").foregroundStyle(Theme.muted);Spacer();Menu("Add card") { ForEach(SummaryKind.allCases,id:\.self) { kind in Button(kind.title) { store.changePreferences { if $0.widgets.count<14 { $0.widgets.append(SummaryWidget(kind:kind)) } } } } };Button("Swap map / trips") { store.changePreferences{$0.mapFirst.toggle()} } }.font(.system(size:11)).padding(12).background(Theme.raised).clipShape(RoundedRectangle(cornerRadius:6))
    }
    var mapSection:some View {
        Panel(title:"Your roads",icon:"map") {
            HStack { Text("\(store.filteredTrips.count) recordings · select a recorded trace to inspect").font(.system(size:11)).foregroundStyle(Theme.muted);Spacer();Picker("Map",selection:Binding(get:{store.preferences.mapStyle},set:{value in store.changePreferences{$0.mapStyle = value}})) { Text("Roads").tag("standard");Text("Satellite").tag("satellite") }.labelsHidden().frame(width:120);Button { expanded.toggle() } label:{Image(systemName:expanded ? "arrow.down.right.and.arrow.up.left":"arrow.up.left.and.arrow.down.right")}.help(expanded ? "Restore map":"Expand map") }.padding(12)
            MapPanel(trips:store.filteredTrips,viewport:$viewport,style:store.preferences.mapStyle,height:expanded ? 650:350,onSelect:{corridor = $0})
            if let corridor = corridor {
                HStack { Text(corridor.name);Text(corridor.start.formatted(date:.abbreviated,time:.shortened)).foregroundStyle(Theme.muted);Spacer();Button("Inspect drive") { store.selectedTripID = corridor.id;store.page = .drives } }.font(.system(size:11)).padding(12)
            }
        }
    }
    var recentTrips:some View {
        Panel(title:"Recent drives") {
            if store.filteredTrips.isEmpty { EmptyPanel(title:"Your next drive starts here",message:"Import a recording for the selected vehicle. GPS-only data is welcome; unavailable signals stay blank.") }
            ForEach(store.filteredTrips.prefix(4)) { trip in TripRow(trip:trip,annotation:store.journeyAnnotation(for:trip.id)) { store.selectedTripID = trip.id;store.page = .drives };Divider().overlay(Theme.line) }
            HStack { Spacer();Button("View all drives") { store.page = .drives } }.padding(10)
        }
    }
    var inspector:some View {
        VStack(spacing:14) {
            Panel(title:"Vehicle snapshot",icon:"car") {
                VStack(alignment:.leading,spacing:14) {
                    Text([store.selectedVehicle?.year,store.selectedVehicle?.make].compactMap{$0}.joined(separator:" ").uppercased()).font(.system(size:10)).tracking(1.5).foregroundStyle(Theme.muted)
                    Text(store.selectedVehicle?.name ?? "No vehicle selected").font(.system(size:18,weight:.medium))
                    Image(systemName:"car.side").font(.system(size:46)).foregroundStyle(Theme.blue).frame(maxWidth:.infinity).padding(.vertical,10)
                    KeyValue(label:"Fuel level",value:number(latest(.fuelPercent))+" %")
                    KeyValue(label:"Coolant",value:number(latest(.coolantC),digits:0)+" °C")
                    KeyValue(label:"Battery",value:number(latest(.voltage))+" V")
                    Text(store.vehicleTrips.first.map { "Historical · "+$0.end.formatted(date:.abbreviated,time:.shortened) } ?? "No recordings yet").font(.system(size:10)).foregroundStyle(Theme.muted)
                }.padding(14)
            }
            Panel(title:"Data health",icon:"checkmark.shield") {
                VStack(spacing:12) {
                    KeyValue(label:"GPS coverage",value:"\(store.vehicleTrips.filter{!$0.coordinates.isEmpty}.count) drives")
                    KeyValue(label:"Signal coverage",value:"\(store.vehicleTrips.filter{!$0.availableSignals.isEmpty}.count) drives")
                    KeyValue(label:"Raw CAN",value:"\(store.vehicleTrips.reduce(0){$0+$1.rawFrameCount}) frames")
                    Text("Sources remain separate. Historical imports are never presented as a live connection.").font(.system(size:10)).foregroundStyle(Theme.muted)
                }.padding(14)
            }
            Panel(title:"Recent imports") {
                VStack(alignment:.leading,spacing:13) { ForEach(store.receiptList.prefix(4)) { receipt in VStack(alignment:.leading,spacing:4) { Text(receipt.originalName).lineLimit(1);Text(receipt.status.rawValue+" · "+receipt.createdAt.formatted(date:.abbreviated,time:.shortened)).foregroundStyle(Theme.muted) }.font(.system(size:11)) };if store.state.receipts.isEmpty { Text("No imports yet").foregroundStyle(Theme.muted).font(.system(size:11)) } }.padding(14).frame(maxWidth:.infinity,alignment:.leading)
            }
        }
    }
    func latest(_ key:Signal) -> Double? { store.latestObservation(key)?.value }
}
struct SignalsView:View {
    @EnvironmentObject var store:AppStore
    @State private var selectedDate:Date?
    @State private var availableWidth:CGFloat = 0
    var body:some View {
        if let trip = store.selectedTrip {
            VStack(alignment:.leading,spacing:14) {
                HStack { Label("Historical recording · \(trip.source)",systemImage:"clock").foregroundStyle(Theme.muted);Spacer();Picker("Recording",selection:Binding(get:{Optional(trip.id)},set:{store.selectedTripID = $0})) { ForEach(store.vehicleTrips) { item in Text(item.name).tag(Optional(item.id)) } }.frame(maxWidth:340) }.font(.system(size:12))
                LazyVGrid(columns:Array(repeating:GridItem(.flexible(minimum:290)),count:availableWidth>1050 ? 3:2),spacing:14) {
                    ForEach(Array(store.preferences.signals.enumerated()),id:\.offset) { index,signal in
                        Panel(title:"Signal card \(index+1)",icon:"slider.horizontal.3") {
                            Picker("Reading",selection:Binding(get:{store.preferences.signals[index]},set:{value in store.changePreferences{$0.signals[index] = value}})) { ForEach(Signal.allCases) { s in Text(s.title).tag(s) } }.accessibilityLabel("Reading for signal card \(index+1)").padding(12)
                            HStack(alignment:.firstTextBaseline) { Text(number(value(trip,signal),digits:signal == .rpm ? 0:1)).font(.system(size:30,weight:.medium,design:.monospaced));Text(signal.unit).font(.system(size:11)).foregroundStyle(Theme.muted) }.frame(maxWidth:.infinity,alignment:.leading).padding(.horizontal,14)
                            SignalChart(trip:trip,signal:signal,selectedDate:$selectedDate,height:150)
                        }
                    }
                }
                Text("Cards are independent and can show duplicate signals. Drag the chart to inspect a timestamp; values are not carried across recording gaps.").font(.system(size:11)).foregroundStyle(Theme.muted)
            }.background {
                GeometryReader { geometry in Color.clear.onAppear { availableWidth = geometry.size.width }.onChange(of:geometry.size.width) { _,width in availableWidth = width } }
            }
        } else { EmptyPanel(title:"No signals recorded yet",message:"Import a diagnostic or telemetry recording. Raw CAN requires a decoder before it can provide vehicle readings.") }
    }
    func value(_ trip:Trip,_ key:Signal) -> Double? {
        let points = trip.samples.filter{$0.value(key) != nil}
        guard let date = selectedDate else { return points.last?.value(key) }
        guard let nearest = points.min(by:{abs($0.timestamp.timeIntervalSince(date))<abs($1.timestamp.timeIntervalSince(date))}),abs(nearest.timestamp.timeIntervalSince(date))<=10 else { return nil };return nearest.value(key)
    }
}
