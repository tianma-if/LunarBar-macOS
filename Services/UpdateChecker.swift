import Foundation
import Combine
import AppKit
@preconcurrency import UserNotifications

struct ReleaseAsset: Decodable, Equatable {
    let name: String
    let size: Int
    let browserDownloadURL: URL

    enum CodingKeys: String, CodingKey {
        case name
        case size
        case browserDownloadURL = "browser_download_url"
    }
}

struct UpdateCheckResult: Equatable {
    let latestVersion: String
    let releaseURL: URL
    let dmgURL: URL?
    let dmgSize: Int?
    let releaseNotes: String?
}

enum UpdateCheckerError: LocalizedError {
    case invalidResponse
    case invalidRelease
    case noDmgFound
    case extractFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "更新服务暂时不可用"
        case .invalidRelease:
            return "更新信息无效"
        case .noDmgFound:
            return "未找到适用于 macOS 的更新安装包"
        case .extractFailed(let msg):
            return "解压更新失败: \(msg)"
        }
    }
}

struct UpdateChecker {
    static let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"

    private struct Release: Decodable {
        let tagName: String
        let htmlURL: URL
        let body: String?
        let assets: [ReleaseAsset]?

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case body
            case assets
        }
    }

    func checkForUpdates() async throws -> UpdateCheckResult {
        guard let url = URL(string: "https://api.github.com/repos/tianma-if/LunarBar-macOS/releases/latest") else {
            throw UpdateCheckerError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("LunarBar/\(Self.currentVersion)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw UpdateCheckerError.invalidResponse
        }

        let release = try JSONDecoder().decode(Release.self, from: data)
        let latestVersion = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        guard !latestVersion.isEmpty else {
            throw UpdateCheckerError.invalidRelease
        }

        let dmgAsset = release.assets?.first(where: { $0.name.lowercased().hasSuffix(".dmg") })

        return UpdateCheckResult(
            latestVersion: latestVersion,
            releaseURL: release.htmlURL,
            dmgURL: dmgAsset?.browserDownloadURL,
            dmgSize: dmgAsset?.size,
            releaseNotes: release.body
        )
    }

    static func isNewer(_ version: String, than currentVersion: String) -> Bool {
        let latest = version.split(separator: ".").map { Int($0) ?? 0 }
        let current = currentVersion.split(separator: ".").map { Int($0) ?? 0 }
        let count = max(latest.count, current.count)

        for index in 0..<count {
            let latestPart = index < latest.count ? latest[index] : 0
            let currentPart = index < current.count ? current[index] : 0
            if latestPart != currentPart {
                return latestPart > currentPart
            }
        }

        return false
    }
}

@MainActor
final class AutoUpdateManager: NSObject, ObservableObject, URLSessionDownloadDelegate {
    static let shared = AutoUpdateManager()

    enum UpdateStatus: Equatable {
        case idle
        case checking
        case latest
        case downloading(progress: Double, version: String)
        case readyToRestart(version: String)
        case installing
        case failed(String)
    }

    @Published private(set) var status: UpdateStatus = .idle
    @Published var automaticallyCheckForUpdates: Bool {
        didSet {
            UserDefaults.standard.set(automaticallyCheckForUpdates, forKey: "automaticallyCheckForUpdates")
        }
    }

    var readyVersion: String? {
        if case .readyToRestart(let version) = status {
            return version
        }
        return nil
    }

    private let checker = UpdateChecker()
    private var downloadTask: URLSessionDownloadTask?
    private lazy var urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        return URLSession(configuration: config, delegate: self, delegateQueue: .main)
    }()

    private var targetVersion: String?
    private var cancellables = Set<AnyCancellable>()

    private override init() {
        self.automaticallyCheckForUpdates = UserDefaults.standard.object(forKey: "automaticallyCheckForUpdates") as? Bool ?? true
        super.init()

        setupObservers()
        startPeriodicCheck()
    }

    func checkForUpdates(manual: Bool = false) {
        guard status != .checking && !isDownloading else { return }

        status = .checking

        Task {
            do {
                let result = try await checker.checkForUpdates()
                if UpdateChecker.isNewer(result.latestVersion, than: UpdateChecker.currentVersion) {
                    if let dmgURL = result.dmgURL {
                        self.startDownload(from: dmgURL, version: result.latestVersion)
                    } else {
                        self.status = .failed("未找到可下载的 DMG 资源")
                    }
                } else {
                    self.status = manual ? .latest : .idle
                }
            } catch {
                if manual {
                    self.status = .failed((error as? LocalizedError)?.errorDescription ?? "检查更新失败")
                } else {
                    self.status = .idle
                }
            }
        }
    }

    func applyUpdateAndRestart() {
        guard case .readyToRestart = status else { return }

        status = .installing

        let currentAppURL = Bundle.main.bundleURL
        let stagedAppURL = getStagedAppURL()
        let updatesDir = stagedAppURL.deletingLastPathComponent()
        let pid = ProcessInfo.processInfo.processIdentifier

        guard FileManager.default.fileExists(atPath: stagedAppURL.path) else {
            status = .failed("更新包未就绪，请重新检查")
            return
        }

        let script = """
        while kill -0 \(pid) 2>/dev/null; do
            sleep 0.2
        done
        rm -rf "\(currentAppURL.path)"
        cp -R "\(stagedAppURL.path)" "\(currentAppURL.path)"
        xattr -dr com.apple.quarantine "\(currentAppURL.path)" 2>/dev/null || true
        open "\(currentAppURL.path)"
        rm -rf "\(updatesDir.path)"
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", script]

        do {
            try process.run()
            NSApplication.shared.terminate(nil)
        } catch {
            status = .failed("启动更新失败: \(error.localizedDescription)")
        }
    }

    private var isDownloading: Bool {
        if case .downloading = status {
            return true
        }
        return false
    }

    private func startDownload(from url: URL, version: String) {
        self.targetVersion = version
        self.status = .downloading(progress: 0.0, version: version)

        downloadTask?.cancel()
        let task = urlSession.downloadTask(with: url)
        downloadTask = task
        task.resume()
    }

    private func setupObservers() {
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.autoCheckIfEnabled()
            }
            .store(in: &cancellables)
    }

    private func startPeriodicCheck() {
        // Initial check 10s after launch
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            self?.autoCheckIfEnabled()
        }

        // Periodic check every 4 hours
        Timer.publish(every: 4 * 3600, tolerance: 300, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.autoCheckIfEnabled()
            }
            .store(in: &cancellables)
    }

    private func autoCheckIfEnabled() {
        guard automaticallyCheckForUpdates else { return }
        guard status == .idle || status == .latest else { return }
        checkForUpdates(manual: false)
    }

    private func getStagedAppURL() -> URL {
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("dev.lunarbar.LunarBar/Updates", isDirectory: true)
        return cacheDir.appendingPathComponent("LunarBar.app", isDirectory: true)
    }

    private func extractApp(from dmgURL: URL, to stagedAppURL: URL) throws {
        let parentDir = stagedAppURL.deletingLastPathComponent()
        let mountDir = parentDir.appendingPathComponent("mnt", isDirectory: true)

        try? FileManager.default.removeItem(at: stagedAppURL)
        try? FileManager.default.removeItem(at: mountDir)
        try FileManager.default.createDirectory(at: mountDir, withIntermediateDirectories: true)

        let detachPrev = Process()
        detachPrev.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        detachPrev.arguments = ["detach", mountDir.path, "-force"]
        try? detachPrev.run()
        detachPrev.waitUntilExit()

        let attachProcess = Process()
        attachProcess.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        attachProcess.arguments = [
            "attach",
            dmgURL.path,
            "-nobrowse",
            "-readonly",
            "-mountpoint", mountDir.path,
            "-noverify",
            "-noautoopen"
        ]

        let pipe = Pipe()
        attachProcess.standardError = pipe
        try attachProcess.run()
        attachProcess.waitUntilExit()

        guard attachProcess.terminationStatus == 0 else {
            let errData = pipe.fileHandleForReading.readDataToEndOfFile()
            let errMsg = String(data: errData, encoding: .utf8) ?? "hdiutil attach failed"
            throw UpdateCheckerError.extractFailed(errMsg)
        }

        defer {
            let detachProcess = Process()
            detachProcess.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
            detachProcess.arguments = ["detach", mountDir.path, "-force"]
            try? detachProcess.run()
            detachProcess.waitUntilExit()
            try? FileManager.default.removeItem(at: mountDir)
        }

        let appInMount = mountDir.appendingPathComponent("LunarBar.app")
        guard FileManager.default.fileExists(atPath: appInMount.path) else {
            throw UpdateCheckerError.extractFailed("DMG 中未找到 LunarBar.app")
        }

        try FileManager.default.copyItem(at: appInMount, to: stagedAppURL)

        let binaryPath = stagedAppURL.appendingPathComponent("Contents/MacOS/LunarBar").path
        guard FileManager.default.fileExists(atPath: binaryPath) else {
            throw UpdateCheckerError.extractFailed("提取的 LunarBar.app 损坏")
        }
    }

    private func sendUpdateReadyNotification(version: String) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "LunarBar 更新就绪"
            content.body = "新版本 v\(version) 已自动下载完成，点击面板即可一键重启更新。"
            content.sound = .default
            let request = UNNotificationRequest(
                identifier: "dev.lunarbar.update.ready",
                content: content,
                trigger: nil
            )
            UNUserNotificationCenter.current().add(request)
        }
    }

    // MARK: - URLSessionDownloadDelegate

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        Task { @MainActor in
            guard let version = self.targetVersion, self.isDownloading else { return }
            let progress = totalBytesExpectedToWrite > 0 ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) : 0.0
            self.status = .downloading(progress: progress, version: version)
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        Task { @MainActor in
            guard let version = self.targetVersion else { return }
            do {
                let stagedAppURL = self.getStagedAppURL()
                let updatesDir = stagedAppURL.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: updatesDir, withIntermediateDirectories: true)
                let localDmg = updatesDir.appendingPathComponent("update-\(version).dmg")
                try? FileManager.default.removeItem(at: localDmg)
                try FileManager.default.moveItem(at: location, to: localDmg)

                try self.extractApp(from: localDmg, to: stagedAppURL)
                try? FileManager.default.removeItem(at: localDmg)

                self.status = .readyToRestart(version: version)
                self.sendUpdateReadyNotification(version: version)
            } catch {
                self.status = .failed("更新准备失败: \(error.localizedDescription)")
            }
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let error = error {
            Task { @MainActor in
                self.status = .failed("下载更新失败: \(error.localizedDescription)")
            }
        }
    }
}
