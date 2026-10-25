import SwiftUI

struct DriveLedgerTodayView:View {
    @EnvironmentObject private var store:AppStore
    @State private var viewport=MapViewport()
    @State private var width:CGFloat=0
    private var presentation:MacTodayPresentation { .make(state:store.state,now:Date()) }

    var body:some View {
        VStack(alignment:.leading,spacing:14) {
            HStack(alignment:.firstTextBaseline) {
                VStack(alignment:.leading,spacing:4) {
                    Text(presentation.date.formatted(.dateTime.weekday(.wide).day().month(.wide))).font(.title2.weight(.semibold))
                    Text(presentation.vehicle?.name ?? "No vehicle selected").foregroundStyle(Theme.secondaryText)
                }
                Spacer();StatusPill(state:store.readOnly ? .unavailable:.healthy,text:store.readOnly ? "Library read only":"Library ready")
                StatusPill(state:serverState,text:"Server: \(store.serverStatus)")
                if presentation.queuedImports>0 { StatusPill(state:.queued,text:"\(presentation.queuedImports) queued") }
            }
            summary
            if width>1120 { HStack(alignment:.top,spacing:14) { mainColumn;sideColumn.frame(width:320) } }
            else { mainColumn;sideColumn }
        }.background { GeometryReader { proxy in Color.clear.onAppear { width=proxy.size.width }.onChange(of:proxy.size.width) { _,value in width=value } } }
            .onAppear { viewport=store.preferences.map }
            .accessibilityIdentifier("mac.today.content")
    }

    private var summary:some View {
        LazyVGrid(columns:Array(repeating:GridItem(.flexible(minimum:150)),count:4),spacing:10) {
            MetricTile(title:"Distance today",value:presentation.todayDistanceKm.map{number($0,digits:1)},unit:"km",
                       state:presentation.todayDistanceKm == nil ? .unavailable:.healthy,source:"Recorded")
            MetricTile(title:"Duration today",value:presentation.todayTrips.isEmpty ? nil:duration(presentation.todayDuration),
                       state:presentation.todayTrips.isEmpty ? .unavailable:.healthy,source:"Recorded")
            MetricTile(title:"Drives today",value:presentation.todayTrips.isEmpty ? nil:String(presentation.todayTrips.count),
                       state:presentation.todayTrips.isEmpty ? .unavailable:.healthy,source:"Local library")
            MetricTile(title:"Trip fuel today",value:presentation.todayFuelLitres.map{number($0,digits:2)},unit:"L",
                       state:presentation.todayFuelLitres == nil ? .unavailable:.healthy,source:"Measured")
        }
    }

    private var mainColumn:some View {
        VStack(spacing:14) {
            if let trip=presentation.latestTrip {
                SectionCard(title:"Latest recorded route",icon:"map") {
                    HStack { VStack(alignment:.leading,spacing:3) { Text(trip.name).font(.headline);Text(trip.start.formatted(date:.abbreviated,time:.shortened)).foregroundStyle(Theme.secondaryText) };Spacer();SourceBadge(source:trip.source,verified:true);Button("Open drive") { store.selectedTripID=trip.id;store.page = .drives } }
                    if !trip.coordinates.isEmpty { MapPanel(trips:[trip],viewport:$viewport,style:store.preferences.mapStyle,height:300,onSelect:{ _ in }) }
                    else { EmptyStateCard(icon:"location.slash",title:"No route in this recording",message:"The original drive remains available with its recorded signals and timing.") }
                }
            } else {
                EmptyStateCard(icon:"road.lanes",title:"No real drives yet",message:"Import or transfer a recording for this vehicle. Demo recordings never contribute to Today.",actionTitle:"Open Imports") { store.page = .imports }
            }
            SectionCard(title:"Recent drives",icon:"clock.arrow.circlepath") {
                if presentation.recentTrips.isEmpty { Text("No real recordings for this vehicle.").foregroundStyle(Theme.secondaryText) }
                ForEach(presentation.recentTrips) { trip in
                    Button { store.selectedTripID=trip.id;store.page = .drives } label: {
                        HStack { VStack(alignment:.leading,spacing:3) { Text(trip.name);Text(trip.start.formatted(date:.abbreviated,time:.shortened)).font(.caption).foregroundStyle(Theme.secondaryText) };Spacer();Text(number(trip.distanceKm)+" km").monospacedDigit();Text(duration(trip.duration)).foregroundStyle(Theme.secondaryText);Image(systemName:"chevron.right") }.contentShape(Rectangle())
                    }.buttonStyle(.plain);Divider().overlay(Theme.border)
                }
            }
        }
    }

    private var sideColumn:some View {
        VStack(spacing:14) {
            SectionCard(title:"Vehicle & library",icon:"car") {
                keyValue("Vehicle",presentation.vehicle?.name ?? "—")
                keyValue("Real recordings",String(store.vehicleTrips.filter{!$0.isDemo}.count))
                keyValue("Import queue",presentation.queuedImports == 0 ? "Clear":"\(presentation.queuedImports) queued")
                Text("Historical library status only. DriveLine for Mac does not claim a live scanner connection.").font(.caption).foregroundStyle(Theme.secondaryText)
            }
            SectionCard(title:"Latest fill",icon:"fuelpump") {
                if let fill=presentation.latestFill {
                    keyValue("Station",fill.stationName ?? "Fuel fill")
                    keyValue("Purchased",number(fill.litresPurchased)+" L")
                    keyValue("Date",fill.date.formatted(date:.abbreviated,time:.omitted))
                    Text("Purchased quantity is separate from measured trip fuel.").font(.caption).foregroundStyle(Theme.secondaryText)
                } else { Text("No real fuel entries for this vehicle.").foregroundStyle(Theme.secondaryText) }
            }
            if presentation.fuelTripCount<presentation.todayTrips.count {
                RecoveryBanner(title:"Partial fuel coverage",message:"Today fuel includes only drives with measured fuel coverage; unavailable fuel is not treated as zero.")
            }
        }
    }
    private var serverState:DriveLineSemanticState { store.serverStatus=="Listening" ? .healthy:(store.serverStatus=="Stopped" ? .unavailable:.stale) }
    private func keyValue(_ label:String,_ value:String)->some View { HStack { Text(label).foregroundStyle(Theme.secondaryText);Spacer();Text(value).monospacedDigit() }.font(.system(size:11)) }
}
