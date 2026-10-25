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
    var body:some View {
        VStack(spacing:0) {
            HStack(spacing:0) {
                sidebar.frame(width:190)
                VStack(alignment:.leading,spacing:0) {
                    HStack { VStack(alignment:.leading,spacing:4) { Text(store.page.rawValue).font(.system(size:25,weight:.semibold));Text(store.page.subtitle).font(.system(size:11)).foregroundStyle(Theme.muted) };Spacer();Button("Import",systemImage:"square.and.arrow.down") { store.importFiles() } }.padding(22)
                    if let error = store.error { banner(error,isError:true) }
                    if let notice = store.notice { banner(notice,isError:false) }
                    ScrollView { Group { switch store.page { case .overview:OverviewView();case .trips:TripsView();case .compare:CompareView();case .signals:SignalsView();case .garage:GarageView();case .imports:ImportsView();case .server:ServerView() } }.padding(.horizontal,22).padding(.bottom,22).frame(maxWidth:.infinity,alignment:.topLeading) }
                }.frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
            }
            Divider().overlay(Theme.line)
            HStack(spacing:16) { Circle().fill(store.serverStatus=="Listening" ? Theme.green:Theme.muted).frame(width:6,height:6);Text("Server: "+store.serverStatus);Text("\(store.state.vehicles.count) vehicles");Text(store.processing ? "Processing imports":"Local library");Spacer();Text(store.readOnly ? "READ ONLY":"No live vehicle connection") }.font(.system(size:10)).foregroundStyle(Theme.muted).padding(.horizontal,14).padding(.vertical,8)
        }.background(Theme.background).foregroundStyle(Theme.text).tint(Theme.blue)
            .onAppear { if store.state.vehicles.isEmpty { store.page = .garage } }
    }
    var sidebar:some View {
        VStack(alignment:.leading,spacing:18) {
            Text("DriveLine").font(.system(size:11,weight:.semibold)).tracking(2).padding(.top,8)
            VStack(alignment:.leading,spacing:5) {
                Text("YOUR GARAGE").font(.system(size:9)).tracking(1.5).foregroundStyle(Theme.muted)
                Picker("Vehicle",selection:Binding(get:{store.state.selectedVehicleID},set:{ if let id = $0 { store.selectVehicle(id) } })) { if store.state.vehicles.isEmpty { Text("Add a vehicle").tag(nil as UUID?) };ForEach(store.state.vehicles) { vehicle in Text(vehicle.name).tag(Optional(vehicle.id)) } }.labelsHidden()
            }.padding(10).background(Theme.raised).clipShape(RoundedRectangle(cornerRadius:7))
            VStack(alignment:.leading,spacing:4) {
                Text("WORKSPACE").font(.system(size:9)).tracking(1.5).foregroundStyle(Theme.muted).padding(.horizontal,8).padding(.bottom,5)
                ForEach(Workspace.allCases.filter{$0 != .imports && $0 != .server}) { page in navigation(page) }
            }
            VStack(alignment:.leading,spacing:4) {
                Text("INFRASTRUCTURE").font(.system(size:9)).tracking(1.5).foregroundStyle(Theme.muted).padding(.horizontal,8).padding(.bottom,5)
                navigation(.imports);navigation(.server)
            }
            Spacer()
            Divider().overlay(Theme.line)
            VStack(alignment:.leading,spacing:7) { Text("HOME SERVER").font(.system(size:9)).tracking(1.5);Text(Host.current().localizedName ?? "This Mac").font(.system(size:12));Text(store.serverStatus).font(.system(size:10)).foregroundStyle(Theme.muted) }.padding(8)
        }.padding(12).background(Theme.sidebar).overlay(alignment:.trailing) { Rectangle().fill(Theme.line).frame(width:1) }
    }
    func navigation(_ page:Workspace) -> some View {
        Button { store.page = page } label: { HStack(spacing:10) { Image(systemName:page.icon).frame(width:18);Text(page.rawValue);Spacer() }.font(.system(size:12)).foregroundStyle(store.page==page ? Theme.text:Theme.muted).padding(10).background(store.page==page ? Theme.blue.opacity(0.19):Color.clear).clipShape(RoundedRectangle(cornerRadius:6)).contentShape(Rectangle()) }.buttonStyle(.plain)
    }
    func banner(_ text:String,isError:Bool) -> some View { HStack { Image(systemName:isError ? "exclamationmark.triangle":"info.circle");Text(text).textSelection(.enabled);Spacer();Button { if isError { store.error = nil } else { store.notice = nil } } label:{Image(systemName:"xmark")} }.font(.system(size:12)).padding(12).background(isError ? Color.orange.opacity(0.15):Theme.blue.opacity(0.12)).padding(.horizontal,22).padding(.bottom,12) }
}
