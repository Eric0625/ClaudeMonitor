# Claude Monitor

Claude Monitor is a macOS menu bar app. It shows the state of the Claude Code sessions that run in the Claude desktop app (Code tab).

- The app shows an icon in the menu bar. It has no Dock icon.
- When the pointer stays on the icon, a panel shows the running sessions and the recently finished turns.
- When a session completes a turn, the app shows a macOS notification.

## Requirements

- macOS 14 or later.
- Xcode 16 or later. The project was built with Xcode 27.2 and Swift 6.4.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) 2.38 or later, only if you change `project.yml`.

## Build and run

The Xcode project is generated from `project.yml`. The generated `ClaudeMonitor.xcodeproj` is in the repository.

1. If you changed `project.yml`, generate the project again:

   ```bash
   xcodegen generate
   ```

2. Open `ClaudeMonitor.xcodeproj` in Xcode, select the `ClaudeMonitor` scheme, and select **Product > Run**.

To build from the command line:

```bash
xcodebuild -project ClaudeMonitor.xcodeproj -scheme ClaudeMonitor -configuration Debug -derivedDataPath build/DerivedData build
```

```bash
open build/DerivedData/Build/Products/Debug/ClaudeMonitor.app
```

On first launch, the app shows a welcome window and asks for permission to show notifications.

### Signing

`project.yml` sets the development team `WS7X3S9H5W` and automatic signing. To use a different team, change `DEVELOPMENT_TEAM` in `project.yml` and in `scripts/ExportOptions.plist`, then generate the project again.

## Run the tests

All logic and all tests are in the Swift package `Packages/ClaudeMonitorCore`. The tests use Swift Testing.

```bash
swift test --package-path Packages/ClaudeMonitorCore
```

In Xcode, select **Product > Test** (the `ClaudeMonitor` scheme includes the package tests). From the command line:

```bash
xcodebuild -project ClaudeMonitor.xcodeproj -scheme ClaudeMonitor -derivedDataPath build/DerivedData test
```

The tests read fixture folders, not your real `~/.claude`. They replace the process table, the clock, and the notification center with fakes. `BehaviorScenarioTests.swift` has one test for each behavior scenario of version 1.

## Why the app has no App Sandbox

The app must read two folders that belong to other apps:

- `~/.claude/sessions`, which Claude Code writes.
- `~/Library/Application Support/Claude/claude-code-sessions`, which the Claude app writes.

A sandboxed app cannot read these folders without a file dialog each time. Thus the app has no sandbox, and it cannot go to the Mac App Store. Distribute it with Developer ID and notarization. The app uses the hardened runtime. It only reads files. It does not write to these folders.

## Distribute with Developer ID

1. Archive the app:

   ```bash
   xcodebuild -project ClaudeMonitor.xcodeproj -scheme ClaudeMonitor -configuration Release -archivePath build/ClaudeMonitor.xcarchive archive
   ```

2. Export it with the Developer ID certificate:

   ```bash
   xcodebuild -exportArchive -archivePath build/ClaudeMonitor.xcarchive -exportOptionsPlist scripts/ExportOptions.plist -exportPath build/export
   ```

3. Send it to the notary service and staple the ticket. `notary-profile` is a keychain profile that you made with `xcrun notarytool store-credentials`:

   ```bash
   ditto -c -k --keepParent build/export/ClaudeMonitor.app build/ClaudeMonitor.zip
   ```

   ```bash
   xcrun notarytool submit build/ClaudeMonitor.zip --keychain-profile notary-profile --wait
   ```

   ```bash
   xcrun stapler staple build/export/ClaudeMonitor.app
   ```

## The data source

> [!WARNING]
> Anthropic does not document these files. The facts below come from Claude desktop 4.23118.0 and Claude Code 2.1.317 on macOS. A later version can change them. If no session file has a known format, the icon shows a warning and the panel shows "Unsupported Claude Code session format (version x.y.z)".

### Session files

Each running Claude Code process writes `~/.claude/sessions/<pid>.json`. If `CLAUDE_CONFIG_DIR` is set in the environment of Claude Monitor, the folder is `$CLAUDE_CONFIG_DIR/sessions`. An app that you start from the Finder or at login does not get the environment of your shell.

The app uses these fields:

| Field | Use |
|---|---|
| `pid`, `procStart` | The liveness check. The file is valid only while a process with this PID runs and started at `procStart` (UTC, the format of `ps -o lstart`). |
| `status`, `waitingFor` | `busy`, `idle`, or `waiting` with a reason. Other values show as their raw text. |
| `statusUpdatedAt` | Turn start and end times. An `idle` record with a newer value is a turn that started and ended between two reads. |
| `hostSessionId` | The session identity. The app falls back to `sessionId`, then to the PID. |
| `name`, `cwd` | The title when the desktop title is not available, and the folder name. |
| `entrypoint` | The surface. Version 1 shows only desktop sessions (`claude-desktop`, `claude-desktop-3p`, `local-agent`). |
| `spare` | `true` for a pre-started process that has no session. The app ignores these records. |

Rules:

- The app reads all files every second. It also reads at once when the folder changes. The timer is the source of truth because a process can stop without a file change.
- If a file contains partial JSON, the app keeps the last good state of that file.
- If two live files have the same `hostSessionId`, the app uses the file with the newest `statusUpdatedAt`.
- When a process stops, the session is "unloaded". The Claude app stops idle sessions that are not in focus after 30 minutes. Thus a stopped process does not mean that the user closed the session.
- When a different process takes over a session between two reads, the app does not count a completed turn.

### Desktop session metadata

The Claude app keeps one file for each session at `~/Library/Application Support/Claude/claude-code-sessions/<uuid>/<uuid>/<hostSessionId>.json`. The app reads `title` (the sidebar title), `isArchived`, and `lastActivityAt`. These files can be large. The app finds a file by name, caches its path, and reads it again only when its modification time changes, at most every 5 seconds.

### Deep links

A click on a row or on a notification opens `claude://code/continue?session=<hostSessionId>` in the Claude app (`com.anthropic.claudefordesktop`). For an archived session or an ID that is not a desktop ID, the app only activates Claude, because the deep link does not find these sessions. Claude can turn off its deep links. Then the click only activates Claude.

## Add support for a new file format version

`SessionFileParser` is the only code that knows the JSON format of the session files. The rest of the app uses `SessionRecord`.

1. Copy a real session file of the new version. Remove personal paths, titles, and IDs. Add it to `Packages/ClaudeMonitorCore/Tests/ClaudeMonitorCoreTests/Fixtures/`, for example `session-busy-v3.json`.
2. Add a test to `SessionFileParserTests.swift` that parses the new fixture and checks each field of `SessionRecord`. Run the tests and make sure that the new test fails.
3. Change `SessionFileParser.parse(_:)` so that it reads both the old and the new layout. Keep the old fixtures and tests. Users can run old and new Claude Code processes at the same time.
4. If the new version adds a `status` or `waitingFor` value, add it to `SessionStatus` or `WaitingReason`, and to the `switch` statements in the parser and in the UI.
5. Run all tests. Then update the verified versions in this README.

If the desktop metadata format changes, change `DesktopMetadataReader` and its tests in the same way.

## App icon

The source of the app icon is `design/AppIcon.svg` (1024 × 1024 px, with the icon body at 824 × 824 px). The script `scripts/make-app-icon.swift` renders it with the SVG support of macOS into `App/Assets.xcassets/AppIcon.appiconset` (16 px to 1024 px). Xcode compiles this set into `Assets.car` and `AppIcon.icns`.

After you change the SVG, render the icon again:

```bash
swift scripts/make-app-icon.swift
```

The SVG renderer of macOS ignores SVG filters. Thus the SVG draws its shadows with stacked translucent shapes. Do not use `filter`, `feGaussianBlur`, or `feDropShadow` in the SVG.

## Notifications

The app shows "Turn completed" with the session title and the turn duration. A click on the notification opens the session. The app does not show notifications for the state that exists when it starts.

The Claude app has its own notification setting. To prevent duplicate notifications, turn off one of the two: the notifications in the Claude app settings, or Claude Monitor in **System Settings > Notifications**.

## Project layout

| Path | Contents |
|---|---|
| `App/` | AppKit and SwiftUI: `StatusItemController` (icon, hover tracking, menu), `SessionPanelController` (non-activating `NSPanel`), `SessionPanelView`, `UserNotificationPoster`, `LaunchAtLogin`, `SessionOpener`, the welcome window. |
| `Packages/ClaudeMonitorCore/Sources/` | `SessionFileParser`, `SessionRecord`, `ProcessInspector`, `DesktopMetadataReader`, `SessionStore` (the only owner of state transitions), `NotificationService`, `SessionMonitor` (reads files and publishes `PanelState`), `HoverPresenter` (open and close timing), `SessionRefreshDriver` (timer and folder watcher). |
| `Packages/ClaudeMonitorCore/Tests/` | Behavior scenarios, unit tests, and fixtures made from real files. |
| `project.yml` | The XcodeGen project definition. |
| `scripts/ExportOptions.plist` | Export options for Developer ID. |
| `design/AppIcon.svg` | The source of the app icon. |
| `scripts/make-app-icon.swift` | Renders the app icon into the asset catalog. |

## Known limits of version 1

- The app shows only sessions of the Claude desktop app. VS Code and terminal sessions are filtered out.
- When a whole turn starts and ends between two reads, the app does not know its duration. The notification then shows only the title.
- The "Recently finished" list starts empty each time the app starts.
