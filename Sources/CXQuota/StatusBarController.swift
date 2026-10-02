import AppKit
import SwiftUI

@MainActor
final class StatusBarController: NSObject, NSApplicationDelegate {
    let quotaStore = QuotaStore()
    private let popover = NSPopover()
    private var statusItem: NSStatusItem?
    private var outsideClickMonitors: [Any] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 560, height: 450)
        popover.contentViewController = NSHostingController(rootView: QuotaPopoverView(store: quotaStore))
        installOutsideClickMonitors()

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = item.button else { return }
        button.image = NSImage(systemSymbolName: "gauge.with.dots.needle.33percent", accessibilityDescription: "CX \u{989D}\u{5EA6}")
        button.image?.size = NSSize(width: 20, height: 20)
        button.image?.isTemplate = true
        button.toolTip = "CX \u{989D}\u{5EA6}"
        button.target = self
        button.action = #selector(togglePopover(_:))
        statusItem = item
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            quotaStore.refreshOnOpen()
        }
    }

    private func installOutsideClickMonitors() {
        if let monitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown],
            handler: { [weak self] _ in
            DispatchQueue.main.async {
                self?.closePopover()
            }
            }
        ) {
            outsideClickMonitors.append(monitor)
        }
        if let monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown],
            handler: { [weak self] event in
            self?.closePopoverIfNeeded(for: event)
            return event
            }
        ) {
            outsideClickMonitors.append(monitor)
        }
    }

    private func closePopoverIfNeeded(for event: NSEvent) {
        guard event.window !== popover.contentViewController?.view.window,
              event.window !== statusItem?.button?.window,
              event.window?.sheetParent == nil else {
            return
        }
        closePopover()
    }

    private func closePopover() {
        guard popover.isShown else { return }
        popover.performClose(nil)
    }
}
