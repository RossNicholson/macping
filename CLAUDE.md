# MacPing

Open-source (MIT) Mac app: a Mac version of vmPing (r-smith/vmPing, Windows) with the same features,
in the house style via the shared HouseStyle package. Window + menu bar. GitHub: RossNicholson/macping
(public). Cask (when released): `macping` in RossNicholson/homebrew-tap.

Ross's decisions (2026-11-12): name MacPing, public and open source, window + menu bar, no email
alerts. Left out on purpose: vmPing's packet generator / flood tester.

## Layout
- `MacPing/Ping/`: `Target` (host / host:port / [v6]:port parsing, lists), `ICMP` (`Address`
  resolve + names, `ICMPSocket`: unprivileged SOCK_DGRAM ICMP/ICMPv6 echo, packet building and reply
  matching incl. time exceeded / unreachable), `TCPCheck` (NWConnection handshake), `Traceroute`.
- `MacPing/Model/`: `Probe` (a tile: status, log, stats) + `ProbeRunner` (thread per monitor),
  `Monitor` (all tiles, history, aliases, favourites, alerts) + `Alerts` (notifications, sound, log
  file), `AppSettings` (UserDefaults, injectable), `Library` (JSON in Application Support),
  `HistoryExport`, `Demo` (Debug only).
- `MacPing/Views/`: `MainView` (top bar + `ProbeGrid`), `ProbeTile`, `Sheets` (add hosts,
  favourites, aliases, about), `SettingsView` (its own window), `HistoryView`, `TracerouteView` (+ `TracerouteSession`),
  `MenuBarPanel`.
- `MacPing/App/`: `AppDelegate` (main/history/traceroute windows, activation policy, StatusBarController).
- `MacPing/Theme/`: `Mascot` (ping-pong ball, happy/worried, `bounce`), `MenuBarIcon`, status colours.

## Commands
- `make run`: signed (Developer ID) dev build, opens it. Run unsandboxed.
- `make test`: unit tests (one pings 127.0.0.1). `TEST_RUNNER_NETWORK=1 make test` adds real
  internet ping, port check and traceroute tests.
- `make screenshots`, `make icon` (redraws the app icon from Mascot).
- `-demo YES` launch argument (Debug only): sample monitors, no pinging.
- Release: `make release VERSION=x.y.z` (see RELEASING.md). Ask Ross before releasing. CI needs the 6
  secrets (see the Mac release secrets memory) set by Ross, and a `macping` cask in the tap.

## Gotchas
- Tests run inside the app as host and share its UserDefaults domain: use `AppSettings(defaults:)`
  and `Monitor(libraryURL: nil)`, and set `quiet`.
- IPv4 datagram ICMP sockets return the IP header; IPv6 ones don't. Every ICMP socket sees every
  reply: identifiers come from a process-wide counter, replies must also come from the address
  pinged, and each socket drains other monitors' replies before it sends.
- `Monitor.columns` saves the session on every set: read `library` before setting it (see `restore`).
- A probe's runner events carry its generation; events from a stopped runner are dropped.
- Command-line `-Key value` pairs are skipped as a pair (Xcode passes some).
- Synthetic (computer-use) mouse drags don't trigger SwiftUI `.draggable`; tile reordering by drag
  needs a real mouse to test. Tiles' ⋯ menu has Move Earlier/Later too.
- After dev builds, `lsregister -u` the build copy so it can't hijack launches of an installed copy.

## Where we left off (2026-11-12)
- First version built: all features above, 31 unit tests + 3 network tests pass, screenshots and
  icon rendered. Not yet run by Ross.
- Bug review + live test of every feature done 2026-11-12. Fixed: last-hosts restore wiped itself,
  late runner events hitting a new host, DNS hiccups turning down into error, missed back-up alerts,
  flag values as hosts, socket buffer overflow / identifier collisions, settings clipped (now a
  window), hover-only tile buttons (now ⋯ + right-click menu), repeated error lines (now ×N), and more.
  Not tested live: notifications (Focus was on), open at login (would register the dev build),
  drag to reorder (see Gotchas). Not released; nothing on rossnicholson.dev until it's finished.
- **1.0.0 RELEASED 2026-11-12** (CI notarized, cask `macping` in the tap, release notes written).
  Next: HouseStyle MoreApps + BrewDock Discover + rossnicholson.dev page.
