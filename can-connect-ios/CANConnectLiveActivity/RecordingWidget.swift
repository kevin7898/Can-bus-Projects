import ActivityKit
import SwiftUI
import WidgetKit

@main
struct CANConnectWidgets: WidgetBundle {
    var body: some Widget { RecordingWidget() }
}

struct RecordingWidget: Widget {
    private let accent = Color(red:88/255,green:167/255,blue:1)
    var body: some WidgetConfiguration {
        ActivityConfiguration(for:RecordingActivityAttributes.self) { context in
            HStack(spacing:16) {
                Image(systemName:"waveform.path.ecg").font(.title2).foregroundStyle(accent)
                VStack(alignment:.leading,spacing:4) {
                    Text("CAN / CONNECT").font(.caption.weight(.semibold)).tracking(1.5)
                    Text(context.attributes.source).font(.caption).foregroundStyle(.secondary)
                    Text(status(context)).font(.subheadline.weight(.medium))
                }
                Spacer(minLength:8)
                VStack(alignment:.trailing,spacing:4) {
                    timer(context).font(.title2.monospacedDigit())
                    if !context.attributes.countUnit.isEmpty { Text("\(context.state.responses) \(context.attributes.countUnit)").font(.caption2).foregroundStyle(.secondary) }
                }
            }
            .padding(16)
            .activityBackgroundTint(Color(red:11/255,green:16/255,blue:23/255))
            .activitySystemActionForegroundColor(.white)
            .foregroundStyle(.white)
            .widgetURL(URL(string:"canconnect://recording"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("CAN / CONNECT",systemImage:"waveform.path.ecg").font(.caption.weight(.semibold)).foregroundStyle(accent)
                }
                DynamicIslandExpandedRegion(.trailing) { timer(context).font(.headline.monospacedDigit()) }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        VStack(alignment:.leading) {
                            Text(status(context)).font(.subheadline.weight(.medium))
                            Text(context.attributes.source).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if !context.attributes.countUnit.isEmpty { Text("\(context.state.responses) \(context.attributes.countUnit)").font(.caption).foregroundStyle(.secondary) }
                    }.padding(.top,4).padding(.horizontal,8)
                }
            } compactLeading: {
                Image(systemName:context.isStale ? "pause.circle" : "waveform.path.ecg").foregroundStyle(accent)
            } compactTrailing: {
                timer(context).font(.caption2.monospacedDigit()).frame(maxWidth:64)
            } minimal: {
                Image(systemName:context.isStale ? "pause.circle" : "waveform.path.ecg").foregroundStyle(accent)
            }
            .widgetURL(URL(string:"canconnect://recording"))
            .keylineTint(accent)
        }
    }
    private func status(_ context: ActivityViewContext<RecordingActivityAttributes>) -> String {
        context.isStale && !context.state.ended ? "Waiting for readings" : context.state.status
    }
    @ViewBuilder
    private func timer(_ context: ActivityViewContext<RecordingActivityAttributes>) -> some View {
        if context.isStale || context.state.ended { Text(context.state.elapsedText) }
        else { Text(timerInterval:context.state.startedAt...Date.distantFuture,countsDown:false).multilineTextAlignment(.trailing) }
    }
}
