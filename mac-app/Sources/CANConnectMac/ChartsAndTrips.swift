import SwiftUI
import Charts
import Combine

struct SignalChart:View {
    let trip:Trip
    let signal:Signal
    @Binding var selectedDate:Date?
    var height:CGFloat = 160
    var body:some View {
        let values = trip.trace(signal)
        VStack(alignment:.leading,spacing:6) {
            HStack { Text(signal.title); Spacer(); Text(signal.unit).foregroundStyle(Theme.muted) }.font(.system(size:11))
            if values.isEmpty { Text("No recorded \(signal.title.lowercased()) signal").font(.system(size:12)).foregroundStyle(Theme.muted).frame(maxWidth:.infinity,maxHeight:.infinity) }
            else {
                Chart {
                    ForEach(values) { point in
                        if let value = point.sample.value(signal) { LineMark(x:.value("Time",point.sample.timestamp),y:.value(signal.unit,value),series:.value("Recorded segment",point.segment)).foregroundStyle(Theme.blue) }
                    }
                    if let selectedDate = selectedDate { RuleMark(x:.value("Playback",selectedDate)).foregroundStyle(Theme.muted).lineStyle(StrokeStyle(lineWidth:1,dash:[3])) }
                }.chartLegend(.hidden).chartXScale(domain:trip.start...max(trip.end,trip.start.addingTimeInterval(0.001)))
                    .chartOverlay { proxy in GeometryReader { geometry in
                        Rectangle().fill(Color.clear).contentShape(Rectangle()).gesture(DragGesture(minimumDistance:0).onChanged { value in
                            guard let frame = proxy.plotFrame else { return }
                            let x = value.location.x-geometry[frame].origin.x
                            if let date:Date = proxy.value(atX:x) { selectedDate = min(max(date,trip.start),trip.end) }
                        })
                    } }
            }
        }.padding(13).frame(height:height)
    }
}
struct TripStats:View {
    let trip:Trip
    var body:some View {
        LazyVGrid(columns:[GridItem(.adaptive(minimum:105),alignment:.leading)],alignment:.leading,spacing:14) {
            stat(number(trip.distanceKm),"km recorded")
            stat(duration(trip.duration),"duration")
            stat(number(trip.economyL100),"L/100 km")
            stat(number(trip.fuelUsedL,digits:2),"litres used")
            if trip.rawFrameCount>0 { stat(String(trip.rawFrameCount),"raw frames") }
        }.padding(14).frame(maxWidth:.infinity,alignment:.leading)
    }
    func stat(_ value:String,_ caption:String) -> some View { VStack(alignment:.leading,spacing:4) { Text(value).font(.system(size:21,weight:.medium,design:.monospaced)); Text(caption).font(.system(size:10)).foregroundStyle(Theme.muted) } }
}
struct TripRow:View {
    let trip:Trip
    let annotation:DriveLineJourneyAnnotation
    var selected = false
    var action:()->Void
    var body:some View {
        Button(action:action) {
            VStack(alignment:.leading,spacing:7) {
                HStack {
                    VStack(alignment:.leading,spacing:4) { Text(trip.name).font(.system(size:12,weight:.medium)).lineLimit(2); Text(trip.start.formatted(date:.abbreviated,time:.shortened)+" · "+trip.source).font(.system(size:10)).foregroundStyle(Theme.muted) }
                    Spacer()
                    Text(number(trip.distanceKm)+" km").font(.system(size:12,design:.monospaced))
                    Text(duration(trip.duration)).font(.system(size:11)).foregroundStyle(Theme.muted).frame(width:60,alignment:.trailing)
                }
                HStack(spacing:8) {
                    let summary=DriveLineJourneyPolicy.summary(for:trip.sharedRecording)
                    StatusPill(state:summary.quality == .complete ? .healthy:(summary.quality == .unavailable ? .unavailable:.stale),text:summary.quality.title)
                    if let purpose=annotation.purpose { Label(purpose.title,systemImage:"tag") }
                    Spacer()
                    Label(annotation.reviewed ? "Reviewed":"Unreviewed",systemImage:annotation.reviewed ? "checkmark.circle.fill":"circle")
                    if trip.isDemo { Text("SAMPLE").foregroundStyle(Theme.cobalt) }
                }.font(.system(size:9)).foregroundStyle(Theme.secondaryText)
            }.padding(12).background(selected ? Theme.blue.opacity(0.17) : Color.clear).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}
struct TripsView:View {
    @EnvironmentObject var store:AppStore
    @State private var viewport = MapViewport()
    @State private var playSeconds = 0.0
    @State private var playing = false
    @State private var selectedDate:Date?
    @State private var signal = Signal.speedKph
    @State private var dateDays=0
    @State private var source="all"
    @State private var purpose="all"
    @State private var quality="all"
    @State private var editingAnnotation=false
    let timer = Timer.publish(every:0.25,on:.main,in:.common).autoconnect()
    var filteredTrips:[Trip] {
        store.vehicleTrips.filter { trip in
            let annotation=store.journeyAnnotation(for:trip.id)
            let summary=DriveLineJourneyPolicy.summary(for:trip.sharedRecording)
            let dateMatch=dateDays == 0 || trip.end >= Date().addingTimeInterval(-Double(dateDays)*86_400)
            return dateMatch && (source == "all" || trip.sharedRecording.sourceIDs.contains(source)) &&
                (purpose == "all" || annotation.purpose?.rawValue == purpose) &&
                (quality == "all" || summary.quality.rawValue == quality)
        }
    }
    var body:some View {
        if let trip = filteredTrips.first(where:{$0.id==store.selectedTripID}) ?? filteredTrips.first {
            VStack(alignment:.leading,spacing:12) {
                filterBar
                HStack(alignment:.top,spacing:14) {
                Panel(title:"Journey Ledger · \(filteredTrips.count)") { ScrollView { LazyVStack(spacing:0) { ForEach(filteredTrips) { item in TripRow(trip:item,annotation:store.journeyAnnotation(for:item.id),selected:item.id==trip.id) { store.selectedTripID = item.id } } } }.frame(maxHeight:700) }.frame(width:310)
                VStack(spacing:14) {
                    Panel(title:trip.name,icon:trip.isDemo ? "testtube.2" : "route") {
                        MapPanel(trips:[trip],viewport:$viewport,style:store.preferences.mapStyle,height:330,marker:playbackSample(trip))
                        TripStats(trip:trip)
                        HStack { Text(trip.source).foregroundStyle(Theme.muted);Spacer();Button("Purpose and review") { editingAnnotation=true };Button("Export JSON") { store.export(trip) }; Button("Export CSV") { store.export(trip,asJSON:false) } }.font(.system(size:11)).padding(12)
                    }
                    Panel(title:"Drive playback") {
                        HStack { Picker("Signal",selection:$signal) { ForEach(Signal.allCases) { s in Text(s.title).tag(s) } }.frame(maxWidth:300); Spacer(); Text("Historical recording").foregroundStyle(Theme.muted) }.font(.system(size:11)).padding(12)
                        SignalChart(trip:trip,signal:signal,selectedDate:$selectedDate)
                        HStack {
                            Button { if playSeconds>=trip.duration { playSeconds = 0 }; playing.toggle() } label: { Image(systemName:playing ? "pause.fill" : "play.fill") }.help("Play or pause").accessibilityLabel(playing ? "Pause playback":"Play playback")
                            Text(duration(playSeconds)).monospacedDigit().frame(width:65)
                            Slider(value:$playSeconds,in:0...max(0.001,trip.duration)).accessibilityLabel("Playback position").onChange(of:playSeconds) { _,value in selectedDate = trip.start.addingTimeInterval(value) }
                            Text(duration(trip.duration)).monospacedDigit()
                        }.font(.system(size:11)).padding(12)
                    }
                    if trip.rawFrameCount>0 { Panel(title:"Raw CAN IDs · no decoder applied") { ForEach(trip.arbitrationIDs.keys.sorted(),id:\.self) { key in KeyValue(label:key,value:String(trip.arbitrationIDs[key] ?? 0)+" frames").padding(.horizontal,14).padding(.vertical,5) } } }
                }
                }
            }.id(trip.id).onAppear { viewport = RouteMap.fitted([trip]); selectedDate = trip.start; playSeconds = 0 }
                .onChange(of:trip.id) { _,_ in viewport = RouteMap.fitted([trip]); playSeconds = 0; playing = false; selectedDate = trip.start }
                .onReceive(timer) { _ in guard playing else { return }; playSeconds = min(trip.duration,playSeconds+0.25); if playSeconds>=trip.duration { playing = false } }
                .onChange(of:selectedDate) { _,date in if let date = date { playSeconds = min(max(0,date.timeIntervalSince(trip.start)),trip.duration) } }
                .sheet(isPresented:$editingAnnotation) { MacJourneyAnnotationEditor(recordingID:trip.id).environmentObject(store) }
        } else { EmptyStateCard(icon:"point.topleft.down.to.point.bottomright.curvepath",title:"No journeys match",message:"Choose another vehicle or change the date, source, purpose, or quality filter. Sample content is always labelled and excluded from real totals.") }
    }
    var filterBar:some View {
        HStack(spacing:10) {
            Picker("Date",selection:$dateDays) { Text("Any date").tag(0);Text("7 days").tag(7);Text("30 days").tag(30) }.frame(width:120)
            Picker("Source",selection:$source) { Text("Any source").tag("all");Text("GPS").tag("gps");Text("OBD").tag("obd");Text("Imported").tag("imported");Text("Synthetic").tag("synthetic") }.frame(width:135)
            Picker("Purpose",selection:$purpose) { Text("Any purpose").tag("all");ForEach(DriveLineJourneyPurpose.allCases) { Text($0.title).tag($0.rawValue) } }.frame(width:140)
            Picker("Quality",selection:$quality) { Text("Any quality").tag("all");ForEach(DriveLineJourneyQuality.allCases,id:\.self) { Text($0.title).tag($0.rawValue) } }.frame(width:165)
            Spacer()
            Text("Vehicle: \(store.selectedVehicle?.name ?? "None")").foregroundStyle(Theme.secondaryText)
        }.font(.system(size:11)).accessibilityIdentifier("mac.journey.filters")
    }
    func playbackSample(_ trip:Trip) -> TelemetrySample? {
        guard let date = selectedDate else { return nil }
        let closest = trip.coordinates.min { abs($0.timestamp.timeIntervalSince(date))<abs($1.timestamp.timeIntervalSince(date)) }
        guard let closest = closest,abs(closest.timestamp.timeIntervalSince(date))<=10 else { return nil }; return closest
    }
}

private struct MacJourneyAnnotationEditor:View {
    let recordingID:UUID
    @EnvironmentObject private var store:AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var value:DriveLineJourneyAnnotation
    init(recordingID:UUID) { self.recordingID=recordingID;_value=State(initialValue:DriveLineJourneyAnnotation(recordingID:recordingID)) }
    var body:some View {
        VStack(alignment:.leading,spacing:16) {
            Text("Journey details").font(.title2.weight(.semibold))
            Picker("Purpose",selection:$value.purpose) {
                Text("Unclassified").tag(Optional<DriveLineJourneyPurpose>.none)
                ForEach(DriveLineJourneyPurpose.allCases) { Text($0.title).tag(Optional($0)) }
            }
            Toggle("Reviewed",isOn:$value.reviewed)
            TextField("Start place, when known",text:optional($value.startPlace))
            TextField("Finish place, when known",text:optional($value.finishPlace))
            TextField("Note",text:optional($value.note),axis:.vertical).lineLimit(3...6)
            Text("Stored only in this Mac library as sidecar metadata. The preserved original and import receipt hash remain unchanged.").font(.caption).foregroundStyle(Theme.secondaryText)
            HStack { Spacer();Button("Cancel",role:.cancel) { dismiss() };Button("Save locally") { store.saveJourneyAnnotation(value);dismiss() }.keyboardShortcut(.defaultAction) }
        }.padding(24).frame(width:460).onAppear { value=store.journeyAnnotation(for:recordingID) }
    }
    private func optional(_ binding:Binding<String?>)->Binding<String> {
        Binding(get:{binding.wrappedValue ?? ""},set:{binding.wrappedValue=$0.isEmpty ? nil:$0})
    }
}
struct CompareView:View {
    @EnvironmentObject var store:AppStore
    @State private var a:UUID?
    @State private var b:UUID?
    @State private var viewport = MapViewport()
    @State private var selectedDate:Date?
    var body:some View {
        if store.vehicleTrips.count<2 { EmptyPanel(title:"Two recordings needed",message:"Import at least two recordings for the selected vehicle to compare them.") }
        else {
            VStack(alignment:.leading,spacing:14) {
                Label("Maps share zoom and center. Each drive selection remains independent.",systemImage:"link").font(.system(size:12)).foregroundStyle(Theme.muted)
                HStack(alignment:.top,spacing:14) { comparison("Drive A",selection:$a,fallback:0); comparison("Drive B",selection:$b,fallback:1) }
            }.onAppear { a = a ?? store.vehicleTrips.first?.id; b = b ?? store.vehicleTrips.dropFirst().first?.id; viewport = RouteMap.fitted(store.vehicleTrips) }
        }
    }
    @ViewBuilder func comparison(_ title:String,selection:Binding<UUID?>,fallback:Int) -> some View {
        if let trip = store.vehicleTrips.first(where:{$0.id==selection.wrappedValue}) ?? store.vehicleTrips.dropFirst(fallback).first {
            Panel(title:title) {
                Picker(title,selection:selection) { ForEach(store.vehicleTrips) { t in Text(t.name+" · "+t.start.formatted(date:.abbreviated,time:.shortened)).tag(Optional(t.id)) } }.accessibilityLabel(title).padding(12)
                MapPanel(trips:[trip],viewport:$viewport,style:store.preferences.mapStyle,height:350)
                TripStats(trip:trip)
                SignalChart(trip:trip,signal:.speedKph,selectedDate:$selectedDate,height:180)
                Text(trip.source).font(.system(size:10)).foregroundStyle(Theme.muted).padding(12)
            }
        }
    }
}
