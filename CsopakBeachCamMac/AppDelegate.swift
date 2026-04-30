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
        window.contentView = NSHostingView(
            rootView: ContentView(streamManager: streamManager)
        )
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
        menu.addItem(withTitle: "Quit Csopak Beach Cam",
                     action: #selector(quit),
                     keyEquivalent: "q").target = self

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard (notification.object as AnyObject) === detachedWindow else { return }
        detachedWindow = nil
        state = .hidden
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
