import SwiftUI

private extension DriveLineSemanticState {
    var phoneColor:Color {
        switch self {
        case .healthy:Palette.healthy
        case .stale,.queued:Palette.fuelAttention
        case .unavailable:Palette.unavailable
        case .recording:Palette.recordingFault
        }
    }
}

struct StatusPill:View {
    let state:DriveLineSemanticState
    var text:String?=nil
    var body:some View {
        Label(text ?? state.title,systemImage:state.icon).font(.caption.weight(.semibold))
            .foregroundStyle(state.phoneColor).padding(.horizontal,9).padding(.vertical,6)
            .background(state.phoneColor.opacity(0.12),in:Capsule()).accessibilityElement(children:.combine)
    }
}

struct SourceBadge:View {
    let source:String
    var verified=false
    var body:some View {
        Label(source,systemImage:verified ? "checkmark.shield.fill":"dot.radiowaves.left.and.right")
            .font(.caption2.weight(.medium)).foregroundStyle(verified ? Palette.healthy:Palette.secondaryText)
            .accessibilityLabel("Source: \(source)\(verified ? ", verified":"")")
    }
}

struct FreshnessLabel:View {
    let observedAt:Date?
    var now=Date()
    var staleAfter:TimeInterval=60
    var body:some View {
        let age=observedAt.map { max(0,now.timeIntervalSince($0)) }
        let state:DriveLineSemanticState=age==nil ? .unavailable:(age!>staleAfter ? .stale:.healthy)
        Label(freshness(age),systemImage:state.icon).font(.caption2).foregroundStyle(state.phoneColor)
            .accessibilityLabel("Freshness: \(freshness(age))")
    }
    private func freshness(_ age:TimeInterval?)->String {
        guard let age else { return "Not observed" }
        if age<5 { return "Live" }
        if age<60 { return "Observed \(Int(age)) seconds ago" }
        return "Observed \(Int(age/60)) minutes ago"
    }
}

struct AvailabilityValue:View {
    let value:String?
    var unit=""
    var source:String?=nil
    var observedAt:Date?=nil
    var body:some View {
        VStack(alignment:.leading,spacing:5) {
            HStack(alignment:.firstTextBaseline,spacing:4) {
                Text(value ?? "—").font(.title2.weight(.semibold)).monospacedDigit()
                if !unit.isEmpty { Text(unit).font(.caption).foregroundStyle(Palette.secondaryText) }
            }
            HStack(spacing:8) { if let source { SourceBadge(source:source) };FreshnessLabel(observedAt:observedAt) }
        }.accessibilityElement(children:.combine).accessibilityValue(value.map { "\($0) \(unit)" } ?? "Unavailable")
    }
}

struct MetricTile:View {
    let title:String
    let value:String?
    var unit=""
    var state:DriveLineSemanticState = .healthy
    var source:String?=nil
    var body:some View {
        VStack(alignment:.leading,spacing:10) {
            HStack { Text(title).font(.caption.weight(.medium)).foregroundStyle(Palette.secondaryText);Spacer();Image(systemName:state.icon).foregroundStyle(state.phoneColor) }
            AvailabilityValue(value:value,unit:unit,source:source,observedAt:state == .unavailable ? nil:Date())
        }.padding(13).background(Palette.primarySurface,in:RoundedRectangle(cornerRadius:Palette.Radius.medium))
            .overlay(RoundedRectangle(cornerRadius:Palette.Radius.medium).stroke(Palette.border))
    }
}

struct SectionCard<Content:View>:View {
    let title:String
    var icon:String?=nil
    @ViewBuilder var content:Content
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            HStack { if let icon { Image(systemName:icon).foregroundStyle(Palette.cobalt) };Text(title).font(.headline);Spacer() }
            content
        }.padding(16).background(Palette.primarySurface,in:RoundedRectangle(cornerRadius:Palette.Radius.large))
            .overlay(RoundedRectangle(cornerRadius:Palette.Radius.large).stroke(Palette.border))
    }
}

struct RecoveryBanner:View {
    let title:String
    let message:String
    var actionTitle:String?=nil
    var action:(()->Void)?=nil
    var body:some View {
        VStack(alignment:.leading,spacing:9) {
            Label(title,systemImage:"arrow.clockwise.circle.fill").font(.headline).foregroundStyle(Palette.fuelAttention)
            Text(message).font(.subheadline).foregroundStyle(Palette.secondaryText)
            if let actionTitle,let action { Button(actionTitle,action:action).frame(minHeight:44) }
        }.frame(maxWidth:.infinity,alignment:.leading).padding(14)
            .background(Palette.fuelAttention.opacity(0.1),in:RoundedRectangle(cornerRadius:Palette.Radius.medium))
            .overlay(RoundedRectangle(cornerRadius:Palette.Radius.medium).stroke(Palette.fuelAttention.opacity(0.55)))
            .accessibilityElement(children:.combine)
    }
}

struct EmptyStateCard:View {
    let icon:String
    let title:String
    let message:String
    var actionTitle:String?=nil
    var action:(()->Void)?=nil
    var body:some View {
        VStack(spacing:12) {
            Image(systemName:icon).font(.system(size:30)).foregroundStyle(Palette.unavailable)
            Text(title).font(.headline)
            Text(message).font(.body).foregroundStyle(Palette.secondaryText).multilineTextAlignment(.center)
            if let actionTitle,let action { Button(actionTitle,action:action).buttonStyle(.borderedProminent).frame(minHeight:44) }
        }.frame(maxWidth:.infinity,minHeight:180).padding(20).background(Palette.primarySurface,in:RoundedRectangle(cornerRadius:Palette.Radius.large))
            .overlay(RoundedRectangle(cornerRadius:Palette.Radius.large).stroke(Palette.border))
    }
}

#if DEBUG
struct PhoneSemanticStateGallery:View {
    var body:some View { ScrollView { VStack(alignment:.leading,spacing:14) {
        AppearancePreferencePicker()
        LazyVGrid(columns:[GridItem(.adaptive(minimum:105))]) { ForEach(DriveLineSemanticState.allCases) { StatusPill(state:$0) } }
        HStack { MetricTile(title:"Coolant",value:"89",unit:"°C",state:.healthy,source:"OBD");MetricTile(title:"Boost",value:nil,unit:"kPa",state:.unavailable,source:"OBD") }
        RecoveryBanner(title:"Upload queued",message:"The original is safe locally and will retry automatically.")
    }.padding(18) }.background(Palette.appBackground).foregroundStyle(Palette.primaryText) }
}
#Preview("iPhone semantic states · Light") { PhoneSemanticStateGallery().preferredColorScheme(.light) }
#Preview("iPhone semantic states · Dark") { PhoneSemanticStateGallery().preferredColorScheme(.dark) }
#endif
