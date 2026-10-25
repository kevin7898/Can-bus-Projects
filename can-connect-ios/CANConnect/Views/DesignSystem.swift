import SwiftUI
import UIKit

enum Palette {
    static let appBackground = semantic(light:0xF7F5F1,dark:0x0B1017)
    static let navigationBackground = semantic(light:0xF3F1EC,dark:0x101722)
    static let primarySurface = semantic(light:0xFFFFFF,dark:0x141C27)
    static let raisedSurface = semantic(light:0xF1F4F8,dark:0x1C2735)
    static let fieldSurface = semantic(light:0xEEF1F5,dark:0x101923)
    static let primaryText = semantic(light:0x0D1A2B,dark:0xF3F6FB)
    static let secondaryText = semantic(light:0x43536A,dark:0xA3B1C4)
    static let tertiaryText = semantic(light:0x708096,dark:0x7F8DA1)
    static let border = semantic(light:0xD8DDE5,dark:0x263344)
    static let selectedBorder = semantic(light:0x086CF0,dark:0x4C9FFF)
    static let cobalt = semantic(light:0x066FF9,dark:0x3D99FF)
    static let cobaltPressed = semantic(light:0x0056C7,dark:0x1D7EDF)
    static let cobaltDisabled = semantic(light:0xA7C8EF,dark:0x345472)
    static let healthy = semantic(light:0x138A4A,dark:0x36C477)
    static let fuelAttention = semantic(light:0xA65E00,dark:0xE7A62B)
    static let recordingFault = semantic(light:0xD83443,dark:0xFF5C62)
    static let unavailable = semantic(light:0x737E8D,dark:0x7B8798)
    static let chartSeries:[Color] = [
        semantic(light:0x0068D7,dark:0x4CA6FF),semantic(light:0xB84A00,dark:0xFF9B52),
        semantic(light:0x167A43,dark:0x50D890),semantic(light:0x7D43A8,dark:0xC68CFF),
        semantic(light:0xA1264D,dark:0xFF7CA5)
    ]
    static let routePrimary=cobalt, routeSecondary=semantic(light:0x306F91,dark:0x65B6D9), routeGap=unavailable
    static let background=appBackground, surface=primarySurface, raised=raisedSurface
    static let text=primaryText, muted=secondaryText, blue=cobalt, green=healthy, amber=fuelAttention, red=recordingFault
    enum Spacing { static let xSmall:CGFloat=4, small:CGFloat=8, medium:CGFloat=12, large:CGFloat=18, xLarge:CGFloat=24 }
    enum Radius { static let small:CGFloat=8, medium:CGFloat=12, large:CGFloat=16 }
    enum Control { static let minimum:CGFloat=44, prominent:CGFloat=48 }
    private static func semantic(light:UInt32,dark:UInt32)->Color { Color(uiColor:UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex:dark):UIColor(hex:light) }) }
}
extension Color { init(hex: UInt32) { self.init(.sRGB, red:Double((hex >> 16) & 255)/255, green:Double((hex >> 8) & 255)/255, blue:Double(hex & 255)/255, opacity:1) } }
private extension UIColor { convenience init(hex:UInt32) { self.init(red:CGFloat((hex>>16)&255)/255,green:CGFloat((hex>>8)&255)/255,blue:CGFloat(hex&255)/255,alpha:1) } }
extension DriveLineAppearance { var colorScheme:ColorScheme? { switch self { case .system:nil;case .light:.light;case .dark:.dark } } }
struct AppearancePreferencePicker:View {
    @AppStorage(DriveLineAppearance.storageKey) private var rawValue=DriveLineAppearance.system.rawValue
    var body:some View { Picker("Appearance",selection:$rawValue) { ForEach(DriveLineAppearance.allCases) { Text($0.title).tag($0.rawValue) } }.pickerStyle(.segmented).accessibilityIdentifier("appearance.picker") }
}
extension View {
    func card() -> some View { padding(14).background(Palette.surface, in:RoundedRectangle(cornerRadius:14)).overlay(RoundedRectangle(cornerRadius:14).stroke(Palette.border, lineWidth:1)) }
    func captionStyle() -> some View { font(.system(size:11)).foregroundStyle(Palette.muted) }
}
struct Eyebrow: View { let text: String; var body: some View { Text(text.uppercased()).font(.system(size:10, weight:.medium)).tracking(1.7).foregroundStyle(Palette.blue) } }
struct AppButton: View {
    let title: String; var icon: String = ""; var destructive = false; var secondary = false; let action: () -> Void
    var body: some View {
        Button(action:action) { HStack(spacing:8) { if !icon.isEmpty { Image(systemName:icon) }; Text(title) }.font(.system(size:14, weight:.medium)).frame(maxWidth:.infinity).frame(height:46).contentShape(Rectangle()) }
            .foregroundStyle(secondary ? Palette.text : Palette.background)
            .background(secondary ? Palette.raised : (destructive ? Palette.red : Palette.blue), in:RoundedRectangle(cornerRadius:12))
    }
}
struct PageControl: View {
    let labels: [String]; @Binding var selection: Int
    var body: some View {
        HStack(spacing:3) { ForEach(labels.indices, id:\.self) { index in
            Button { withAnimation(.easeInOut(duration:0.2)) { selection = index } } label: {
                Text(labels[index]).font(.system(size:12, weight:.medium)).lineLimit(1).minimumScaleFactor(0.75).frame(maxWidth:.infinity).frame(minHeight:42).background(selection == index ? Palette.raised : .clear, in:RoundedRectangle(cornerRadius:9))
            }.foregroundStyle(selection == index ? Palette.text : Palette.muted).accessibilityAddTraits(selection == index ? .isSelected : [])
        } }.padding(3).background(Color(hex:0x101923), in:RoundedRectangle(cornerRadius:12))
    }
}
struct Metric: View {
    let title: String; let value: String; var unit = ""
    var body: some View { VStack(alignment:.leading, spacing:5) { Text(title).captionStyle(); HStack(alignment:.firstTextBaseline, spacing:4) { Text(value).font(.system(size:23, weight:.medium)).monospacedDigit(); Text(unit).font(.system(size:10)).foregroundStyle(Palette.muted) }.lineLimit(1).minimumScaleFactor(0.65) }.frame(maxWidth:.infinity, alignment:.leading) }
}
struct DataRow: View {
    let label: String; let value: String
    var body: some View { HStack { Text(label).foregroundStyle(Palette.muted); Spacer(); Text(value).fontWeight(.medium) }.font(.system(size:13)).padding(.vertical,13).overlay(alignment:.bottom) { Rectangle().fill(Palette.border).frame(height:0.5) } }
}
struct InfoNote: View {
    let text: String; var icon = "info.circle"
    var body: some View { HStack(alignment:.top, spacing:8) { Image(systemName:icon); Text(text).fixedSize(horizontal:false, vertical:true) }.font(.system(size:11)).foregroundStyle(Palette.muted).frame(maxWidth:.infinity, alignment:.leading) }
}
struct SheetShell<Content: View>: View {
    let title: String; @ViewBuilder var content: Content
    @Environment(\.dismiss) private var dismiss
    var body: some View { NavigationStack { ScrollView { VStack(alignment:.leading, spacing:18) { content }.padding(20) }.background(Palette.background).navigationTitle(title).navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement:.topBarTrailing) { Button("Done") { dismiss() } } }.toolbarBackground(Palette.surface, for:.navigationBar).toolbarBackground(.visible, for:.navigationBar) }.tint(Palette.blue) }
}
struct EconomyChart: View {
    var body: some View { GeometryReader { g in
        Path { p in let values: [Double] = [6.2,5.9,6,5.7,5.8,5.5,5.6,5.3,5.5,5.4,5.2,5.4]
            for (i,v) in values.enumerated() { let point = CGPoint(x:Double(i) / Double(values.count - 1) * g.size.width, y:(6.5-v)/1.6*g.size.height); if i == 0 { p.move(to:point) } else { p.addLine(to:point) } }
        }.stroke(Palette.blue, style:StrokeStyle(lineWidth:2, lineCap:.round, lineJoin:.round))
    }.frame(height:65).accessibilityLabel("Sample fuel economy trend from 6.2 to 5.4 litres per 100 kilometres") }
}
