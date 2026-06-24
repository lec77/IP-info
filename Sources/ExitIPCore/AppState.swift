public enum FailureReason: Sendable, Equatable {
    case offline
    case lookupFailed
}

public enum FetchOutcome: Sendable, Equatable {
    case success(IPInfo)
    case offline
    case lookupFailed
}

public struct ExitIPModel: Sendable, Equatable {
    public enum Phase: Sendable, Equatable {
        case initial
        case ok
        case failed(FailureReason)
    }

    public var phase: Phase
    public var lastGoodIP: IPInfo?

    public init(phase: Phase = .initial, lastGoodIP: IPInfo? = nil) {
        self.phase = phase
        self.lastGoodIP = lastGoodIP
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
