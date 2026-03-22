//
//  EcowittClient.swift
//  EcowittLocal
//

import SwiftUI
import Combine
import os.log

/// Client that polls an Ecowitt gateway on the local network for live weather data.
///
/// Usage:
/// ```swift
/// let client = EcowittClient()
/// client.connect(host: "192.168.1.100")
/// // Observe client.liveData for updates
/// ```
@MainActor
public class EcowittClient: ObservableObject {

    // MARK: - Published State

    @Published public private(set) var liveData: EcowittLiveData?
    @Published public private(set) var connectionStatus: EcowittConnectionStatus = .disconnected
    @Published public private(set) var connectionError: Error?

    // MARK: - Private

    private var host: String = ""
    private var port: Int = 80
    private var pollingInterval: TimeInterval = 16
    private var pollingTimer: Timer?
    private var units: EcowittUnits = EcowittUnits()
    private var consecutiveFailures = 0
    private let maxConsecutiveFailures = 5

    private static let logger = Logger(
        subsystem: "com.ecowitt.local",
        category: "EcowittClient"
    )

    // MARK: - Public Interface

    public init() {}

    /// Connect to the Ecowitt gateway and begin polling.
    /// - Parameters:
    ///   - host: The gateway's IP address or hostname
    ///   - port: HTTP port (default 80)
    ///   - pollingInterval: Seconds between polls (default 16, matching Ecowitt's update rate)
    public func connect(host: String, port: Int = 80, pollingInterval: TimeInterval = 16) {
        disconnect()

        self.host = host
        self.port = port
        self.pollingInterval = pollingInterval
        self.consecutiveFailures = 0

        connectionStatus = .connecting
        connectionError = nil

        Self.logger.info("Connecting to Ecowitt gateway at \(host):\(port)")

        Task {
            // Fetch unit configuration first
            await fetchUnits()
            // Then fetch initial live data
            await fetchLiveData()
            // Start polling timer
            startPolling()
        }
    }

    /// Stop polling and disconnect.
    public func disconnect() {
        pollingTimer?.invalidate()
        pollingTimer = nil
        connectionStatus = .disconnected
        consecutiveFailures = 0
        Self.logger.info("Disconnected from Ecowitt gateway")
    }

    // MARK: - Polling

    private func startPolling() {
        pollingTimer?.invalidate()
        pollingTimer = Timer.scheduledTimer(withTimeInterval: pollingInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.fetchLiveData()
            }
        }
    }

    // MARK: - HTTP Requests

    private var baseURL: String {
        "http://\(host):\(port)"
    }

    /// Fetch the gateway's unit configuration (called once on connect)
    private func fetchUnits() async {
        guard let url = URL(string: "\(baseURL)/get_units_info") else { return }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                units = EcowittUnits.from(json: json)
                Self.logger.info("Gateway units: temp=\(self.units.temperature.rawValue) wind=\(self.units.wind.rawValue) pressure=\(self.units.pressure.rawValue) rain=\(self.units.rain.rawValue)")
            }
        } catch {
            Self.logger.warning("Failed to fetch units (using defaults): \(error.localizedDescription)")
            // Continue with default units — not a fatal error
        }
    }

    /// Fetch live data from the gateway
    private func fetchLiveData() async {
        guard let url = URL(string: "\(baseURL)/get_livedata_info") else {
            connectionError = EcowittError.invalidURL
            connectionStatus = .disconnected
            return
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                throw EcowittError.badResponse
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw EcowittError.invalidJSON
            }

            let parsed = EcowittJSONParser.parse(json, units: units)
            liveData = parsed
            consecutiveFailures = 0

            if connectionStatus != .connected {
                connectionStatus = .connected
                connectionError = nil
                Self.logger.info("Connected to Ecowitt gateway")
            }
        } catch {
            consecutiveFailures += 1
            connectionError = error
            Self.logger.error("Fetch failed (\(self.consecutiveFailures)/\(self.maxConsecutiveFailures)): \(error.localizedDescription)")

            if consecutiveFailures >= maxConsecutiveFailures {
                connectionStatus = .disconnected
                pollingTimer?.invalidate()
                pollingTimer = nil
                Self.logger.error("Too many failures, disconnecting")
            }
        }
    }
}

// MARK: - Errors

public enum EcowittError: LocalizedError, Sendable {
    case invalidURL
    case badResponse
    case invalidJSON

    public var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid gateway URL"
        case .badResponse: return "Gateway returned an error response"
        case .invalidJSON: return "Could not parse gateway response"
        }
    }
}
