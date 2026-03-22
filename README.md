# EcowittLocal

A Swift package for communicating with [Ecowitt](https://www.ecowitt.com) weather station gateways over your local network. No cloud account required — all data is fetched directly from the device via its local HTTP API.

## Features

- **Local network discovery** — automatically scan your subnet to find Ecowitt gateways
- **Live data polling** — connect to a gateway and receive continuous weather updates (default 16-second interval matching the device's update rate)
- **Comprehensive sensor support** — outdoor/indoor temp & humidity, wind, rain, solar radiation, UV, soil moisture, lightning, CO2, PM2.5, leak detection, and multi-channel sensors
- **Automatic unit conversion** — reads the gateway's configured units and normalizes all values to imperial (°F, mph, inHg, inches)
- **Battery monitoring** — tracks battery status for all connected sensors
- **SwiftUI ready** — `ObservableObject` classes with `@Published` properties for seamless SwiftUI integration
- **Swift 6 concurrency** — fully `Sendable` data types and `@MainActor` isolation

## Requirements

- macOS 15+
- Swift 6.1+

## Installation

Add EcowittLocal to your project using Swift Package Manager:

```swift
dependencies: [
    .package(url: "https://github.com/YOUR_USERNAME/EcowittLocal.git", from: "1.0.0")
]
```

Or in Xcode: **File → Add Package Dependencies** and enter the repository URL.

## Usage

### Connecting to a Known Gateway

```swift
import EcowittLocal

let client = EcowittClient()

// Connect by IP address
client.connect(host: "192.168.1.100")

// Observe live data updates in SwiftUI
struct WeatherView: View {
    @StateObject private var client = EcowittClient()

    var body: some View {
        VStack {
            if let data = client.liveData {
                Text("Temperature: \(data.outdoorTemp ?? 0, specifier: "%.1f")°F")
                Text("Humidity: \(data.outdoorHumidity ?? 0)%")
                Text("Wind: \(data.windSpeed ?? 0, specifier: "%.1f") mph")
            } else {
                Text("Connecting...")
            }
        }
        .onAppear {
            client.connect(host: "192.168.1.100")
        }
    }
}
```

### Discovering Gateways on the Network

```swift
let scanner = EcowittScanner()

// Start scanning the local /24 subnet
scanner.startScan()

// Observe results
for gateway in scanner.discoveredGateways {
    print("\(gateway.model) at \(gateway.host):\(gateway.port)")
}
```

### Connection Options

```swift
client.connect(
    host: "192.168.1.100",
    port: 80,                // HTTP port (default: 80)
    pollingInterval: 16      // seconds between updates (default: 16)
)

// Monitor connection state
switch client.connectionStatus {
case .connected:    print("Receiving data")
case .connecting:   print("Connecting...")
case .disconnected: print("Offline")
}

// Disconnect when done
client.disconnect()
```

## Supported Sensor Data

| Category | Properties |
|----------|-----------|
| **Outdoor** | Temperature, humidity, dew point, wind chill, heat index, feels-like |
| **Indoor (WH25)** | Temperature, humidity, barometric pressure (absolute & relative) |
| **Wind** | Speed, gust, direction, max daily gust |
| **Rain** | Rate, event total, daily, weekly, monthly, yearly (traditional & piezo sensors) |
| **Solar & UV** | Solar radiation (W/m²), UV index |
| **Soil** | Moisture and temperature (up to 8 channels) |
| **Lightning** | Strike distance, last strike time, daily count |
| **Air Quality** | CO2 (ppm), PM2.5 (µg/m³) |
| **Leak Detection** | Dry/leak status (up to 4 channels) |
| **Multi-channel** | Additional temperature & humidity sensors (up to 8 channels) |
| **Battery** | Status for all connected sensors |

## How It Works

1. The client fetches the gateway's unit configuration from `/get_units_info`
2. It then polls `/get_livedata_info` at the configured interval
3. The JSON response is parsed and all values are converted to imperial units
4. If 5 consecutive requests fail, the client automatically disconnects

## Compatible Hardware

This package works with Ecowitt gateway devices that expose a local HTTP API, including:

- GW1000 / GW1100
- GW1200
- GW2000
- HP2550 / HP2560 (with built-in gateway)
- Other Ecowitt gateways with local API support

## License

[Add your license here]
