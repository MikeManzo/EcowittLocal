//
//  EcowittJSONParser.swift
//  EcowittLocal
//

import Foundation

/// Parses the JSON response from the Ecowitt gateway's /get_livedata_info endpoint.
///
/// The response contains multiple arrays:
/// - `common_list`: outdoor sensors with hex IDs (e.g., "0x02" = outdoor temp)
/// - `wh25`: indoor temp/humidity/pressure from the built-in WH25 sensor
/// - `rain`: precipitation data with hex IDs
/// - `ch_aisle`: multi-channel temperature/humidity sensors
/// - `ch_soil`: soil moisture sensors
/// - `ch_leak`: leak detection sensors
/// - `lightning`: lightning detection data
/// - `co2`: CO2/PM2.5 sensor data
///
/// Values often embed unit suffixes (e.g., "72.5°F", "5.3 mph") that must be stripped.
enum EcowittJSONParser {

    // MARK: - Hex ID Mappings

    /// Common list sensor IDs (from Ecowitt HTTP API protocol)
    private enum CommonID: String {
        case indoorTemp     = "0x01"
        case outdoorTemp    = "0x02"
        case dewPoint       = "0x03"
        case windChill      = "0x04"
        case heatIndex      = "0x05"
        case indoorHumidity = "0x06"
        case outdoorHumidity = "0x07"
        case pressureAbs    = "0x08"
        case pressureRel    = "0x09"
        case windDirection  = "0x0A"
        case windSpeed      = "0x0B"
        case gustSpeed      = "0x0C"
        case solarRadiation = "0x15"
        case uvRaw          = "0x16"
        case uvIndex        = "0x17"
        case maxDailyGust   = "0x19"
    }

    /// Rain section sensor IDs
    private enum RainID: String {
        case event   = "0x0D"
        case rate    = "0x0E"
        case daily   = "0x10"
        case weekly  = "0x11"
        case monthly = "0x12"
        case yearly  = "0x13"
    }

    // MARK: - Main Parse Entry Point

    static func parse(_ json: [String: Any], units: EcowittUnits) -> EcowittLiveData {
        var data = EcowittLiveData()

        parseCommonList(json["common_list"], into: &data, units: units)
        parseWH25(json["wh25"], into: &data, units: units)
        parseRain(json["rain"], into: &data, units: units)
        parsePiezoRain(json["piezoRain"], into: &data, units: units)
        parseChannels(json["ch_aisle"], into: &data, units: units)
        parseSoil(json["ch_soil"], into: &data, units: units)
        parseLeak(json["ch_leak"], into: &data)
        parseLightning(json["lightning"], into: &data, units: units)
        parseCO2(json["co2"], into: &data)

        // Calculate feels-like if not provided
        if data.feelsLike == nil, let temp = data.outdoorTemp, let humidity = data.outdoorHumidity {
            data.feelsLike = calculateFeelsLike(tempF: temp, humidity: Double(humidity), windMPH: data.windSpeed ?? 0)
        }

        return data
    }

    // MARK: - Section Parsers

    private static func parseCommonList(_ raw: Any?, into data: inout EcowittLiveData, units: EcowittUnits) {
        guard let items = raw as? [[String: Any]] else { return }

        for item in items {
            guard let id = item["id"] as? String,
                  let val = item["val"] as? String else { continue }

            let battery = item["battery"] as? String

            switch CommonID(rawValue: id) {
            case .outdoorTemp:
                if let v = EcowittUnitConverter.parseNumericValue(from: val) {
                    data.outdoorTemp = EcowittUnitConverter.toFahrenheit(v, from: units.temperature)
                }
            case .outdoorHumidity:
                data.outdoorHumidity = EcowittUnitConverter.parseIntValue(from: val)
            case .dewPoint:
                if let v = EcowittUnitConverter.parseNumericValue(from: val) {
                    data.dewPoint = EcowittUnitConverter.toFahrenheit(v, from: units.temperature)
                }
            case .windChill:
                if let v = EcowittUnitConverter.parseNumericValue(from: val) {
                    data.windChill = EcowittUnitConverter.toFahrenheit(v, from: units.temperature)
                }
            case .heatIndex:
                if let v = EcowittUnitConverter.parseNumericValue(from: val) {
                    data.heatIndex = EcowittUnitConverter.toFahrenheit(v, from: units.temperature)
                }
            case .windDirection:
                data.windDir = EcowittUnitConverter.parseIntValue(from: val)
            case .windSpeed:
                if let v = EcowittUnitConverter.parseNumericValue(from: val) {
                    data.windSpeed = EcowittUnitConverter.toMPH(v, from: units.wind)
                }
            case .gustSpeed:
                if let v = EcowittUnitConverter.parseNumericValue(from: val) {
                    data.windGust = EcowittUnitConverter.toMPH(v, from: units.wind)
                }
            case .maxDailyGust:
                if let v = EcowittUnitConverter.parseNumericValue(from: val) {
                    data.maxDailyGust = EcowittUnitConverter.toMPH(v, from: units.wind)
                }
            case .solarRadiation:
                if let v = EcowittUnitConverter.parseNumericValue(from: val) {
                    data.solarRadiation = EcowittUnitConverter.toWm2(v, from: units.light)
                }
            case .uvIndex:
                data.uvIndex = EcowittUnitConverter.parseIntValue(from: val)
            case .indoorTemp:
                if let v = EcowittUnitConverter.parseNumericValue(from: val) {
                    data.indoorTemp = EcowittUnitConverter.toFahrenheit(v, from: units.temperature)
                }
            case .indoorHumidity:
                data.indoorHumidity = EcowittUnitConverter.parseIntValue(from: val)
            case .pressureAbs:
                if let v = EcowittUnitConverter.parseNumericValue(from: val) {
                    data.pressureAbsolute = EcowittUnitConverter.toInHg(v, from: units.pressure)
                }
            case .pressureRel:
                if let v = EcowittUnitConverter.parseNumericValue(from: val) {
                    data.pressureRelative = EcowittUnitConverter.toInHg(v, from: units.pressure)
                }
            case .uvRaw, nil:
                break
            }

            // Track battery from common_list items
            if let battery, let batteryId = CommonID(rawValue: id) {
                if let bv = EcowittUnitConverter.parseIntValue(from: battery) {
                    data.batteries["common_\(batteryId)"] = bv
                }
            }
        }
    }

    private static func parseWH25(_ raw: Any?, into data: inout EcowittLiveData, units: EcowittUnits) {
        guard let items = raw as? [[String: Any]], let wh25 = items.first else { return }

        if let val = wh25["intemp"] as? String, let v = EcowittUnitConverter.parseNumericValue(from: val) {
            data.indoorTemp = EcowittUnitConverter.toFahrenheit(v, from: units.temperature)
        }
        if let val = wh25["inhumi"] as? String {
            data.indoorHumidity = EcowittUnitConverter.parseIntValue(from: val)
        }
        if let val = wh25["abs"] as? String, let v = EcowittUnitConverter.parseNumericValue(from: val) {
            data.pressureAbsolute = EcowittUnitConverter.toInHg(v, from: units.pressure)
        }
        if let val = wh25["rel"] as? String, let v = EcowittUnitConverter.parseNumericValue(from: val) {
            data.pressureRelative = EcowittUnitConverter.toInHg(v, from: units.pressure)
        }
    }

    private static func parseRain(_ raw: Any?, into data: inout EcowittLiveData, units: EcowittUnits) {
        guard let items = raw as? [[String: Any]] else { return }

        for item in items {
            guard let id = item["id"] as? String,
                  let val = item["val"] as? String,
                  let v = EcowittUnitConverter.parseNumericValue(from: val) else { continue }

            let converted = EcowittUnitConverter.toInches(v, from: units.rain)

            switch RainID(rawValue: id) {
            case .event:   data.rainEvent = converted
            case .rate:    data.rainRate = converted
            case .daily:   data.dailyRain = converted
            case .weekly:  data.weeklyRain = converted
            case .monthly: data.monthlyRain = converted
            case .yearly:  data.yearlyRain = converted
            case nil: break
            }

            if let battery = item["battery"] as? String,
               let bv = EcowittUnitConverter.parseIntValue(from: battery) {
                data.batteries["rain"] = bv
            }
        }
    }

    private static func parsePiezoRain(_ raw: Any?, into data: inout EcowittLiveData, units: EcowittUnits) {
        guard let items = raw as? [[String: Any]] else { return }

        // Piezo rain uses the same IDs; only fill in if traditional rain sensor didn't provide values
        for item in items {
            guard let id = item["id"] as? String,
                  let val = item["val"] as? String,
                  let v = EcowittUnitConverter.parseNumericValue(from: val) else { continue }

            let converted = EcowittUnitConverter.toInches(v, from: units.rain)

            switch RainID(rawValue: id) {
            case .event:   if data.rainEvent == nil { data.rainEvent = converted }
            case .rate:    if data.rainRate == nil { data.rainRate = converted }
            case .daily:   if data.dailyRain == nil { data.dailyRain = converted }
            case .weekly:  if data.weeklyRain == nil { data.weeklyRain = converted }
            case .monthly: if data.monthlyRain == nil { data.monthlyRain = converted }
            case .yearly:  if data.yearlyRain == nil { data.yearlyRain = converted }
            case nil: break
            }
        }
    }

    private static func parseChannels(_ raw: Any?, into data: inout EcowittLiveData, units: EcowittUnits) {
        guard let items = raw as? [[String: Any]] else { return }

        for item in items {
            guard let channel = item["channel"] as? String,
                  let ch = Int(channel) else { continue }

            if let val = item["temp"] as? String, let v = EcowittUnitConverter.parseNumericValue(from: val) {
                data.channelTemp[ch] = EcowittUnitConverter.toFahrenheit(v, from: units.temperature)
            }
            if let val = item["humidity"] as? String {
                data.channelHumidity[ch] = EcowittUnitConverter.parseIntValue(from: val)
            }
            if let battery = item["battery"] as? String,
               let bv = EcowittUnitConverter.parseIntValue(from: battery) {
                data.batteries["ch\(ch)"] = bv
            }
        }
    }

    private static func parseSoil(_ raw: Any?, into data: inout EcowittLiveData, units: EcowittUnits) {
        guard let items = raw as? [[String: Any]] else { return }

        for item in items {
            guard let channel = item["channel"] as? String,
                  let ch = Int(channel) else { continue }

            if let val = item["humidity"] as? String {
                data.soilMoisture[ch] = EcowittUnitConverter.parseIntValue(from: val)
            }
            if let val = item["temp"] as? String, let v = EcowittUnitConverter.parseNumericValue(from: val) {
                data.soilTemp[ch] = EcowittUnitConverter.toFahrenheit(v, from: units.temperature)
            }
            if let battery = item["battery"] as? String,
               let bv = EcowittUnitConverter.parseIntValue(from: battery) {
                data.batteries["soil\(ch)"] = bv
            }
        }
    }

    private static func parseLeak(_ raw: Any?, into data: inout EcowittLiveData) {
        guard let items = raw as? [[String: Any]] else { return }

        for item in items {
            guard let channel = item["channel"] as? String,
                  let ch = Int(channel),
                  let val = item["status"] as? String else { continue }

            data.leakSensors[ch] = EcowittUnitConverter.parseIntValue(from: val) ?? 0

            if let battery = item["battery"] as? String,
               let bv = EcowittUnitConverter.parseIntValue(from: battery) {
                data.batteries["leak\(ch)"] = bv
            }
        }
    }

    private static func parseLightning(_ raw: Any?, into data: inout EcowittLiveData, units: EcowittUnits) {
        guard let items = raw as? [[String: Any]], let lightning = items.first else { return }

        if let val = lightning["distance"] as? String, let v = EcowittUnitConverter.parseNumericValue(from: val) {
            // Distance comes in km or miles depending on unit config; convert to miles
            // Ecowitt reports lightning distance in km when metric
            let miles: Double
            if units.wind == .kmh || units.wind == .ms {
                miles = v * 0.621371  // km to miles
            } else {
                miles = v
            }
            data.lightningDistance = miles
        }
        if let val = lightning["timestamp"] as? String, let ts = Int64(val) {
            data.lightningTime = ts
        }
        if let val = lightning["count"] as? String {
            data.lightningDayCount = EcowittUnitConverter.parseIntValue(from: val)
        }
        if let battery = lightning["battery"] as? String,
           let bv = EcowittUnitConverter.parseIntValue(from: battery) {
            data.batteries["lightning"] = bv
        }
    }

    private static func parseCO2(_ raw: Any?, into data: inout EcowittLiveData) {
        guard let items = raw as? [[String: Any]], let co2Data = items.first else { return }

        if let val = co2Data["CO2"] as? String {
            data.co2 = EcowittUnitConverter.parseIntValue(from: val)
        }
        if let val = co2Data["PM25"] as? String {
            data.pm25 = EcowittUnitConverter.parseNumericValue(from: val)
        }
        if let battery = co2Data["battery"] as? String,
           let bv = EcowittUnitConverter.parseIntValue(from: battery) {
            data.batteries["co2"] = bv
        }
    }

    // MARK: - Derived Calculations

    /// Calculate feels-like temperature using heat index or wind chill as appropriate
    private static func calculateFeelsLike(tempF: Double, humidity: Double, windMPH: Double) -> Double {
        if tempF >= 80 {
            // Heat index formula (NWS)
            let hi = -42.379 + 2.04901523 * tempF + 10.14333127 * humidity
                - 0.22475541 * tempF * humidity - 0.00683783 * tempF * tempF
                - 0.05481717 * humidity * humidity + 0.00122874 * tempF * tempF * humidity
                + 0.00085282 * tempF * humidity * humidity
                - 0.00000199 * tempF * tempF * humidity * humidity
            return hi
        } else if tempF <= 50 && windMPH > 3 {
            // Wind chill formula (NWS)
            return 35.74 + 0.6215 * tempF - 35.75 * pow(windMPH, 0.16) + 0.4275 * tempF * pow(windMPH, 0.16)
        }
        return tempF
    }
}
