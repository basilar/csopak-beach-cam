import AppKit
import SwiftUI

private enum DisplayState {
    case hidden
    case attached
    case detached
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let popoverSize = NSSize(width: 480, height: 270)
    private static let detachedFrameAutosaveName = "CsopakBeachCamDetachedWindow"

    private let streamManager = StreamManager()

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var detachedWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var state: DisplayState = .hidden

    func applicationDidFinishLaunching(_ notification: Notification) {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            let icon = NSImage(named: "MenuBarIcon")
            icon?.size = NSSize(width: 18, height: 18)
            icon?.isTemplate = false
            button.image = icon
            button.toolTip = "Csopak Beach Cam"
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        self.statusItem = statusItem
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        let event = NSApp.currentEvent
        let isRightClick = event?.type == .rightMouseUp
            || (event?.modifierFlags.contains(.control) ?? false)

        if isRightClick {
            showContextMenu()
        } else {
            toggleFromMenuBar()
        }
    }

    private func toggleFromMenuBar() {
        switch state {
        case .hidden:
            showAttached()
        case .attached:
            closePopover()
        case .detached:
            closeDetachedWindow()
            showAttached()
        }
    }

    // MARK: - Attached popover

    private func showAttached() {
        guard let button = statusItem?.button else { return }

        let popover = NSPopover()
        popover.contentSize = Self.popoverSize
        popover.behavior = .applicationDefined
        popover.animates = true
        popover.contentViewController = makePopoverContent()
        self.popover = popover

        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        state = .attached
    }

    private func closePopover() {
        popover?.performClose(nil)
        popover = nil
        if state == .attached { state = .hidden }
    }

    private func makePopoverContent() -> NSViewController {
        let viewController = NSViewController()
        let container = NSView(frame: NSRect(origin: .zero, size: Self.popoverSize))

        let host = NSHostingView(
            rootView: ContentView(streamManager: streamManager, showWeather: false)
                .frame(width: Self.popoverSize.width, height: Self.popoverSize.height)
        )
        // The popover is fixed-size; letting SwiftUI drive sizing from inside
        // a layout pass trips AppKit's layout-recursion warning.
        host.sizingOptions = []
        host.frame = container.bounds
        host.autoresizingMask = [.width, .height]
        container.addSubview(host)

        let click = ClickCaptureView(frame: container.bounds)
        click.autoresizingMask = [.width, .height]
        click.onClick = { [weak self] in self?.detachToWindow() }
        container.addSubview(click)

        viewController.view = container
        return viewController
    }

    // MARK: - Detached window

    private func detachToWindow() {
        guard state == .attached else { return }
        closePopover()

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.popoverSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Csopak Beach Cam"
        window.isReleasedWhenClosed = false
        window.contentMinSize = Self.popoverSize
        let host = NSHostingView(
            rootView: ContentView(streamManager: streamManager)
        )
        // Window size comes from the autosaved frame + contentMinSize;
        // SwiftUI-driven sizing here can recurse into layout.
        host.sizingOptions = []
        window.contentView = host
        window.delegate = self

        window.setFrameAutosaveName(Self.detachedFrameAutosaveName)
        if !window.setFrameUsingName(Self.detachedFrameAutosaveName) {
            window.center()
        }

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)

        detachedWindow = window
        state = .detached
    }

    private func closeDetachedWindow() {
        detachedWindow?.delegate = nil
        detachedWindow?.close()
        detachedWindow = nil
        if state == .detached { state = .hidden }
    }

    // MARK: - Context menu

    private func showContextMenu() {
        guard let statusItem else { return }

        let menu = NSMenu()
        menu.addItem(withTitle: "Windguru Credentials…",
                     action: #selector(openSettings),
                     keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Csopak Beach Cam",
                     action: #selector(quit),
                     keyEquivalent: "q").target = self

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 260),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Windguru Credentials"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: WindguruSettingsView())
        window.center()
        window.delegate = self

        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        let closed = notification.object as AnyObject
        if closed === detachedWindow {
            detachedWindow = nil
            state = .hidden
        } else if closed === settingsWindow {
            settingsWindow = nil
        }
    }
}

private final class ClickCaptureView: NSView {
    var onClick: () -> Void = {}

    override func mouseDown(with event: NSEvent) {
        onClick()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        return self
    }
}
