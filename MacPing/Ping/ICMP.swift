import Darwin
import Foundation

/// A resolved address, IPv4 or IPv6, ready for `sendto`
struct Address: Sendable, Equatable {
    let storage: sockaddr_storage
    let length: socklen_t

    var family: Int32 { Int32(storage.ss_family) }

    /// e.g. "1.1.1.1" or "2606:4700::1111"
    var text: String {
        var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        var copy = storage
        let result = withUnsafePointer(to: &copy) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getnameinfo($0, length, &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST)
            }
        }
        return result == 0 ? Self.string(buffer) : "?"
    }

    /// The name the address points back to, if it has one. Blocks while it asks DNS.
    func reverseName() -> String? {
        var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        var copy = storage
        let result = withUnsafePointer(to: &copy) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getnameinfo($0, length, &buffer, socklen_t(buffer.count), nil, 0, NI_NAMEREQD)
            }
        }
        return result == 0 ? Self.string(buffer) : nil
    }

    static func == (a: Address, b: Address) -> Bool { a.text == b.text }

    /// A C string from getnameinfo
    private static func string(_ buffer: [CChar]) -> String {
        String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    init(storage: sockaddr_storage, length: socklen_t) {
        self.storage = storage
        self.length = length
    }

    /// Looks a host up (blocking). IPv4 first when it has both, like ping.
    static func resolve(_ host: String) throws(PingError) -> Address {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_DGRAM
        var list: UnsafeMutablePointer<addrinfo>?
        let status = getaddrinfo(host, nil, &hints, &list)
        guard status == 0, let first = list else { throw .unknownHost }
        defer { freeaddrinfo(list) }
        var chosen = first
        var node: UnsafeMutablePointer<addrinfo>? = first
        while let current = node {
            if current.pointee.ai_family == AF_INET { chosen = current; break }
            node = current.pointee.ai_next
        }
        var storage = sockaddr_storage()
        memcpy(&storage, chosen.pointee.ai_addr, Int(chosen.pointee.ai_addrlen))
        return Address(storage: storage, length: chosen.pointee.ai_addrlen)
    }
}

enum PingError: Error, Equatable, Sendable {
    case unknownHost
    case socket(Int32)

    var message: String {
        switch self {
        case .unknownHost: return "Couldn't find that host"
        case .socket(let code): return String(cString: strerror(code))
        }
    }
}

/// What came back for one probe
enum PingReply: Equatable, Sendable {
    /// An echo reply (or an open port), in milliseconds
    case reply(ms: Double, from: String, ttl: Int?, bytes: Int)
    /// A router on the way gave up on it: the hop, in traceroute terms
    case ttlExpired(ms: Double, from: String)
    /// A router said the host can't be reached
    case unreachable(from: String, code: Int)
    /// A TCP port that answered, but refused the connection
    case refused(ms: Double)
    case timedOut
    /// Couldn't send at all, e.g. no network
    case failed(String)

    var isReply: Bool { if case .reply = self { return true } else { return false } }
}

/// ICMP echo over an unprivileged datagram socket: macOS lets any app ping
/// this way, without root or a helper. One per monitor, used from one thread.
final class ICMPSocket {
    private let fd: Int32
    private let family: Int32
    /// Echo requests carry this, so replies meant for other sockets (every
    /// ICMP socket sees every reply) are ignored
    let identifier: UInt16

    init(family: Int32, identifier: UInt16 = ICMPSocket.nextIdentifier()) throws(PingError) {
        self.family = family
        self.identifier = identifier
        let proto = family == AF_INET6 ? IPPROTO_ICMPV6 : IPPROTO_ICMP
        fd = socket(family, SOCK_DGRAM, proto)
        guard fd >= 0 else { throw .socket(errno) }
        // Room for everyone else's replies between pings, with many monitors
        var size: Int32 = 256 * 1024
        setsockopt(fd, SOL_SOCKET, SO_RCVBUF, &size, socklen_t(MemoryLayout<Int32>.size))
    }

    private static let identifierLock = NSLock()
    nonisolated(unsafe) private static var lastIdentifier = UInt16.random(in: 1...UInt16.max)

    /// A different identifier for each socket, so no two monitors take each
    /// other's replies. Starts at random to keep clear of other apps.
    static func nextIdentifier() -> UInt16 {
        identifierLock.withLock {
            lastIdentifier = lastIdentifier == .max ? 1 : lastIdentifier + 1
            return lastIdentifier
        }
    }

    deinit { close(fd) }

    /// Sends one echo request and waits for its answer. Blocks for up to `timeout`.
    func ping(_ address: Address, sequence: UInt16, timeout: TimeInterval,
              ttl: Int = 64, payloadSize: Int = 32) -> PingReply {
        var hops = Int32(ttl)
        if family == AF_INET6 {
            setsockopt(fd, IPPROTO_IPV6, IPV6_UNICAST_HOPS, &hops, socklen_t(MemoryLayout<Int32>.size))
        } else {
            setsockopt(fd, IPPROTO_IP, IP_TTL, &hops, socklen_t(MemoryLayout<Int32>.size))
        }

        // Throw away what came in since the last ping: other monitors' replies
        var buffer = [UInt8](repeating: 0, count: 2048)
        while recv(fd, &buffer, buffer.count, MSG_DONTWAIT) > 0 {}

        let packet = Self.echoRequest(v6: family == AF_INET6, identifier: identifier,
                                      sequence: sequence, payloadSize: payloadSize)
        let start = DispatchTime.now()
        var target = address.storage
        let sent = packet.withUnsafeBytes { bytes in
            withUnsafePointer(to: &target) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(fd, bytes.baseAddress, bytes.count, 0, $0, address.length)
                }
            }
        }
        guard sent == packet.count else { return .failed(String(cString: strerror(errno))) }

        let deadline = start.uptimeNanoseconds + UInt64(timeout * 1_000_000_000)
        let destination = address.text
        while true {
            let now = DispatchTime.now().uptimeNanoseconds
            guard now < deadline else { return .timedOut }
            var wait = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let ready = poll(&wait, 1, Int32(max(1, (deadline - now) / 1_000_000)))
            if ready < 0 {
                if errno == EINTR { continue }
                return .failed(String(cString: strerror(errno)))
            }
            guard ready > 0 else { return .timedOut }

            var from = sockaddr_storage()
            var fromLength = socklen_t(MemoryLayout<sockaddr_storage>.size)
            let count = withUnsafeMutablePointer(to: &from) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    recvfrom(fd, &buffer, buffer.count, 0, $0, &fromLength)
                }
            }
            guard count > 0 else {
                if count < 0, errno != EINTR, errno != EAGAIN { return .failed(String(cString: strerror(errno))) }
                continue
            }
            let ms = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
            let sender = Address(storage: from, length: fromLength).text
            let message = Array(buffer[0..<count])
            if let reply = Self.match(message, v6: family == AF_INET6, identifier: identifier,
                                      sequence: sequence, ms: ms, from: sender, destination: destination) {
                return reply
            }
        }
    }

    // MARK: - Packets

    static func echoRequest(v6: Bool, identifier: UInt16, sequence: UInt16, payloadSize: Int) -> [UInt8] {
        var packet: [UInt8] = [v6 ? 128 : 8, 0, 0, 0,
                               UInt8(identifier >> 8), UInt8(identifier & 0xff),
                               UInt8(sequence >> 8), UInt8(sequence & 0xff)]
        // "abcdefg…", as ping fills it
        packet += (0..<max(0, payloadSize)).map { UInt8(0x61 + $0 % 23) }
        // The kernel fills in ICMPv6 checksums itself
        if !v6 {
            let sum = checksum(packet)
            packet[2] = UInt8(sum >> 8)
            packet[3] = UInt8(sum & 0xff)
        }
        return packet
    }

    static func checksum(_ bytes: [UInt8]) -> UInt16 {
        var sum: UInt32 = 0
        var index = 0
        while index + 1 < bytes.count {
            sum += UInt32(bytes[index]) << 8 | UInt32(bytes[index + 1])
            index += 2
        }
        if index < bytes.count { sum += UInt32(bytes[index]) << 8 }
        while sum >> 16 != 0 { sum = (sum & 0xffff) + (sum >> 16) }
        return ~UInt16(sum)
    }

    /// Reads a received message, if it answers our request. An IPv4 datagram
    /// socket hands over the IP header too; an IPv6 one starts at the ICMPv6
    /// header. Errors from routers quote the start of our request, which
    /// is how they're matched.
    static func match(_ message: [UInt8], v6: Bool, identifier: UInt16, sequence: UInt16,
                      ms: Double, from: String, destination: String? = nil) -> PingReply? {
        var icmp = message[...]
        var ttl: Int?
        if !v6 {
            guard let first = message.first, first >> 4 == 4 else { return nil }
            let headerLength = Int(first & 0x0f) * 4
            guard message.count >= headerLength + 8 else { return nil }
            ttl = Int(message[8])
            icmp = message[headerLength...]
        }
        guard icmp.count >= 8 else { return nil }
        let type = icmp[icmp.startIndex]
        let code = Int(icmp[icmp.startIndex + 1])

        func ours(_ header: ArraySlice<UInt8>) -> Bool {
            guard header.count >= 8 else { return false }
            let start = header.startIndex
            return UInt16(header[start + 4]) << 8 | UInt16(header[start + 5]) == identifier
                && UInt16(header[start + 6]) << 8 | UInt16(header[start + 7]) == sequence
        }

        let echoReply: UInt8 = v6 ? 129 : 0
        if type == echoReply {
            // Only the host pinged can answer it: Terminal's ping could share the identifier
            guard ours(icmp), destination == nil || destination == from else { return nil }
            return .reply(ms: ms, from: from, ttl: ttl, bytes: icmp.count)
        }

        // Time exceeded or destination unreachable: they quote our request
        let timeExceeded: UInt8 = v6 ? 3 : 11
        let unreachable: UInt8 = v6 ? 1 : 3
        guard type == timeExceeded || type == unreachable else { return nil }
        let quoted = icmp.dropFirst(8)
        let original: ArraySlice<UInt8>
        if v6 {
            original = quoted.dropFirst(40)
        } else {
            guard let first = quoted.first else { return nil }
            original = quoted.dropFirst(Int(first & 0x0f) * 4)
        }
        guard ours(original) else { return nil }
        return type == timeExceeded ? .ttlExpired(ms: ms, from: from) : .unreachable(from: from, code: code)
    }
}
