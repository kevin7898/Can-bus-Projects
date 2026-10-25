import SwiftUI
import AppKit

@MainActor final class AppDelegate:NSObject,NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows flag:Bool) -> Bool {
        if !flag { for window in sender.windows { window.makeKeyAndOrderFront(nil) } };return true
    }
}
@main @MainActor struct CANConnectApp:App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var store:AppStore
    @AppStorage(DriveLineAppearance.storageKey) private var appearanceRaw=DriveLineAppearance.system.rawValue
    init() {
        let args = CommandLine.arguments
        func argument(_ key:String) -> String? { guard let i = args.firstIndex(of:key),args.indices.contains(i+1) else { return nil };return args[i+1] }
        let root = argument("--library").map { URL(fileURLWithPath:$0,isDirectory:true) }
        let state = AppStore(root:root);_store = StateObject(wrappedValue:state)
        #if DEBUG
        if args.contains("--phase3-fixture") { state.loadPhase3Fixture() }
        #endif
        if args.contains("--headless") {
            guard let token = ProcessInfo.processInfo.environment["CAN_CONNECT_TEST_TOKEN"],token.count>=16,let port = UInt16(argument("--port") ?? "18765") else { fputs("Headless validation needs CAN_CONNECT_TEST_TOKEN (16+ characters) and a valid --port.\n",stderr);exit(2) }
            do { try state.startHeadless(port:port,token:token);dispatchMain() } catch { fputs("Server startup failed: \(error.localizedDescription)\n",stderr);exit(1) }
        }
    }
    var body:some Scene {
        WindowGroup("DriveLine",id:"main") {
            RootView().environmentObject(store)
                .preferredColorScheme((DriveLineAppearance(rawValue:appearanceRaw) ?? .system).colorScheme)
                .frame(minWidth:1080,minHeight:720)
        }.defaultSize(width:1540,height:1000)
            .commands {
                CommandGroup(after:.newItem) { Button("Import recordings…") { store.importFiles() }.keyboardShortcut("i",modifiers:.command);Button("Open data folder") { store.openLibrary() } }
            }
        MenuBarExtra("DriveLine",systemImage:"waveform.path.ecg") { MenuBarContent().environmentObject(store) }
    }
}
struct MenuBarContent:View {
    @EnvironmentObject var store:AppStore
    @Environment(\.openWindow) var openWindow
    var body:some View { Button("Open DriveLine") { openWindow(id:"main");NSApp.activate(ignoringOtherApps:true) };Text("Server: "+store.serverStatus);Divider();Button("Import recordings…") { store.importFiles() };Button(store.ingestionPaused ? "Resume ingestion":"Pause ingestion") { store.togglePause() };Divider();Button("Quit DriveLine") { NSApp.terminate(nil) } }
}
struct RootView:View {
    @EnvironmentObject var store:AppStore
    @AppStorage(DriveLineAppearance.storageKey) private var appearanceRaw=DriveLineAppearance.system.rawValue
    var body:some View {
        VStack(spacing:0) {
            topNavigation
            Divider().overlay(Theme.border)
            HStack { VStack(alignment:.leading,spacing:4) { Text(store.page.title).font(.system(size:25,weight:.semibold));Text(store.page.subtitle).font(.system(size:11)).foregroundStyle(Theme.secondaryText) };Spacer() }.padding(.horizontal,22).padding(.vertical,18)
            if let error = store.error { banner(error,isError:true) }
            if let notice = store.notice { banner(notice,isError:false) }
            ScrollView { destination.padding(.horizontal,22).padding(.bottom,22).frame(maxWidth:.infinity,alignment:.topLeading) }
            Divider().overlay(Theme.line)
            HStack(spacing:14) {
                Button { store.page = .server } label:{ Label("Server: "+store.serverStatus,systemImage:store.serverStatus=="Listening" ? "checkmark.circle.fill":"server.rack") }.accessibilityIdentifier("mac.secondary.server")
                Button { store.page = .imports } label:{ Label(store.processing ? "Processing imports":"Imports",systemImage:"square.and.arrow.down") }.accessibilityIdentifier("mac.secondary.imports")
                Text("\(store.state.vehicles.count) vehicles")
                Spacer()
                Text(store.readOnly ? "READ ONLY":"Local library")
            }.buttonStyle(.plain).font(.system(size:10)).foregroundStyle(Theme.secondaryText).padding(.horizontal,14).padding(.vertical,8).background(Theme.navigationBackground)
        }.background(Theme.background).foregroundStyle(Theme.text).tint(Theme.blue)
            .onAppear { if store.state.vehicles.isEmpty { store.page = .garage } }
    }
    @ViewBuilder var destination:some View {
        switch store.page {
        case .today: DriveLedgerTodayView()
        case .drives: DrivesDestinationView()
        case .fuel: FuelDestinationView()
        case .signals: SignalsView()
        case .garage: GarageView()
        case .imports: ImportsView()
        case .server: ServerView()
        }
    }
    var topNavigation:some View {
        HStack(spacing:8) {
            Label("DriveLine",systemImage:"road.lanes").font(.system(size:17,weight:.bold)).foregroundStyle(Theme.primaryText).frame(width:140,alignment:.leading)
            ForEach(Workspace.primary) { page in navigation(page) }
            Spacer(minLength:8)
            Picker("Vehicle",selection:Binding(get:{store.state.selectedVehicleID},set:{ if let id=$0 { store.selectVehicle(id) } })) {
                if store.state.vehicles.isEmpty { Text("Add a vehicle").tag(nil as UUID?) }
                ForEach(store.state.vehicles) { Text($0.name).tag(Optional($0.id)) }
            }.labelsHidden().frame(width:180).accessibilityIdentifier("mac.vehicle.picker")
            Menu {
                Button("Imports",systemImage:"square.and.arrow.down") { store.page = .imports }
                Button("Server",systemImage:"server.rack") { store.page = .server }
                Divider()
                Menu("Appearance") { ForEach(DriveLineAppearance.allCases) { appearance in Button { appearanceRaw=appearance.rawValue } label:{ if appearanceRaw==appearance.rawValue { Label(appearance.title,systemImage:"checkmark") } else { Text(appearance.title) } } } }
                Divider()
                Button("Open data folder",systemImage:"folder") { store.openLibrary() }
            } label:{ Image(systemName:"ellipsis").frame(width:32,height:30) }.menuStyle(.borderlessButton).accessibilityLabel("Services and appearance").accessibilityIdentifier("mac.secondary.menu")
        }.padding(.horizontal,16).frame(height:58).background(Theme.navigationBackground)
    }
    func navigation(_ page:Workspace) -> some View {
        Button { store.page = page } label: {
            VStack(spacing:7) { Label(page.title,systemImage:page.icon).labelStyle(.titleOnly).font(.system(size:12,weight:store.page==page ? .semibold:.regular));Rectangle().fill(store.page==page ? Theme.cobalt:Color.clear).frame(height:3).clipShape(Capsule()) }
                .foregroundStyle(store.page==page ? Theme.cobalt:Theme.secondaryText).frame(width:70,height:48).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier("mac.nav.\(page.rawValue)").accessibilityAddTraits(store.page==page ? .isSelected:[])
    }
    func banner(_ text:String,isError:Bool) -> some View { HStack { Image(systemName:isError ? "exclamationmark.triangle":"info.circle");Text(text).textSelection(.enabled);Spacer();Button { if isError { store.error = nil } else { store.notice = nil } } label:{Image(systemName:"xmark")} }.font(.system(size:12)).padding(12).background(isError ? Theme.recordingFault.opacity(0.13):Theme.cobalt.opacity(0.11)).padding(.horizontal,22).padding(.bottom,12) }
}

#if DEBUG
@MainActor struct MacNavigationCanvas:View {
    @StateObject private var store:AppStore
    init() {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("DriveLineMacPreviews/\(UUID().uuidString)",isDirectory:true)
        _store=StateObject(wrappedValue:AppStore(root:root))
    }
    var body:some View { RootView().environmentObject(store).frame(width:1080,height:720) }
}
#Preview("Mac navigation · Light") { MacNavigationCanvas().preferredColorScheme(.light) }
#Preview("Mac navigation · Dark") { MacNavigationCanvas().preferredColorScheme(.dark) }
#endif
