//
//  EcowittUnitConverter.swift
//  EcowittLocal
//

import Foundation

// MARK: - Gateway Unit Configuration

/// Unit configuration reported by the gateway's /get_units_info endpoint
public struct EcowittUnits: Sendable {
    public enum TempUnit: Int, Sendable { case celsius = 0, fahrenheit = 1 }
    public enum PressureUnit: Int, Sendable { case hPa = 0, inHg = 1, mmHg = 2 }
    public enum WindUnit: Int, Sendable { case ms = 0, kmh = 1, mph = 2, knots = 3 }
    public enum RainUnit: Int, Sendable { case mm = 0, inches = 1 }
    public enum LightUnit: Int, Sendable { case lux = 0, wm2 = 1 }

    public var temperature: TempUnit
    public var pressure: PressureUnit
    public var wind: WindUnit
    public var rain: RainUnit
    public var light: LightUnit

    /// Default assumes imperial settings (common for US gateways)
    public init(
        temperature: TempUnit = .fahrenheit,
        pressure: PressureUnit = .inHg,
        wind: WindUnit = .mph,
        rain: RainUnit = .inches,
        light: LightUnit = .wm2
    ) {
        self.temperature = temperature
        self.pressure = pressure
        self.wind = wind
        self.rain = rain
        self.light = light
    }

    /// Parse from /get_units_info JSON response
    public static func from(json: [String: Any]) -> EcowittUnits {
        var units = EcowittUnits()
        if let t = json["temperature"] as? Int, let tu = TempUnit(rawValue: t) { units.temperature = tu }
        if let p = json["pressure"] as? Int, let pu = PressureUnit(rawValue: p) { units.pressure = pu }
        if let w = json["wind"] as? Int, let wu = WindUnit(rawValue: w) { units.wind = wu }
        if let r = json["rain"] as? Int, let ru = RainUnit(rawValue: r) { units.rain = ru }
        if let l = json["light"] as? Int, let lu = LightUnit(rawValue: l) { units.light = lu }
        return units
    }
}

// MARK: - Unit Conversion

/// Converts values from the gateway's configured units to imperial (matching Ambient Weather format)
enum EcowittUnitConverter {

    /// Strip unit suffix from value string (e.g., "72.5°F" → 72.5, "5.3 mph" → 5.3)
    static func parseNumericValue(from string: String) -> Double? {
        let cleaned = string
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespaces)

        // Extract leading numeric portion (including negative and decimal)
        var numStr = ""
        for char in cleaned {
            if char.isNumber || char == "." || char == "-" {
                numStr.append(char)
            } else if !numStr.isEmpty {
                break
            }
        }
        return Double(numStr)
    }

    /// Parse an integer value from a string, stripping any suffix
    static func parseIntValue(from string: String) -> Int? {
        guard let d = parseNumericValue(from: string) else { return nil }
        return Int(d)
    }

    // MARK: - Temperature conversions (to °F)

    static func toFahrenheit(_ value: Double, from unit: EcowittUnits.TempUnit) -> Double {
        switch unit {
        case .celsius: return value * 9.0 / 5.0 + 32.0
        case .fahrenheit: return value
        }
    }

    // MARK: - Pressure conversions (to inHg)

    static func toInHg(_ value: Double, from unit: EcowittUnits.PressureUnit) -> Double {
        switch unit {
        case .hPa: return value * 0.02953
        case .inHg: return value
        case .mmHg: return value * 0.03937
        }
    }

    // MARK: - Wind conversions (to mph)

    static func toMPH(_ value: Double, from unit: EcowittUnits.WindUnit) -> Double {
        switch unit {
        case .ms: return value * 2.23694
        case .kmh: return value * 0.621371
        case .mph: return value
        case .knots: return value * 1.15078
        }
    }

    // MARK: - Rain conversions (to inches)

    static func toInches(_ value: Double, from unit: EcowittUnits.RainUnit) -> Double {
        switch unit {
        case .mm: return value / 25.4
        case .inches: return value
        }
    }

    // MARK: - Solar radiation (lux to W/m²)

    static func toWm2(_ value: Double, from unit: EcowittUnits.LightUnit) -> Double {
        switch unit {
        case .lux: return value / 126.7  // approximate conversion
        case .wm2: return value
        }
    }
}
