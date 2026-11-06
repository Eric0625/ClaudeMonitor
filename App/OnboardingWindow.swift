import AppKit
import SwiftUI

/// The window that the app shows on first launch.
@MainActor
final class OnboardingWindowController {
    private var window: NSWindow?

    func show() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 360),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to Claude Monitor"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: OnboardingView { [weak window] in window?.close() })
        window.setContentSize(window.contentView?.fittingSize ?? NSSize(width: 460, height: 360))
        window.center()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}

private struct OnboardingView: View {
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Claude Monitor is in the menu bar", systemImage: "sparkle")
                .font(.title2.weight(.semibold))

            Text("Move the pointer onto the menu bar icon to see the running and recently finished Claude Code sessions of the Claude app. Click a row to open the session in Claude.")

            Text("When a turn completes, Claude Monitor shows a notification.")

            GroupBox {
                Text("The Claude app can also show a notification when a turn completes. To prevent duplicate notifications, turn off one of the two: the notifications in the Claude app settings, or Claude Monitor in System Settings > Notifications.")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(4)
            } label: {
                Label("Duplicate notifications", systemImage: "bell.badge")
            }

            Text("Claude Monitor reads files that Claude Code writes. Anthropic does not document these files, and an update of Claude can change them. If this occurs, the icon shows a warning.")
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack {
                Button("Open Notification Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                }
                Spacer()
                Button("Done", action: close)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(20)
        .frame(width: 460)
    }
}
