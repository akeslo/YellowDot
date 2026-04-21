//
//  YellowDotApp.swift
//  YellowDot
//
//  Created by Alin Panaitiu on 21.12.2021.
//

import Combine
import Defaults
import LaunchAtLogin
import SwiftUI

let cid = CGSMainConnectionID()

struct OverlayTarget: Codable, Identifiable, Equatable, Defaults.Serializable {
    var id: UUID = UUID()
    var ownerName: String
    var windowName: String
    var width: CGFloat
    var height: CGFloat
    var enabled: Bool = true

    var description: String {
        let name = windowName.isEmpty ? "" : " (\(windowName))"
        return "\(ownerName)\(name) [\(Int(width))x\(Int(height))]"
    }
}

extension Defaults.Keys {
    static let showMenubarIcon = Key<Bool>("showMenubarIcon", default: true)
    static let overlayColor = Key<String>("overlayColor", default: "#FFFF00FF")
    static let targets = Key<[OverlayTarget]>("targets", default: [])
    static let launchCount = Key<Int>("launchCount", default: 0)
}

extension NSColor {
    convenience init(hex: String) {
        let hex = hex.trimmingCharacters(in: .alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b, a: UInt64
        switch hex.count {
        case 6: (r, g, b, a) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF, 255)
        case 8: (r, g, b, a) = ((int >> 24) & 0xFF, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default: (r, g, b, a) = (0, 0, 0, 255)
        }
        self.init(srgbRed: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, alpha: Double(a) / 255)
    }

    var hexString: String {
        let c = usingColorSpace(.sRGB) ?? self
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255), Int(a * 255))
    }
}

extension Color {
    var hexString: String { NSColor(self).usingColorSpace(.sRGB)?.hexString ?? "#000000FF" }
    init(hex: String) {
        self.init(nsColor: NSColor(hex: hex))
    }
}

struct WindowInfo {
    var bounds: CGRect
    var number: Int
    var ownerName: String
    var name: String
    var screen: String?
    var space: Int?
    var pillNumber: Int?

    var isIndicator: Bool {
        name == "StatusIndicator" && ownerName == "Window Server"
    }

    var displayName: String {
        if ownerName == "Control Center" {
            if !name.isEmpty && name != "Item-0" {
                if name.contains(".") {
                    return name.components(separatedBy: ".").last?.replacingOccurrences(of: "menu", with: "").capitalized ?? name
                }
                return name
            }
            return "Menu Extra"
        }
        return ownerName
    }

    var displaySub: String {
        if ownerName == "Control Center" && (name.isEmpty || name == "Item-0") {
            return "Internal ID: \(number)"
        }
        return name
    }

    static func fromInfoDict(_ dict: [String: Any], pillNumber: Int? = nil) -> WindowInfo {
        var rect = CGRect.zero
        if let bounds = dict["kCGWindowBounds"] as? [String: CGFloat],
           let x = bounds["X"], let y = bounds["Y"],
           let width = bounds["Width"], let height = bounds["Height"]
        {
            rect = CGRect(x: x, y: y, width: width, height: height)
        }
        let id = (dict["kCGWindowNumber"] as? Int) ?? 0
        let screen = CGSCopyManagedDisplayForWindow(cid, id)?.takeRetainedValue() as String?
        return WindowInfo(
            bounds: rect,
            number: id,
            ownerName: (dict["kCGWindowOwnerName"] as? String) ?? "",
            name: (dict["kCGWindowName"] as? String) ?? "",
            screen: screen,
            space: CGSManagedDisplayGetCurrentSpace(cid, screen as CFString?),
            pillNumber: pillNumber
        )
    }
}

func getWindows() -> [WindowInfo] {
    let options = CGWindowListOption(arrayLiteral: .excludeDesktopElements, .optionOnScreenOnly)
    guard let windowsListInfo = CGWindowListCopyWindowInfo(options, CGWindowID(0)) as? [[String: Any]] else {
        return []
    }
    return windowsListInfo.map { WindowInfo.fromInfoDict($0) }
}

@MainActor var allWindows: [WindowInfo] = []

@MainActor
class IndicatorOverlayManager {
    private var overlays: [Int: NSWindow] = [:]
    private var highlightWindow: NSWindow?

    func showHighlight(bounds: CGRect) {
        let frame = flipped(bounds)
        if let win = highlightWindow {
            win.setFrame(frame, display: true)
            win.orderFrontRegardless()
        } else {
            let win = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
            win.isOpaque = false
            win.backgroundColor = .clear
            win.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow) + 2))
            win.ignoresMouseEvents = true
            win.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
            
            let view = NSView(frame: CGRect(origin: .zero, size: frame.size))
            view.wantsLayer = true
            view.layer?.borderColor = NSColor.red.cgColor
            view.layer?.borderWidth = 2
            view.layer?.cornerRadius = frame.height / 2
            win.contentView = view
            
            win.orderFrontRegardless()
            highlightWindow = win
        }
    }

    func hideHighlight() {
        highlightWindow?.orderOut(nil)
        highlightWindow = nil
    }

    func update(windows: [WindowInfo], targets: [OverlayTarget], colorHex: String) {
        let color = NSColor(hex: colorHex)
        
        // Find windows to overlay based on targets
        var toOverlay: [Int: CGRect] = [:]
        for target in targets where target.enabled {
            for win in windows {
                if win.ownerName == target.ownerName && 
                   win.name == target.windowName &&
                   abs(win.bounds.width - target.width) < 1 &&
                   abs(win.bounds.height - target.height) < 1 {
                    toOverlay[win.number] = win.bounds
                }
            }
        }

        // Also hide any StatusIndicator dots found
        // (Removed auto-detection of status dots per user request)

        let current = Set(toOverlay.keys)

        for key in overlays.keys where !current.contains(key) {
            CGSSetWindowAlpha(cid, CGSWindow(key), 1.0)
            overlays[key]?.orderOut(nil)
            overlays.removeValue(forKey: key)
        }

        for (winNumber, bounds) in toOverlay {
            CGSSetWindowAlpha(cid, CGSWindow(winNumber), 0.0)
            let frame = flipped(bounds)
            if let win = overlays[winNumber] {
                win.setFrame(frame, display: true)
                win.contentView?.layer?.backgroundColor = color.cgColor
                CGSSetWindowLevel(cid, CGSWindow(win.windowNumber), Int32(CGWindowLevelForKey(.statusWindow) + 1))
                win.orderFrontRegardless()
            } else {
                let win = makeOverlay(frame: frame, color: color)
                CGSSetWindowLevel(cid, CGSWindow(win.windowNumber), Int32(CGWindowLevelForKey(.statusWindow) + 1))
                win.orderFrontRegardless()
                overlays[winNumber] = win
            }
        }
    }

    func hideAll() {
        for (key, win) in overlays {
            CGSSetWindowAlpha(cid, CGSWindow(key), 1.0)
            win.orderOut(nil)
        }
        overlays.removeAll()
    }

    private func makeOverlay(frame: CGRect, color: NSColor) -> NSWindow {
        let win = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        win.isOpaque = false
        win.backgroundColor = .clear
        win.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow) + 1))
        win.ignoresMouseEvents = true
        win.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        win.hasShadow = false

        let view = NSView(frame: CGRect(origin: .zero, size: frame.size))
        view.wantsLayer = true
        view.layer?.backgroundColor = color.cgColor
        view.layer?.cornerRadius = frame.height / 2
        view.layer?.masksToBounds = true
        win.contentView = view
        return win
    }

    private func flipped(_ rect: CGRect) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }
}

func pub<T: Equatable>(_ key: Defaults.Key<T>) -> Publishers.Filter<Publishers.RemoveDuplicates<Publishers.Drop<AnyPublisher<Defaults.KeyChange<T>, Never>>>> {
    Defaults.publisher(key).dropFirst().removeDuplicates().filter { $0.oldValue != $0.newValue }
}

@MainActor
class WindowManager: ObservableObject {
    static let shared = WindowManager()
    @Published var windowToOpen: String? = nil

    func open(_ window: String) {
        windowToOpen = window
    }
}

func mainActor(_ action: @escaping @MainActor () -> Void) {
    Task.init { await MainActor.run { action() }}
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) static var instance: AppDelegate!

    var application = NSApplication.shared
    var observers: Set<AnyCancellable> = []
    var overlayTimer: Timer?
    var windowFetcher: Timer?
    let overlayManager = IndicatorOverlayManager()

    var didBecomeActiveAtLeastOnce = false

    func application(_ application: NSApplication, open urls: [URL]) {
        guard didBecomeActiveAtLeastOnce, !Defaults[.showMenubarIcon] else { return }
        WindowManager.shared.open("settings")
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        guard didBecomeActiveAtLeastOnce else {
            didBecomeActiveAtLeastOnce = true
            return
        }
        guard !Defaults[.showMenubarIcon] else { return }
        WindowManager.shared.open("settings")
    }

    @MainActor func initOverlay() {
        allWindows = getWindows()

        overlayManager.update(
            windows: allWindows,
            targets: Defaults[.targets],
            colorHex: Defaults[.overlayColor]
        )

        windowFetcher?.invalidate()
        overlayTimer?.invalidate()

        windowFetcher = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
            mainActor { allWindows = getWindows() }
        }
        overlayTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [overlayManager] _ in
            let colorHex = Defaults[.overlayColor]
            let targets = Defaults[.targets]
            mainActor {
                overlayManager.update(
                    windows: allWindows,
                    targets: targets,
                    colorHex: colorHex
                )
            }
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.instance = self
        Defaults[.launchCount] += 1

        NSApp.windows.first { $0.title.contains("Settings") }?.close()

        if !CGPreflightScreenCaptureAccess() {
            let alert = NSAlert()
            alert.messageText = "Screen Recording permission needed"
            alert.informativeText = "YellowDot needs Screen Recording access to detect and overlay the screen sharing indicator."
            alert.addButton(withTitle: "Grant Access")
            alert.addButton(withTitle: "Cancel")
            alert.alertStyle = .informational
            if alert.runModal() == .alertFirstButtonReturn {
                CGRequestScreenCaptureAccess()
            }
        }

        initOverlay()

        pub(.overlayColor).sink { [overlayManager] change in
            mainActor {
                overlayManager.update(
                    windows: allWindows,
                    targets: Defaults[.targets],
                    colorHex: change.newValue
                )
            }
        }.store(in: &observers)

        pub(.targets).sink { [overlayManager] change in
            mainActor {
                overlayManager.update(
                    windows: allWindows,
                    targets: change.newValue,
                    colorHex: Defaults[.overlayColor]
                )
            }
        }.store(in: &observers)

        NotificationCenter.default.addObserver(self, selector: #selector(windowWillClose), name: NSWindow.willCloseNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(windowDidBecomeMain), name: NSWindow.didBecomeMainNotification, object: nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    @objc func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window.title == "YellowDot Settings" else { return }
        NSApp.setActivationPolicy(.accessory)
    }

    @objc func windowDidBecomeMain(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window.title == "YellowDot Settings" else { return }
        NSApp.setActivationPolicy(.regular)
    }
}

extension NSScreen {
    var id: CGDirectDisplayID? {
        guard let id = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
        return CGDirectDisplayID(id.uint32Value)
    }
    var uuid: String {
        guard let id, let uuid = CGDisplayCreateUUIDFromDisplayID(id) else { return "" }
        let uuidValue = uuid.takeRetainedValue()
        return CFUUIDCreateString(kCFAllocatorDefault, uuidValue) as String
    }
}

struct WindowPickerSheet: View {
    @Environment(\.dismiss) var dismiss
    @State var windows: [WindowInfo] = []
    let onSelect: (WindowInfo) -> Void
    
    let manager = AppDelegate.instance.overlayManager

    var body: some View {
        VStack {
            Text("Select a window to overlay").font(.headline).padding()
            List(windows, id: \.number) { win in
                Button {
                    onSelect(win)
                    dismiss()
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(win.displayName).bold()
                            if !win.displaySub.isEmpty {
                                Text(win.displaySub).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text("\(Int(win.bounds.width))x\(Int(win.bounds.height))")
                            .font(.system(.caption, design: .monospaced))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { inside in
                    if inside {
                        manager.showHighlight(bounds: win.bounds)
                    } else {
                        manager.hideHighlight()
                    }
                }
            }
            Button("Cancel") { dismiss() }.padding()
        }
        .frame(width: 350, height: 450)
        .onDisappear {
            manager.hideHighlight()
        }
        .onAppear {
            windows = getWindows().filter { win in
                // Only show windows that are likely menubar icons
                win.bounds.minY < 50 && win.bounds.height <= 40 && !win.ownerName.isEmpty && win.ownerName != "Window Server"
            }.sorted { $0.displayName < $1.displayName }
        }
    }
}

@main
struct YellowDotApp: App {
    init() {}

    @AppStorage("showMenubarIcon") var showMenubarIcon = Defaults[.showMenubarIcon]
    @AppStorage("overlayColor") var overlayColorHex = Defaults[.overlayColor]
    @Default(.targets) var targets: [OverlayTarget]

    @Environment(\.openWindow) var openWindow
    @ObservedObject var wm = WindowManager.shared
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @State var showingPicker = false

    var overlayColor: Binding<Color> {
        Binding(
            get: { Color(hex: overlayColorHex) },
            set: { overlayColorHex = $0.hexString }
        )
    }

    var body: some Scene {
        MenuBarExtra(isInserted: $showMenubarIcon) {
            Toggle("Show menubar icon", isOn: $showMenubarIcon)
            LaunchAtLogin.Toggle()
            Divider()
            Button("Settings...") {
                openWindow(id: "settings")
                NSApp.activate(ignoringOtherApps: true)
            }
            Divider()
            Button("Quit") {
                NSApplication.shared.terminate(self)
            }
        } label: {
            Image(systemName: "dot.viewfinder")
                .foregroundStyle(.yellow)
        }
        .menuBarExtraStyle(.menu)
        .onChange(of: showMenubarIcon) { show in
            if !show, appDelegate.didBecomeActiveAtLeastOnce {
                openWindow(id: "settings")
                NSApp.activate(ignoringOtherApps: true)
            }
        }
        .onChange(of: wm.windowToOpen) { window in
            guard let window else { return }
            openWindow(id: window)
            wm.windowToOpen = nil
        }
        Window("YellowDot Settings", id: "settings") {
            VStack(alignment: .trailing) {
                Form {
                    Section("General") {
                        Toggle("Show menubar icon", isOn: $showMenubarIcon)
                        LaunchAtLogin.Toggle()
                        ColorPicker("Indicator overlay color", selection: overlayColor)
                    }
                    Section {
                        List {
                            ForEach($targets) { $target in
                                HStack {
                                    Toggle("", isOn: $target.enabled).labelsHidden()
                                    Text(target.description)
                                    Spacer()
                                    Button(role: .destructive) {
                                        targets.removeAll { $0.id == target.id }
                                    } label: {
                                        Image(systemName: "trash")
                                    }.buttonStyle(.borderless)
                                }
                            }
                        }
                        Button {
                            showingPicker = true
                        } label: {
                            Label("Add Overlay Target", systemImage: "plus")
                        }
                    } header: {
                        Text("Active Overlays")
                    } footer: {
                        Text("Pick icons from the menubar to overlay with your custom color.")
                    }
                }.formStyle(.grouped)
                Button("Quit") {
                    NSApplication.shared.terminate(self)
                }.padding()
            }
            .frame(minWidth: 450, minHeight: 400)
            .sheet(isPresented: $showingPicker) {
                WindowPickerSheet { win in
                    let newTarget = OverlayTarget(
                        ownerName: win.ownerName,
                        windowName: win.name,
                        width: win.bounds.width,
                        height: win.bounds.height
                    )
                    if !targets.contains(where: { 
                        $0.ownerName == newTarget.ownerName && 
                        $0.windowName == newTarget.windowName &&
                        $0.width == newTarget.width &&
                        $0.height == newTarget.height
                    }) {
                        targets.append(newTarget)
                    }
                }
            }
        }
        .defaultSize(width: 450, height: 400)
    }
}
