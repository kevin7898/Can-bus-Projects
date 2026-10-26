import SwiftUI

private extension DriveLineSemanticState {
    var phoneColor:Color {
        switch self {
        case .ready,.complete,.recovered:Palette.healthy
        case .waiting,.queued,.processing,.degraded,.stale:Palette.fuelAttention
        case .unavailable,.offline,.readOnly:Palette.unavailable
        case .active,.failed:Palette.recordingFault
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

struct ObservationFreshnessDisplay:Equatable {
    var state:DriveLineSemanticState
    var label:String
    static func resolve(observedAt:Date?,now:Date,staleAfter:TimeInterval,
                        semanticState:DriveLineSemanticState?=nil,statusText:String?=nil)->Self {
        let age=observedAt.map { max(0,now.timeIntervalSince($0)) }
        let state=semanticState ?? (age == nil ? .unavailable:(age! > staleAfter ? .stale:.ready))
        if let statusText { return Self(state:state,label:statusText) }
        if state == .offline { return Self(state:state,label:"Scanner disconnected") }
        if state == .unavailable { return Self(state:state,label:"Not observed") }
        guard let age else { return Self(state:state,label:state == .stale ? "Stale":"Not observed") }
        if state == .stale {
            let text=age < 60 ? "\(max(1,Int(age)))s ago":age < 3_600 ? "\(Int(age/60))m ago":"\(Int(age/3_600))h ago"
            return Self(state:state,label:"Stale · \(text)")
        }
        if age<5 { return Self(state:state,label:"Live") }
        if age<60 { return Self(state:state,label:"Observed \(Int(age)) seconds ago") }
        return Self(state:state,label:"Observed \(Int(age/60)) minutes ago")
    }
}

struct FreshnessLabel:View {
    let observedAt:Date?
    var now=Date()
    var staleAfter:TimeInterval=60
    var semanticState:DriveLineSemanticState?=nil
    var statusText:String?=nil
    var body:some View {
        let display=ObservationFreshnessDisplay.resolve(observedAt:observedAt,now:now,staleAfter:staleAfter,
            semanticState:semanticState,statusText:statusText)
        Label(display.label,systemImage:display.state.icon).font(.caption2).foregroundStyle(display.state.phoneColor)
            .accessibilityLabel("Freshness: \(display.label)")
    }
}

struct AvailabilityValue:View {
    let value:String?
    var unit=""
    var source:String?=nil
    var observedAt:Date?=nil
    var showsFreshness=true
    var state:DriveLineSemanticState = .ready
    var statusText:String?=nil
    var now=Date()
    var body:some View {
        VStack(alignment:.leading,spacing:5) {
            HStack(alignment:.firstTextBaseline,spacing:4) {
                Text(value ?? "—").font(.title2.weight(.semibold)).monospacedDigit()
                    .foregroundStyle(state == .ready ? Palette.primaryText:state.phoneColor)
                if !unit.isEmpty { Text(unit).font(.caption).foregroundStyle(Palette.secondaryText) }
            }
            HStack(spacing:8) { if let source { SourceBadge(source:source) };if showsFreshness { FreshnessLabel(observedAt:observedAt,now:now,semanticState:state,statusText:statusText) } }
        }.accessibilityElement(children:.combine).accessibilityValue(value.map { "\($0) \(unit)" } ?? "Unavailable")
    }
}

struct MetricTile:View {
    let title:String
    let value:String?
    var unit=""
    var state:DriveLineSemanticState = .ready
    var source:String?=nil
    var showsFreshness=true
    var observedAt:Date?=nil
    var statusText:String?=nil
    var now=Date()
    var body:some View {
        VStack(alignment:.leading,spacing:10) {
            HStack { Text(title).font(.caption.weight(.medium)).foregroundStyle(Palette.secondaryText);Spacer();Image(systemName:state.icon).foregroundStyle(state.phoneColor) }
            AvailabilityValue(value:value,unit:unit,source:source,observedAt:observedAt,showsFreshness:showsFreshness,
                state:state,statusText:statusText,now:now)
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
struct Phase8StateEvidenceView:View {
    let ids:[Int]
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var states:[DriveLineStateDescriptor] { ids.compactMap(DriveLineStateMatrix.state) }
    private var heading:some View {
        VStack(alignment:.leading,spacing:4) {
            Text(dynamicTypeSize.isAccessibilitySize ? "SANITIZED\nSAMPLE" : "SANITIZED SAMPLE")
                .font(.caption2.weight(.bold)).tracking(dynamicTypeSize.isAccessibilitySize ? 0:1.4)
                .foregroundStyle(Palette.fuelAttention).fixedSize(horizontal:false,vertical:true)
            Text("Recovery states").font(.title2.weight(.semibold)).fixedSize(horizontal:false,vertical:true)
            Text("Fictional 2013 Volkswagen Jetta TDI · debug-only evidence").font(.caption).foregroundStyle(Palette.secondaryText).fixedSize(horizontal:false,vertical:true)
        }
    }
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            if dynamicTypeSize.isAccessibilitySize {
                heading
            } else {
                HStack {
                    heading
                    Spacer();Image(systemName:"shield.checkered").foregroundStyle(Palette.cobalt)
                }
            }
            ScrollView {
                VStack(spacing:12) {
                    ForEach(states) { item in
                        SectionCard(title:item.title,icon:item.state.icon) {
                            HStack { StatusPill(state:item.state);Spacer();Text(item.platform.rawValue).font(.caption2).foregroundStyle(Palette.tertiaryText) }
                            Text(item.wording).font(.subheadline).foregroundStyle(Palette.primaryText)
                            VStack(alignment:.leading,spacing:5) {
                                Label("Safe: \(item.persistedEvidence)",systemImage:"lock.shield")
                                    .accessibilityLabel("Persisted evidence. \(item.persistedEvidence)")
                                    .accessibilityIdentifier("phase8.state.\(item.id).evidence")
                                Label(item.recoveryResult,systemImage:"arrow.counterclockwise")
                                    .accessibilityLabel("Recovery result. \(item.recoveryResult)")
                                    .accessibilityIdentifier("phase8.state.\(item.id).recovery")
                            }.font(.caption).foregroundStyle(Palette.secondaryText)
                            if !item.actions.isEmpty {
                                HStack { ForEach(item.actions.prefix(2),id:\.self) { action in Button(action.title) {}.buttonStyle(.bordered).disabled(true) } }
                                Text("Fixture actions are disabled; production enables only safe implemented targets.").font(.caption2).foregroundStyle(Palette.tertiaryText)
                            }
                        }.accessibilityIdentifier("phase8.state.\(item.id)")
                    }
                }.padding(.bottom,12)
            }
        }.padding(18).background(Palette.appBackground.ignoresSafeArea()).foregroundStyle(Palette.primaryText)
            .accessibilityIdentifier("phase8.evidence")
    }
}
#endif

#if DEBUG
struct PhoneSemanticStateGallery:View {
    var body:some View { ScrollView { VStack(alignment:.leading,spacing:14) {
        AppearancePreferencePicker()
        LazyVGrid(columns:[GridItem(.adaptive(minimum:105))]) { ForEach(DriveLineSemanticState.allCases) { StatusPill(state:$0) } }
        HStack { MetricTile(title:"Coolant",value:"89",unit:"°C",state:.ready,source:"OBD");MetricTile(title:"Boost",value:nil,unit:"kPa",state:.unavailable,source:"OBD") }
        RecoveryBanner(title:"Upload queued",message:"The original is safe locally and will retry automatically.")
    }.padding(18) }.background(Palette.appBackground).foregroundStyle(Palette.primaryText) }
}
#Preview("iPhone semantic states · Light") { PhoneSemanticStateGallery().preferredColorScheme(.light) }
#Preview("iPhone semantic states · Dark") { PhoneSemanticStateGallery().preferredColorScheme(.dark) }
#endif
