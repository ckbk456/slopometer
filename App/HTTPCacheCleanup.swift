import Foundation

/// Development builds before 1.0.1 sent GitHub requests through the shared URL session,
/// whose disk cache stored them with their Authorization header. The app now uses a
/// session that caches nothing; this empties the shared cache and removes what earlier
/// builds left behind. Runs before any session is created.
enum HTTPCacheCleanup {
    /// The shared cache's files, inside the app's own Caches folder. Nothing else there
    /// (Sparkle's downloads, for example) is touched.
    static let cacheFileNames = ["Cache.db", "Cache.db-shm", "Cache.db-wal", "fsCachedData"]

    static func run() {
        URLCache.shared = URLCache(memoryCapacity: 0, diskCapacity: 0, directory: nil)
        guard
            let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
                .first,
            let bundleID = Bundle.main.bundleIdentifier
        else { return }
        let directory = caches.appendingPathComponent(bundleID, isDirectory: true)
        for name in cacheFileNames {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
    }
}
