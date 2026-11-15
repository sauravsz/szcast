import Foundation

/// The cacheless exchange-rate fetcher. See docs/features/calculator.md#exchange-rates.
@MainActor
@Observable
final class CurrencyRateStore {
    /// Direct open CC0 currency snapshot on Cloudflare Pages.
    private nonisolated static let primaryEndpoint = URL(
        string: "https://latest.currency-api.pages.dev/v1/currencies/usd.min.json")!
    /// Fastly/jsDelivr fallback in case Cloudflare Pages experiences an outage.
    private nonisolated static let fallbackEndpoint = URL(
        string: "https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@latest/v1/currencies/usd.min.json")!
    /// Daily, measured from `completedAt`, so relaunching never re-fetches a snapshot still fresh.
    private static let refreshInterval: TimeInterval = 24 * 3600
    /// Shorter retry, so a machine offline at launch picks rates up soon after it reconnects.
    private static let retryInterval: TimeInterval = 30 * 60

    private(set) var rates: CurrencyRates?
    private(set) var isRefreshing = false

    private let fileURL: URL
    @ObservationIgnored private var pump: Task<Void, Never>?
    /// Drives the schedule: a partial snapshot answers, but only a whole one resets the clock.
    @ObservationIgnored private var completedAt: Date?

    init() {
        fileURL = AppPaths.caches().appendingPathComponent("currency-rates.json")
        guard let data = try? Data(contentsOf: fileURL),
            let cached = try? JSONDecoder().decode(CurrencyRates.self, from: data)
        else { return }
        rates = cached
        // A cache from before coins existed still prices fiat, but has to be replaced at once.
        if CurrencyFeed.pricesCoins(cached) { completedAt = cached.fetchedAt }
    }

    func start() {
        // Replace rather than bail: an exited loop leaves a non-nil task that would block restart.
        pump?.cancel()
        pump = Task { [weak self] in
            while !Task.isCancelled, let self {
                // Clamped, so a future-stamped snapshot can't park the loop past one interval.
                let age = max(0, self.completedAt.map { Date().timeIntervalSince($0) } ?? .infinity)
                guard age >= Self.refreshInterval else {
                    try? await Task.sleep(for: .seconds(Self.refreshInterval - age))
                    continue
                }
                let ok = await self.fetchAndStore()
                try? await Task.sleep(for: .seconds(ok ? Self.refreshInterval : Self.retryInterval))
            }
        }
    }

    /// The pump re-measures age from `completedAt` when it wakes, so its schedule needs no reset.
    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        Task {
            await fetchAndStore()
            isRefreshing = false
        }
    }

    @discardableResult
    private func fetchAndStore() async -> Bool {
        guard let result = await Self.fetch() else { return false }
        rates = result.rates
        // Never persist a coin-less run: `pricesCoins` reads the cache as whole by definition.
        guard result.complete, let data = try? JSONEncoder().encode(result.rates) else { return false }
        completedAt = result.rates.fetchedAt
        try? data.write(to: fileURL, options: .atomic)
        return true
    }

    /// Cacheless, never `URLSession.shared`, so the snapshot on disk stays the only copy.
    private nonisolated static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

    /// Off-main via `URLSession`; only the plain-value `CurrencyRates` crosses back.
    private nonisolated static func fetch() async -> (rates: CurrencyRates, complete: Bool)? {
        let now = Date()
        if let primaryData = await body(of: primaryEndpoint),
            let snapshot = try? CurrencyFeed.snapshot(openApi: primaryData, now: now)
        {
            return snapshot
        }
        if let fallbackData = await body(of: fallbackEndpoint),
            let snapshot = try? CurrencyFeed.snapshot(openApi: fallbackData, now: now)
        {
            return snapshot
        }
        return nil
    }

    private nonisolated static func body(of url: URL) async -> Data? {
        let request = URLRequest(url: url, timeoutInterval: 20)
        guard let (data, response) = try? await session.data(for: request),
            let http = response as? HTTPURLResponse, http.statusCode == 200
        else { return nil }
        return data
    }
}
