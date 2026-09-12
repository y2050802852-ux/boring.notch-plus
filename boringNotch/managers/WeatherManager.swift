//
//  WeatherManager.swift
//  boringNotch
//
//  Created by imac on 2026. 09. 12..
//

import AppKit
import Combine
import Defaults
import Foundation

/// A single idle-weather reading.
struct WeatherInfo: Codable, Equatable {
    var temperatureC: Double
    var weatherCode: Int
    var windSpeedMs: Double
    var isDay: Bool
    var cityName: String
    var fetchedAt: Date

    var symbolName: String {
        Self.symbol(for: weatherCode, isDay: isDay, windSpeedMs: windSpeedMs)
    }

    var temperatureText: String {
        "\(Int(temperatureC.rounded()))°"
    }

    /// WMO weather code → SF Symbol. Extreme wind (~typhoon force) maps to
    /// the hurricane symbol since current-weather APIs don't report storms by name.
    static func symbol(for code: Int, isDay: Bool, windSpeedMs: Double) -> String {
        if windSpeedMs >= 32 { return "hurricane" }
        switch code {
        case 0: return isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2: return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51, 53, 55: return "cloud.drizzle.fill"
        case 56, 57: return "cloud.sleet.fill"
        case 61, 63: return "cloud.rain.fill"
        case 65: return "cloud.heavyrain.fill"
        case 66, 67: return "cloud.hail.fill"
        case 71, 73, 75, 77: return "cloud.snow.fill"
        case 80: return isDay ? "cloud.sun.rain.fill" : "cloud.moon.rain.fill"
        case 81: return "cloud.rain.fill"
        case 82: return "cloud.heavyrain.fill"
        case 85, 86: return "cloud.snow.fill"
        case 95, 96, 99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }
}

/// A resolved coordinate (manual city override or IP auto-detection).
struct WeatherLocation: Codable, Equatable {
    var latitude: Double
    var longitude: Double
    var name: String
}

/// Fetches current weather for the idle-state notch icon. Uses the free
/// Open-Meteo API (no key) and IP geolocation, with an optional manual city
/// override. Polls every 30 minutes and keeps the last reading cached so the
/// icon still works offline. Zero new permissions.
@MainActor
final class WeatherManager: ObservableObject {
    static let shared = WeatherManager()
    static let refreshInterval: TimeInterval = 30 * 60

    @Published private(set) var current: WeatherInfo?
    @Published private(set) var autoDetectedCity: String?
    @Published private(set) var isFetching = false

    private var refreshTimer: Timer?
    private var cancellables: Set<AnyCancellable> = []

    private init() {
        // Restore the last successful reading so the icon works offline.
        if let data = Defaults[.weatherCacheData],
           let cached = try? JSONDecoder().decode(WeatherInfo.self, from: data) {
            current = cached
        }

        Defaults.publisher(.idleWeatherEnabled)
            .receive(on: RunLoop.main)
            .sink { [weak self] change in
                change.newValue ? self?.start() : self?.stop()
            }
            .store(in: &cancellables)

        if Defaults[.idleWeatherEnabled] {
            start()
        }
    }

    func start() {
        Task { await refresh() }
        scheduleNext()
    }

    func stop() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    private func scheduleNext() {
        refreshTimer?.invalidate()
        let timer = Timer(timeInterval: Self.refreshInterval, repeats: true, block: { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refresh()
            }
        })
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    func refresh() async {
        guard !isFetching else { return }
        isFetching = true
        defer { isFetching = false }

        let location: WeatherLocation?
        if let manual = Self.manualLocation {
            location = manual
        } else {
            location = await Self.locateByIP()
            autoDetectedCity = location?.name
        }
        guard let loc = location else { return }

        // On failure the previous reading is kept (the icon just goes stale).
        if let info = await Self.fetchWeather(for: loc) {
            current = info
            if let data = try? JSONEncoder().encode(info) {
                Defaults[.weatherCacheData] = data
            }
        }
    }

    // MARK: - Location

    static var manualLocation: WeatherLocation? {
        guard let data = Defaults[.weatherManualLocationData] else { return nil }
        return try? JSONDecoder().decode(WeatherLocation.self, from: data)
    }

    static func setManualLocation(_ location: WeatherLocation?) {
        Defaults[.weatherManualLocationData] = location.flatMap { try? JSONEncoder().encode($0) }
        Task { @MainActor in
            await WeatherManager.shared.refresh()
        }
    }

    /// IP-based geolocation: ipapi.co first, ip-api.com as an HTTP fallback.
    private static func locateByIP() async -> WeatherLocation? {
        struct IPAPICoResponse: Decodable {
            let city: String?
            let latitude: Double?
            let longitude: Double?
        }
        if let (data, _) = try? await fetchData(url: URL(string: "https://ipapi.co/json/")!),
           let response = try? JSONDecoder().decode(IPAPICoResponse.self, from: data),
           let latitude = response.latitude, let longitude = response.longitude {
            return WeatherLocation(latitude: latitude, longitude: longitude, name: response.city ?? "自动定位")
        }

        struct IPAPIComResponse: Decodable {
            let status: String?
            let city: String?
            let lat: Double?
            let lon: Double?
        }
        if let (data, _) = try? await fetchData(url: URL(string: "http://ip-api.com/json/?fields=status,city,lat,lon&lang=zh-CN")!),
           let response = try? JSONDecoder().decode(IPAPIComResponse.self, from: data),
           response.status == "success", let latitude = response.lat, let longitude = response.lon {
            return WeatherLocation(latitude: latitude, longitude: longitude, name: response.city ?? "自动定位")
        }

        return nil
    }

    // MARK: - Weather

    private static func fetchWeather(for location: WeatherLocation) async -> WeatherInfo? {
        struct OpenMeteoResponse: Decodable {
            struct Current: Decodable {
                let temperature_2m: Double
                let weather_code: Int
                let is_day: Int
                let wind_speed_10m: Double
            }
            let current: Current
        }
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(location.latitude)),
            URLQueryItem(name: "longitude", value: String(location.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code,is_day,wind_speed_10m"),
            URLQueryItem(name: "wind_speed_unit", value: "ms"),
            URLQueryItem(name: "timezone", value: "auto"),
        ]
        guard let (data, _) = try? await fetchData(url: components.url!),
              let response = try? JSONDecoder().decode(OpenMeteoResponse.self, from: data) else {
            return nil
        }
        return WeatherInfo(
            temperatureC: response.current.temperature_2m,
            weatherCode: response.current.weather_code,
            windSpeedMs: response.current.wind_speed_10m,
            isDay: response.current.is_day == 1,
            cityName: location.name,
            fetchedAt: Date()
        )
    }

    // MARK: - Geocoding (manual city search)

    struct GeoCity: Identifiable, Decodable {
        let id: Int
        let name: String
        let admin1: String?
        let country: String?
        let latitude: Double
        let longitude: Double

        var displayName: String {
            [name, admin1, country].compactMap { $0 }.joined(separator: " · ")
        }
    }

    static func searchCities(_ query: String) async -> [GeoCity] {
        struct GeoResponse: Decodable {
            let results: [GeoCity]?
        }
        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        components.queryItems = [
            URLQueryItem(name: "name", value: query),
            URLQueryItem(name: "count", value: "5"),
            URLQueryItem(name: "language", value: "zh"),
        ]
        guard let (data, _) = try? await fetchData(url: components.url!),
              let response = try? JSONDecoder().decode(GeoResponse.self, from: data) else {
            return []
        }
        return response.results ?? []
    }

    private static func fetchData(url: URL) async throws -> (Data, URLResponse) {
        let request = URLRequest(url: url, timeoutInterval: 10)
        return try await URLSession.shared.data(for: request)
    }
}
