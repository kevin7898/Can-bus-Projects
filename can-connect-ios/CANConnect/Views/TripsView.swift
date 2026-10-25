import SwiftUI
import UniformTypeIdentifiers

struct TripsView: View {
    @EnvironmentObject private var store: AppStore
    @Binding var filter: Int
    @Binding var page: Int
    @State private var selected: Trip?
    private var filtered: [Trip] { store.sortedTrips.filter { filter == 0 || (filter == 1 ? $0.source == .phoneGPS : $0.source != .phoneGPS) } }
    var body: some View {
        GeometryReader { geometry in
            let rows = max(1,min(3,Int((geometry.size.height-110)/120)))
            let pages = max(1,Int(ceil(Double(filtered.count)/Double(rows))))
            VStack(alignment:.leading,spacing:13) {
                PageControl(labels:["All trips","Phone GPS","Vehicle data"],selection:$filter)
                HStack { Text("\(filtered.count) trips").font(.system(size:16)); Spacer(); Text("\(filtered.reduce(0) { $0 + $1.distanceKM }.text()) km").captionStyle() }
                if filtered.isEmpty { Spacer(); VStack(spacing:12) { Image(systemName:"point.topleft.down.to.point.bottomright.curvepath").font(.system(size:32)).foregroundStyle(Palette.blue); Text("No drives here yet").font(.system(size:18)); Text("Record a GPS drive or import a recording.").captionStyle() }.frame(maxWidth:.infinity); Spacer() }
                else {
                    TabView(selection:$page) { ForEach(0..<pages,id:\.self) { index in
                        VStack(spacing:11) { ForEach(Array(filtered.dropFirst(index*rows).prefix(rows))) { trip in TripCard(trip:trip) { selected = trip } }; Spacer(minLength:0) }.padding(.horizontal,1).tag(index)
                    } }.tabViewStyle(.page(indexDisplayMode:.never))
                }
                HStack { Button { page = max(0,page-1) } label: { Image(systemName:"chevron.left").frame(width:44,height:36) }.disabled(page == 0); Spacer(); Text("Page \(min(page+1,pages)) of \(pages)").captionStyle(); Spacer(); Button { page = min(pages-1,page+1) } label: { Image(systemName:"chevron.right").frame(width:44,height:36) }.disabled(page >= pages-1) }
            }.onChange(of:filter) { _,_ in page = 0 }.onChange(of:filtered.count) { _,_ in page = min(page,pages-1) }.onChange(of:rows) { _,_ in page = 0 }
        }.sheet(item:$selected) { TripDetailView(trip:$0) }
    }
}
struct TripCard: View {
    let trip: Trip; let action: () -> Void
    var body: some View { Button(action:action) { VStack(alignment:.leading,spacing:9) {
        HStack { Text(trip.name).font(.system(size:14,weight:.medium)).lineLimit(1); Spacer(minLength:4); Image(systemName:"chevron.right").font(.system(size:10)).foregroundStyle(Palette.muted) }
        Text("\(trip.startedAt.formatted(date:.abbreviated,time:.shortened)) · \(trip.isSample ? "Sample · " : "")\(trip.source.title)").captionStyle().lineLimit(1).minimumScaleFactor(0.8)
        HStack(spacing:12) { Text("\(trip.distanceKM.text()) km").fontWeight(.medium); Text(trip.durationText).foregroundStyle(Palette.muted); Spacer(minLength:0); Text(trip.economy.map { "\($0.text()) L/100 km" } ?? (trip.source == .phoneGPS ? "GPS only" : "Fuel unavailable")).foregroundStyle(Palette.muted) }.font(.system(size:11)).lineLimit(1).minimumScaleFactor(0.8)
    }.card().foregroundStyle(Palette.text) }.buttonStyle(.plain) }
}
struct JSONDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents:data) }
}
struct TripDetailView: View {
    let trip: Trip
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var exporting = false
    @State private var document = JSONDocument(data:Data())
    @State private var delete = false
    var body: some View { SheetShell(title:"Drive details") {
        VStack(alignment:.leading,spacing:7) { Text(trip.name).font(.title3); Text(trip.startedAt.formatted(date:.complete,time:.shortened)).captionStyle() }
        if !trip.route.isEmpty { NativeRouteMap(route:trip.route).frame(height:230).clipShape(RoundedRectangle(cornerRadius:14)) }
        else { InfoNote(text:"This recording has no GPS route.",icon:"map") }
        HStack { Metric(title:"Distance",value:trip.distanceKM.text(),unit:"km"); Metric(title:"Duration",value:trip.durationText) }
        HStack { Metric(title:"Average fuel",value:trip.economy?.text() ?? "—",unit:"L/100 km"); Metric(title:"Fuel used",value:trip.fuelLitres?.text(2) ?? "—",unit:"L") }
        InfoNote(text:"\(trip.isSample ? "Sample data · " : "")\(trip.source.title) · Stored on this iPhone. \(trip.source == .phoneGPS ? "GPS does not provide engine or fuel readings." : "")")
        if let samples = trip.samples, !samples.isEmpty {
            DataRow(label:"Measured OBD responses",value:String(samples.count))
            ForEach(OBDDecoder.definitions.filter { d in samples.contains(where:{$0.signals[d.key] != nil}) }, id:\.key) { definition in
                if let sample = samples.last(where:{$0.signals[definition.key] != nil}), let value = sample.signals[definition.key] {
                    let label = OBDDecoder.labels[definition.key]!
                    DataRow(label:label.title,value:"\(value.text()) \(label.unit) · \(sample.timestamp.formatted(date:.omitted,time:.standard))")
                }
            }
        }
        AppButton(title:"Export recording",icon:"square.and.arrow.up") { do { document = JSONDocument(data:try store.archive([trip]).encoded()); exporting = true } catch { store.error = error.localizedDescription } }
        Button("Delete recording",role:.destructive) { delete = true }.frame(maxWidth:.infinity).padding(.top,8)
    }.fileExporter(isPresented:$exporting,document:document,contentType:.json,defaultFilename:"DriveLine-\(trip.id.uuidString.prefix(8))") { result in if case .failure(let error) = result { store.error = error.localizedDescription } }
        .confirmationDialog("Delete this recording from this iPhone?",isPresented:$delete,titleVisibility:.visible) { Button("Delete recording",role:.destructive) { store.removeTrip(trip.id); dismiss() } }
    }
}

#if DEBUG
#Preview("Drives · Sample data") { DriveLineCanvas(tab:.drives) }
#endif
