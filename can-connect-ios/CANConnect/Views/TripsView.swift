import SwiftUI
import UniformTypeIdentifiers

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
    private var summary:DriveLineJourneySummary { DriveLineJourneyPolicy.summary(for:trip.sharedRecording) }
    var body:some View {
        SheetShell(title:"Trip Story") {
            VStack(alignment:.leading,spacing:7) {
                Text(trip.name).font(.title3)
                Text(trip.startedAt.formatted(date:.complete,time:.shortened)).captionStyle()
                HStack { ForEach(trip.sharedRecording.sourceIDs,id:\.self) { SourceBadge(source:$0.uppercased(),verified:true) };Spacer();StatusPill(state:summary.quality == .complete ? .healthy:.stale,text:summary.quality.title) }
            }
            if !trip.route.isEmpty { NativeRouteMap(route:trip.route).frame(height:230).clipShape(RoundedRectangle(cornerRadius:14)) }
            else { EmptyStateCard(icon:"map",title:"Route unavailable",message:"This recording has no saved GPS coordinates. No route is inferred from scanner data.") }
            HStack { Metric(title:"Measured distance",value:summary.metrics.distanceKm?.text() ?? "—",unit:"km");Metric(title:"Duration",value:trip.durationText) }
            HStack { Metric(title:"Trip economy",value:summary.metrics.economyL100Km?.text() ?? "—",unit:"L/100 km");Metric(title:"Measured trip fuel",value:summary.metrics.tripFuelLitres?.text(2) ?? "—",unit:"L") }
            InfoNote(text:summary.statement,icon:"checkmark.shield")
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
