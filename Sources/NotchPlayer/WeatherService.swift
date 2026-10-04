import AppKit
import CoreLocation

/// Current weather where you are, from Open-Meteo (free, no account needed).
///
/// The location is rounded to about 1 km before it's sent, and cached so
/// the weather keeps working if Location access is reset.
final class WeatherService: NSObject, ObservableObject, CLLocationManagerDelegate {
    struct Conditions: Equatable {
        /// In Celsius; formatted in the user's preferred unit.
        let temperature: Double
        let high: Double
        let low: Double
        let code: Int
        let isDay: Bool

        var summary: String { WeatherCode.summary(code) }
        var symbol: String { WeatherCode.symbol(code, isDay: isDay) }
    }

    @Published private(set) var current: Conditions?

    private let manager = CLLocationManager()
    private var coordinate: CLLocationCoordinate2D?
    private var lastLocated: Date?
    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var task: URLSessionDataTask?

    private static let refreshInterval: TimeInterval = 30 * 60
    private static let relocateInterval: TimeInterval = 2 * 60 * 60
    private static let latitudeKey = "weatherLatitude"
    private static let longitudeKey = "weatherLongitude"

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Self.latitudeKey) != nil {
            coordinate = CLLocationCoordinate2D(latitude: defaults.double(forKey: Self.latitudeKey),
                                                longitude: defaults.double(forKey: Self.longitudeKey))
        }
    }

    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in self?.refresh() }
        timer.tolerance = 60
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            // The network needs a moment after waking.
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { self?.refresh() }
        }

        // Only prompt when there's no saved location to fall back on.
        if manager.authorizationStatus == .notDetermined && coordinate == nil {
            manager.requestWhenInUseAuthorization()
        }
        refresh()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        wakeObserver = nil
        task?.cancel()
    }

    private var isAuthorized: Bool {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: true
        default: false
        }
    }

    private func refresh() {
        if isAuthorized, lastLocated.map({ Date().timeIntervalSince($0) > Self.relocateInterval }) ?? true {
            manager.requestLocation()
        }
        fetch()
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if isAuthorized && timer != nil && lastLocated == nil {
            manager.requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        lastLocated = Date()
        let moved = coordinate.map {
            CLLocation(latitude: $0.latitude, longitude: $0.longitude).distance(from: location) > 2_000
        } ?? true
        coordinate = location.coordinate
        UserDefaults.standard.set(location.coordinate.latitude, forKey: Self.latitudeKey)
        UserDefaults.standard.set(location.coordinate.longitude, forKey: Self.longitudeKey)
        if moved || current == nil { fetch() }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        NSLog("NotchPlayer: location unavailable: %@", error.localizedDescription)
    }

    // MARK: - Forecast

    private struct Response: Decodable {
        struct Current: Decodable {
            let temperature_2m: Double
            let weather_code: Int
            let is_day: Int
        }
        struct Daily: Decodable {
            let temperature_2m_max: [Double]
            let temperature_2m_min: [Double]
        }
        let current: Current
        let daily: Daily
    }

    private func fetch() {
        guard let coordinate, timer != nil else { return }
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.2f", coordinate.latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.2f", coordinate.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code,is_day"),
            URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_min"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "1"),
        ]
        guard let url = components.url else { return }

        task?.cancel()
        task = URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            guard let data, let response = try? JSONDecoder().decode(Response.self, from: data),
                  let high = response.daily.temperature_2m_max.first,
                  let low = response.daily.temperature_2m_min.first else {
                if let error, (error as? URLError)?.code != .cancelled {
                    NSLog("NotchPlayer: weather request failed: %@", error.localizedDescription)
                }
                return
            }
            let conditions = Conditions(temperature: response.current.temperature_2m,
                                        high: high, low: low,
                                        code: response.current.weather_code,
                                        isDay: response.current.is_day == 1)
            DispatchQueue.main.async {
                if self?.current != conditions { self?.current = conditions }
            }
        }
        task?.resume()
    }
}

/// WMO weather codes, as used by Open-Meteo.
private enum WeatherCode {
    static func summary(_ code: Int) -> String {
        switch code {
        case 0: "Clear"
        case 1: "Mostly clear"
        case 2: "Partly cloudy"
        case 3: "Cloudy"
        case 45, 48: "Fog"
        case 51, 53, 55: "Drizzle"
        case 56, 57, 66, 67: "Freezing rain"
        case 61, 63: "Rain"
        case 65: "Heavy rain"
        case 71, 73, 77: "Snow"
        case 75: "Heavy snow"
        case 80, 81: "Showers"
        case 82: "Heavy showers"
        case 85, 86: "Snow showers"
        case 95, 96, 99: "Thunderstorms"
        default: "—"
        }
    }

    static func symbol(_ code: Int, isDay: Bool) -> String {
        switch code {
        case 0, 1: isDay ? "sun.max.fill" : "moon.stars.fill"
        case 2: isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: "cloud.fill"
        case 45, 48: "cloud.fog.fill"
        case 51, 53, 55: "cloud.drizzle.fill"
        case 56, 57, 66, 67: "cloud.sleet.fill"
        case 61, 63: "cloud.rain.fill"
        case 65, 82: "cloud.heavyrain.fill"
        case 71, 73, 75, 77, 85, 86: "cloud.snow.fill"
        case 80, 81: isDay ? "cloud.sun.rain.fill" : "cloud.moon.rain.fill"
        case 95, 96, 99: "cloud.bolt.rain.fill"
        default: "cloud.fill"
        }
    }
}

extension Double {
    /// "72°" in the US, "22°" elsewhere, from a Celsius value.
    var temperatureText: String {
        Measurement(value: self, unit: UnitTemperature.celsius)
            .formatted(.measurement(width: .narrow, usage: .weather,
                                    numberFormatStyle: .number.precision(.fractionLength(0))))
    }
}

#if DEBUG
extension WeatherService {
    func loadSample(_ conditions: Conditions?) {
        current = conditions
    }
}
#endif
