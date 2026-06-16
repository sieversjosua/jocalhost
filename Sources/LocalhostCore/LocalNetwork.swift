import Darwin
import Foundation

public enum LocalNetwork {
    public static func localURL(port: Int) -> String {
        "http://localhost:\(port)"
    }

    public static func networkURL(port: Int) -> String? {
        preferredIPv4Address().map { "http://\($0):\(port)" }
    }

    public static func preferredIPv4Address() -> String? {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let firstInterface = interfaces else {
            return nil
        }

        defer {
            freeifaddrs(interfaces)
        }

        var candidates: [NetworkAddressCandidate] = []
        var current: UnsafeMutablePointer<ifaddrs>? = firstInterface

        while let interface = current {
            defer {
                current = interface.pointee.ifa_next
            }

            guard let address = interface.pointee.ifa_addr,
                  address.pointee.sa_family == sa_family_t(AF_INET) else {
                continue
            }

            let flags = Int32(interface.pointee.ifa_flags)
            guard flags & IFF_UP != 0,
                  flags & IFF_RUNNING != 0,
                  flags & IFF_LOOPBACK == 0 else {
                continue
            }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                address,
                socklen_t(address.pointee.sa_len),
                &host,
                socklen_t(host.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            guard result == 0 else {
                continue
            }

            let name = String(cString: interface.pointee.ifa_name)
            let ipAddress = String(decoding: host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            guard isUsableIPv4Address(ipAddress) else {
                continue
            }

            candidates.append(
                NetworkAddressCandidate(
                    interfaceName: name,
                    address: ipAddress,
                    preference: preferenceScore(for: name)
                )
            )
        }

        return candidates
            .sorted { lhs, rhs in
                if lhs.preference != rhs.preference {
                    return lhs.preference < rhs.preference
                }
                return lhs.interfaceName < rhs.interfaceName
            }
            .first?
            .address
    }

    private static func preferenceScore(for interfaceName: String) -> Int {
        if interfaceName == "en0" {
            return 0
        }
        if interfaceName == "en1" {
            return 1
        }
        if interfaceName.hasPrefix("en") {
            return 2
        }
        if interfaceName.hasPrefix("bridge") {
            return 20
        }
        if interfaceName.hasPrefix("utun") {
            return 30
        }
        return 10
    }

    private static func isUsableIPv4Address(_ address: String) -> Bool {
        address.hasPrefix("127.") == false &&
            address.hasPrefix("169.254.") == false &&
            address != "0.0.0.0"
    }
}

private struct NetworkAddressCandidate {
    var interfaceName: String
    var address: String
    var preference: Int
}
