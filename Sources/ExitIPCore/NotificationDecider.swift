/// Advances the model with a fetch outcome and returns what to notify: exit
/// changes / connectivity transitions, plus any exit warnings that appeared or
/// cleared (assessed against `context` on every good reading).
public func reduce(
    _ model: ExitIPModel,
    applying outcome: FetchOutcome,
    context: WarningContext = WarningContext()
) -> (model: ExitIPModel, notifications: [AppNotification]) {
    switch outcome {
    case .success(let snapshot):
        let info = snapshot.primary
        let newModel = ExitIPModel(phase: .ok, lastGood: snapshot, warnings: model.warnings)
        var notes: [AppNotification] = []
        if let prev = model.lastGoodIP { // silent initial success
            if prev.ip != info.ip {
                let body = "\(ipWithCountryCode(prev)) → \(ipWithCountryCode(info))"
                notes.append(AppNotification(title: "Exit IP changed", body: body))
            } else if case .failed = model.phase {
                notes.append(AppNotification(title: "Exit IP restored", body: "\(info.ip) (unchanged)"))
            }
        }
        let (assessed, warningNotes) = reassess(newModel, context: context)
        return (assessed, notes + warningNotes)

    case .failure(let reason):
        let newModel = ExitIPModel(phase: .failed(reason), lastGood: model.lastGood, warnings: model.warnings)
        if model.lastGood == nil { return (newModel, []) } // silent initial failure
        if case .failed(let previous) = model.phase, !(reason.isActionable && reason != previous) {
            return (newModel, []) // no repeat while failed
        }
        let action: AppNotification.Action? = reason == .captivePortal ? .openSignIn : nil
        return (newModel, [AppNotification(title: "Exit IP unavailable", body: failureBody(reason), action: action)])
    }
}

/// Re-evaluates the exit warnings against a changed context (a new expected
/// country, a different interface) without a new reading. No-op unless the
/// model holds a current good reading.
public func reassess(
    _ model: ExitIPModel,
    context: WarningContext
) -> (model: ExitIPModel, notifications: [AppNotification]) {
    guard model.phase == .ok, let snapshot = model.lastGood else { return (model, []) }
    var updated = model
    updated.warnings = assessWarnings(snapshot, context: context)
    let notes = warningNotifications(
        previous: model.warnings, current: updated.warnings,
        snapshot: snapshot, expectedCountryCode: context.expectedCountryCode
    )
    return (updated, notes)
}

private func failureBody(_ reason: FailureReason) -> String {
    switch reason {
    case .offline: return "No network connection."
    case .captivePortal: return "Captive portal detected — open a browser to sign in."
    case .tunnelDown: return "The VPN/proxy tunnel isn't passing traffic; the network underneath is fine."
    case .lookupFailed: return "Could not reach IP lookup service."
    }
}
