import XCTest
@testable import MacPing

final class TargetTests: XCTestCase {
    func testParsing() {
        XCTAssertEqual(Target(parsing: "example.com"), Target(host: "example.com"))
        XCTAssertEqual(Target(parsing: " 10.0.0.1 "), Target(host: "10.0.0.1"))
        XCTAssertEqual(Target(parsing: "example.com:443"), Target(host: "example.com", port: 443))
        XCTAssertEqual(Target(parsing: "fe80::1"), Target(host: "fe80::1"))
        XCTAssertEqual(Target(parsing: "[fe80::1]:22"), Target(host: "fe80::1", port: 22))
        XCTAssertEqual(Target(parsing: "[2606:4700::1111]"), Target(host: "2606:4700::1111"))
        XCTAssertNil(Target(parsing: ""))
        XCTAssertNil(Target(parsing: "two words"))
        XCTAssertNil(Target(parsing: "host:0"))
        XCTAssertNil(Target(parsing: "host:99999"))
        XCTAssertNil(Target(parsing: ":80"))
        XCTAssertNil(Target(parsing: "[fe80::1"))
    }

    func testTextRoundTrips() {
        for text in ["example.com", "example.com:443", "fe80::1", "[fe80::1]:22"] {
            XCTAssertEqual(Target(parsing: text)?.text, text)
        }
    }

    func testList() {
        let text = """
        # office
        192.168.1.1, nas.local
        example.com:443;github.com  bad host:0
        """
        XCTAssertEqual(Target.list(from: text).map(\.text),
                       ["192.168.1.1", "nas.local", "example.com:443", "github.com", "bad"])
    }
}

final class ICMPTests: XCTestCase {
    func testEchoRequest() {
        let packet = ICMPSocket.echoRequest(v6: false, identifier: 0x1234, sequence: 7, payloadSize: 4)
        XCTAssertEqual(Array(packet[0..<2]), [8, 0])
        XCTAssertEqual(Array(packet[4..<8]), [0x12, 0x34, 0, 7])
        XCTAssertEqual(packet.count, 12)
        // A packet with its checksum in place sums to zero
        XCTAssertEqual(ICMPSocket.checksum(packet), 0)
        XCTAssertEqual(ICMPSocket.echoRequest(v6: true, identifier: 1, sequence: 1, payloadSize: 0)[0], 128)
    }

    private func ipHeader(ttl: UInt8 = 57) -> [UInt8] {
        [0x45, 0, 0, 0, 0, 0, 0, 0, ttl, 1, 0, 0, 1, 1, 1, 1, 10, 0, 0, 2]
    }

    func testMatchesEchoReply() {
        let reply = ipHeader() + [0, 0, 0, 0, 0x12, 0x34, 0, 7] + [UInt8](repeating: 0x61, count: 32)
        let match = ICMPSocket.match(reply, v6: false, identifier: 0x1234, sequence: 7, ms: 5, from: "1.1.1.1")
        XCTAssertEqual(match, .reply(ms: 5, from: "1.1.1.1", ttl: 57, bytes: 40))
        // Someone else's ping, or an old sequence number
        XCTAssertNil(ICMPSocket.match(reply, v6: false, identifier: 0x9999, sequence: 7, ms: 5, from: "x"))
        XCTAssertNil(ICMPSocket.match(reply, v6: false, identifier: 0x1234, sequence: 8, ms: 5, from: "x"))
    }

    func testMatchesTimeExceeded() {
        let quoted = ipHeader() + [8, 0, 0, 0, 0x12, 0x34, 0, 3]
        let message = ipHeader(ttl: 250) + [11, 0, 0, 0, 0, 0, 0, 0] + quoted
        XCTAssertEqual(ICMPSocket.match(message, v6: false, identifier: 0x1234, sequence: 3, ms: 2, from: "10.0.0.1"),
                       .ttlExpired(ms: 2, from: "10.0.0.1"))
        let unreachable = ipHeader() + [3, 1, 0, 0, 0, 0, 0, 0] + quoted
        XCTAssertEqual(ICMPSocket.match(unreachable, v6: false, identifier: 0x1234, sequence: 3, ms: 2, from: "10.0.0.1"),
                       .unreachable(from: "10.0.0.1", code: 1))
    }

    func testMatchesV6Reply() {
        let reply: [UInt8] = [129, 0, 0, 0, 0, 5, 0, 9, 1, 2]
        XCTAssertEqual(ICMPSocket.match(reply, v6: true, identifier: 5, sequence: 9, ms: 1, from: "::1"),
                       .reply(ms: 1, from: "::1", ttl: nil, bytes: 10))
    }

    /// Pings this Mac itself: proves the unprivileged socket works here
    func testPingsLoopback() throws {
        let address = try Address.resolve("127.0.0.1")
        let socket = try ICMPSocket(family: address.family)
        XCTAssertTrue(socket.ping(address, sequence: 1, timeout: 2).isReply)
    }

    func testUnknownHost() {
        XCTAssertThrowsError(try Address.resolve("no-such-host.invalid"))
    }
}

@MainActor
final class ProbeTests: XCTestCase {
    func testStatusFromReplies() {
        let probe = Probe(input: "10.0.0.1")
        probe.apply(.reply(ms: 3, from: "10.0.0.1", ttl: 64, bytes: 40), downAfter: 2)
        XCTAssertEqual(probe.status, .up)
        probe.apply(.timedOut, downAfter: 2)
        XCTAssertEqual(probe.status, .indeterminate)
        probe.apply(.timedOut, downAfter: 2)
        XCTAssertEqual(probe.status, .down)
        probe.apply(.reply(ms: 5, from: "10.0.0.1", ttl: 64, bytes: 40), downAfter: 2)
        XCTAssertEqual(probe.status, .up)
        XCTAssertEqual(probe.stats.sent, 4)
        XCTAssertEqual(probe.stats.received, 2)
        XCTAssertEqual(probe.stats.lossPercent, 50)
        XCTAssertEqual(probe.stats.averageMs, 4)
        XCTAssertEqual(probe.stats.minMs, 3)
        XCTAssertEqual(probe.stats.maxMs, 5)
    }

    func testClosedPortIsDown() {
        let probe = Probe(input: "example.com:22")
        probe.apply(.refused(ms: 4), downAfter: 3)
        XCTAssertEqual(probe.status, .down)
    }

    func testLogIsCapped() {
        let probe = Probe(input: "10.0.0.1")
        for _ in 0..<(Probe.maxLines + 50) { probe.apply(.timedOut, downAfter: 2) }
        XCTAssertEqual(probe.lines.count, Probe.maxLines)
    }

    func testFormat() {
        XCTAssertEqual(Probe.format(0.4), "<1 ms")
        XCTAssertEqual(Probe.format(3.25), "3.2 ms")
        XCTAssertEqual(Probe.format(24.6), "25 ms")
    }
}

@MainActor
final class MonitorTests: XCTestCase {
    private func makeMonitor() -> Monitor {
        let defaults = UserDefaults(suiteName: "MacPingTests-\(UUID().uuidString)")!
        let monitor = Monitor(settings: AppSettings(defaults: defaults), libraryURL: nil)
        monitor.quiet = true
        return monitor
    }

    func testHistoryAndAlerts() {
        let monitor = makeMonitor()
        monitor.addDemoProbe(Probe(input: "10.0.0.1"))
        let probe = monitor.probes[0]
        probe.apply(.reply(ms: 1, from: "10.0.0.1", ttl: 64, bytes: 40), downAfter: 2)
        probe.apply(.timedOut, downAfter: 2)
        probe.apply(.timedOut, downAfter: 2)
        probe.apply(.reply(ms: 1, from: "10.0.0.1", ttl: 64, bytes: 40), downAfter: 2)
        XCTAssertEqual(monitor.history.map(\.kind), [.up, .down, .up])
        XCTAssertEqual(monitor.upCount, 1)
    }

    func testFavorites() {
        let monitor = makeMonitor()
        monitor.replaceAll(with: ["10.0.0.1", "example.com:443"], start: false)
        XCTAssertTrue(monitor.saveFavorite(named: "Office"))
        XCTAssertFalse(monitor.saveFavorite(named: "office"))
        XCTAssertTrue(monitor.saveFavorite(named: "office", replacing: true))
        XCTAssertEqual(monitor.favorites.count, 1)
        XCTAssertEqual(monitor.favorites[0].hosts, ["10.0.0.1", "example.com:443"])
        monitor.deleteFavorite(monitor.favorites[0])
        XCTAssertTrue(monitor.favorites.isEmpty)
    }

    func testAliases() {
        let monitor = makeMonitor()
        monitor.setAlias("Router", for: "192.168.1.1")
        XCTAssertEqual(monitor.alias(for: Target(parsing: "192.168.1.1")), "Router")
        XCTAssertEqual(monitor.alias(for: Target(parsing: "192.168.1.1:80")), "Router")
        monitor.setAlias("", for: "192.168.1.1")
        XCTAssertNil(monitor.alias(for: Target(parsing: "192.168.1.1")))
    }

    func testAddManyFillsEmptyTilesFirst() {
        let monitor = makeMonitor()
        monitor.replaceAll(with: [], start: false)
        monitor.add(start: false)
        XCTAssertEqual(monitor.probes.count, 2)
        monitor.addMany("10.0.0.1\n10.0.0.2\n10.0.0.3")
        XCTAssertEqual(monitor.probes.map(\.input), ["10.0.0.1", "10.0.0.2", "10.0.0.3"])
        monitor.stopAll()
    }

    func testCommandLineHostsWin() {
        let monitor = makeMonitor()
        monitor.restore(arguments: ["-NSDocumentRevisionsDebugMode", "YES", "10.0.0.9"])
        // "YES" parses as a host name too; only flags are skipped
        XCTAssertEqual(monitor.probes.map(\.input), ["YES", "10.0.0.9"])
        monitor.stopAll()
    }
}

final class LibraryTests: XCTestCase {
    func testRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("MacPing-\(UUID().uuidString)/Library.json")
        var library = Library()
        library.aliases = ["10.0.0.1": "Router"]
        library.favorites = [Favorite(name: "Office", hosts: ["10.0.0.1"], columns: 2)]
        library.lastHosts = ["10.0.0.1"]
        library.save(to: url)
        XCTAssertEqual(Library.load(from: url), library)
        XCTAssertEqual(Library.load(from: url.appendingPathExtension("missing")), Library())
    }

    func testExport() {
        let date = Date(timeIntervalSince1970: 0)
        let events = [StatusEvent(id: 0, date: date, host: "10.0.0.1", alias: "Router, main", kind: .down)]
        let csv = HistoryExport.text(events, delimiter: .comma).split(separator: "\n")
        XCTAssertEqual(csv[0], "Time,Host,Alias,Status")
        XCTAssertTrue(csv[1].hasSuffix(",10.0.0.1,\"Router, main\",Down"))
        let spaced = HistoryExport.text(events, delimiter: .space).split(separator: "\n")
        XCTAssertTrue(spaced[1].hasSuffix(" 10.0.0.1 Router,_main Down"))
    }
}

@MainActor
final class GridTests: XCTestCase {
    func testColumns() {
        XCTAssertEqual(ProbeGrid.columns(count: 6, setting: 3, size: CGSize(width: 900, height: 600)), 3)
        XCTAssertEqual(ProbeGrid.columns(count: 1, setting: 0, size: CGSize(width: 900, height: 600)), 1)
        // Never more columns than fit at the minimum width
        XCTAssertLessThanOrEqual(ProbeGrid.columns(count: 20, setting: 0, size: CGSize(width: 600, height: 600)), 2)
        let four = ProbeGrid.columns(count: 4, setting: 0, size: CGSize(width: 1000, height: 600))
        XCTAssertEqual(four, 2)
    }
}

/// Real pings over the internet. Skipped unless NETWORK is set:
/// `TEST_RUNNER_NETWORK=1 make test`
final class NetworkTests: XCTestCase {
    override func setUpWithError() throws {
        guard ProcessInfo.processInfo.environment["NETWORK"] != nil else { throw XCTSkip("Set NETWORK to run") }
    }

    func testPingsInternet() throws {
        let address = try Address.resolve("1.1.1.1")
        let socket = try ICMPSocket(family: address.family)
        XCTAssertTrue(socket.ping(address, sequence: 1, timeout: 3).isReply)
    }

    func testPortCheck() {
        XCTAssertTrue(TCPCheck.check(host: "github.com", port: 443, timeout: 5).isReply)
        // Nothing listens on port 1 here
        let closed = TCPCheck.check(host: "127.0.0.1", port: 1, timeout: 3)
        XCTAssertEqual(closed.isReply, false)
    }

    func testTraceroute() {
        let done = expectation(description: "finished")
        let hops = Hops()
        Traceroute().run(host: "1.1.1.1", maxHops: 20, timeout: 1) { event in
            switch event {
            case .hop(let hop): hops.add(hop)
            case .finished(let reached):
                XCTAssertTrue(reached)
                done.fulfill()
            case .failed(let message):
                XCTFail(message)
                done.fulfill()
            default: break
            }
        }
        wait(for: [done], timeout: 40)
        XCTAssertGreaterThan(hops.all.count, 1)
        XCTAssertTrue(hops.all.last?.reachedTarget ?? false)
        print("Hops:", hops.all.map { "\($0.number) \($0.address ?? "*") \($0.ms.map { Probe.format($0) } ?? "")" })
    }

    private final class Hops: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: [Hop] = []
        var all: [Hop] { lock.withLock { stored } }
        func add(_ hop: Hop) { lock.withLock { stored.append(hop) } }
    }
}
