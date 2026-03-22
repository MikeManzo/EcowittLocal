//
//  EcowittScanner.swift
//  EcowittLocal
//

import SwiftUI
import Network
import os.log

/// Represents a discovered Ecowitt gateway on the local network
public struct DiscoveredGateway: Identifiable, Sendable, Hashable {
    public let id: String  // IP address
    public let host: String
    public let port: Int
    public let model: String  // e.g., "GW1200B" or "Ecowitt Gateway"

    public init(host: String, port: Int = 80, model: String = "Ecowitt Gateway") {
        self.id = host
        self.host = host
        self.port = port
        self.model = model
    }
}

/// Scans the local network for Ecowitt gateways by probing each IP on the subnet
/// for the /get_livedata_info endpoint.
@MainActor
public class EcowittScanner: ObservableObject {

    @Published public private(set) var discoveredGateways: [DiscoveredGateway] = []
    @Published public private(set) var isScanning = false
    @Published public private(set) var scanProgress: Double = 0  // 0.0 to 1.0

    private var scanTask: Task<Void, Never>?

    private static let logger = Logger(
        subsystem: "com.ecowitt.local",
        category: "EcowittScanner"
    )

    public init() {}

    /// Start scanning the local network for Ecowitt gateways.
    /// Discovers the local subnet and probes each IP in the /24 range.
    public func startScan() {
        stopScan()
        discoveredGateways = []
        isScanning = true
        scanProgress = 0

        scanTask = Task {
            await performScan()
            isScanning = false
        }
    }

    /// Stop an in-progress scan
    public func stopScan() {
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
    }

    // MARK: - Private

    private func performScan() async {
        guard let subnet = Self.localSubnet() else {
            Self.logger.warning("Could not determine local subnet")
            return
        }

        Self.logger.info("Scanning subnet \(subnet).0/24")

        // Scan IPs 1-254 in batches to avoid overwhelming the network
        let batchSize = 20
        let totalIPs = 254

        for batchStart in stride(from: 1, through: totalIPs, by: batchSize) {
            guard !Task.isCancelled else { return }

            let batchEnd = min(batchStart + batchSize - 1, totalIPs)
            let ips = (batchStart...batchEnd).map { "\(subnet).\($0)" }

            await withTaskGroup(of: DiscoveredGateway?.self) { group in
                for ip in ips {
                    group.addTask {
                        await Self.probeGateway(at: ip)
                    }
                }

                for await result in group {
                    if let gateway = result {
                        discoveredGateways.append(gateway)
                        Self.logger.info("Found gateway at \(gateway.host): \(gateway.model)")
                    }
                }
            }

            scanProgress = Double(batchEnd) / Double(totalIPs)
        }

        scanProgress = 1.0
        Self.logger.info("Scan complete. Found \(self.discoveredGateways.count) gateway(s)")
    }

    /// Probe a single IP to see if it's an Ecowitt gateway
    private nonisolated static func probeGateway(at ip: String, port: Int = 80) async -> DiscoveredGateway? {
        guard let url = URL(string: "http://\(ip):\(port)/get_livedata_info") else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 2  // Short timeout for fast scanning

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else { return nil }

            // Verify it's valid Ecowitt JSON (should have common_list or wh25)
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  json["common_list"] != nil || json["wh25"] != nil else { return nil }

            // Try to determine the model from the response
            let model = detectModel(from: json)

            return DiscoveredGateway(host: ip, port: port, model: model)
        } catch {
            return nil
        }
    }

    /// Try to determine the gateway model from JSON response characteristics
    private nonisolated static func detectModel(from json: [String: Any]) -> String {
        // The presence of certain keys can hint at the model
        if json["piezoRain"] != nil {
            return "Ecowitt Gateway (Piezo)"  // GW2000 or similar with piezo rain
        }
        if json["co2"] != nil {
            return "Ecowitt Gateway (CO2)"
        }
        return "Ecowitt Gateway"
    }

    /// Determine the local /24 subnet prefix (e.g., "192.168.1")
    private static func localSubnet() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        var result: String?

        var ptr: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let addr = ptr {
            let flags = Int32(addr.pointee.ifa_flags)
            let isUp = (flags & IFF_UP) != 0
            let isLoopback = (flags & IFF_LOOPBACK) != 0

            if isUp && !isLoopback,
               addr.pointee.ifa_addr.pointee.sa_family == UInt8(AF_INET) {
                // Get the interface name
                let name = String(cString: addr.pointee.ifa_name)

                // Prefer en0 (Wi-Fi) or en* interfaces
                if name.hasPrefix("en") {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(addr.pointee.ifa_addr, socklen_t(addr.pointee.ifa_addr.pointee.sa_len),
                                   &hostname, socklen_t(hostname.count),
                                   nil, 0, NI_NUMERICHOST) == 0 {
                        let ip: String
                        if let nullIndex = hostname.firstIndex(of: 0) {
                            ip = String(decoding: hostname[..<nullIndex].map { UInt8(bitPattern: $0) }, as: UTF8.self)
                        } else {
                            ip = String(decoding: hostname.map { UInt8(bitPattern: $0) }, as: UTF8.self)
                        }
                        // Extract the /24 subnet prefix
                        let components = ip.split(separator: ".")
                        if components.count == 4 {
                            result = "\(components[0]).\(components[1]).\(components[2])"
                            if name == "en0" { break }  // Prefer en0
                        }
                    }
                }
            }
            ptr = addr.pointee.ifa_next
        }

        return result
    }
}
