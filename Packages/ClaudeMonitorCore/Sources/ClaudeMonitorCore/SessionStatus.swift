import Foundation

/// Why a session waits for the user.
public enum WaitingReason: Hashable, Sendable {
    case permissionPrompt
    case inputNeeded
    case dialogOpen
    case sandboxRequest
    case goalProposal
    /// A value that this version of the app does not know.
    case other(String)

    public var displayText: String {
        switch self {
        case .permissionPrompt: "Permission prompt"
        case .inputNeeded: "Input needed"
        case .dialogOpen: "Dialog open"
        case .sandboxRequest: "Sandbox request"
        case .goalProposal: "Goal proposal"
        case .other(let raw): raw.isEmpty ? "Waiting" : raw
        }
    }
}

/// The status that Claude Code writes for a session.
public enum SessionStatus: Hashable, Sendable {
    /// Claude is working.
    case busy
    /// The turn is done.
    case idle
    /// Claude needs the user.
    case waiting(WaitingReason)
    /// A value that this version of the app does not know, for example `shell`.
    case unknown(String)
}
