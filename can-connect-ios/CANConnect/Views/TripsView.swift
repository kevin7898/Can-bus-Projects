import SwiftUI
import UniformTypeIdentifiers
import Charts

private struct HistoricalSignalChoice:Identifiable,Hashable {
    var key:String
    var title:String
    var unit:String
    var id:String { key }
    static let all:[Self] = [
        .init(key:"speedKph",title:"Vehicle speed",unit:"km/h"),.init(key:"rpm",title:"Engine speed",unit:"rpm"),
        .init(key:"coolantC",title:"Coolant",unit:"°C"),.init(key:"boostKpa",title:"Gauge boost",unit:"kPa gauge"),
        .init(key:"boostAbsoluteKpa",title:"Boost pressure A",unit:"kPa absolute"),.init(key:"barometricKpa",title:"Barometric pressure",unit:"kPa absolute"),
        .init(key:"fuelRateLph",title:"Fuel rate",unit:"L/h"),.init(key:"fuelPercent",title:"Fuel level",unit:"%"),
        .init(key:"dpfRegenTrigger",title:"DPF regen trigger · normalized",unit:"%"),.init(key:"dpfSootG",title:"DPF soot mass",unit:"g")
    ]
    static func choice(_ key:String)->Self { all.first(where:{$0.key==key}) ?? .init(key:key,title:key,unit:"") }
}

private enum JourneyDateFilter:String,CaseIterable,Identifiable {
    case all,seven,thirty
    var id:String { rawValue }
    var title:String { switch self { case .all:"Any date";case .seven:"Last 7 days";case .thirty:"Last 30 days" } }
    var interval:TimeInterval? { switch self { case .all:nil;case .seven:7*86_400;case .thirty:30*86_400 } }
}

private enum JourneySourceFilter:String,CaseIterable,Identifiable {
    case all,gps,obd,imported,synthetic
    var id:String { rawValue }
    var title:String { rawValue == "all" ? "Any source":rawValue.uppercased() }
}

private enum JourneyQualityFilter:String,CaseIterable,Identifiable {
    case all,complete,degraded,limited
    var id:String { rawValue }
    var title:String { rawValue == "all" ? "Any quality":rawValue.capitalized }
}

struct TripsView:View {
    @EnvironmentObject private var store:AppStore
    @Binding var filter:Int
    @Binding var page:Int
    @State private var selected:Trip?
    @State private var vehicleID:UUID?
    @State private var dateFilter:JourneyDateFilter = .all
    @State private var sourceFilter:JourneySourceFilter = .all
    @State private var purpose:DriveLineJourneyPurpose?
    @State private var quality:JourneyQualityFilter = .all

    private var filteredTrips:[Trip] {
        store.state.trips.sorted { $0.startedAt > $1.startedAt }.filter { trip in
            let summary=DriveLineJourneyPolicy.summary(for:trip.sharedRecording)
            let annotation=store.journeyAnnotation(for:trip.id)
            let sourceMatch=sourceFilter == .all || trip.sharedRecording.sourceIDs.contains(sourceFilter.rawValue)
            let qualityMatch=quality == .all || summary.quality.rawValue == quality.rawValue
            let vehicleMatch=vehicleID == nil || trip.vehicleID == vehicleID
            let dateMatch=dateFilter.interval.map { trip.startedAt >= Date().addingTimeInterval(-$0) } ?? true
            return sourceMatch && qualityMatch && vehicleMatch && dateMatch && (purpose == nil || annotation.purpose == purpose)
        }
    }

    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            ScrollView(.horizontal,showsIndicators:false) {
                HStack(spacing:8) {
                    filterMenu(title:vehicleID.flatMap { id in store.state.vehicles.first(where:{$0.id==id})?.title } ?? "All vehicles",icon:"car.2") {
                        Button("All vehicles") { vehicleID=nil }
                        ForEach(store.state.vehicles) { vehicle in Button(vehicle.title) { vehicleID=vehicle.id } }
                    }
                    filterMenu(title:dateFilter.title,icon:"calendar") {
                        ForEach(JourneyDateFilter.allCases) { value in Button(value.title) { dateFilter=value } }
                    }
                    filterMenu(title:sourceFilter.title,icon:"antenna.radiowaves.left.and.right") {
                        ForEach(JourneySourceFilter.allCases) { value in Button(value.title) { sourceFilter=value } }
                    }
                    filterMenu(title:purpose?.title ?? "Any purpose",icon:"tag") {
                        Button("Any purpose") { purpose=nil }
                        ForEach(DriveLineJourneyPurpose.allCases) { value in Button(value.title) { purpose=value } }
                    }
                    filterMenu(title:quality.title,icon:"checkmark.shield") {
                        ForEach(JourneyQualityFilter.allCases) { value in Button(value.title) { quality=value } }
                    }
                }.padding(.vertical,1)
            }.accessibilityIdentifier("journey.filters")
            HStack {
                Text("\(filteredTrips.count) journeys").font(.system(size:14,weight:.medium))
                Spacer()
                Text("\(filteredTrips.filter{!$0.isSample}.reduce(0){$0+$1.distanceKM}.text()) km real history").captionStyle()
            }
            if filteredTrips.isEmpty {
                EmptyStateCard(icon:"point.topleft.down.to.point.bottomright.curvepath",title:"No journeys match",message:"Change a filter or record a drive. Sample recordings remain labelled and never count toward real totals.")
            } else {
                ScrollView {
                    LazyVStack(spacing:10) {
                        ForEach(filteredTrips) { trip in
                            JourneyRow(trip:trip,annotation:store.journeyAnnotation(for:trip.id),
                                       transfer:store.state.transfers.first(where:{$0.tripID==trip.id})) { selected=trip }
                        }
                    }.padding(.bottom,4)
                }
            }
        }.onAppear { if vehicleID == nil { vehicleID=store.state.selectedVehicleID } }
            .sheet(item:$selected) { TripStoryView(trip:$0) }
    }

    @ViewBuilder private func filterMenu<Content:View>(title:String,icon:String,@ViewBuilder content:()->Content)->some View {
        Menu(content:content) { Label(title,systemImage:icon).font(.system(size:11,weight:.medium)).padding(.horizontal,10).frame(minHeight:38).background(Palette.raisedSurface,in:Capsule()) }
            .foregroundStyle(Palette.primaryText)
    }
}

private struct JourneyRow:View {
    let trip:Trip
    let annotation:DriveLineJourneyAnnotation
    let transfer:TransferItem?
    let action:()->Void
    private var summary:DriveLineJourneySummary { DriveLineJourneyPolicy.summary(for:trip.sharedRecording) }
    var body:some View {
        Button(action:action) {
            VStack(alignment:.leading,spacing:10) {
                HStack(alignment:.top) {
                    VStack(alignment:.leading,spacing:3) {
                        Text(trip.name).font(.system(size:15,weight:.semibold)).lineLimit(1)
                        Text(trip.startedAt.formatted(date:.abbreviated,time:.shortened)).captionStyle()
                    }
                    Spacer()
                    qualityBadge
                    Image(systemName:"chevron.right").font(.caption).foregroundStyle(Palette.tertiaryText)
                }
                HStack(spacing:12) {
                    Label("\(trip.distanceKM.text()) km",systemImage:"road.lanes")
                    Label(trip.durationText,systemImage:"clock")
                    if let purpose=annotation.purpose { Label(purpose.title,systemImage:"tag") }
                }.font(.system(size:11)).foregroundStyle(Palette.secondaryText)
                HStack(spacing:10) {
                    ForEach(sourceTitles,id:\.self) { SourceBadge(source:$0,verified:true) }
                    Spacer()
                    if let transfer { StatusPill(state:transfer.status == .complete ? .healthy:.queued,text:transfer.status.rawValue.capitalized) }
                    Label(annotation.reviewed ? "Reviewed":"Unreviewed",systemImage:annotation.reviewed ? "checkmark.circle.fill":"circle")
                        .font(.caption2).foregroundStyle(annotation.reviewed ? Palette.healthy:Palette.tertiaryText)
                }
                if annotation.startPlace != nil || annotation.finishPlace != nil {
                    Text("\(annotation.startPlace ?? "Start unknown") → \(annotation.finishPlace ?? "Finish unknown")").captionStyle().lineLimit(1)
                }
            }.padding(14).background(Palette.primarySurface,in:RoundedRectangle(cornerRadius:14))
                .overlay(RoundedRectangle(cornerRadius:14).stroke(Palette.border))
        }.buttonStyle(.plain).accessibilityIdentifier("journey.row.\(trip.id.uuidString)")
    }
    private var sourceTitles:[String] {
        trip.sharedRecording.sourceIDs.map { id in switch id { case "gps":"GPS";case "obd":"OBD";case "synthetic":"Synthetic";default:"Imported" } }
    }
    private var qualityBadge:some View {
        let state:DriveLineSemanticState=summary.quality == .complete ? .healthy:(summary.quality == .unavailable ? .unavailable:.stale)
        return StatusPill(state:state,text:summary.quality.title)
    }
}

struct JSONDocument:FileDocument {
    static var readableContentTypes:[UTType] { [.json] }
    var data:Data
    init(data:Data) { self.data=data }
    init(configuration:ReadConfiguration) throws { data=configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration:WriteConfiguration) throws ->FileWrapper { FileWrapper(regularFileWithContents:data) }
}

struct TripStoryView:View {
    let trip:Trip
    @EnvironmentObject private var store:AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var exporting=false
    @State private var document=JSONDocument(data:Data())
    @State private var delete=false
    @State private var editingAnnotation=false
    @State private var playbackSeconds=0.0
    @State private var signalKeys=["speedKph","rpm","boostKpa"]
    private var summary:DriveLineJourneySummary { DriveLineJourneyPolicy.summary(for:trip.sharedRecording) }
    private var selectedDate:Date { trip.startedAt.addingTimeInterval(playbackSeconds) }
    private var cursor:DriveLineCursorSelection {
        DriveLineJourneyPolicy.cursor(at:selectedDate,recording:trip.sharedRecording,
                                      signalKeys:["speedKph","rpm","coolantC","fuelRateLph","dpfRegenTrigger"])
    }
    private var events:[DriveLineTripEvent] { DriveLineJourneyPolicy.timeline(for:trip.sharedRecording) }
    private var annotation:DriveLineJourneyAnnotation { store.journeyAnnotation(for:trip.id) }
    var body:some View {
        SheetShell(title:"Trip Story") {
            VStack(alignment:.leading,spacing:7) {
                Text(trip.name).font(.title3)
                Text(trip.startedAt.formatted(date:.complete,time:.shortened)).captionStyle()
                HStack { ForEach(trip.sharedRecording.sourceIDs,id:\.self) { SourceBadge(source:$0.uppercased(),verified:true) };Spacer();StatusPill(state:summary.quality == .complete ? .healthy:.stale,text:summary.quality.title) }
            }
            if !trip.route.isEmpty { NativeRouteMap(route:trip.route,selectedPoint:selectedRoutePoint).frame(height:230).clipShape(RoundedRectangle(cornerRadius:14)) }
            else { EmptyStateCard(icon:"map",title:"Route unavailable",message:"This recording has no saved GPS coordinates. No route is inferred from scanner data.") }
            VStack(spacing:8) {
                Slider(value:$playbackSeconds,in:0...max(0.001,trip.duration)).accessibilityLabel("Shared trip playback position")
                HStack { Text(selectedDate.formatted(date:.omitted,time:.standard)).monospacedDigit();Spacer();Text("\(Int(playbackSeconds))s of \(Int(trip.duration))s").captionStyle() }
            }.padding(12).background(Palette.fieldSurface,in:RoundedRectangle(cornerRadius:12))
            HStack { Metric(title:"Measured distance",value:summary.metrics.distanceKm?.text() ?? "—",unit:"km");Metric(title:"Duration",value:trip.durationText) }
            HStack { Metric(title:"Trip economy",value:summary.metrics.economyL100Km?.text() ?? "—",unit:"L/100 km");Metric(title:"Measured trip fuel",value:summary.metrics.tripFuelLitres?.text(2) ?? "—",unit:"L") }
            InfoNote(text:summary.statement,icon:"checkmark.shield")
            SectionCard(title:"Start and finish",icon:"mappin.and.ellipse") {
                DataRow(label:"Start",value:annotation.startPlace ?? "Place unavailable")
                DataRow(label:"Finish",value:annotation.finishPlace ?? "Place unavailable")
            }
            SectionCard(title:"Coverage and selected evidence",icon:"waveform.path.ecg") {
                HStack { coverage("GPS",summary.gpsCoverage);coverage("OBD",summary.obdCoverage) }
                ForEach(["speedKph","rpm","coolantC","fuelRateLph","dpfRegenTrigger"],id:\.self) { key in
                    let observation=cursor.observations[key]
                    DataRow(label:signalTitle(key),value:observation.map { valueText(key,$0.value)+" · "+$0.timestamp.formatted(date:.omitted,time:.standard) } ?? "Unavailable at cursor")
                }
                if cursor.gpsPoint == nil { InfoNote(text:"No GPS observation is close enough to the shared cursor. The map does not forward-fill a position.",icon:"location.slash") }
            }
            SectionCard(title:"Synchronized signals",icon:"chart.xyaxis.line") {
                ForEach(signalKeys.indices,id:\.self) { index in
                    let choice=HistoricalSignalChoice.choice(signalKeys[index])
                    Picker("Signal \(index+1)",selection:$signalKeys[index]) { ForEach(HistoricalSignalChoice.all) { option in Text(option.title).tag(option.key) } }
                    PhoneSignalChart(trip:trip,choice:choice,playbackSeconds:$playbackSeconds)
                }
                InfoNote(text:"Signal choices are independent, including duplicates. Lines use real observation times, break at gaps, and never smooth or forward-fill missing values.")
            }
            SectionCard(title:"Evidence timeline",icon:"list.bullet.rectangle") {
                ForEach(events) { event in
                    Button { playbackSeconds=min(max(0,event.timestamp.timeIntervalSince(trip.startedAt)),trip.duration) } label: {
                        HStack(alignment:.top,spacing:10) {
                            Image(systemName:event.severity == .attention ? "exclamationmark.triangle.fill":"circle.fill").foregroundStyle(event.severity == .attention ? Palette.fuelAttention:Palette.cobalt).font(.caption)
                            VStack(alignment:.leading,spacing:3) { Text(event.note ?? event.kind).foregroundStyle(Palette.primaryText);Text(event.timestamp.formatted(date:.omitted,time:.standard)+(event.endTimestamp.map { " – "+$0.formatted(date:.omitted,time:.standard) } ?? "")).captionStyle() }
                            Spacer();Image(systemName:"scope").foregroundStyle(Palette.tertiaryText)
                        }.frame(minHeight:40)
                    }.buttonStyle(.plain)
                }
                if let transfer=store.state.transfers.first(where:{$0.tripID==trip.id}) {
                    HStack { Image(systemName:"arrow.up.circle");Text("Transfer \(transfer.status.rawValue): \(transfer.message)");Spacer();StatusPill(state:transfer.status == .complete ? .healthy:.queued) }.font(.caption)
                }
            }
            if let samples=trip.samples,!samples.isEmpty {
                DisclosureGroup("Raw command and reply evidence · \(samples.count)") {
                    VStack(alignment:.leading,spacing:8) {
                        ForEach(Array(samples.prefix(30).enumerated()),id:\.offset) { _,sample in
                            VStack(alignment:.leading,spacing:3) { Text("\(sample.timestamp.formatted(date:.omitted,time:.standard)) · \(sample.command)").font(.caption.weight(.semibold));Text(sample.reply).font(.caption2.monospaced()).textSelection(.enabled).lineLimit(4) }.frame(maxWidth:.infinity,alignment:.leading).padding(8).background(Palette.fieldSurface,in:RoundedRectangle(cornerRadius:8))
                        }
                        if samples.count>30 { Text("Showing the first 30 preserved replies. Export includes every observation.").captionStyle() }
                    }.padding(.top,8)
                }
            }
            Button { editingAnnotation=true } label: {
                HStack { Label("Purpose and review",systemImage:"tag");Spacer();Text(store.journeyAnnotation(for:trip.id).purpose?.title ?? "Unclassified").foregroundStyle(Palette.secondaryText);Image(systemName:"chevron.right") }.frame(minHeight:44)
            }
            AppButton(title:"Export preserved recording",icon:"square.and.arrow.up") {
                do { document=JSONDocument(data:try store.archive([trip]).encoded());exporting=true }
                catch { store.error=error.localizedDescription }
            }
            Button("Delete recording",role:.destructive) { delete=true }.frame(maxWidth:.infinity).padding(.top,8)
        }.sheet(isPresented:$editingAnnotation) { JourneyAnnotationEditor(recordingID:trip.id) }
            .fileExporter(isPresented:$exporting,document:document,contentType:.json,defaultFilename:"DriveLine-\(trip.id.uuidString.prefix(8))") { result in if case .failure(let error)=result { store.error=error.localizedDescription } }
            .confirmationDialog("Delete this recording from this iPhone?",isPresented:$delete,titleVisibility:.visible) { Button("Delete recording",role:.destructive) { store.removeTrip(trip.id);dismiss() } }
    }
    private var selectedRoutePoint:RoutePoint? {
        guard let point=cursor.gpsPoint else { return nil }
        return RoutePoint(latitude:point.latitude,longitude:point.longitude,timestamp:point.timestamp,accuracy:point.horizontalAccuracyM ?? 0,speed:point.speedMps)
    }
    private func coverage(_ title:String,_ fraction:Double?)->some View {
        VStack(alignment:.leading,spacing:4) { Text(title).captionStyle();Text(fraction.map { "\(Int(($0*100).rounded()))%" } ?? "—").font(.title3.monospacedDigit()) }.frame(maxWidth:.infinity,alignment:.leading)
    }
    private func signalTitle(_ key:String)->String {
        if key == "dpfRegenTrigger" { return "Regen trigger · normalized" }
        return OBDDecoder.labels[key]?.title ?? key
    }
    private func valueText(_ key:String,_ value:Double)->String {
        let normalized=key == "dpfRegenTrigger" ? DriveLineMetricPolicy.normalizedDPFRegenTrigger(value) ?? value:value
        return "\(normalized.text()) \(OBDDecoder.labels[key]?.unit ?? "")"
    }
}

private struct PhoneSignalChart:View {
    let trip:Trip
    let choice:HistoricalSignalChoice
    @Binding var playbackSeconds:Double
    private var series:DriveLineSignalSeries { DriveLineJourneyPolicy.signalSeries(choice.key,unit:choice.unit,recording:trip.sharedRecording) }
    var body:some View {
        VStack(alignment:.leading,spacing:6) {
            HStack {
                SourceBadge(source:series.provenance == .derived ? "Derived · \(series.algorithmIdentifier ?? "policy")":"Measured",verified:true)
                if let coverage=series.coverage { Text("\(Int((coverage.fraction*100).rounded()))% coverage").captionStyle() }
                Spacer();Text(choice.unit).captionStyle()
            }
            if series.segments.flatMap({$0}).isEmpty { Text("No recorded \(choice.title.lowercased()) observations").captionStyle().frame(maxWidth:.infinity,minHeight:80) }
            else {
                Chart {
                    ForEach(Array(series.segments.enumerated()),id:\.offset) { segment,points in
                        ForEach(points) { point in LineMark(x:.value("Time",point.timestamp),y:.value(choice.unit,point.value),series:.value("Observed segment",segment)).foregroundStyle(series.provenance == .derived ? Palette.fuelAttention:Palette.cobalt) }
                    }
                    ForEach(DriveLineJourneyPolicy.timeline(for:trip.sharedRecording).filter{$0.severity == .attention}) { event in RuleMark(x:.value("Evidence event",event.timestamp)).foregroundStyle(Palette.recordingFault.opacity(0.55)).lineStyle(StrokeStyle(lineWidth:1,dash:[2,3])) }
                    RuleMark(x:.value("Shared cursor",trip.startedAt.addingTimeInterval(playbackSeconds))).foregroundStyle(Palette.tertiaryText).lineStyle(StrokeStyle(lineWidth:1,dash:[3]))
                }.chartXScale(domain:trip.startedAt...max(trip.startedAt.addingTimeInterval(trip.duration),trip.startedAt.addingTimeInterval(0.001)))
                    .frame(height:130).chartLegend(.hidden)
                    .chartOverlay { proxy in GeometryReader { geometry in
                        Rectangle().fill(.clear).contentShape(Rectangle()).gesture(DragGesture(minimumDistance:0).onChanged { value in
                            guard let frame=proxy.plotFrame else { return }
                            let x=value.location.x-geometry[frame].origin.x
                            if let date:Date=proxy.value(atX:x) { playbackSeconds=min(max(0,date.timeIntervalSince(trip.startedAt)),trip.duration) }
                        })
                    } }
            }
        }.padding(.vertical,5)
    }
}

typealias TripDetailView = TripStoryView

private struct JourneyAnnotationEditor:View {
    let recordingID:UUID
    @EnvironmentObject private var store:AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var value:DriveLineJourneyAnnotation
    init(recordingID:UUID) { self.recordingID=recordingID;_value=State(initialValue:DriveLineJourneyAnnotation(recordingID:recordingID)) }
    var body:some View {
        SheetShell(title:"Journey details") {
            Picker("Purpose",selection:$value.purpose) {
                Text("Unclassified").tag(Optional<DriveLineJourneyPurpose>.none)
                ForEach(DriveLineJourneyPurpose.allCases) { purpose in Text(purpose.title).tag(Optional(purpose)) }
            }
            Toggle("Reviewed",isOn:$value.reviewed)
            TextField("Start place, when known",text:optional($value.startPlace)).textFieldStyle(.roundedBorder)
            TextField("Finish place, when known",text:optional($value.finishPlace)).textFieldStyle(.roundedBorder)
            TextField("Note",text:optional($value.note),axis:.vertical).lineLimit(2...5).textFieldStyle(.roundedBorder)
            InfoNote(text:"Saved locally as sidecar metadata. It does not alter the original recording or queued transfer payload, and is not synchronized to another device.")
            AppButton(title:"Save locally",icon:"checkmark") { store.saveJourneyAnnotation(value);dismiss() }
        }.onAppear { value=store.journeyAnnotation(for:recordingID) }
    }
    private func optional(_ binding:Binding<String?>)->Binding<String> {
        Binding(get:{binding.wrappedValue ?? ""},set:{binding.wrappedValue=$0.isEmpty ? nil:$0})
    }
}

#if DEBUG
#Preview("Journey Ledger · Sample data") { DriveLineCanvas(tab:.drives) }
#endif
