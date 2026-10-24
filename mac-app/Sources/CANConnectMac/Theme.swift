import SwiftUI

enum Theme {
    static let background = Color(red:0.063,green:0.082,blue:0.11)
    static let sidebar = Color(red:0.078,green:0.102,blue:0.137)
    static let panel = Color(red:0.098,green:0.129,blue:0.173)
    static let raised = Color(red:0.125,green:0.169,blue:0.22)
    static let line = Color(red:0.17,green:0.21,blue:0.27)
    static let text = Color(red:0.91,green:0.93,blue:0.96)
    static let muted = Color(red:0.61,green:0.66,blue:0.74)
    static let blue = Color(red:0.4,green:0.67,blue:1)
    static let green = Color(red:0.48,green:0.8,blue:0.7)
}
enum Workspace: String, CaseIterable, Identifiable {
    case overview = "Overview", trips = "Trips", compare = "Compare", signals = "Signals", garage = "Garage", imports = "Imports", server = "Server"
    var id: String { rawValue }
    var icon: String {
        switch self { case .overview:return "square.grid.2x2";case .trips:return "point.topleft.down.curvedto.point.bottomright.up";case .compare:return "rectangle.split.2x1";case .signals:return "waveform.path.ecg";case .garage:return "car";case .imports:return "square.and.arrow.down";case .server:return "server.rack" }
    }
    var subtitle: String {
        switch self {case .overview:return "Your roads. Your data. All in one place.";case .trips:return "Explore each drive with its original data source.";case .compare:return "Two recordings. One synchronized workspace.";case .signals:return "Independent cards for recorded vehicle signals.";case .garage:return "One system for every vehicle.";case .imports:return "From phone or recorder to your Mac.";case .server:return "Ingestion, storage, and background services."}
    }
}
struct Panel<Content:View>: View {
    let title:String
    var icon:String? = nil
    @ViewBuilder var content:Content
    var body:some View {
        VStack(alignment:.leading,spacing:0) {
            HStack { Text(title).font(.system(size:13,weight:.semibold)); Spacer(); if let icon = icon { Image(systemName:icon).foregroundStyle(Theme.muted) } }.padding(13)
            Divider().overlay(Theme.line)
            content
        }.background(Theme.panel).clipShape(RoundedRectangle(cornerRadius:8)).overlay(RoundedRectangle(cornerRadius:8).stroke(Theme.line))
    }
}
struct EmptyPanel: View {
    let title:String
    let message:String
    var body:some View { VStack(spacing:12) { Image(systemName:"tray").font(.system(size:30)).foregroundStyle(Theme.blue); Text(title).font(.headline); Text(message).font(.system(size:12)).foregroundStyle(Theme.muted).multilineTextAlignment(.center) }.frame(maxWidth:.infinity,minHeight:220).padding(20) }
}
struct KeyValue:View {
    let label:String
    let value:String
    var body:some View { HStack(alignment:.firstTextBaseline) { Text(label).foregroundStyle(Theme.muted); Spacer(); Text(value).monospacedDigit().multilineTextAlignment(.trailing) }.font(.system(size:11)) }
}
func number(_ value:Double?,digits:Int = 1) -> String { guard let value = value,value.isFinite else { return "—" }; return value.formatted(.number.precision(.fractionLength(digits))) }
func duration(_ seconds:TimeInterval) -> String { let minutes = Int(seconds)/60; return minutes>=60 ? "\(minutes/60)h \(minutes%60)m" : "\(minutes)m" }
