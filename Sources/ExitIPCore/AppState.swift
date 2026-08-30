public enum FailureReason: Sendable, Equatable {
    case offline
    case captivePortal
    case lookupFailed

    /// Whether the user can do something about it — worth announcing even when
    /// already in a failed state.
    public var isActionable: Bool {
        switch self {
        case .captivePortal: return true
        case .offline, .lookupFailed: return false
        }
    }
}

public enum FetchOutcome: Sendable, Equatable {
    case success(ExitSnapshot)
    case failure(FailureReason)
}

public struct ExitIPModel: Sendable, Equatable {
    public enum Phase: Sendable, Equatable {
        case initial
        case ok
        case failed(FailureReason)
    }

    public var phase: Phase
    public var lastGood: ExitSnapshot?
    /// Exit warnings as of the last good reading. Kept through failures so the
    /// same warning doesn't re-alert after a blip; see `activeWarnings`.
    public var warnings: [ExitWarning]

    /// The primary address of the last good reading.
    public var lastGoodIP: IPInfo? { lastGood?.primary }

    /// Warnings that apply right now — only a current good reading can be wrong.
    public var activeWarnings: [ExitWarning] { phase == .ok ? warnings : [] }

    public init(phase: Phase = .initial, lastGood: ExitSnapshot? = nil, warnings: [ExitWarning] = []) {
        self.phase = phase
        self.lastGood = lastGood
        self.warnings = warnings
    }
}

public struct AppNotification: Sendable, Equatable {
    public var title: String
    public var body: String

    public init(title: String, body: String) {
        self.title = title
        self.body = body
    }
}
