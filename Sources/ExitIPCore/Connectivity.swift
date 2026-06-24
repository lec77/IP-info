/// Combines the connectivity-probe result with the IP-lookup result into a single
/// `FetchOutcome`. The probe's reachability is authoritative for online/offline;
/// the IP lookup only refines a reachable connection into success vs. lookup-failed.
public func combinedOutcome(reachable: Bool, fetchedIP: IPInfo?) -> FetchOutcome {
    guard reachable else { return .offline }
    if let info = fetchedIP { return .success(info) }
    return .lookupFailed
}
