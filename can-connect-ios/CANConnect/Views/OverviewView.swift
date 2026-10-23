import SwiftUI

struct OverviewView: View {
    @EnvironmentObject private var store: AppStore
    @Binding var page: Int
    @State private var map = false
    @State private var customize = false
    @State private var latestTrip: Trip?
    var body: some View {
        VStack(spacing:12) {
            PageControl(labels:["Your roads","Summary"], selection:$page)
            TabView(selection:$page) {
                roads.tag(0)
                summary.tag(1)
            }.tabViewStyle(.page(indexDisplayMode:.never))
        }.sheet(isPresented:$map) { SheetShell(title:"Your roads") {
            NativeRouteMap(route:store.latest?.route ?? []).frame(height:420).clipShape(RoundedRectangle(cornerRadius:16))
            InfoNote(text:store.latest?.isSample == true ? "Illustrative sample route near Nanaimo. The overview highlights sample road corridors." : "Latest saved route. Pinch to zoom and drag to explore.")
            Text(store.latest?.name ?? "No recorded drives yet").font(.headline)
        } }.sheet(isPresented:$customize) { CustomizeSummary() }.sheet(item:$latestTrip) { TripDetailView(trip:$0) }
    }
    private var roads: some View {
        VStack(alignment:.leading,spacing:12) {
            HStack { VStack(alignment:.leading,spacing:4) { Text("Driving history").font(.system(size:17)); Text(store.latest?.isSample == false ? "Latest recorded route · kept on iPhone" : "Sample roads · Nanaimo, BC").captionStyle() }; Spacer(); Button { map = true } label: { Image(systemName:"arrow.up.left.and.arrow.down.right").frame(width:36,height:36).background(Palette.surface,in:Circle()) }.accessibilityLabel("Expand map") }
            Group {
                if let trip = store.latest, !trip.isSample { NativeRouteMap(route:trip.route).clipShape(RoundedRectangle(cornerRadius:14)) }
                else { RoadMap() }
            }.frame(maxWidth:.infinity,maxHeight:.infinity).overlay(alignment:.topLeading) { Text(store.latest?.isSample == false ? "RECORDED ROUTE" : "SAMPLE COVERAGE").font(.system(size:9,weight:.medium)).tracking(1).padding(9).background(Palette.background.opacity(0.88),in:Capsule()).padding(12) }
            HStack(spacing:14) { Circle().fill(Palette.blue).frame(width:7,height:7); Text(store.latest?.isSample == false ? "Recorded GPS route" : "Driven roads · sample").captionStyle(); Spacer(); Text("Saved locally").captionStyle() }
            Button { map = true } label: { HStack { Image(systemName:"mappin.and.ellipse").foregroundStyle(Palette.blue); VStack(alignment:.leading,spacing:4) { Text(store.latest?.name ?? "Your next drive starts here").font(.system(size:13)).foregroundStyle(Palette.text).lineLimit(1); Text(store.latest.map { $0.startedAt.formatted(date:.abbreviated,time:.shortened) } ?? "Start a recording from Live").captionStyle() }; Spacer(); Image(systemName:"chevron.right").font(.system(size:11)).foregroundStyle(Palette.muted) }.card() }
            Text("Recorded history stays separate from Live.").captionStyle()
        }.padding(.horizontal,1).padding(.bottom,2)
    }
    private var summary: some View {
        GeometryReader { geometry in
            VStack(alignment:.leading,spacing:geometry.size.height < 470 ? 10 : 16) {
                HStack { Text("At a glance").font(.system(size:17)); Spacer(); Button("Customize") { customize = true }.font(.system(size:11)) }
                ForEach(store.state.preferences.summaryOrder, id:\.self) { key in
                    switch key {
                    case "week": VStack(alignment:.leading,spacing:12) { Text("This week").captionStyle(); HStack { Metric(title:"Distance",value:store.weekKM.text(0),unit:"km"); Metric(title:"Drives",value:String(store.weekTrips.count)); Metric(title:"Avg. fuel",value:store.weekEconomy?.text() ?? "—",unit:"L/100") } }.card()
                    case "fuel": HStack { Image(systemName:"fuelpump").foregroundStyle(Palette.blue); VStack(alignment:.leading,spacing:6) { Text("Fuel & range · sample").captionStyle(); Text("620 km").font(.system(size:26)); Text("62% tank · 5.4 L/100 km").captionStyle() }; Spacer(); Button { store.selectedTab = .vehicle } label: { Image(systemName:"chevron.right").frame(width:30,height:40) }.accessibilityLabel("Open Vehicle") }.card()
                    default: if let trip = store.latest { Button { latestTrip = trip } label: { VStack(alignment:.leading,spacing:9) { HStack { Text("Latest drive").captionStyle(); Spacer(); if trip.isSample { Text("Sample").captionStyle() } }; Text(trip.name).font(.system(size:14,weight:.medium)).foregroundStyle(Palette.text).lineLimit(1); HStack { Text("\(trip.distanceKM.text()) km").foregroundStyle(Palette.text); Spacer(); Text(trip.durationText).foregroundStyle(Palette.muted) }.font(.system(size:12)) }.card() } }
                    }
                }
                Spacer(minLength:0)
                HStack(spacing:8) { Image(systemName:"externaldrive").foregroundStyle(Palette.muted); Text("On this iPhone · server not configured").captionStyle() }
            }.padding(.horizontal,1).padding(.vertical,2)
        }
    }
}
struct CustomizeSummary: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    var body: some View { NavigationStack { List { Section("Drag to reorder your summary") { ForEach(store.state.preferences.summaryOrder,id:\.self) { key in Text(key == "week" ? "Week summary" : key == "fuel" ? "Fuel & range" : "Latest drive") }.onMove { from,to in store.state.preferences.summaryOrder.move(fromOffsets:from,toOffset:to); store.save() } } }.environment(\.editMode,.constant(.active)).scrollContentBackground(.hidden).background(Palette.background).navigationTitle("Customize").navigationBarTitleDisplayMode(.inline).toolbar { Button("Done") { dismiss() } } }.preferredColorScheme(.dark) }
}
