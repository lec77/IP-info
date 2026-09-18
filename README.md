# IP-info

A tiny native macOS **menu bar app** that shows your current **exit (public) IP** at a glance — with the country flag and city — and tells you when it changes, when connectivity drops, or when your VPN isn't doing what you think. Pin the country you expect to exit from and the menu bar turns ⛔ the moment traffic leaves elsewhere.

> Menu bar: `🇩🇪 Berlin` · Dropdown: IPv4/IPv6 (click to copy), location, ISP, interface, latency, history, and controls.

## Features

- **Live exit IP** in the menu bar (flag + city), updated the moment your network/VPN changes (via `NWPathMonitor`) plus a backstop poll whose interval you pick under *Settings ▸ Check every ▸* (15 s … 10 min, default 1 min). While a check runs, the dropdown shows *Checking…* with a rotating mark.
- **Expected-exit guard.** Pin a country under *Settings ▸ Expected exit ▸* (it lists the countries the app has seen, so pinning is one click while connected to the right place). The title becomes `⛔ 🇺🇸 San Jose` and you get a notification when the exit lands somewhere else — and an "Exit OK" when it's back.
- **VPN leak detection.** The dropdown shows which interface carries your traffic (`Via: VPN tunnel (utun1500)` / `Wi-Fi (en0)`), found by asking the routing table directly, so a proxy's TUN device (Clash, Surge, …) that `NWPathMonitor` doesn't list is still seen. The app actively measures the direct exit through the current physical interface and compares it with the normal exit in the same address family. It uses numeric Cloudflare HTTPS trace endpoints, bypassing system DNS/Fake-IP and proxies while keeping TLS verification enabled. If the numeric endpoints fail, it resolves icanhazip through interface-bound AliDNS HTTPS queries and pins the returned addresses, still bypassing system DNS. Matching IPs show a caution about possible direct routing, not a confirmed VPN-wide leak. Failed measurements show **Direct exit unavailable**, or retain the last display with **Stale · Last success … ago**; stale readings are never used for comparisons. Direct probes use macOS's bundled `/usr/bin/curl`, with bounded timeouts and no fallback to the default interface.
- **IPv4 + IPv6.** Both exits are looked up (hosts without IPv6 just show IPv4). If IPv6 exits in a different country than IPv4 — or, on a tunnel, via a different ISP — that's the classic IPv6 leak and it's flagged.
- **DNS leak detection.** Every 5 minutes a poll asks an authoritative server which resolver looked up a one-off name (`DNS: 🇺🇸 Google LLC` in the dropdown); a resolver in a different country than the exit is flagged.
- **History.** *History ▸* lists recent exit changes (`14:05  🇺🇸 → 🇩🇪  5.6.7.8`, click to copy) and the dropdown shows "Unchanged for 3h 12m". Persisted, so a change that happened while the app wasn't running is still recorded at launch.
- **Connection states** with hysteresis (a single blip is re-checked before it's reported): `⚠︎ offline`, `⚠︎ captive portal` (the *Open network sign-in…* action is available under *Settings* and also in the main menu when sign-in is required; it opens the portal's login URL), `⚠︎ tunnel down` when the physical network works but nothing gets through the VPN/proxy tunnel, and `⚠︎` + last known place when the lookup services are unreachable. Latency to the probe endpoint is shown in the dropdown with a sparkline of the last 12 checks.
- **Notifications** on exit change, connectivity loss/restore, captive portal (with an *Open sign-in page* button), tunnel down, and every warning above (toggle in the menu; the setting persists).
- **Pause monitoring** (`⏸` in the title) when you don't want the traffic — e.g. on a metered connection.
- **Launch at login** toggle (via `SMAppService`).
- **No dependencies, no API keys, menu-bar only** (no Dock icon). Addresses come from `ipify` → `icanhazip` (per family); geo/ISP from `ipinfo.io` → `ipwho.is` → `ipapi.co`, looked up **only when an address is first seen** and cached, so the periodic poll never touches the rate-limited geo services.

### Menu bar legend

| Prefix | Meaning |
|---|---|
| `⛔` | Exit is not in the country you pinned |
| `⚠︎` | Degraded (offline, captive portal, tunnel down, partial geo) or a leak warning — open the menu |
| `⏸` | Monitoring paused |

### Dropdown

```
VPN TUNNEL
VPN tunnel (utun4)
🇩🇪 Germany · Berlin
Example VPN GmbH
IPv4  203.0.113.42          ← click to copy
IPv6  2001:db8::1           ← when available
Latency: 32 ms ▂▃▂▅▁
────────────────────────────
DIRECT
Wi-Fi (en0)
🇺🇸 United States · San Jose
Example ISP
IPv4  198.51.100.20         ← click to copy
────────────────────────────
CONNECTION CHECK
Detected exit differs from direct connection
DNS: 🇩🇪 Example VPN GmbH   ← click to copy
Last checked: just now
Unchanged for 3h 12m
Refresh now                ⌘R
────────────────────────────
History                    ▸
Settings                   ▸
Quit IP-info               ⌘Q
```

## Architecture

- `Sources/ExitIPCore` — pure, fully unit-tested logic, Swift 6 language mode: data model, provider JSON parsing, the address/geo resolver with its per-address geo cache, connectivity verdicts (reachable / captive portal / offline) + hysteresis, the state + notification reducer, exit-warning assessment (expected country, IPv6 mismatch, tunnel-but-direct-IP), change history, interface classification, and display formatting.
- `Sources/ExitIPApp` — a thin AppKit shell: status item + menu, network watcher (`NWPathMonitor`, incl. which interface carries the default route), connectivity probe (HTTPS first; plain-HTTP fallback *bound to the physical interface* — bypassing any VPN/proxy TUN and its DNS hijack — to distinguish a captive portal from being offline and to catch the portal's redirect URL), default-route probe (finds a proxy's TUN device that `NWPathMonitor` doesn't list), fetcher wiring, notifier, UserDefaults-backed settings, login item.
- `Tests/ExitIPCoreTests` — 176 unit tests covering the core logic.

Persisted state lives in UserDefaults under `com.lec77.ipinfo` (notifications toggle, expected country, poll interval, history).

## Build & run

Requires macOS 13+ and a Swift 6 toolchain (Xcode or Command Line Tools).

```bash
./build-app.sh          # produces IP-info.app
open IP-info.app
# or install it:
./build-app.sh --install   # copies to /Applications
```

Run the tests (XCTest needs full Xcode):

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

The app icon is generated by `Assets/make-icon.swift`. Each check logs one line (`check: probe=… exit=…`) to the unified log — `log stream --predicate 'process == "IP-info"'` — handy when a network looks wrong.

## Download

Signed and notarized builds are on the [Releases page](https://github.com/lec77/IP-info/releases) — download the zip, unzip, and drag `IP-info.app` to `/Applications`. It opens without Gatekeeper warnings (Developer ID + notarization).

### Making a release (maintainer)

`release.sh` builds with a Developer ID signature and hardened runtime, notarizes with Apple, staples the ticket, verifies with `spctl`, and zips the result:

```bash
./release.sh 1.1.0             # -> dist/IP-info-1.1.0.zip (+ .sha256)
./release.sh 1.1.0 --publish   # …and tag v1.1.0, push, create the GitHub release
```

One-time setup: a "Developer ID Application" certificate in your keychain (Xcode ▸ Settings ▸ Accounts ▸ Manage Certificates…), and notarization credentials saved as a keychain profile named `developer` (override with `NOTARY_PROFILE`):

```bash
xcrun notarytool store-credentials developer --apple-id you@example.com --team-id TEAMID
```

using an [app-specific password](https://account.apple.com). `build-app.sh` on its own ad-hoc signs, which is fine for your own Mac but not for sharing.

## License

Personal project — use freely.
