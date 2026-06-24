/// Combines the connectivity-probe result with the IP-lookup result into a single
/// `FetchOutcome`. The probe's reachability is authoritative for online/offline;
/// the IP lookup only refines a reachable connection into success vs. lookup-failed.
public func combinedOutcome(reachable: Bool, fetchedIP: IPInfo?) -> FetchOutcome {
    guard reachable else { return .offline }
    if let info = fetchedIP { return .success(info) }
    return .lookupFailed
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
