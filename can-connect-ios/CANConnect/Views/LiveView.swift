import SwiftUI

struct LiveView: View {
    @EnvironmentObject private var store: AppStore
    @Binding var page: Int

    private var presentation:PhoneRecordingPresentation {
        .make(state:store.state,selectedSource:store.source,pendingGPS:store.pendingGPS,
              scannerConnected:store.scanner.connected,scannerConnecting:store.scanner.connecting,
              scannerStatus:store.scanner.status,gpsStatus:store.gps.status,gpsSpeedKMH:store.gps.speedKMH,
              gpsLastFix:store.gps.lastFix,now:store.now)
    }

    var body:some View {
        GeometryReader { geometry in
            VStack(spacing:8) {
                ScrollView {
                    VStack(alignment:.leading,spacing:12) {
                        recordingHeader
                        if let title=presentation.recoveryTitle,let message=presentation.recoveryMessage {
                            RecoveryBanner(title:title,message:message,actionTitle:store.source == .scanner ? "Retry connection":nil) {
                                store.reconcileScannerConnection(at:Date().addingTimeInterval(61))
                            }.accessibilityIdentifier("record.recovery")
                        }
                        if presentation.phase == .idle || presentation.phase == .starting { preflight }
                        else { activeRecording }
                    }
                    .padding(.horizontal,1).padding(.bottom,4)
                    .frame(maxWidth:.infinity,minHeight:max(0,geometry.size.height-88),alignment:.top)
                }.scrollBounceBehavior(.basedOnSize).accessibilityIdentifier("record.content")
                recordButton
            }
        }
    }

    private var recordingHeader:some View {
        VStack(alignment:.leading,spacing:9) {
            HStack {
                StatusPill(state:presentation.phase == .active || presentation.phase == .degraded ? .recording:phaseSemantic,
                           text:presentation.statusTitle)
                Spacer()
                if store.recording { Text(store.timerText).font(.headline).monospacedDigit() }
            }
            Text(presentation.statusMessage).font(.subheadline).foregroundStyle(Palette.secondaryText)
            HStack(spacing:8) {
                StatusPill(state:presentation.gpsState,text:"GPS")
                StatusPill(state:presentation.scannerState,text:"Scanner")
                StatusPill(state:presentation.localState,text:store.recording ? "Recording locally":"Local ready")
            }
            if let queuedStatusTitle=presentation.queuedStatusTitle { StatusPill(state:.queued,text:queuedStatusTitle) }
        }.padding(.bottom,2)
    }

    private var preflight:some View {
        VStack(alignment:.leading,spacing:12) {
            SectionCard(title:"Recording source",icon:"dot.radiowaves.left.and.right") {
                Picker("Recording source",selection:$store.source) {
                    Text("iPhone GPS").tag(TripSource.phoneGPS)
                    Text("OBD scanner + GPS").tag(TripSource.scanner)
                    Text("Sample preview").tag(TripSource.demo)
                }.pickerStyle(.segmented).disabled(store.pendingGPS).accessibilityIdentifier("record.source")
                SourceBadge(source:presentation.sourceTitle,verified:store.source != .demo)
                Text(sourceExplanation).font(.caption).foregroundStyle(Palette.secondaryText)
            }
            SectionCard(title:"Preflight",icon:"checklist") {
                preflightRow("Vehicle",value:store.activeVehicle?.title,state:store.activeVehicle == nil ? .unavailable:.healthy)
                preflightRow("iPhone GPS",value:store.gps.status,state:presentation.gpsState)
                preflightRow("Scanner",value:store.source == .scanner ? store.scanner.status:"Optional",state:store.source == .scanner ? presentation.scannerState:.unavailable)
                preflightRow("Storage",value:"Saves on this iPhone first",state:.healthy)
            }
        }
    }

    private var activeRecording:some View {
        VStack(alignment:.leading,spacing:12) {
            SectionCard(title:"Current drive",icon:"record.circle") {
                VStack(spacing:4) {
                    Text(presentation.speed.value.map { $0.text(0) } ?? "—").font(.system(size:68,weight:.semibold,design:.rounded)).monospacedDigit().minimumScaleFactor(0.65)
                    Text("km/h").font(.caption).foregroundStyle(Palette.secondaryText)
                    FreshnessLabel(observedAt:presentation.speed.observedAt,now:store.now,staleAfter:10)
                }.frame(maxWidth:.infinity).accessibilityElement(children:.combine)
                HStack { metricSummary("Distance",value:presentation.distanceKM.text(1),unit:"km");Spacer();metricSummary("Elapsed",value:store.timerText,unit:"") }
                if !presentation.route.isEmpty {
                    NativeRouteMap(route:presentation.route,isLive:true).frame(height:150).clipShape(RoundedRectangle(cornerRadius:Palette.Radius.medium))
                } else {
                    HStack { Image(systemName:"location.slash");Text("No GPS route observed yet") }.font(.caption).foregroundStyle(Palette.secondaryText).frame(maxWidth:.infinity,minHeight:54)
                }
            }
            SectionCard(title:"Observed telemetry",icon:"gauge.with.dots.needle.50percent") {
                LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:10) {
                    ForEach(presentation.metrics) { metric in
                        MetricTile(title:metric.title,value:formatted(metric),unit:metric.unit,state:metric.state,source:metric.source)
                            .accessibilityIdentifier("record.metric.\(metric.key)")
                    }
                }
                Text("Regen trigger is a normalized ECU trigger indicator, never physical DPF fullness.").font(.caption).foregroundStyle(Palette.secondaryText)
            }
        }
    }

    private var recordButton:some View {
        VStack(spacing:7) {
            AppButton(title:store.pendingGPS ? "Cancel GPS request":(store.recording ? "Finish & save":"Start recording"),
                      icon:store.recording ? "stop.fill":"record.circle",destructive:store.recording) {
                if store.pendingGPS { store.cancelGPS() } else if store.recording { store.finishRecording() } else { store.startRecording() }
            }.accessibilityIdentifier(store.recording ? "record.finish":"record.start")
            Text(store.recording ? "Finish saves exactly once and leaves queued transfer work intact.":"No connection is required to save locally.")
                .font(.caption2).foregroundStyle(Palette.secondaryText).multilineTextAlignment(.center).frame(maxWidth:.infinity)
        }
    }

    private func preflightRow(_ title:String,value:String?,state:DriveLineSemanticState)->some View {
        HStack(alignment:.firstTextBaseline) { Text(title).font(.subheadline);Spacer();Text(value ?? "—").font(.caption).foregroundStyle(Palette.secondaryText).multilineTextAlignment(.trailing);Image(systemName:state.icon).foregroundStyle(color(state)) }
            .accessibilityElement(children:.combine)
    }
    private func metricSummary(_ title:String,value:String,unit:String)->some View { VStack(alignment:.leading,spacing:3) { Text(title).font(.caption).foregroundStyle(Palette.secondaryText);Text(value+(unit.isEmpty ? "":" \(unit)")).font(.headline).monospacedDigit() } }
    private func formatted(_ metric:PhoneSignalPresentation)->String? {
        guard let value=metric.value else { return nil }
        return value.text(metric.key == "rpm" || metric.key == "coolantC" || metric.key == "dsgFluidC" || metric.key == "dpfRegenTrigger" ? 0:1)
    }
    private var sourceExplanation:String {
        switch store.source { case .phoneGPS:return "Records route, speed, distance and duration. Engine telemetry stays unavailable.";case .scanner:return "Records actual scanner observations while GPS independently records the route.";case .demo:return "Clearly labelled sample data for preview only.";case .imported:return "Imported recordings cannot be used as a live source." }
    }
    private var phaseSemantic:DriveLineSemanticState { presentation.phase == .starting ? .stale:(presentation.phase == .idle ? .healthy:.queued) }
    private func color(_ state:DriveLineSemanticState)->Color { switch state {
        case .ready,.complete,.recovered:return Palette.healthy
        case .waiting,.queued,.processing,.degraded,.stale:return Palette.fuelAttention
        case .unavailable,.offline,.readOnly:return Palette.unavailable
        case .active,.failed:return Palette.recordingFault
    } }
}

#if DEBUG
#Preview("Record · Idle light") { DriveLineCanvas(tab:.record,scheme:.light) }
#Preview("Record · Active dark") { DriveLineCanvas(tab:.record,recording:true,scheme:.dark) }
#endif
