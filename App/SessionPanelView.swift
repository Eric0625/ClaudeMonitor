import ClaudeMonitorCore
import Observation
import SwiftUI

@MainActor
@Observable
final class PanelLayout {
    var maxListHeight: CGFloat = 600
    var isVisible = false
}

/// Fixed heights, so that the panel size depends only on the panel state.
enum PanelMetrics {
    static let rowHeight: CGFloat = 46
    static let headerHeight: CGFloat = 28
    static let emptyHeight: CGFloat = 30
    static let dividerHeight: CGFloat = 9
    static let listPadding: CGFloat = 6

    static func listHeight(runningRows: Int, finishedRows: Int) -> CGFloat {
        func section(_ rows: Int) -> CGFloat {
            headerHeight + (rows == 0 ? emptyHeight : CGFloat(rows) * rowHeight)
        }
        return listPadding * 2 + section(runningRows) + dividerHeight + section(finishedRows)
    }
}

struct PanelActions {
    var openSession: (SessionID, SessionOpenTarget) -> Void
    var quit: () -> Void
    var sizeChanged: (CGSize) -> Void
}

struct SessionPanelView: View {
    static let width: CGFloat = 340

    let monitor: SessionMonitor
    let launchAtLogin: LaunchAtLogin
    let layout: PanelLayout
    let actions: PanelActions

    var body: some View {
        let state = monitor.panelState
        VStack(alignment: .leading, spacing: 0) {
            if let warning = state.formatWarning {
                FormatWarningView(text: warning)
                Divider()
            }
            ScrollView {
                TimelineView(.animation(minimumInterval: 1, paused: !layout.isVisible)) { context in
                    VStack(alignment: .leading, spacing: 0) {
                        RunningSection(rows: state.running, now: context.date, open: actions.openSession)
                        Divider()
                            .frame(height: PanelMetrics.dividerHeight)
                        FinishedSection(rows: state.recentlyFinished, now: context.date, open: actions.openSession)
                    }
                    .padding(.vertical, PanelMetrics.listPadding)
                }
            }
            .scrollIndicators(.automatic)
            .frame(height: min(listHeight(for: state), layout.maxListHeight))
            Divider()
            PanelFooter(launchAtLogin: launchAtLogin, quit: actions.quit)
        }
        .frame(width: Self.width)
        .fixedSize(horizontal: false, vertical: true)
        .background {
            GeometryReader { proxy in
                Color.clear.preference(key: PanelSizeKey.self, value: proxy.size)
            }
        }
        .onPreferenceChange(PanelSizeKey.self) { size in
            actions.sizeChanged(size)
        }
    }

    private func listHeight(for state: PanelState) -> CGFloat {
        PanelMetrics.listHeight(runningRows: state.running.count, finishedRows: state.recentlyFinished.count)
    }
}

private struct PanelSizeKey: PreferenceKey {
    static let defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

private struct FormatWarningView: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(.callout)
            .foregroundStyle(.orange)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SectionHeader: View {
    let title: String
    var count: Int?

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            if let count, count > 0 {
                Text("\(count)").monospacedDigit()
            }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .textCase(.uppercase)
        .padding(.horizontal, 14)
        .padding(.bottom, 4)
        .frame(height: PanelMetrics.headerHeight, alignment: .bottom)
    }
}

private struct EmptySectionText: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 14)
            .frame(height: PanelMetrics.emptyHeight, alignment: .leading)
    }
}

private struct RunningSection: View {
    let rows: [RunningSessionRow]
    let now: Date
    let open: (SessionID, SessionOpenTarget) -> Void

    var body: some View {
        SectionHeader(title: "Running", count: rows.count)
        if rows.isEmpty {
            EmptySectionText(text: "No running sessions")
        } else {
            ForEach(rows) { row in
                SessionRowButton(action: { open(row.id, row.openTarget) }) {
                    RunningRowContent(row: row, now: now)
                }
            }
        }
    }
}

private struct FinishedSection: View {
    let rows: [FinishedTurnRow]
    let now: Date
    let open: (SessionID, SessionOpenTarget) -> Void

    var body: some View {
        SectionHeader(title: "Recently finished")
        if rows.isEmpty {
            EmptySectionText(text: "No finished turns yet")
        } else {
            ForEach(rows) { row in
                SessionRowButton(action: { open(row.sessionID, row.openTarget) }) {
                    FinishedRowContent(row: row, now: now)
                }
            }
        }
    }
}

private struct RunningRowContent: View {
    let row: RunningSessionRow
    let now: Date

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            indicator
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                subtitle
            }
            Spacer(minLength: 8)
            if let start = row.turnStartedAt {
                Text(TimeText.duration(now.timeIntervalSince(start)))
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var indicator: some View {
        switch row.activity {
        case .working:
            Image(systemName: "circle.fill")
                .font(.system(size: 7))
                .foregroundStyle(.green)
                .frame(width: 14)
        case .waiting:
            Image(systemName: "hand.raised.fill")
                .foregroundStyle(.orange)
                .frame(width: 14)
        case .unrecognized:
            Image(systemName: "questionmark.circle")
                .foregroundStyle(.secondary)
                .frame(width: 14)
        }
    }

    private var subtitle: some View {
        HStack(spacing: 4) {
            if !row.folderName.isEmpty {
                Text(row.folderName)
            }
            if let activity = row.activityText {
                if !row.folderName.isEmpty {
                    Text("·")
                }
                Text(activity)
                    .foregroundStyle(row.isWaiting ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
}

private struct FinishedRowContent: View {
    let row: FinishedTurnRow
    let now: Date

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: row.isUnread ? "checkmark.circle.fill" : "checkmark.circle")
                .foregroundStyle(row.isUnread ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(.body.weight(row.isUnread ? .bold : .regular))
                    .lineLimit(1)
                    .truncationMode(.tail)
                HStack(spacing: 4) {
                    if !row.folderName.isEmpty {
                        Text(row.folderName)
                    }
                    if let duration = row.duration {
                        if !row.folderName.isEmpty {
                            Text("·")
                        }
                        Text("took \(TimeText.duration(duration))")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(TimeText.relative(from: row.endedAt, now: now))
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(row.isUnread ? "Unread" : "")
    }
}

private struct SessionRowButton<Label: View>: View {
    let action: () -> Void
    @ViewBuilder let label: () -> Label
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            label()
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: PanelMetrics.rowHeight - 4)
                .contentShape(Rectangle())
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isHovered ? Color.primary.opacity(0.08) : .clear)
                )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
        .frame(height: PanelMetrics.rowHeight)
        .onHover { isHovered = $0 }
        .help("Open in Claude")
        .accessibilityHint("Opens the session in Claude")
    }
}

private struct PanelFooter: View {
    let launchAtLogin: LaunchAtLogin
    let quit: () -> Void

    var body: some View {
        HStack {
            Toggle("Launch at Login", isOn: Binding(
                get: { launchAtLogin.isEnabled },
                set: { launchAtLogin.setEnabled($0) }
            ))
            .toggleStyle(.checkbox)
            Spacer()
            Button("Quit", action: quit)
        }
        .controlSize(.small)
        .font(.callout)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}
