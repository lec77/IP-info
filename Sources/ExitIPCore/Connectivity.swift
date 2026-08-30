public enum ProbeVerdict: Sendable, Equatable {
    case reachable
    case captivePortal
    case unreachable
}

/// Classifies the connectivity probe's HTTP status. The probe never follows
/// redirects, so a 3xx (portal bouncing to its login page) or an unexpected 2xx
/// (portal serving its own page) means a captive portal; no response at all
/// means unreachable.
public func probeVerdict(statusCode: Int?, expected: Int = Config.probeExpectedStatus) -> ProbeVerdict {
    guard let statusCode else { return .unreachable }
    return statusCode == expected ? .reachable : .captivePortal
}

/// Combines the connectivity-probe verdict with the exit-lookup result into a
/// single `FetchOutcome`. The probe is authoritative for online/offline/portal;
/// the lookup only refines a reachable connection into success vs. lookup-failed.
public func combinedOutcome(probe: ProbeVerdict, fetched: ExitSnapshot?) -> FetchOutcome {
    switch probe {
    case .unreachable: return .failure(.offline)
    case .captivePortal: return .failure(.captivePortal)
    case .reachable: return fetched.map(FetchOutcome.success) ?? .failure(.lookupFailed)
    }
}

/// Offline hysteresis. A success always reports immediately and resets the
/// streak. A failure increments the consecutive-failure streak and is only
/// reported (shown/notified) once the streak reaches `confirmAfter` — so a
/// single transient blip is held back until a re-check confirms it.
public func confirmOutcome(
    _ outcome: FetchOutcome,
    failureStreak: Int,
    confirmAfter: Int
) -> (report: Bool, failureStreak: Int) {
    if case .success = outcome {
        return (true, 0)
    }
    let streak = failureStreak + 1
    return (streak >= max(1, confirmAfter), streak)
}
