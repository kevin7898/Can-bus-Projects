import SwiftUI

enum Palette {
    static let background = Color(hex:0x0b1017), surface = Color(hex:0x141c27), raised = Color(hex:0x1c2735)
    static let border = Color(hex:0x263344), text = Color(hex:0xf3f6fb), muted = Color(hex:0xa3b1c4)
    static let blue = Color(hex:0x58a7ff), green = Color(hex:0x7ed5b5), amber = Color(hex:0xe7bc74), red = Color(hex:0xf28a92)
}
extension Color { init(hex: UInt32) { self.init(.sRGB, red:Double((hex >> 16) & 255)/255, green:Double((hex >> 8) & 255)/255, blue:Double(hex & 255)/255, opacity:1) } }
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
    var body: some View { NavigationStack { ScrollView { VStack(alignment:.leading, spacing:18) { content }.padding(20) }.background(Palette.background).navigationTitle(title).navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement:.topBarTrailing) { Button("Done") { dismiss() } } }.toolbarBackground(Palette.surface, for:.navigationBar).toolbarBackground(.visible, for:.navigationBar) }.preferredColorScheme(.dark).tint(Palette.blue) }
}
struct EconomyChart: View {
    var body: some View { GeometryReader { g in
        Path { p in let values: [Double] = [6.2,5.9,6,5.7,5.8,5.5,5.6,5.3,5.5,5.4,5.2,5.4]
            for (i,v) in values.enumerated() { let point = CGPoint(x:Double(i) / Double(values.count - 1) * g.size.width, y:(6.5-v)/1.6*g.size.height); if i == 0 { p.move(to:point) } else { p.addLine(to:point) } }
        }.stroke(Palette.blue, style:StrokeStyle(lineWidth:2, lineCap:.round, lineJoin:.round))
    }.frame(height:65).accessibilityLabel("Sample fuel economy trend from 6.2 to 5.4 litres per 100 kilometres") }
}
