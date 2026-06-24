/// Advances the model with a fetch outcome and decides whether to notify.
public func reduce(
    _ model: ExitIPModel,
    applying outcome: FetchOutcome
) -> (model: ExitIPModel, notification: AppNotification?) {
    switch outcome {
    case .success(let info):
        let newModel = ExitIPModel(phase: .ok, lastGoodIP: info)
        guard let prev = model.lastGoodIP else {
            return (newModel, nil) // silent initial success
        }
        if prev.ip != info.ip {
            let body = "\(ipWithCountryCode(prev)) → \(ipWithCountryCode(info))"
            return (newModel, AppNotification(title: "Exit IP changed", body: body))
        }
        if case .failed = model.phase {
            return (newModel, AppNotification(title: "Exit IP restored", body: "\(info.ip) (unchanged)"))
        }
        return (newModel, nil)

    case .offline, .lookupFailed:
        let reason: FailureReason = (outcome == .offline) ? .offline : .lookupFailed
        let newModel = ExitIPModel(phase: .failed(reason), lastGoodIP: model.lastGoodIP)
        if model.lastGoodIP == nil { return (newModel, nil) } // silent initial failure
        if case .failed = model.phase { return (newModel, nil) } // no repeat while failed
        let body = (reason == .offline) ? "No network connection." : "Could not reach IP lookup service."
        return (newModel, AppNotification(title: "Exit IP unavailable", body: body))
    }
}

private func ipWithCountryCode(_ info: IPInfo) -> String {
    if let cc = info.countryCode, !cc.isEmpty {
        return "\(info.ip) (\(cc))"
    }
    return info.ip
}
