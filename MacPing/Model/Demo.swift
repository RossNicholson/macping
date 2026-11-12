#if DEBUG
import Foundation

/// Sample monitors for screenshots and for checking the design, with no pinging
@MainActor
enum Demo {
    static func load(into monitor: Monitor) {
        monitor.loadDemo { monitor in
            monitor.setDemoAliases(["192.168.1.1": "Office router", "nas.local": "NAS"])
            monitor.setDemoFavorites([
                Favorite(name: "Office", hosts: ["192.168.1.1", "nas.local", "printer.local"], columns: 0),
                Favorite(name: "Websites", hosts: ["rossnicholson.dev:443", "github.com"], columns: 2),
            ])
            monitor.addDemoProbe(probe("192.168.1.1", replies: [1.2, 0.9, 1.4, 1.1, 0.8, 1.3, 1.0, 1.2]))
            monitor.addDemoProbe(probe("1.1.1.1", replies: [11.4, 12.1, 10.8, 13.5, 11.9, 12.4, 11.2, 12.8]))
            monitor.addDemoProbe(probe("rossnicholson.dev:443", replies: [24.6, 22.9, 25.3, 23.8, 24.1, 26.2, 23.4, 24.9]))
            monitor.addDemoProbe(probe("nas.local", replies: [3.1, 2.8, nil, 3.4, nil]))
            monitor.addDemoProbe(probe("10.0.0.40", replies: [4.2, 3.9, nil, nil, nil, nil]))
            monitor.addDemoProbe(Probe(input: "printer.local"))
            monitor.setDemoHistory([
                (180, "192.168.1.1", .start), (180, "1.1.1.1", .start), (180, "rossnicholson.dev:443", .start),
                (179, "192.168.1.1", .up), (179, "1.1.1.1", .up), (179, "rossnicholson.dev:443", .up),
                (95, "nas.local", .start), (95, "nas.local", .up), (62, "nas.local", .down), (58, "nas.local", .up),
                (40, "10.0.0.40", .start), (40, "10.0.0.40", .up), (3, "10.0.0.40", .down),
                (1, "printer.local", .stop),
            ])
        }
    }

    static let hops: [Hop] = [
        Hop(number: 1, address: "192.168.1.1", name: "router.lan", ms: 1.1),
        Hop(number: 2, address: "100.64.0.1", ms: 8.4),
        Hop(number: 3, address: nil),
        Hop(number: 4, address: "62.24.240.6", name: "lon-core-1.isp.net", ms: 11.7),
        Hop(number: 5, address: "195.66.225.179", name: "linx.cloudflare.com", ms: 12.2),
        Hop(number: 6, address: "1.1.1.1", name: "one.one.one.one", ms: 11.9, reachedTarget: true),
    ]

    /// A monitor that's had these replies, nil being a lost one
    static func probe(_ host: String, replies: [Double?]) -> Probe {
        let probe = Probe(input: host)
        probe.demoRunning = true
        for ms in replies {
            if let ms {
                probe.apply(.reply(ms: ms, from: host.components(separatedBy: ":").first ?? host,
                                   ttl: host.contains(":") ? nil : 57, bytes: 40), downAfter: 3)
            } else {
                probe.apply(.timedOut, downAfter: 3)
            }
        }
        return probe
    }
}
#endif
