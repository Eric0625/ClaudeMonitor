# Claude Monitor

Claude Monitor is a macOS menu bar app. It shows the state of the Claude Code sessions that run in the Claude desktop app (Code tab).

- The app shows an icon in the menu bar. It has no Dock icon.
- The menu bar icon shows these states:

  | Icon | Meaning |
  | --- | --- |
  | Dimmed sparkle | No session runs and no session is unread. |
  | Sparkle and a number | The number of running sessions. |
  | Raised hand and a number | One or more sessions wait for you. The number is the count of all running sessions. |
  | Dot and a number | The number of unread rows in "Recently finished". It shows next to the sparkle or the raised hand, or alone when no session runs. |
  | Warning triangle | At least one session file has an unknown format and no session file has a known format. The icon then shows no number and no dot. |
- When the pointer stays on the icon, or when you click the icon, a panel shows the running sessions and the recently finished sessions.
- Right-click or Control-click the icon to show a menu with **Launch at Login** and **Quit Claude Monitor**.
- "Recently finished" shows the latest completed turn of each session, for the 10 most recent sessions. A session that starts a new turn moves to "Running". Thus each session shows only one time.
- A row in "Recently finished" shows an unread dot in the accent color and a bold title until you open the session after its turn ended. You can open it in the Claude app, or click its row or its notification in Claude Monitor.
- When a session completes a turn, the app shows a macOS notification. See [Notifications](#notifications).
- The app only reads local files. It does not send data over the network.

## Install

1. Get a notarized `ClaudeMonitor.app` (see [Distribute with Developer ID](#distribute-with-developer-id)).
2. Move it to the `/Applications` folder and open it.
3. On first launch, the app shows a welcome window and asks for permission to show notifications.
4. To start the app at login, right-click the menu bar icon and select **Launch at Login**.

## Requirements

- macOS 14 or later.
- Xcode 27.2 with Swift 6.4. The project was not tested with other versions.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) 2.46, only if you change `project.yml`. The project was not tested with other versions.

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

### Signing

`project.yml` sets the development team `WS7X3S9H5W`, automatic signing, and the bundle ID `com.ericyuan.ClaudeMonitor`. A bundle ID belongs to one team only. To use a different team:

1. Change `DEVELOPMENT_TEAM` in `project.yml` and `teamID` in `scripts/ExportOptions.plist`.
2. Change `bundleIdPrefix` and `PRODUCT_BUNDLE_IDENTIFIER` in `project.yml` to a bundle ID that your team owns.
3. Generate the project again.

## Run the tests

All logic and all tests are in the Swift package `Packages/ClaudeMonitorCore`. The tests use Swift Testing.

```bash
swift test --package-path Packages/ClaudeMonitorCore
```

In Xcode, select **Product > Test** (the `ClaudeMonitor` scheme includes the package tests). From the command line:

```bash
xcodebuild -project ClaudeMonitor.xcodeproj -scheme ClaudeMonitor -derivedDataPath build/DerivedData test
```

The tests read fixture folders, not your real `~/.claude`. They replace the process table, the clock, and the notification center with fakes. The behavior scenarios have one test each:

- `BehaviorScenarioTests.swift`: turns, waits, process liveness, partial files, and titles.
- `UnreadTurnTests.swift`: unread rows and the unread count on the icon.

## Notifications

The app shows "Turn completed" with the session title and the turn duration. A click on the notification opens the session.

The app does not show a notification:

- For the state that exists when the app starts.
- For a turn that is read as it ends, because Claude is the frontmost app and shows that session (see [Unread turns](#unread-turns)).

The Claude app has its own notification setting. To prevent duplicate notifications, turn off one of the two: the notifications in the Claude app settings, or Claude Monitor in **System Settings > Notifications**.

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
| `statusUpdatedAt` | Turn start and end times, in milliseconds since 1970. An `idle` record with a newer value is a turn that started and ended between two reads. |
| `hostSessionId` | The session identity. The app falls back to `sessionId`, then to the PID. |
| `name`, `cwd` | The title when the desktop title is not available, and the folder name. |
| `entrypoint` | The surface. Version 1 shows only desktop sessions (`claude-desktop`, `claude-desktop-3p`, `local-agent`). |
| `spare` | `true` for a pre-started process that has no session. The app ignores these records. |
| `version` | The Claude Code version. The format warning shows the newest version of the files that have an unknown format. |

The known `waitingFor` values are `permission prompt`, `input needed`, `dialog open`, `sandbox request`, and `goal proposal`. The panel shows other values as their raw text.

Rules:

- The app reads all files every second. It also reads at once when the folder changes. The timer is the source of truth because a process can stop without a file change.
- If a file contains partial JSON, the app keeps the last good state of that file. The app also keeps the last good state when a file is valid JSON but has no required field, for example while a spare process changes into a session.
- If two live files have the same `hostSessionId`, the app uses the file with the newest `statusUpdatedAt`.
- When a process stops, the session is "unloaded". The Claude app stops idle sessions that are not in focus after 30 minutes. Thus a stopped process does not mean that the user closed the session.
- When a different process takes over a session between two reads, the app does not count a completed turn.

### Desktop session metadata

The Claude app keeps one file for each session at `~/Library/Application Support/Claude/claude-code-sessions/<uuid>/<uuid>/<hostSessionId>.json`. The app reads these fields:

| Field | Use |
|---|---|
| `title` | The sidebar title. |
| `isArchived` | An archived session does not open with the deep link. |
| `lastActivityAt` | The last activity in the session. The parser reads it, but version 1 does not use it. |
| `lastFocusedAt` | The last time that you opened the session in the Claude app. |

These files can be large. The app finds a file by name and caches its path. It reads the file again only when its modification time changes, at most every 5 seconds.

### Unread turns

A finished turn is unread when it ended after both of these times:

- The `lastFocusedAt` of its session.
- The last click on its row or on its notification in Claude Monitor.

The Claude app does not change `lastFocusedAt` while you look at a session. Thus a turn is also read when it ends while both of these conditions are true:

- Claude is the frontmost app.
- Its session has the newest `lastFocusedAt` of all live sessions.

### Deep links

A click on a row or on a notification opens `claude://code/continue?session=<hostSessionId>` in the Claude app (`com.anthropic.claudefordesktop`). For an archived session or an ID that is not a desktop ID, the app only activates Claude, because the deep link does not find these sessions. Claude can turn off its deep links. Then the click only activates Claude.

## Add support for a new file format version

`SessionFileParser` is the only code that knows the JSON format of the session files. The rest of the app uses `SessionRecord`.

1. Copy a real session file of the new version. Remove personal paths, titles, and IDs. Add it to `Packages/ClaudeMonitorCore/Tests/ClaudeMonitorCoreTests/Fixtures/`. Put the Claude Code version in the file name, for example `session-busy-2.2.0.json`.
2. Add a test to `SessionFileParserTests.swift` that parses the new fixture and checks each field of `SessionRecord`. Run the tests and make sure that the new test fails.
3. Change `SessionFileParser.parse(_:)` so that it reads both the old and the new layout. Keep the old fixtures and tests. Users can run old and new Claude Code processes at the same time.
4. If the new version adds a `status` or `waitingFor` value, add it to `SessionStatus` or `WaitingReason`, and to the `switch` statements in the parser and in the UI.
5. Run all tests. Then update the verified versions in this README.

If the desktop metadata format changes, change `DesktopMetadataReader` and its tests in the same way.

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

## App icon

The source of the app icon is `design/AppIcon.svg` (1024 × 1024 px, with the icon body at 824 × 824 px). The script `scripts/make-app-icon.swift` renders it with the SVG support of macOS into `App/Assets.xcassets/AppIcon.appiconset` (16 px to 1024 px). Xcode compiles this set into `Assets.car` and `AppIcon.icns`.

After you change the SVG, render the icon again:

```bash
swift scripts/make-app-icon.swift
```

The SVG renderer of macOS ignores SVG filters. Thus the SVG draws its shadows with stacked translucent shapes. Do not use `filter`, `feGaussianBlur`, or `feDropShadow` in the SVG.

## Project layout

| Path | Contents |
|---|---|
| `App/` | The AppKit and SwiftUI app. See the table below. |
| `Packages/ClaudeMonitorCore/Sources/ClaudeMonitorCore/` | All logic. See the table below. |
| `Packages/ClaudeMonitorCore/Tests/` | Behavior scenarios, unit tests, and fixtures made from real files. |
| `project.yml` | The XcodeGen project definition. |
| `scripts/ExportOptions.plist` | Export options for Developer ID. |
| `scripts/make-app-icon.swift` | Renders the app icon into the asset catalog. |
| `design/AppIcon.svg` | The source of the app icon. |

Files in `App/`:

| File | Contents |
|---|---|
| `main.swift` | The entry point. Starts the app without a Dock icon. |
| `AppDelegate.swift` | Starts the monitor, the refresh driver, the notifications, and the welcome window. |
| `StatusItemController.swift` | The menu bar icon, its hover tracking, and its menu. |
| `SessionPanelController.swift` | The non-activating `NSPanel` below the icon. |
| `SessionPanelView.swift` | The SwiftUI content of the panel. |
| `UserNotificationPoster.swift` | Posts notifications and handles clicks on them. |
| `SessionOpener.swift` | Opens a session in the Claude app. |
| `LaunchAtLogin.swift` | The **Launch at Login** setting. |
| `OnboardingWindow.swift` | The welcome window. |

Files in `Packages/ClaudeMonitorCore/Sources/ClaudeMonitorCore/`:

| File | Contents |
|---|---|
| `ClaudePaths.swift` | The paths of the session folder and the desktop metadata folder. |
| `SessionDirectoryReader.swift` | Reads all session files, keeps the last good state of each file, and finds an unsupported format. |
| `SessionFileParser.swift` | The only code that knows the JSON format of the session files. |
| `SessionRecord.swift` | `SessionRecord`, `SessionID`, and `SessionSurface`. |
| `SessionStatus.swift` | `SessionStatus` and `WaitingReason`. |
| `ProcessInspector.swift` | The liveness check of a session process. |
| `LiveSessionFilter.swift` | Keeps the records of live processes on visible surfaces, one record for each session. |
| `SessionStore.swift` | The only owner of state transitions. Finds completed turns. |
| `DesktopMetadataReader.swift` | Reads the desktop session metadata. |
| `NotificationService.swift` | Makes notifications from completed turns. |
| `SessionMonitor.swift` | Reads the files, finds unread turns, and publishes `PanelState`. |
| `PanelState.swift` | Everything that the menu bar icon and the panel show. |
| `SessionOpenTarget.swift` | The deep link of a session, or only the activation of Claude. |
| `HoverPresenter.swift` | The open and close timing of the panel. |
| `SessionRefreshDriver.swift` | The timer and the folder watcher. |
| `TimeText.swift` | The text of durations and relative times. |

## Known limits of version 1

- The app shows only sessions of the Claude desktop app. VS Code and terminal sessions are filtered out.
- When a whole turn starts and ends between two reads, the app does not know its duration. The notification then shows only the title.
- The "Recently finished" list starts empty each time the app starts.
- The app cannot see which session you look at. It uses the session with the newest `lastFocusedAt` when Claude is the frontmost app. This causes two errors:
  - When the Claude app shows more than one session, for example in split view, a turn that ends in a session that you did not open last stays unread.
  - When Claude is the frontmost app but shows a different screen, for example its settings, a turn that ends in the session that you opened last is read.
- When a turn ends and the next turn starts between two reads, the app sees one long turn. The files look the same as a short wait for the user (`busy` to `waiting` to `busy`), which does not end a turn.
- When the first read of a turn shows `waiting`, the app uses the start of the wait as the turn start. The time since the turn started and the duration are then too short.
- A change from an unknown status to `idle` is not a completed turn, unless the app saw `busy` or `waiting` before it. This prevents false notifications for states that are not turns.
