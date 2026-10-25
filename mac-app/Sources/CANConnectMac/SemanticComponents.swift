import SwiftUI

private extension DriveLineSemanticState {
    var macColor:Color {
        switch self {
        case .ready,.complete,.recovered:Theme.healthy
        case .waiting,.queued,.processing,.degraded,.stale:Theme.fuelAttention
        case .unavailable,.offline,.readOnly:Theme.unavailable
        case .active,.failed:Theme.recordingFault
        }
    }
}

struct StatusPill:View {
    let state:DriveLineSemanticState
    var text:String?=nil
    var body:some View {
        Label(text ?? state.title,systemImage:state.icon).font(.system(size:10,weight:.semibold))
            .foregroundStyle(state.macColor).padding(.horizontal,9).padding(.vertical,5)
            .background(state.macColor.opacity(0.12),in:Capsule())
            .accessibilityElement(children:.combine)
    }
}

struct SourceBadge:View {
    let source:String
    var verified=false
    var body:some View {
        Label(source,systemImage:verified ? "checkmark.shield.fill":"dot.radiowaves.left.and.right")
            .font(.system(size:10,weight:.medium)).foregroundStyle(verified ? Theme.healthy:Theme.secondaryText)
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
        Label(freshness(age),systemImage:state.icon).font(.system(size:10)).foregroundStyle(state.macColor)
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
    var showsFreshness=true
    var body:some View {
        VStack(alignment:.leading,spacing:4) {
            HStack(alignment:.firstTextBaseline,spacing:4) {
                Text(value ?? "—").font(.system(size:21,weight:.semibold,design:.rounded)).monospacedDigit()
                if !unit.isEmpty { Text(unit).font(.caption).foregroundStyle(Theme.secondaryText) }
            }
            HStack(spacing:8) { if let source { SourceBadge(source:source) };if showsFreshness { FreshnessLabel(observedAt:observedAt) } }
        }.accessibilityElement(children:.combine).accessibilityValue(value.map { "\($0) \(unit)" } ?? "Unavailable")
    }
}

struct MetricTile:View {
    let title:String
    let value:String?
    var unit=""
    var state:DriveLineSemanticState = .healthy
    var source:String?=nil
    var showsFreshness=true
    var body:some View {
        VStack(alignment:.leading,spacing:10) {
            HStack { Text(title).font(.system(size:11,weight:.medium)).foregroundStyle(Theme.secondaryText);Spacer();Image(systemName:state.icon).foregroundStyle(state.macColor) }
            AvailabilityValue(value:value,unit:unit,source:source,observedAt:state == .unavailable ? nil:Date(),showsFreshness:showsFreshness)
        }.padding(13).background(Theme.primarySurface,in:RoundedRectangle(cornerRadius:Theme.Radius.medium))
            .overlay(RoundedRectangle(cornerRadius:Theme.Radius.medium).stroke(Theme.border))
    }
}

struct SectionCard<Content:View>:View {
    let title:String
    var icon:String?=nil
    @ViewBuilder var content:Content
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            HStack { if let icon { Image(systemName:icon).foregroundStyle(Theme.cobalt) };Text(title).font(.headline);Spacer() }
            content
        }.padding(16).background(Theme.primarySurface,in:RoundedRectangle(cornerRadius:Theme.Radius.large))
            .overlay(RoundedRectangle(cornerRadius:Theme.Radius.large).stroke(Theme.border))
    }
}

struct RecoveryBanner:View {
    let title:String
    let message:String
    var actionTitle:String?=nil
    var action:(()->Void)?=nil
    var body:some View {
        HStack(alignment:.top,spacing:12) {
            Image(systemName:"arrow.clockwise.circle.fill").foregroundStyle(Theme.fuelAttention)
            VStack(alignment:.leading,spacing:4) { Text(title).font(.headline);Text(message).font(.caption).foregroundStyle(Theme.secondaryText) }
            Spacer()
            if let actionTitle,let action { Button(actionTitle,action:action) }
        }.padding(13).background(Theme.fuelAttention.opacity(0.1),in:RoundedRectangle(cornerRadius:Theme.Radius.medium))
            .overlay(RoundedRectangle(cornerRadius:Theme.Radius.medium).stroke(Theme.fuelAttention.opacity(0.55)))
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
            Image(systemName:icon).font(.system(size:30)).foregroundStyle(Theme.unavailable)
            Text(title).font(.headline)
            Text(message).font(.body).foregroundStyle(Theme.secondaryText).multilineTextAlignment(.center)
            if let actionTitle,let action { Button(actionTitle,action:action).buttonStyle(.borderedProminent) }
        }.frame(maxWidth:.infinity,minHeight:180).padding(20).background(Theme.primarySurface,in:RoundedRectangle(cornerRadius:Theme.Radius.large))
            .overlay(RoundedRectangle(cornerRadius:Theme.Radius.large).stroke(Theme.border))
    }
}

#if DEBUG
struct MacSemanticStateGallery:View {
    var body:some View { VStack(alignment:.leading,spacing:14) {
        AppearancePreferencePicker().frame(width:320)
        HStack { ForEach(DriveLineSemanticState.allCases) { StatusPill(state:$0) } }
        HStack { MetricTile(title:"Coolant",value:"89",unit:"°C",state:.healthy,source:"OBD");MetricTile(title:"Boost",value:nil,unit:"kPa",state:.unavailable,source:"OBD") }
        RecoveryBanner(title:"Upload queued",message:"The original is safe locally and will retry automatically.")
    }.padding(24).background(Theme.appBackground).foregroundStyle(Theme.primaryText).frame(width:760,height:360) }
}
#Preview("Mac semantic states · Light") { MacSemanticStateGallery().preferredColorScheme(.light) }
#Preview("Mac semantic states · Dark") { MacSemanticStateGallery().preferredColorScheme(.dark) }
#endif
