import SwiftUI
import AppKit

enum Theme {
    static let appBackground = semantic(light:0xF7F5F1,dark:0x0B1017)
    static let navigationBackground = semantic(light:0xF3F1EC,dark:0x101722)
    static let primarySurface = semantic(light:0xFFFFFF,dark:0x141C27)
    static let raisedSurface = semantic(light:0xF1F4F8,dark:0x1C2735)
    static let fieldSurface = semantic(light:0xEEF1F5,dark:0x101923)
    static let primaryText = semantic(light:0x0D1A2B,dark:0xF3F6FB)
    static let secondaryText = semantic(light:0x43536A,dark:0xA3B1C4)
    static let tertiaryText = semantic(light:0x5F6F84,dark:0x7F8DA1)
    static let border = semantic(light:0xD8DDE5,dark:0x263344)
    static let selectedBorder = semantic(light:0x086CF0,dark:0x4C9FFF)
    static let cobalt = semantic(light:0x005FC9,dark:0x3D99FF)
    static let cobaltPressed = semantic(light:0x0056C7,dark:0x1D7EDF)
    static let cobaltDisabled = semantic(light:0xA7C8EF,dark:0x345472)
    static let healthy = semantic(light:0x08773D,dark:0x36C477)
    static let fuelAttention = semantic(light:0xA65E00,dark:0xE7A62B)
    static let recordingFault = semantic(light:0xC52637,dark:0xFF5C62)
    static let unavailable = semantic(light:0x5F6F84,dark:0x7B8798)
    static let chartSeries:[Color] = [
        semantic(light:0x0068D7,dark:0x4CA6FF), semantic(light:0xB84A00,dark:0xFF9B52),
        semantic(light:0x167A43,dark:0x50D890), semantic(light:0x7D43A8,dark:0xC68CFF),
        semantic(light:0xA1264D,dark:0xFF7CA5)
    ]
    static let routePrimary = cobalt
    static let routeSecondary = semantic(light:0x306F91,dark:0x65B6D9)
    static let routeGap = unavailable

    // Compatibility aliases while feature views move to named semantic roles.
    static let background=appBackground, sidebar=navigationBackground, panel=primarySurface, raised=raisedSurface
    static let line=border, text=primaryText, muted=secondaryText, blue=cobalt, green=healthy
    enum Spacing { static let xSmall:CGFloat=4, small:CGFloat=8, medium:CGFloat=12, large:CGFloat=18, xLarge:CGFloat=24 }
    enum Radius { static let small:CGFloat=7, medium:CGFloat=10, large:CGFloat=14 }
    enum Control { static let standardHeight:CGFloat=36, prominentHeight:CGFloat=44 }

    private static func semantic(light:UInt32,dark:UInt32)->Color {
        Color(nsColor:NSColor(name:nil) { appearance in
            appearance.bestMatch(from:[.darkAqua,.aqua]) == .darkAqua ? NSColor(hex:dark):NSColor(hex:light)
        })
    }
}
private extension NSColor {
    convenience init(hex:UInt32) { self.init(srgbRed:CGFloat((hex>>16)&255)/255,green:CGFloat((hex>>8)&255)/255,blue:CGFloat(hex&255)/255,alpha:1) }
}
extension DriveLineAppearance {
    var colorScheme:ColorScheme? { switch self { case .system:nil;case .light:.light;case .dark:.dark } }
}
struct AppearancePreferencePicker:View {
    @AppStorage(DriveLineAppearance.storageKey) private var rawValue=DriveLineAppearance.system.rawValue
    var body:some View {
        Picker("Appearance",selection:$rawValue) { ForEach(DriveLineAppearance.allCases) { Text($0.title).tag($0.rawValue) } }
            .pickerStyle(.segmented).accessibilityIdentifier("appearance.picker")
    }
}
typealias Workspace=DriveLineMacDestination
extension DriveLineMacDestination {
    var icon: String {
        switch self { case .today:return "sun.max";case .drives:return "point.topleft.down.curvedto.point.bottomright.up";case .fuel:return "fuelpump";case .signals:return "waveform.path.ecg";case .garage:return "car";case .imports:return "square.and.arrow.down";case .server:return "server.rack" }
    }
    var subtitle: String {
        switch self {case .today:return "Current status, recent activity, and summaries.";case .drives:return "Your drive ledger, playback, and comparisons.";case .fuel:return "Purchased fills and receipt history.";case .signals:return "Independent cards for recorded vehicle signals.";case .garage:return "One system for every vehicle.";case .imports:return "From phone or recorder to your Mac.";case .server:return "Ingestion, storage, and background services."}
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
