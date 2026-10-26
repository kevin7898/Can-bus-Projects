import SwiftUI
import UniformTypeIdentifiers
import Charts

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
private enum SignalChartInteraction:String,CaseIterable,Identifiable {
    case scrub,pan
    var id:String { rawValue }
    var title:String { rawValue.capitalized }
}

struct SignalsView:View {
    @EnvironmentObject private var store:AppStore
    @State private var selectedDate:Date?
    @State private var viewport=MapViewport()
    @State private var search=""
    @State private var targetLane=0
    @State private var alignment=DriveLineSignalAlignment.elapsedTime
    @State private var visibleRange:ClosedRange<Double> = 0...1
    @State private var interaction=SignalChartInteraction.scrub
    @State private var comparing=CommandLine.arguments.contains("--phase6-compare")
    @State private var comparisonID:UUID?

    private var trip:Trip? { store.selectedTrip }
    private var comparison:Trip? {
        guard comparing,let trip else { return nil }
        return store.vehicleTrips.first { $0.id == comparisonID && DriveLineJourneyPolicy.comparisonIneligibility(primary:trip.sharedRecording,candidate:$0.sharedRecording) == nil }
    }
    private var laneKeys:[String] { store.preferences.resolvedSignalKeys }
    private var evidenceRender:Bool {
        #if DEBUG
        CommandLine.arguments.contains("--phase6-render-directory")
        #else
        false
        #endif
    }

    var body:some View {
        if let trip {
            VStack(alignment:.leading,spacing:14) {
                controls(trip)
                if alignment == .travelledDistance || !distanceAvailability(trip).isAvailable {
                    Label(distanceAvailability(trip).explanation,systemImage:distanceAvailability(trip).isAvailable ? "point.bottomleft.forward.to.point.topright.scurvepath":"location.slash")
                        .font(.system(size:10)).foregroundStyle(distanceAvailability(trip).isAvailable ? Theme.secondaryText:Theme.fuelAttention)
                }
                if evidenceRender {
                    SignalsEvidenceRoutePanel(trips:[trip]+(comparison.map{[$0]} ?? []),marker:playbackSample(trip)).frame(height:245)
                } else {
                    MapPanel(trips:[trip]+(comparison.map{[$0]} ?? []),viewport:$viewport,style:store.preferences.mapStyle,
                             height:245,marker:playbackSample(trip))
                }
                HStack(alignment:.top,spacing:14) {
                    signalBrowser(trip).frame(width:270)
                    LazyVGrid(columns:[GridItem(.adaptive(minimum:430),spacing:14)],spacing:14) {
                        ForEach(Array(laneKeys.enumerated()),id:\.offset) { index,key in
                            MacSignalLane(index:index,key:key,trip:trip,comparison:comparison,alignment:alignment,
                                          visibleRange:$visibleRange,selectedDate:$selectedDate,interaction:interaction)
                                .onTapGesture { targetLane=index }
                        }
                    }.frame(maxWidth:.infinity)
                }
                if let raw=rawEvidence(trip) {
                    DisclosureGroup("Raw diagnostic evidence at shared cursor") {
                        VStack(alignment:.leading,spacing:6) {
                            Text(raw.command ?? "Command unavailable").font(.system(size:10,weight:.semibold,design:.monospaced))
                            Text(raw.reply ?? "Reply unavailable").font(.system(size:9,design:.monospaced)).textSelection(.enabled)
                            Text("Observed \(raw.timestamp.formatted(date:.omitted,time:.standard)); no interpolation or credential data added.").font(.system(size:9)).foregroundStyle(Theme.secondaryText)
                        }.padding(12)
                    }
                }
                Text("Six independent lanes may intentionally repeat a signal. Statistics use finite observations in the visible range; ‘average’ means arithmetic mean of recorded observations, never a time-weighted estimate. Gaps remain gaps.")
                    .font(.system(size:11)).foregroundStyle(Theme.muted)
            }
            .onAppear { initialize(trip,fitMap:true) }
            .onChange(of:trip.id) { _,_ in initialize(trip,fitMap:true) }
            .onChange(of:alignment) { _,_ in resetRange(trip) }
            .onChange(of:comparing) { _,enabled in
                if enabled,comparisonID == nil {
                    comparisonID=store.vehicleTrips.first(where:{$0.id != trip.id})?.id
                }
                resetRange(trip)
            }
            .onChange(of:comparisonID) { _,_ in resetRange(trip) }
            .accessibilityIdentifier("mac.signals.workspace")
        } else {
            EmptyPanel(title:"No signals recorded yet",message:"Import a diagnostic, GPS, or telemetry recording. Unknown stable identifiers remain visible; unsupported metadata stays unavailable.")
        }
    }

    @ViewBuilder private func controls(_ trip:Trip)->some View {
        VStack(alignment:.leading,spacing:10) {
            HStack(spacing:10) {
                if evidenceRender {
                    Label(trip.name,systemImage:"record.circle").padding(.horizontal,10).padding(.vertical,6).background(Theme.fieldSurface,in:RoundedRectangle(cornerRadius:6))
                    StatusPill(state:comparing ? .queued:.ready,text:comparing ? "Comparison active":"Single recording")
                    if let comparison { Label(comparison.name,systemImage:"rectangle.on.rectangle").foregroundStyle(Theme.fuelAttention) }
                } else {
                    Picker("Recording",selection:Binding(get:{Optional(trip.id)},set:{store.selectedTripID=$0})) {
                        ForEach(store.vehicleTrips) { item in Text(item.name+" · "+item.start.formatted(date:.abbreviated,time:.shortened)).tag(Optional(item.id)) }
                    }.frame(maxWidth:330).accessibilityIdentifier("mac.signals.recording")
                    Toggle("Compare",isOn:$comparing).toggleStyle(.switch).accessibilityIdentifier("mac.signals.compare")
                    if comparing {
                        Picker("Comparison",selection:$comparisonID) {
                            Text("Choose recording").tag(nil as UUID?)
                            ForEach(store.vehicleTrips.filter{$0.id != trip.id}) { item in Text(item.name+" · "+item.start.formatted(date:.abbreviated,time:.shortened)).tag(Optional(item.id)) }
                        }.frame(maxWidth:300).accessibilityIdentifier("mac.signals.comparison-recording")
                    }
                }
                Spacer()
                Text(selectedDate?.formatted(date:.omitted,time:.standard) ?? "No cursor").monospacedDigit().foregroundStyle(Theme.secondaryText)
            }.font(.system(size:11))
            HStack(spacing:8) {
                ForEach(DriveLineSignalAlignment.allCases) { mode in
                    Button(mode.title) { alignment=mode }
                        .buttonStyle(.borderedProminent).tint(alignment == mode ? Theme.cobalt:Theme.unavailable)
                        .disabled(mode == .travelledDistance && !distanceAvailability(trip).isAvailable)
                        .accessibilityIdentifier("mac.signals.alignment.\(mode.rawValue)")
                }
                Divider().frame(height:20)
                if evidenceRender {
                    Label("Scrub linked cursor",systemImage:"timeline.selection").padding(.horizontal,8).padding(.vertical,5).background(Theme.fieldSurface,in:RoundedRectangle(cornerRadius:6))
                } else {
                    Picker("Chart gesture",selection:$interaction) { ForEach(SignalChartInteraction.allCases) { Text($0.title).tag($0) } }
                        .pickerStyle(.segmented).frame(width:150)
                }
                Button { zoom(0.65,trip:trip) } label:{Image(systemName:"plus.magnifyingglass")}.help("Zoom in")
                Button { zoom(1.5,trip:trip) } label:{Image(systemName:"minus.magnifyingglass")}.help("Zoom out")
                Button("Reset range") { resetRange(trip) }.accessibilityIdentifier("mac.signals.reset-range")
                Button("Pan back") { pan(-0.3,trip:trip) }
                Button("Pan forward") { pan(0.3,trip:trip) }
                Spacer()
                Button("Fit Route") { viewport=RouteMap.fitted([trip]+(comparison.map{[$0]} ?? [])) }
            }.font(.system(size:10))
        }.padding(12).background(Theme.raised,in:RoundedRectangle(cornerRadius:8))
    }

    private func signalBrowser(_ trip:Trip)->some View {
        Panel(title:"Signal browser",icon:"magnifyingglass") {
            VStack(alignment:.leading,spacing:10) {
                if evidenceRender {
                    HStack { Image(systemName:"magnifyingglass");Text("Search name, ID, alias, source or unit").foregroundStyle(Theme.tertiaryText);Spacer() }
                        .padding(7).background(Theme.fieldSurface,in:RoundedRectangle(cornerRadius:6)).overlay(RoundedRectangle(cornerRadius:6).stroke(Theme.border))
                    Text("Target lane · Lane \(targetLane+1)").font(.system(size:10,weight:.medium))
                } else {
                    TextField("Search name, ID, alias, source or unit",text:$search).textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("mac.signals.search")
                    Picker("Target lane",selection:$targetLane) {
                        ForEach(laneKeys.indices,id:\.self) { Text("Lane \($0+1)").tag($0) }
                    }
                }
                ForEach(DriveLineSignalGroup.allCases) { group in
                    let values=browserDescriptors(trip).filter{$0.group == group}
                    if !values.isEmpty {
                        DisclosureGroup(group.title) {
                            VStack(alignment:.leading,spacing:3) {
                                ForEach(values) { descriptor in
                                    Button { select(descriptor.key,lane:targetLane) } label: {
                                        HStack(alignment:.top) {
                                            VStack(alignment:.leading,spacing:2) {
                                                Text(descriptor.displayName).foregroundStyle(Theme.primaryText)
                                                Text(descriptor.key+(descriptor.unit.map{" · "+$0} ?? " · unit unavailable"))
                                                    .font(.system(size:9,design:.monospaced)).foregroundStyle(Theme.secondaryText)
                                            }
                                            Spacer()
                                            if laneKeys[targetLane] == descriptor.key { Image(systemName:"checkmark.circle.fill").foregroundStyle(Theme.cobalt) }
                                        }.padding(.vertical,4).contentShape(Rectangle())
                                    }.buttonStyle(.plain).accessibilityIdentifier("mac.signals.choice.\(descriptor.key)")
                                }
                            }.padding(.leading,8)
                        }.font(.system(size:11))
                    }
                }
                if browserDescriptors(trip).isEmpty { Text("No signals match this search.").font(.system(size:10)).foregroundStyle(Theme.muted) }
            }.padding(12)
        }
    }

    private func browserDescriptors(_ trip:Trip)->[DriveLineSignalDescriptor] {
        var values=DriveLineJourneyPolicy.signalDescriptors(recording:trip.sharedRecording,query:search,includeUnobservedKnown:true)
        if let comparison {
            for descriptor in DriveLineJourneyPolicy.signalDescriptors(recording:comparison.sharedRecording,query:search) where !values.contains(where:{$0.key == descriptor.key}) {
                values.append(descriptor)
            }
        }
        return values
    }
    private func select(_ key:String,lane:Int) {
        store.changePreferences { preferences in
            var keys=preferences.resolvedSignalKeys
            guard keys.indices.contains(lane) else { return }
            keys[lane]=key;preferences.signalKeys=keys
        }
    }
    private func distanceAvailability(_ trip:Trip)->DriveLineAlignmentAvailability {
        let primary=DriveLineJourneyPolicy.distanceAlignmentAvailability(trip.sharedRecording)
        guard primary.isAvailable,let comparison else { return primary }
        let secondary=DriveLineJourneyPolicy.distanceAlignmentAvailability(comparison.sharedRecording)
        return secondary.isAvailable ? primary:DriveLineAlignmentAvailability(isAvailable:false,
            explanation:"Comparison ‘\(comparison.name)’ cannot use distance alignment. \(secondary.explanation)")
    }
    private func extent(_ trip:Trip)->ClosedRange<Double> {
        let a=DriveLineJourneyPolicy.alignmentExtent(trip.sharedRecording,alignment:alignment) ?? 0...max(0.001,trip.duration)
        guard let comparison,let b=DriveLineJourneyPolicy.alignmentExtent(comparison.sharedRecording,alignment:alignment) else { return a }
        return min(a.lowerBound,b.lowerBound)...max(a.upperBound,b.upperBound)
    }
    private func initialize(_ trip:Trip,fitMap:Bool) {
        selectedDate=trip.start
        if comparisonID == trip.id { comparisonID=nil }
        if comparing,comparisonID == nil { comparisonID=store.vehicleTrips.first(where:{$0.id != trip.id})?.id }
        if fitMap { viewport=RouteMap.fitted([trip]+(comparison.map{[$0]} ?? [])) }
        resetRange(trip)
    }
    private func resetRange(_ trip:Trip) { visibleRange=extent(trip);selectedDate=trip.start }
    private func zoom(_ factor:Double,trip:Trip) {
        let all=extent(trip),span=max(0.0001,visibleRange.upperBound-visibleRange.lowerBound)
        let centre=DriveLineJourneyPolicy.position(at:selectedDate ?? trip.start,recording:trip.sharedRecording,alignment:alignment) ?? (visibleRange.lowerBound+visibleRange.upperBound)/2
        let half=min((all.upperBound-all.lowerBound)/2,span*factor/2)
        let lower=min(max(all.lowerBound,centre-half),max(all.lowerBound,all.upperBound-2*half))
        visibleRange=lower...min(all.upperBound,lower+2*half)
    }
    private func pan(_ fraction:Double,trip:Trip) {
        let all=extent(trip),span=visibleRange.upperBound-visibleRange.lowerBound,shift=span*fraction
        let lower=min(max(all.lowerBound,visibleRange.lowerBound+shift),max(all.lowerBound,all.upperBound-span))
        visibleRange=lower...min(all.upperBound,lower+span)
    }
    private func playbackSample(_ trip:Trip)->TelemetrySample? {
        guard let date=selectedDate else { return nil }
        let latest=trip.coordinates.filter{$0.timestamp <= date}.max(by:{$0.timestamp < $1.timestamp})
        guard let latest,date.timeIntervalSince(latest.timestamp)<=DriveLineMetricPolicy.maximumGPSGap else { return nil }
        return latest
    }
    private func rawEvidence(_ trip:Trip)->TelemetrySample? {
        guard let date=selectedDate else { return nil }
        let latest=trip.samples.filter{($0.command != nil || $0.reply != nil) && $0.timestamp <= date}.max(by:{$0.timestamp < $1.timestamp})
        guard let latest,date.timeIntervalSince(latest.timestamp)<=DriveLineMetricPolicy.maximumSignalGap else { return nil }
        return latest
    }
}

private struct SignalsEvidenceRoutePanel:View {
    let trips:[Trip]
    let marker:TelemetrySample?
    private var points:[TelemetrySample] { trips.flatMap(\.coordinates) }
    var body:some View {
        GeometryReader { proxy in
            ZStack {
                RoundedRectangle(cornerRadius:8).fill(Theme.raised)
                ForEach(Array(trips.enumerated()),id:\.element.id) { index,trip in
                    Path { path in
                        guard let first=trip.coordinates.first else { return }
                        path.move(to:location(first,in:proxy.size))
                        for point in trip.coordinates.dropFirst() { path.addLine(to:location(point,in:proxy.size)) }
                    }.stroke(index == 0 ? Theme.cobalt:Theme.fuelAttention,style:StrokeStyle(lineWidth:4,lineCap:.round,lineJoin:.round))
                }
                if let marker,marker.hasCoordinate {
                    Circle().fill(Theme.primaryText).overlay(Circle().stroke(Theme.raised,lineWidth:2)).frame(width:13,height:13)
                        .position(location(marker,in:proxy.size))
                }
                VStack { HStack { Label("Recorded GPS route",systemImage:"point.bottomleft.forward.to.point.topright.scurvepath").font(.system(size:11,weight:.semibold));Spacer();Text("Sanitized evidence · \(points.count) points").font(.system(size:10)).foregroundStyle(Theme.secondaryText) }.padding(14);Spacer() }
            }.overlay(RoundedRectangle(cornerRadius:8).stroke(Theme.border))
        }.accessibilityIdentifier("mac.signals.map")
    }
    private func location(_ sample:TelemetrySample,in size:CGSize)->CGPoint {
        let latitudes=points.compactMap(\.latitude),longitudes=points.compactMap(\.longitude)
        let minLat=latitudes.min() ?? 0,maxLat=latitudes.max() ?? 1,minLon=longitudes.min() ?? 0,maxLon=longitudes.max() ?? 1
        let x=32+(sample.longitude!-minLon)/max(0.000_001,maxLon-minLon)*(size.width-64)
        let y=32+(maxLat-sample.latitude!)/max(0.000_001,maxLat-minLat)*(size.height-64)
        return CGPoint(x:x,y:y)
    }
}

private struct MacSignalLane:View {
    let index:Int
    let key:String
    let trip:Trip
    let comparison:Trip?
    let alignment:DriveLineSignalAlignment
    @Binding var visibleRange:ClosedRange<Double>
    @Binding var selectedDate:Date?
    let interaction:SignalChartInteraction
    @State private var panOrigin:ClosedRange<Double>?

    private var descriptor:DriveLineSignalDescriptor { DriveLineJourneyPolicy.signalDescriptor(key,recording:trip.sharedRecording) }
    private var series:DriveLineSignalSeries { DriveLineJourneyPolicy.signalSeries(key,unit:descriptor.unit ?? "",recording:trip.sharedRecording) }
    private var cursor:Date { selectedDate ?? trip.start }
    private var stats:DriveLineSignalStatistics { DriveLineJourneyPolicy.signalStatistics(series,recording:trip.sharedRecording,alignment:alignment,visibleRange:visibleRange,at:cursor) }
    private var cursorPosition:Double? { DriveLineJourneyPolicy.position(at:cursor,recording:trip.sharedRecording,alignment:alignment) }

    var body:some View {
        Panel(title:"Lane \(index+1) · \(descriptor.displayName)",icon:"waveform.path.ecg") {
            VStack(alignment:.leading,spacing:9) {
                HStack(alignment:.top) {
                    VStack(alignment:.leading,spacing:3) {
                        Text(key).font(.system(size:9,design:.monospaced)).foregroundStyle(Theme.secondaryText).textSelection(.enabled)
                        HStack(spacing:10) {
                            SourceBadge(source:stats.sourceIDs.isEmpty ? "Source unavailable":stats.sourceIDs.joined(separator:", "),verified:!stats.sourceIDs.isEmpty)
                            Text(series.provenance == .derived ? "Derived":"Measured").foregroundStyle(Theme.secondaryText)
                            if let algorithm=series.algorithmIdentifier { Text("\(algorithm) · v\(series.algorithmVersion ?? "unavailable")").font(.system(size:9,design:.monospaced)).foregroundStyle(Theme.secondaryText) }
                        }
                    }
                    Spacer()
                    StatusPill(state:stats.freshness == .fresh ? .ready:(stats.freshness == .stale ? .stale:.unavailable),text:stats.freshness.title)
                }.font(.system(size:10))
                SignalStatsStrip(name:trip.name,unit:descriptor.unit,coverage:series.coverage?.fraction,stats:stats)
                laneChart
                if let comparison { comparisonEvidence(comparison) }
            }.padding(12)
        }.accessibilityIdentifier("mac.signals.lane.\(index)")
    }

    private var laneChart:some View {
        let primary=DriveLineRenderingPolicy.alignedSegments(DriveLineJourneyPolicy.alignedSegments(series,recording:trip.sharedRecording,alignment:alignment))
        let comparisonSeries=comparison.map { DriveLineJourneyPolicy.signalSeries(key,unit:descriptor.unit ?? "",recording:$0.sharedRecording) }
        let secondary=comparison.flatMap { recording in comparisonSeries.map { DriveLineRenderingPolicy.alignedSegments(DriveLineJourneyPolicy.alignedSegments($0,recording:recording.sharedRecording,alignment:alignment)) } } ?? []
        return Chart {
            ForEach(Array(primary.enumerated()),id:\.offset) { segment,points in
                ForEach(points) { value in
                    LineMark(x:.value(alignment.title,value.position),y:.value(descriptor.unit ?? "Recorded value",value.point.value),series:.value("Primary segment",segment)).foregroundStyle(Theme.cobalt)
                    PointMark(x:.value(alignment.title,value.position),y:.value(descriptor.unit ?? "Recorded value",value.point.value)).foregroundStyle(Theme.cobalt).symbolSize(8)
                }
            }
            ForEach(Array(secondary.enumerated()),id:\.offset) { segment,points in
                ForEach(points) { value in
                    LineMark(x:.value(alignment.title,value.position),y:.value(descriptor.unit ?? "Recorded value",value.point.value),series:.value("Comparison segment",segment+10_000)).foregroundStyle(Theme.fuelAttention)
                    PointMark(x:.value(alignment.title,value.position),y:.value(descriptor.unit ?? "Recorded value",value.point.value)).foregroundStyle(Theme.fuelAttention).symbolSize(8)
                }
            }
            if let cursorPosition { RuleMark(x:.value("Shared recorded cursor",cursorPosition)).foregroundStyle(Theme.primaryText).lineStyle(StrokeStyle(lineWidth:1,dash:[3])) }
        }.chartXScale(domain:visibleRange).chartLegend(.hidden).frame(height:175)
            .chartOverlay { proxy in GeometryReader { geometry in
                Rectangle().fill(.clear).contentShape(Rectangle()).gesture(DragGesture(minimumDistance:0)
                    .onChanged { value in
                        guard let frame=proxy.plotFrame else { return }
                        let width=max(1,geometry[frame].width)
                        if interaction == .scrub {
                            let x=value.location.x-geometry[frame].origin.x
                            if let position:Double=proxy.value(atX:x),let date=DriveLineJourneyPolicy.timestamp(at:position,recording:trip.sharedRecording,alignment:alignment) { selectedDate=date }
                        } else {
                            if panOrigin == nil { panOrigin=visibleRange }
                            guard let start=panOrigin else { return }
                            let span=start.upperBound-start.lowerBound
                            let primary=DriveLineJourneyPolicy.alignmentExtent(trip.sharedRecording,alignment:alignment) ?? start
                            let all:ClosedRange<Double>
                            if let comparison,
                               let secondary=DriveLineJourneyPolicy.alignmentExtent(comparison.sharedRecording,alignment:alignment) {
                                all=min(primary.lowerBound,secondary.lowerBound)...max(primary.upperBound,secondary.upperBound)
                            } else { all=primary }
                            let shift = -Double(value.translation.width/width)*span
                            let lower=min(max(all.lowerBound,start.lowerBound+shift),max(all.lowerBound,all.upperBound-span))
                            visibleRange=lower...min(all.upperBound,lower+span)
                        }
                    }.onEnded { _ in panOrigin=nil })
            } }
    }

    @ViewBuilder private func comparisonEvidence(_ other:Trip)->some View {
        let otherDescriptor=DriveLineJourneyPolicy.signalDescriptor(key,recording:other.sharedRecording)
        let otherSeries=DriveLineJourneyPolicy.signalSeries(key,unit:otherDescriptor.unit ?? "",recording:other.sharedRecording)
        let position=cursorPosition ?? visibleRange.lowerBound
        let date=DriveLineJourneyPolicy.timestamp(at:position,recording:other.sharedRecording,alignment:alignment) ?? other.start
        let otherStats=DriveLineJourneyPolicy.signalStatistics(otherSeries,recording:other.sharedRecording,alignment:alignment,visibleRange:visibleRange,at:date)
        Divider()
        SignalStatsStrip(name:other.name,unit:otherDescriptor.unit,coverage:otherSeries.coverage?.fraction,stats:otherStats,comparison:true)
        Text("Comparison provenance remains independent · \(otherStats.sourceIDs.isEmpty ? "source unavailable":otherStats.sourceIDs.joined(separator:", ")) · \(otherSeries.provenance == .derived ? "derived":"measured")")
            .font(.system(size:9)).foregroundStyle(Theme.secondaryText)
    }
}

private struct SignalStatsStrip:View {
    let name:String
    let unit:String?
    let coverage:Double?
    let stats:DriveLineSignalStatistics
    var comparison=false
    var body:some View {
        VStack(alignment:.leading,spacing:6) {
            HStack { Circle().fill(comparison ? Theme.fuelAttention:Theme.cobalt).frame(width:7,height:7);Text(name).font(.system(size:10,weight:.semibold));Spacer();Text(coverage.map{"\(Int(($0*100).rounded()))% coverage"} ?? "Coverage unavailable").font(.system(size:9)).foregroundStyle(Theme.secondaryText) }
            LazyVGrid(columns:Array(repeating:GridItem(.flexible(),alignment:.leading),count:6),spacing:7) {
                metric("Current",stats.current?.value)
                metric("Minimum",stats.minimum)
                metric("Maximum",stats.maximum)
                metric("Recorded avg",stats.recordedObservationAverage)
                textMetric("Count",String(stats.observationCount))
                textMetric("Latest",stats.latestObservation?.formatted(date:.omitted,time:.standard) ?? "—")
            }
        }
    }
    private func metric(_ title:String,_ value:Double?)->some View { textMetric(title,value.map{number($0,digits:2)+(unit.map{" "+$0} ?? "")} ?? "—") }
    private func textMetric(_ title:String,_ value:String)->some View { VStack(alignment:.leading,spacing:2) { Text(title).font(.system(size:8)).foregroundStyle(Theme.tertiaryText);Text(value).font(.system(size:10,design:.monospaced)).lineLimit(1).minimumScaleFactor(0.65) } }
}
