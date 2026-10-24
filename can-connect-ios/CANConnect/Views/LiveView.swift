import SwiftUI

struct LiveView: View {
    @EnvironmentObject private var store: AppStore
    @Binding var page: Int
    @State private var slot: String?
    var body: some View {
        GeometryReader { geometry in
            let compact = geometry.size.height < 535
            VStack(spacing:compact ? 8 : 12) {
                Menu {
                    Button("Sample CAN feed") { store.source = .demo }
                    Button("iPhone GPS") { store.source = .phoneGPS }
                    Button("OBD scanner") { store.source = .scanner }
                } label: { HStack(spacing:8) { Image(systemName:store.source == .phoneGPS ? "location" : "cpu").foregroundStyle(Palette.blue); Text(store.source.title).foregroundStyle(Palette.text); Text(store.source == .demo ? "· Sample data" : store.source == .scanner ? "· Measured OBD" : "· GPS only").foregroundStyle(Palette.muted); Spacer(); Image(systemName:"chevron.down").foregroundStyle(Palette.muted) }.font(.system(size:11)).padding(12).background(Palette.surface, in:RoundedRectangle(cornerRadius:12)).overlay(RoundedRectangle(cornerRadius:12).stroke(Palette.border)) }.disabled(store.recording || store.pendingGPS)
                PageControl(labels:["Drive","Engine","Economy"], selection:$page)
                TabView(selection:$page) {
                    drive(compact:compact).tag(0)
                    signalPage(title:"Engine signals", subtitle:"Choose the readings you want in view.", prefix:"engine", compact:compact).tag(1)
                    economy(compact:compact).tag(2)
                }.tabViewStyle(.page(indexDisplayMode:.never)).frame(maxHeight:.infinity)
                VStack(spacing:7) {
                    Rectangle().fill(Palette.border).frame(height:1)
                    AppButton(title:store.pendingGPS ? "Cancel GPS request" : (store.recording ? "Finish & save recording" : (store.source == .demo ? "Start sample recording" : store.source == .scanner ? "Start scanner recording" : "Start GPS recording")), icon:store.recording ? "stop.circle" : "record.circle", destructive:store.recording) {
                        if store.pendingGPS { store.cancelGPS() } else if store.recording { store.finishRecording() } else { store.startRecording() }
                    }
                    Text(store.source == .demo ? "Sample feed · no hardware connection" : (store.source == .scanner ? store.scanner.status : (store.recording || store.pendingGPS ? store.gps.status : "Uses iPhone location · vehicle signals unavailable"))).font(.system(size:10)).foregroundStyle(Palette.muted).lineLimit(1).minimumScaleFactor(0.8)
                }
            }
        }
        .sheet(isPresented:Binding(get:{slot != nil}, set:{if !$0 {slot = nil}})) { if let selected = slot {
            SignalPicker(slot:selected).presentationDetents([.medium,.large])
        } }
    }
    private func drive(compact: Bool) -> some View {
        VStack(spacing:compact ? 9 : 16) {
            Spacer(minLength:0)
            VStack(spacing:3) { Eyebrow(text:store.source == .demo ? "Sample CAN · Preview" : store.source == .scanner ? "\(store.scannerTitle) · Vehicle speed" : "iPhone GPS · Speed")
                Text(store.speedText).font(.system(size:compact ? 64 : 80, weight:.regular)).monospacedDigit().minimumScaleFactor(0.6)
                Text("km/h").font(.system(size:13)).foregroundStyle(Palette.muted)
            }
            HStack(spacing:10) { ForEach(0..<21, id:\.self) { i in Rectangle().fill(i == 10 ? Palette.blue : Palette.border).frame(width:i == 10 ? 2 : 1, height:i == 10 ? 10 : 6) } }.padding(.vertical,4)
            HStack(spacing:9) { Image(systemName:"stopwatch").foregroundStyle(Palette.muted); Text(store.timerText); Text("·").foregroundStyle(Palette.muted); Text("\((store.state.draft?.distanceKM ?? 0).text()) km") }.font(.system(size:13)).monospacedDigit()
            HStack { Metric(title:"Range", value:store.source == .demo ? "620" : "—", unit:"km"); Divider().overlay(Palette.border); Metric(title:"Fuel", value:store.source == .demo ? "62%" : store.reading("fuelPercent").map { "\($0.text(0))%" } ?? "—"); Divider().overlay(Palette.border); Metric(title:"Outside", value:store.source == .demo ? "12" : store.reading("outsideC")?.text(0) ?? "—", unit:"°C") }.frame(height:49).padding(.vertical,10).overlay(alignment:.top) { Rectangle().fill(Palette.border).frame(height:1) }.overlay(alignment:.bottom) { Rectangle().fill(Palette.border).frame(height:1) }
            Text("Key readings").font(.system(size:16)).frame(maxWidth:.infinity,alignment:.leading)
            signalGrid(prefix:"drive", count:2, compact:compact)
            InfoNote(text:"Tap a reading to change its signal.")
            Spacer(minLength:0)
        }.padding(.horizontal,1)
    }
    private func signalPage(title: String, subtitle: String, prefix: String, compact: Bool) -> some View {
        VStack(alignment:.leading, spacing:18) { Spacer(minLength:0); Text(title).font(.system(size:19)); Text(subtitle).captionStyle(); signalGrid(prefix:prefix, count:4, compact:compact); InfoNote(text:"Each card keeps its own signal. Duplicates are welcome."); Spacer(minLength:0) }.padding(.horizontal,1)
    }
    private func economy(compact: Bool) -> some View {
        VStack(alignment:.leading, spacing:compact ? 12 : 20) { Spacer(minLength:0)
            VStack(alignment:.leading, spacing:7) { Eyebrow(text:store.source == .demo ? "Rolling average · Sample 500 km" : "Vehicle economy unavailable"); HStack(alignment:.firstTextBaseline) { Text(store.source == .demo ? "5.4" : "—").font(.system(size:compact ? 46 : 60)); Text("L/100 km").font(.system(size:13)).foregroundStyle(Palette.muted) } }.frame(maxWidth:.infinity,alignment:.leading)
            signalGrid(prefix:"economy",count:4,compact:compact)
            InfoNote(text:store.source == .demo ? "Sample readings show the locked dashboard layout." : store.source == .scanner ? "Fuel use requires measured fuel rate and speed. Unsupported readings stay unavailable." : "GPS alone cannot measure fuel use or engine signals.")
            Spacer(minLength:0)
        }.padding(.horizontal,1)
    }
    private func signalGrid(prefix: String, count: Int, compact: Bool) -> some View {
        LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())], spacing:10) { ForEach(0..<count, id:\.self) { i in
            let key = "\(prefix).\(i)", signal = store.signal(key)
            Button { slot = key } label: { VStack(alignment:.leading,spacing:compact ? 5 : 9) {
                HStack(spacing:4) { Text(signal.title); Image(systemName:"slider.horizontal.3").foregroundStyle(Palette.muted.opacity(0.7)) }.font(.system(size:11)).foregroundStyle(Palette.muted).lineLimit(1).minimumScaleFactor(0.7)
                HStack(alignment:.firstTextBaseline,spacing:5) { Text(store.signalText(signal)).font(.system(size:compact ? 27 : 31)).foregroundStyle(Palette.text).monospacedDigit(); Text(signal.unit).font(.system(size:10)).foregroundStyle(Palette.muted) }.lineLimit(1).minimumScaleFactor(0.65)
            }.frame(maxWidth:.infinity,alignment:.leading).padding(compact ? 12 : 14).background(Palette.surface,in:RoundedRectangle(cornerRadius:14)).overlay(RoundedRectangle(cornerRadius:14).stroke(Palette.border)) }.buttonStyle(.plain).accessibilityLabel("\(signal.title), \(store.signalText(signal)). Change signal")
        } }
    }
}
struct SignalPicker: View {
    let slot: String
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    var body: some View { SheetShell(title:"Choose a signal") {
        ForEach(Signal.allCases) { signal in Button { store.setSignal(signal,slot:slot); dismiss() } label: { HStack { VStack(alignment:.leading,spacing:4) { Text(signal.title).foregroundStyle(Palette.text); Text(signal.unit).captionStyle() }; Spacer(); if store.signal(slot) == signal { Image(systemName:"checkmark").foregroundStyle(Palette.blue) } }.padding(.vertical,9).contentShape(Rectangle()) } }
        InfoNote(text:"This changes only the card you selected.")
    } }
}
