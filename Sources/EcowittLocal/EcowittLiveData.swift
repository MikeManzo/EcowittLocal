//
//  EcowittLiveData.swift
//  EcowittLocal
//

import Foundation

/// Typed model representing live weather data from an Ecowitt gateway.
/// All values are normalized to imperial units (°F, mph, inHg, in) to match
/// the Ambient Weather data format used downstream.
public struct EcowittLiveData: Sendable {
    public let timestamp: Date

    // MARK: - Outdoor

    public var outdoorTemp: Double?         // °F
    public var outdoorHumidity: Int?        // %
    public var dewPoint: Double?            // °F
    public var windChill: Double?           // °F
    public var heatIndex: Double?           // °F
    public var feelsLike: Double?           // °F

    // MARK: - Indoor (WH25 sensor)

    public var indoorTemp: Double?          // °F
    public var indoorHumidity: Int?         // %
    public var pressureAbsolute: Double?    // inHg
    public var pressureRelative: Double?    // inHg

    // MARK: - Wind

    public var windSpeed: Double?           // mph
    public var windGust: Double?            // mph
    public var windDir: Int?                // degrees 0-360
    public var maxDailyGust: Double?        // mph

    // MARK: - Rain

    public var rainEvent: Double?           // in
    public var rainRate: Double?            // in/hr
    public var dailyRain: Double?           // in
    public var weeklyRain: Double?          // in
    public var monthlyRain: Double?         // in
    public var yearlyRain: Double?          // in

    // MARK: - Solar & UV

    public var solarRadiation: Double?      // W/m²
    public var uvIndex: Int?                // 0-15+

    // MARK: - Soil sensors (keyed by channel 1-8)

    public var soilMoisture: [Int: Int]     // channel: % (0-100)
    public var soilTemp: [Int: Double]      // channel: °F

    // MARK: - Lightning

    public var lightningDistance: Double?    // miles
    public var lightningTime: Int64?        // unix timestamp
    public var lightningDayCount: Int?      // strikes today

    // MARK: - Air Quality

    public var co2: Int?                    // ppm
    public var pm25: Double?                // µg/m³

    // MARK: - Leak sensors (keyed by channel 1-4)

    public var leakSensors: [Int: Int]      // channel: 0=dry, 1=leak

    // MARK: - Battery statuses

    public var batteries: [String: Int]     // sensorKey: value

    // MARK: - Multi-channel temperature/humidity

    public var channelTemp: [Int: Double]   // channel: °F
    public var channelHumidity: [Int: Int]  // channel: %

    public init(timestamp: Date = Date()) {
        self.timestamp = timestamp
        self.soilMoisture = [:]
        self.soilTemp = [:]
        self.leakSensors = [:]
        self.batteries = [:]
        self.channelTemp = [:]
        self.channelHumidity = [:]
    }
}
