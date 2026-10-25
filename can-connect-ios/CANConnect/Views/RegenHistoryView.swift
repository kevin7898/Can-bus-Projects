import SwiftUI

struct RegenSummaryView: View {
    @EnvironmentObject private var store: AppStore
    @State private var cycles: [RegenCycle] = []
    @State private var history = false
    private var completed: [RegenCycle] { cycles.filter { $0.outcome == .completed } }
    private var refreshID: String {
        "\(store.state.selectedVehicleID?.uuidString ?? "none"):\(store.state.trips.map {$0.id.uuidString}.joined()):\(store.state.draft?.id.uuidString ?? "none"):\((store.state.draft?.samples?.count ?? 0)/100):\(Int(store.now.timeIntervalSince1970/30))"
    }
    var body: some View {
        VStack(alignment:.leading,spacing:15) {
            Text("Regeneration cycles").font(.system(size:17))
            HStack {
                Metric(title:"Complete observations",value:"\(min(completed.count,10)) / 10")
                Metric(title:"Interrupted / incomplete",value:String(cycles.filter {$0.outcome != .completed && $0.outcome != .recording}.count))
            }.card()
            Text(completed.count < 5 ? "Collecting the first five complete cycles for comparison." : "Compare the latest ten complete cycles; interruptions stay separate.").captionStyle()
            DataRow(label:"Recorded soot mass",value:"\(store.latest?.recordedValue("dpfSootG")?.text(1) ?? "—") g")
            DataRow(label:"Cycle recording",value:cycles.contains(where:{$0.outcome == .recording}) ? "Active cycle observed" : "Automatic with scanner recordings")
            InfoNote(text:"A complete observation includes the start and confirmed end. Ending a recording or losing status data leaves an incomplete observation; this does not prove the ECU stopped regenerating.")
            AppButton(title:"Compare regeneration cycles",secondary:true) { history = true }.accessibilityIdentifier("regen.compare")
            Spacer(minLength:0)
        }.padding(.horizontal,1).padding(.top,8)
        .task(id:refreshID) {
            let trips = store.state.trips, vehicle = store.state.selectedVehicleID, draft = store.state.draft
            let since = store.state.regenTrackingStartedAt ?? Date(), now = Date()
            let result = await Task.detached(priority:.utility) { RegenAnalyzer.history(trips:trips,vehicleID:vehicle,since:since,draft:draft,now:now) }.value
            if !Task.isCancelled { cycles = result }
        }
        .sheet(isPresented:$history) { RegenHistoryView(cycles:cycles,trackingStartedAt:store.state.regenTrackingStartedAt) }
    }
}
struct RegenHistoryView: View {
    let cycles: [RegenCycle]
    let trackingStartedAt: Date?
    @State private var selected: RegenCycle?
    @State private var exporting = false
    @State private var document = JSONDocument(data:Data())
    @State private var error: String?
    private var completed: [RegenCycle] { Array(cycles.filter {$0.outcome == .completed}.prefix(10)) }
    private var incomplete: [RegenCycle] { cycles.filter {$0.outcome != .completed} }
    var body: some View { SheetShell(title:"Regeneration comparison") {
        if let date = trackingStartedAt { Text("Tracking since \(date.formatted(date:.abbreviated,time:.shortened))").captionStyle() }
        Text("Latest complete cycles · \(completed.count) / 10").font(.headline)
        if completed.isEmpty { InfoNote(text:"No complete cycle observed yet. Record normal drives with the scanner; cycles appear automatically.") }
        ForEach(completed) { cycle in row(cycle) }
        Text("Interrupted / incomplete · \(incomplete.count)").font(.headline)
        if incomplete.isEmpty { InfoNote(text:"No incomplete observations.") }
        ForEach(incomplete) { cycle in row(cycle) }
        InfoNote(text:"Soot and percentage retain their recorded timestamps. Complete means the ECU active flag ended, not independent confirmation of filter cleanliness. Separate recordings are never stitched into a complete cycle.")
        if let error { Text(error).captionStyle().foregroundStyle(Palette.red) }
        AppButton(title:"Export cycle comparison",icon:"square.and.arrow.up",secondary:true) {
            do {
                let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.prettyPrinted,.sortedKeys]
                document = JSONDocument(data:try encoder.encode(RegenReport(trackingStartedAt:trackingStartedAt,completed:completed,incomplete:incomplete)))
                exporting = true
            } catch { self.error = error.localizedDescription }
        }.disabled(cycles.isEmpty)
    }.sheet(item:$selected) { RegenCycleDetail(cycle:$0) }
        .fileExporter(isPresented:$exporting,document:document,contentType:.json,defaultFilename:"DriveLine-regen-comparison") { if case .failure(let failure) = $0 { error = failure.localizedDescription } }
    }
    private func row(_ cycle: RegenCycle) -> some View {
        Button { selected = cycle } label: {
            VStack(alignment:.leading,spacing:8) {
                Text(cycle.startedAt.formatted(date:.abbreviated,time:.shortened)).foregroundStyle(Palette.text)
                Text("\(cycle.startReadings["dpfSootG"]?.value.text(1) ?? "—") → \(cycle.endReadings["dpfSootG"]?.value.text(1) ?? "—") g · \((cycle.observedDuration/60).text(1)) min observed").captionStyle()
                Text("\(cycle.startReadings["dpfRegenTrigger"]?.value.text(0) ?? "—")% regen trigger at start · \(cycle.peakExhaustC?.text(0) ?? "—") °C peak exhaust").captionStyle()
                Text(cycle.reason).captionStyle().fixedSize(horizontal:false,vertical:true)
            }.frame(maxWidth:.infinity,alignment:.leading).card()
        }.buttonStyle(.plain)
    }
}
private struct RegenReport: Encodable {
    let schemaVersion = 1
    let definition = "ECU active-flag observations; incomplete recordings excluded from completed-cycle comparison. Percentage remains ECU regeneration trigger."
    let trackingStartedAt: Date?
    let completed: [RegenCycle]
    let incomplete: [RegenCycle]
}
private struct RegenCycleDetail: View {
    let cycle: RegenCycle
    var body: some View { SheetShell(title:"Regeneration observation") {
        Text(cycle.reason).font(.headline)
        DataRow(label:"First active status",value:cycle.startedAt.formatted(date:.abbreviated,time:.standard))
        DataRow(label:"Last active status",value:cycle.lastActiveAt.formatted(date:.abbreviated,time:.standard))
        if let prior = cycle.previousInactiveAt { Text("Start occurred between \(prior.formatted(date:.omitted,time:.standard)) and \(cycle.startedAt.formatted(date:.omitted,time:.standard)).").captionStyle() }
        if cycle.outcome == .completed || cycle.outcome == .partial { DataRow(label:"First inactive status",value:cycle.endedAt.formatted(date:.omitted,time:.standard)) }
        DataRow(label:"Observed duration",value:"\((cycle.observedDuration/60).text(1)) min")
        DataRow(label:"Peak recorded exhaust",value:"\(cycle.peakExhaustC?.text(0) ?? "—") °C")
        readings("At start",values:cycle.startReadings,reference:cycle.startedAt)
        readings("At end / last observation",values:cycle.endReadings,reference:cycle.endedAt)
        Text("Recording reference: \(cycle.tripID.uuidString)").captionStyle().textSelection(.enabled)
    } }
    private func readings(_ title: String, values: [String:RegenReading], reference: Date) -> some View {
        VStack(alignment:.leading,spacing:8) {
            Text(title).font(.headline)
            ForEach(["dpfSootG","dpfRegenTrigger","dpfDifferentialKpa","rpm","engineLoad","egt1C","egt2C","egt3C","egt4C"],id:\.self) { key in
                if let label = OBDDecoder.labels[key] {
                    DataRow(label:label.title,value:values[key].map { "\($0.value.text(1)) \(label.unit)" } ?? "—")
                    if let reading = values[key] { Text("\(reading.timestamp.formatted(date:.omitted,time:.standard)) · \(abs(reading.timestamp.timeIntervalSince(reference)).text(0)) s \(reading.timestamp <= reference ? "before" : "after") boundary").captionStyle() }
                }
            }
        }
    }
}
