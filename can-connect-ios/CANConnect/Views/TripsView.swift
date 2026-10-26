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
            let annotation=store.journeyAnnotation(for:trip.id)
            let sourceMatch=sourceFilter == .all || trip.sharedRecording.sourceIDs.contains(sourceFilter.rawValue)
            let qualityMatch=quality == .all || DriveLineJourneyPolicy.summary(for:trip.sharedRecording).quality.rawValue == quality.rawValue
            let vehicleMatch=vehicleID == nil || trip.vehicleID == vehicleID
            let dateMatch=dateFilter.interval.map { trip.startedAt >= Date().addingTimeInterval(-$0) } ?? true
            return sourceMatch && qualityMatch && vehicleMatch && dateMatch && (purpose == nil || annotation.purpose == purpose)
        }
    }

    var body:some View {
        let trips=filteredTrips
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
                Text("\(trips.count) journeys").font(.system(size:14,weight:.medium))
                Spacer()
                Text("\(trips.filter{!$0.isSample}.reduce(0){$0+$1.distanceKM}.text()) km real history").captionStyle()
            }
            if trips.isEmpty {
                EmptyStateCard(icon:"point.topleft.down.to.point.bottomright.curvepath",title:"No journeys match",message:"Change a filter or record a drive. Sample recordings remain labelled and never count toward real totals.")
            } else {
                ScrollView {
                    LazyVStack(spacing:10) {
                        ForEach(trips) { trip in
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
                    if let transfer { StatusPill(state:transfer.status == .complete ? .ready:.queued,text:transfer.status.rawValue.capitalized) }
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
        let state:DriveLineSemanticState=summary.quality == .complete ? .ready:(summary.quality == .unavailable ? .unavailable:.stale)
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var exporting=false
    @State private var document=JSONDocument(data:Data())
    @State private var delete=false
    @State private var editingAnnotation=false
    @State private var signalsOverview=false
    @State private var playbackSeconds=0.0
    @State private var signalKeys=["speedKph","rpm","boostKpa"]
    @State private var snapshot:TripStorySnapshot?
    @State private var snapshotError:String?
    @State private var snapshotRetry=0
    private var annotation:DriveLineJourneyAnnotation { store.journeyAnnotation(for:trip.id) }
    var body:some View {
        let selectedDate=trip.startedAt.addingTimeInterval(playbackSeconds)
        SheetShell(title:"Trip Story") {
            VStack(alignment:.leading,spacing:7) {
                Text(trip.name).font(.title3)
                Text(trip.startedAt.formatted(date:.complete,time:.shortened)).captionStyle()
                if let snapshot { storyStatus(snapshot.summary) }
            }
            if let snapshot {
            let summary=snapshot.summary
            let cursor=snapshot.cursorIndex.selection(at:selectedDate,
                signalKeys:["speedKph","rpm","coolantC","fuelRateLph","dpfRegenTrigger"])
            let selectedRoutePoint=routePoint(cursor.gpsPoint)
            if !snapshot.route.isEmpty { NativeRouteMap(route:snapshot.route,selectedPoint:selectedRoutePoint).frame(height:230).clipShape(RoundedRectangle(cornerRadius:14)) }
            else { EmptyStateCard(icon:"map",title:"Route unavailable",message:"This recording has no saved GPS coordinates. No route is inferred from scanner data.") }
            VStack(spacing:8) {
                Slider(value:$playbackSeconds,in:0...max(0.001,trip.duration)).accessibilityLabel("Shared trip playback position")
                HStack { Text(selectedDate.formatted(date:.omitted,time:.standard)).monospacedDigit();Spacer();Text("\(Int(playbackSeconds))s of \(Int(trip.duration))s").captionStyle() }
            }.padding(12).background(Palette.fieldSurface,in:RoundedRectangle(cornerRadius:12))
            HStack { Metric(title:summary.metrics.distanceIsPartial ? "Partial observed distance":"Measured distance",value:summary.metrics.distanceKm?.text() ?? "—",unit:"km");Metric(title:"Duration",value:trip.durationText) }
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
                    DataRow(label:signalTitle(key),value:observation.map { valueText(key,$0.value)+" · "+$0.sourceID.uppercased()+" · "+$0.timestamp.formatted(date:.omitted,time:.standard) } ?? "Unavailable at cursor")
                }
                if cursor.gpsPoint == nil { InfoNote(text:"No GPS observation is close enough to the shared cursor. The map does not forward-fill a position.",icon:"location.slash") }
            }
            SectionCard(title:"Synchronized signals",icon:"chart.xyaxis.line") {
                ForEach(signalKeys.indices,id:\.self) { index in
                    let choice=HistoricalSignalChoice.choice(signalKeys[index])
                    Picker("Signal \(index+1)",selection:$signalKeys[index]) { ForEach(HistoricalSignalChoice.all) { option in Text(option.title).tag(option.key) } }
                    PhoneSignalChart(trip:trip,choice:choice,events:snapshot.timeline,
                                     prepared:snapshot.signals[choice.key],playbackSeconds:$playbackSeconds)
                }
                InfoNote(text:"Signal choices are independent, including duplicates. Lines use real observation times, break at gaps, and never smooth or forward-fill missing values.")
                Button { signalsOverview=true } label: {
                    HStack { Label("Open complete Signals workspace",systemImage:"waveform.path.ecg");Spacer();Image(systemName:"chevron.right") }.frame(minHeight:44)
                }.accessibilityIdentifier("trip-story.signals")
            }
            SectionCard(title:"Evidence timeline",icon:"list.bullet.rectangle") {
                LazyVStack(alignment:.leading,spacing:8) {
                ForEach(snapshot.timeline) { event in
                    Button { playbackSeconds=min(max(0,event.timestamp.timeIntervalSince(trip.startedAt)),trip.duration) } label: {
                        HStack(alignment:.top,spacing:10) {
                            Image(systemName:event.severity == .attention ? "exclamationmark.triangle.fill":"circle.fill").foregroundStyle(event.severity == .attention ? Palette.fuelAttention:Palette.cobalt).font(.caption)
                            VStack(alignment:.leading,spacing:3) { Text(event.note ?? event.kind).foregroundStyle(Palette.primaryText);Text(event.timestamp.formatted(date:.omitted,time:.standard)+(event.endTimestamp.map { " – "+$0.formatted(date:.omitted,time:.standard) } ?? "")).captionStyle() }
                            Spacer();Image(systemName:"scope").foregroundStyle(Palette.tertiaryText)
                        }.frame(minHeight:40)
                    }.buttonStyle(.plain)
                }
                }
                if let transfer=store.state.transfers.first(where:{$0.tripID==trip.id}) {
                    HStack { Image(systemName:"arrow.up.circle");Text("Transfer \(transfer.status.rawValue): \(transfer.message)");Spacer();StatusPill(state:transfer.status == .complete ? .ready:.queued) }.font(.caption)
                }
            }
            if let samples=trip.samples,!samples.isEmpty {
                DataRow(label:"Measured OBD responses",value:"\(samples.count)")
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
            } else if let snapshotError {
                EmptyStateCard(icon:"exclamationmark.triangle",title:"Trip Story unavailable",message:snapshotError)
                Button("Retry") { self.snapshotError=nil; snapshot=nil;snapshotRetry += 1 }.accessibilityIdentifier("trip-story.retry")
            } else {
                HStack(spacing:12) { ProgressView();Text("Preparing recorded evidence").captionStyle() }
                    .frame(maxWidth:.infinity,minHeight:120).accessibilityIdentifier("trip-story.loading")
            }
        }.sheet(isPresented:$editingAnnotation) { JourneyAnnotationEditor(recordingID:trip.id) }
            .sheet(isPresented:$signalsOverview) { SignalsOverviewView(initialTripID:trip.id) }
            .fileExporter(isPresented:$exporting,document:document,contentType:.json,defaultFilename:"DriveLine-\(trip.id.uuidString.prefix(8))") { result in if case .failure(let error)=result { store.error=error.localizedDescription } }
            .confirmationDialog("Delete this recording from this iPhone?",isPresented:$delete,titleVisibility:.visible) { Button("Delete recording",role:.destructive) { store.removeTrip(trip.id);dismiss() } }
            .task(id:trip.id.uuidString+":\(snapshotRetry)") {
                snapshot=nil; snapshotError=nil
                let expected=trip.id
                do {
                    let prepared=try await TripStorySnapshotCache.shared.snapshot(recording:trip.sharedRecording)
                    try Task.checkCancellation()
                    guard prepared.key.recordingID == expected else { return }
                    snapshot=prepared
                } catch is CancellationError {
                    return
                } catch {
                    snapshotError=error.localizedDescription
                }
            }
    }
    @ViewBuilder private func storyStatus(_ summary:DriveLineJourneySummary)->some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment:.leading,spacing:8) {
                ForEach(trip.sharedRecording.sourceIDs,id:\.self) { SourceBadge(source:$0.uppercased(),verified:true) }
                StatusPill(state:summary.quality == .complete ? .ready:.stale,text:summary.quality.title)
            }
        } else {
            HStack { ForEach(trip.sharedRecording.sourceIDs,id:\.self) { SourceBadge(source:$0.uppercased(),verified:true) };Spacer();StatusPill(state:summary.quality == .complete ? .ready:.stale,text:summary.quality.title) }
        }
    }
    private func routePoint(_ point:DriveLineGPSPoint?)->RoutePoint? {
        guard let point else { return nil }
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
    let events:[DriveLineTripEvent]
    let prepared:TripStorySignalSnapshot?
    @Binding var playbackSeconds:Double
    @State private var chartData:PhoneSignalChartData?
    var body:some View {
        VStack(alignment:.leading,spacing:6) {
            if let chartData {
                let series=chartData.series
                HStack {
                    SourceBadge(source:series.provenance == .derived ? "Derived · \(series.algorithmIdentifier ?? "policy")":(series.coverage?.sourceIDs.joined(separator:", ").uppercased() ?? "Measured"),verified:true)
                    if let coverage=series.coverage { Text("\(Int((coverage.fraction*100).rounded()))% coverage").captionStyle() }
                    Spacer();Text(choice.unit).captionStyle()
                }
                if series.segments.flatMap({$0}).isEmpty { Text("No recorded \(choice.title.lowercased()) observations").captionStyle().frame(maxWidth:.infinity,minHeight:80) }
                else {
                    Chart {
                        ForEach(Array(chartData.renderedSegments.enumerated()),id:\.offset) { segment,points in
                            ForEach(points) { point in LineMark(x:.value("Time",point.timestamp),y:.value(choice.unit,point.value),series:.value("Observed segment",segment)).foregroundStyle(series.provenance == .derived ? Palette.fuelAttention:Palette.cobalt) }
                        }
                        ForEach(events.filter{$0.severity == .attention}) { event in RuleMark(x:.value("Evidence event",event.timestamp)).foregroundStyle(Palette.recordingFault.opacity(0.55)).lineStyle(StrokeStyle(lineWidth:1,dash:[2,3])) }
                        RuleMark(x:.value("Shared cursor",trip.startedAt.addingTimeInterval(playbackSeconds))).foregroundStyle(Palette.tertiaryText).lineStyle(StrokeStyle(lineWidth:1,dash:[3]))
                    }
                    .chartXScale(domain:trip.startedAt...max(trip.startedAt.addingTimeInterval(trip.duration),trip.startedAt.addingTimeInterval(0.001)))
                        .frame(height:130).chartLegend(.hidden)
                        .chartOverlay { proxy in GeometryReader { geometry in
                            Rectangle().fill(.clear).contentShape(Rectangle()).gesture(DragGesture(minimumDistance:0).onChanged { value in
                                guard let frame=proxy.plotFrame else { return }
                                let x=value.location.x-geometry[frame].origin.x
                                if let date:Date=proxy.value(atX:x) { playbackSeconds=min(max(0,date.timeIntervalSince(trip.startedAt)),trip.duration) }
                            })
                        } }
                }
            } else {
                HStack { ProgressView();Text("Preparing recorded \(choice.title.lowercased()) observations").captionStyle() }
                    .frame(maxWidth:.infinity,minHeight:80).accessibilityIdentifier("trip-story.signal-loading")
            }
        }.padding(.vertical,5).task(id:trip.id.uuidString+":"+choice.key) {
            if let prepared { chartData=PhoneSignalChartData(series:prepared.series,renderedSegments:prepared.renderedSegments);return }
            chartData=nil
            let recording=trip.sharedRecording,key=choice.key,unit=choice.unit
            do {
                let signal=try await Task.detached(priority:.userInitiated) {
                    try TripStorySnapshotBuilder.signal(key,unit:unit,recording:recording)
                }.value
                try Task.checkCancellation()
                chartData=PhoneSignalChartData(series:signal.series,renderedSegments:signal.renderedSegments)
            } catch { return }
        }
    }
}

private struct PhoneSignalChartData:Sendable {
    let series:DriveLineSignalSeries
    let renderedSegments:[[DriveLineSignalPoint]]
}

private struct PhoneSignalGroup:Identifiable {
    var id:DriveLineSignalGroup { group }
    var group:DriveLineSignalGroup
    var signals:[DriveLineSignalDescriptor]
}

struct SignalsOverviewView:View {
    let initialTripID:UUID?
    @EnvironmentObject private var store:AppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var selectedTripID:UUID?
    @State private var selectedSignal:DriveLineSignalDescriptor?
    @State private var search=""

    init(initialTripID:UUID? = nil) {
        self.initialTripID=initialTripID
        _selectedTripID=State(initialValue:initialTripID)
    }
    private var recordings:[Trip] {
        store.state.trips.filter { trip in
            store.state.selectedVehicleID == nil || trip.vehicleID == store.state.selectedVehicleID
        }.sorted{$0.startedAt>$1.startedAt}
    }
    private var trip:Trip? { recordings.first(where:{$0.id == selectedTripID}) ?? recordings.first }
    private var groups:[PhoneSignalGroup] {
        guard let trip else { return [] }
        return DriveLineJourneyPolicy.groupedSignalDescriptors(recording:trip.sharedRecording,query:search).map {
            PhoneSignalGroup(group:$0.0,signals:$0.1)
        }
    }
    var body:some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:14) {
                    if let trip {
                        recordingPicker(trip)
                        TextField(dynamicTypeSize.isAccessibilitySize ? "Search signals":"Search name, ID, alias, source or unit",text:$search)
                            .textFieldStyle(.roundedBorder).accessibilityIdentifier("signals.search")
                        if groups.isEmpty {
                            EmptyStateCard(icon:"waveform.slash",title:"No scalar signals recorded",
                                message:trip.route.isEmpty ? "This recording contains no supported scalar observations. Unknown recorded identifiers would appear here unchanged.":"This GPS recording contains a route but no stored GPS speed or accuracy values. Nothing is inferred from the route.")
                        } else {
                            ForEach(groups) { group in
                                VStack(alignment:.leading,spacing:8) {
                                    Text(group.group.title).font(.headline).accessibilityAddTraits(.isHeader)
                                    ForEach(group.signals) { descriptor in
                                        PhoneSignalOverviewRow(trip:trip,descriptor:descriptor) { selectedSignal=descriptor }
                                    }
                                }
                            }
                        }
                        if trip.isSample { InfoNote(text:"Sanitized sample recording. It is labelled sample and contributes zero to real totals.",icon:"testtube.2") }
                    } else {
                        EmptyStateCard(icon:"waveform.path.ecg",title:"No recorded Signals",message:"Record or import a journey. Missing observations remain unavailable and no sample rate is inferred.")
                    }
                }.padding(16)
            }.background(Palette.appBackground)
                .navigationTitle("Signals")
                .toolbar { ToolbarItem(placement:.confirmationAction) { Button("Done") { dismiss() } } }
        }.sheet(item:$selectedSignal) { descriptor in
            if let trip { PhoneSignalDetailView(trip:trip,descriptor:descriptor) }
        }.onAppear { if selectedTripID == nil { selectedTripID=recordings.first?.id } }
            .accessibilityIdentifier("signals.overview")
    }
    private func recordingPicker(_ trip:Trip)->some View {
        Menu {
            ForEach(recordings) { item in Button(item.name+" · "+item.startedAt.formatted(date:.abbreviated,time:.shortened)) { selectedTripID=item.id } }
        } label: {
            HStack { VStack(alignment:.leading,spacing:3) { Text(trip.name).font(.headline);Text(trip.startedAt.formatted(date:.abbreviated,time:.shortened)).captionStyle() };Spacer();Image(systemName:"chevron.up.chevron.down") }.card()
        }.foregroundStyle(Palette.primaryText).accessibilityIdentifier("signals.recording")
    }
}

private struct PhoneSignalOverviewRow:View {
    let trip:Trip
    let descriptor:DriveLineSignalDescriptor
    let action:()->Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var series:DriveLineSignalSeries { DriveLineJourneyPolicy.signalSeries(descriptor.key,unit:descriptor.unit ?? "",recording:trip.sharedRecording) }
    private var stats:DriveLineSignalStatistics { DriveLineJourneyPolicy.signalStatistics(series,at:trip.startedAt.addingTimeInterval(trip.duration)) }
    private var latestPoint:DriveLineSignalPoint? { series.segments.flatMap{$0}.last }
    var body:some View {
        Button(action:action) {
            VStack(alignment:.leading,spacing:9) {
                HStack(alignment:.top,spacing:8) {
                    VStack(alignment:.leading,spacing:2) {
                        Text(descriptor.displayName).font(.system(size:15,weight:.semibold))
                        Text(descriptor.key).font(.caption2.monospaced()).foregroundStyle(Palette.tertiaryText)
                    }
                    Spacer()
                    if !dynamicTypeSize.isAccessibilitySize {
                        StatusPill(state:semanticState,text:stats.freshness.title)
                    }
                    Image(systemName:"chevron.right").foregroundStyle(Palette.tertiaryText)
                }
                if dynamicTypeSize.isAccessibilitySize {
                    StatusPill(state:semanticState,text:stats.freshness.title)
                    valueSummary
                    SignalSparkline(series:series).frame(maxWidth:.infinity).frame(height:64)
                } else {
                    HStack(alignment:.center,spacing:12) {
                        valueSummary
                        SignalSparkline(series:series).frame(width:118,height:48)
                    }
                }
            }.card()
        }.buttonStyle(.plain).accessibilityIdentifier("signals.row.\(descriptor.key)")
    }
    private var valueSummary:some View {
        VStack(alignment:.leading,spacing:5) {
            HStack(alignment:.firstTextBaseline,spacing:4) {
                Text(latestPoint?.value.text(2) ?? "—").font(.title3.monospacedDigit())
                Text(descriptor.unit ?? "unit unavailable").captionStyle()
            }
            SourceBadge(source:stats.sourceIDs.isEmpty ? "Source unavailable":stats.sourceIDs.joined(separator:", "),verified:!stats.sourceIDs.isEmpty)
            Text(series.coverage.map{"\(Int(($0.fraction*100).rounded()))% coverage · \(stats.observationCount) observations"} ?? "Coverage unavailable")
                .captionStyle()
        }.frame(maxWidth:.infinity,alignment:.leading)
    }
    private var semanticState:DriveLineSemanticState {
        stats.freshness == .fresh ? .ready:(stats.freshness == .stale ? .stale:.unavailable)
    }
}

private struct SignalSparkline:View {
    let series:DriveLineSignalSeries
    var body:some View {
        let renderedSegments=DriveLineRenderingPolicy.signalSegments(series.segments,limit:240)
        Chart {
            ForEach(Array(renderedSegments.enumerated()),id:\.offset) { segment,points in
                ForEach(points) { point in
                    LineMark(x:.value("Recorded time",point.timestamp),y:.value("Recorded value",point.value),series:.value("Gap-aware segment",segment))
                        .foregroundStyle(Palette.cobalt).lineStyle(StrokeStyle(lineWidth:1.4))
                    PointMark(x:.value("Recorded time",point.timestamp),y:.value("Recorded value",point.value))
                        .foregroundStyle(Palette.cobalt).symbolSize(6)
                }
            }
        }.chartXAxis(.hidden).chartYAxis(.hidden).chartLegend(.hidden)
            .accessibilityLabel("Gap-aware recorded sparkline")
    }
}

private struct PhoneSignalDetailView:View {
    let trip:Trip
    let descriptor:DriveLineSignalDescriptor
    @Environment(\.dismiss) private var dismiss
    @State private var cursorSeconds:Double
    @State private var visibleStart:Double
    @State private var visibleEnd:Double
    @State private var fitRequest=0

    init(trip:Trip,descriptor:DriveLineSignalDescriptor) {
        self.trip=trip;self.descriptor=descriptor
        _cursorSeconds=State(initialValue:max(0,trip.duration))
        _visibleStart=State(initialValue:0)
        _visibleEnd=State(initialValue:max(0.001,trip.duration))
    }
    private var recording:DriveLineRecording { trip.sharedRecording }
    private var series:DriveLineSignalSeries { DriveLineJourneyPolicy.signalSeries(descriptor.key,unit:descriptor.unit ?? "",recording:recording) }
    private var selectedDate:Date { trip.startedAt.addingTimeInterval(cursorSeconds) }
    private var visibleInterval:DateInterval { DateInterval(start:trip.startedAt.addingTimeInterval(visibleStart),end:trip.startedAt.addingTimeInterval(max(visibleStart,visibleEnd))) }
    private var stats:DriveLineSignalStatistics { DriveLineJourneyPolicy.signalStatistics(series,at:selectedDate,visibleRange:visibleInterval) }
    private var cursor:DriveLineCursorSelection { DriveLineJourneyPolicy.cursor(at:selectedDate,recording:recording,signalKeys:[descriptor.key]) }
    private var gaps:[(Date,Date)] {
        zip(series.segments,series.segments.dropFirst()).compactMap { previous,next in
            guard let a=previous.last?.timestamp,let b=next.first?.timestamp else { return nil }
            return (a,b)
        }
    }
    var body:some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:14) {
                    VStack(alignment:.leading,spacing:4) {
                        Text(descriptor.displayName).font(.title2)
                        Text(descriptor.key).font(.caption.monospaced()).foregroundStyle(Palette.secondaryText).textSelection(.enabled)
                        Text("\(trip.name) · \(trip.startedAt.formatted(date:.abbreviated,time:.shortened))").captionStyle()
                    }
                    provenance
                    trace
                    visibleRangeControls
                    SectionCard(title:"Visible-range observations",icon:"sum") {
                        HStack { detailMetric("Current",stats.current?.value);detailMetric("Minimum",stats.minimum) }
                        HStack { detailMetric("Maximum",stats.maximum);detailMetric("Recorded avg",stats.recordedObservationAverage) }
                        HStack { detailText("Count",String(stats.observationCount));detailText("Coverage",series.coverage.map{"\(Int(($0.fraction*100).rounded()))%"} ?? "—") }
                        DataRow(label:"Latest observation",value:stats.latestObservation?.formatted(date:.omitted,time:.standard) ?? "Unavailable")
                        DataRow(label:"Freshness at cursor",value:stats.freshness.title)
                        InfoNote(text:"Average is the arithmetic mean of finite recorded observations in the visible range. It is not time-weighted.")
                    }
                    if !trip.route.isEmpty {
                        SectionCard(title:"Synchronized route position",icon:"map") {
                            NativeRouteMap(route:trip.route,selectedPoint:selectedRoutePoint,fitRequest:fitRequest).frame(height:220).clipShape(RoundedRectangle(cornerRadius:14))
                            HStack { Text(cursor.gpsPoint == nil ? "No GPS observation is close enough to this recorded cursor.":"Marker uses the nearest qualifying recorded GPS observation.").captionStyle();Spacer();Button("Fit Route") { fitRequest += 1 } }
                        }
                    } else {
                        EmptyStateCard(icon:"location.slash",title:"Route unavailable",message:"This OBD-only recording has no GPS evidence. A route position is not inferred.")
                    }
                    SectionCard(title:"Recorded gaps",icon:"waveform.slash") {
                        if gaps.isEmpty { Text(series.segments.isEmpty ? "No observations were recorded.":"No signal gap longer than the evidence threshold was recorded in this trace.").captionStyle() }
                        ForEach(Array(gaps.enumerated()),id:\.offset) { _,gap in
                            DataRow(label:"Unavailable interval",value:"\(gap.0.formatted(date:.omitted,time:.standard)) – \(gap.1.formatted(date:.omitted,time:.standard)) · \(Int(gap.1.timeIntervalSince(gap.0)))s")
                        }
                    }
                    if descriptor.key == "dpfRegenTrigger" { InfoNote(text:DriveLineMetricPolicy.dpfRegenTriggerExplanation,icon:"exclamationmark.triangle") }
                    if trip.isSample { InfoNote(text:"Sanitized sample recording. It remains excluded from real totals.",icon:"testtube.2") }
                }.padding(16)
            }.background(Palette.appBackground).navigationTitle("Signal Detail")
                .toolbar { ToolbarItem(placement:.confirmationAction) { Button("Done") { dismiss() } } }
        }.accessibilityIdentifier("signals.detail.\(descriptor.key)")
    }
    private var provenance:some View {
        SectionCard(title:"Source and provenance",icon:"checkmark.shield") {
            DataRow(label:"Source",value:stats.sourceIDs.isEmpty ? "Unavailable":stats.sourceIDs.joined(separator:", "))
            DataRow(label:"Status",value:series.provenance == .derived ? "Derived":"Measured")
            DataRow(label:"Unit",value:descriptor.unit ?? "Unavailable — no unit invented")
            if let algorithm=series.algorithmIdentifier {
                DataRow(label:"Derivation",value:"\(algorithm) · version \(series.algorithmVersion ?? "unavailable")")
            }
            DataRow(label:"Recorded range",value:(series.segments.flatMap{$0}.first?.timestamp.formatted(date:.omitted,time:.standard) ?? "—")+" – "+(series.segments.flatMap{$0}.last?.timestamp.formatted(date:.omitted,time:.standard) ?? "—"))
        }
    }
    private var trace:some View {
        let renderedSegments=DriveLineRenderingPolicy.signalSegments(series.segments)
        return SectionCard(title:"Full recorded trace",icon:"chart.xyaxis.line") {
            if series.segments.flatMap({$0}).isEmpty { Text("Unavailable — this identifier has no finite recorded observations.").captionStyle().frame(maxWidth:.infinity,minHeight:120) }
            else {
                Chart {
                    ForEach(Array(renderedSegments.enumerated()),id:\.offset) { segment,points in
                        ForEach(points) { point in
                            LineMark(x:.value("Elapsed seconds",point.timestamp.timeIntervalSince(trip.startedAt)),y:.value(descriptor.unit ?? "Recorded value",point.value),series:.value("Recorded segment",segment)).foregroundStyle(series.provenance == .derived ? Palette.fuelAttention:Palette.cobalt)
                            PointMark(x:.value("Elapsed seconds",point.timestamp.timeIntervalSince(trip.startedAt)),y:.value(descriptor.unit ?? "Recorded value",point.value)).foregroundStyle(series.provenance == .derived ? Palette.fuelAttention:Palette.cobalt).symbolSize(8)
                        }
                    }
                    RuleMark(x:.value("Shared cursor",cursorSeconds)).foregroundStyle(Palette.primaryText).lineStyle(StrokeStyle(lineWidth:1,dash:[3]))
                }.chartXScale(domain:visibleStart...max(visibleStart+0.001,visibleEnd)).frame(height:220).chartLegend(.hidden)
                    .chartOverlay { proxy in GeometryReader { geometry in
                        Rectangle().fill(.clear).contentShape(Rectangle()).gesture(DragGesture(minimumDistance:0).onChanged { value in
                            guard let frame=proxy.plotFrame else { return }
                            let x=value.location.x-geometry[frame].origin.x
                            if let seconds:Double=proxy.value(atX:x) { cursorSeconds=min(max(0,seconds),trip.duration) }
                        })
                    } }
            }
        }
    }
    private var visibleRangeControls:some View {
        SectionCard(title:"Visible range and cursor",icon:"arrow.left.and.right") {
            DataRow(label:"Cursor",value:selectedDate.formatted(date:.omitted,time:.standard)+" · \(Int(cursorSeconds))s elapsed")
            Slider(value:$cursorSeconds,in:0...max(0.001,trip.duration)).accessibilityLabel("Signal cursor")
            Text("Visible start · \(Int(visibleStart))s").captionStyle()
            Slider(value:Binding(get:{visibleStart},set:{visibleStart=min($0,max(0,visibleEnd-0.001));cursorSeconds=min(max(cursorSeconds,visibleStart),visibleEnd)}),in:0...max(0.001,trip.duration)).accessibilityIdentifier("signals.visible-start")
            Text("Visible end · \(Int(visibleEnd))s").captionStyle()
            Slider(value:Binding(get:{visibleEnd},set:{visibleEnd=max($0,min(trip.duration,visibleStart+0.001));cursorSeconds=min(max(cursorSeconds,visibleStart),visibleEnd)}),in:0...max(0.001,trip.duration)).accessibilityIdentifier("signals.visible-end")
            HStack { Button("Zoom in") { zoom(0.6) };Button("Zoom out") { zoom(1.5) };Button("Back") { pan(-0.3) };Button("Forward") { pan(0.3) };Spacer();Button("Reset") { visibleStart=0;visibleEnd=max(0.001,trip.duration) } }
        }
    }
    private var selectedRoutePoint:RoutePoint? {
        guard let point=cursor.gpsPoint else { return nil }
        return RoutePoint(latitude:point.latitude,longitude:point.longitude,timestamp:point.timestamp,accuracy:point.horizontalAccuracyM ?? 0,speed:point.speedMps)
    }
    private func detailMetric(_ title:String,_ value:Double?)->some View { Metric(title:title,value:value?.text(2) ?? "—",unit:descriptor.unit ?? "") }
    private func detailText(_ title:String,_ value:String)->some View { Metric(title:title,value:value) }
    private func zoom(_ factor:Double) {
        let duration=max(0.001,trip.duration),span=max(0.001,visibleEnd-visibleStart),half=min(duration/2,span*factor/2),centre=min(max(cursorSeconds,half),duration-half)
        visibleStart=max(0,centre-half);visibleEnd=min(duration,centre+half)
    }
    private func pan(_ fraction:Double) {
        let duration=max(0.001,trip.duration),span=visibleEnd-visibleStart,shift=span*fraction
        visibleStart=min(max(0,visibleStart+shift),max(0,duration-span));visibleEnd=min(duration,visibleStart+span);cursorSeconds=min(max(cursorSeconds,visibleStart),visibleEnd)
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
