import Cocoa
import Foundation

public struct AppReleaseInfo {
    public let version: String
    public let releaseNotes: String
    public let htmlURL: URL
    public let downloadURL: URL?
}

public class UpdateManager {
    public static let shared = UpdateManager()

    private static let lastCheckKey = "PlatoReaderLastUpdateCheckTimestamp"
    private let session: URLSession

    private init() {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 15
        cfg.timeoutIntervalForResource = 120
        self.session = URLSession(configuration: cfg)
    }

    public var currentVersion: String {
        return (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0.0"
    }

    public func checkInBackgroundIfNeeded(config: AppConfig) {
        let now = Date().timeIntervalSince1970
        let last = UserDefaults.standard.double(forKey: UpdateManager.lastCheckKey)
        guard (now - last) >= 86400 else { return } // Once per 24h
        UserDefaults.standard.set(now, forKey: UpdateManager.lastCheckKey)

        checkForUpdates(config: config, silentIfUpToDate: true)
    }

    public func checkForUpdates(config: AppConfig, silentIfUpToDate: Bool) {
        let feedStr = config.effectiveUpdateFeedURL()
        guard let url = URL(string: feedStr) else {
            if !silentIfUpToDate {
                showInfoAlert(title: "Update Check Failed", message: "Invalid update feed URL.")
            }
            return
        }

        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("PlatoReader/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        session.dataTask(with: req) { [weak self] data, response, error in
            guard let self = self else { return }
            DispatchQueue.main.async {
                if let error = error {
                    if !silentIfUpToDate {
                        self.showInfoAlert(title: "Update Check Failed", message: error.localizedDescription)
                    }
                    return
                }

                guard let http = response as? HTTPURLResponse, let data = data else {
                    if !silentIfUpToDate {
                        self.showInfoAlert(title: "Update Check Failed", message: "No response from update server.")
                    }
                    return
                }

                if http.statusCode == 404 {
                    if !silentIfUpToDate {
                        self.showInfoAlert(
                            title: "No Public Releases Found",
                            message: "No published GitHub release was found at:\n\(feedStr)\n\nTo enable in-app updates for everyone, publish a GitHub Release with PlatoReader.app.zip on a public repository."
                        )
                    }
                    return
                }

                guard http.statusCode == 200,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let rawTag = json["tag_name"] as? String else {
                    if !silentIfUpToDate {
                        self.showInfoAlert(title: "Update Check Failed", message: "Server returned HTTP \(http.statusCode).")
                    }
                    return
                }

                let remoteVersion = self.normalizeVersion(rawTag)
                let notes = (json["body"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let htmlUrlStr = (json["html_url"] as? String) ?? "https://github.com/owlshul/PlatoReader/releases"
                let htmlURL = URL(string: htmlUrlStr) ?? URL(string: "https://github.com/owlshul/PlatoReader/releases")!

                var zipDownloadURL: URL? = nil
                if let assets = json["assets"] as? [[String: Any]] {
                    for asset in assets {
                        if let name = asset["name"] as? String,
                           name.lowercased().hasSuffix(".zip"),
                           let dlStr = asset["browser_download_url"] as? String,
                           let dlURL = URL(string: dlStr) {
                            zipDownloadURL = dlURL
                            break
                        }
                    }
                }

                let release = AppReleaseInfo(
                    version: remoteVersion,
                    releaseNotes: notes,
                    htmlURL: htmlURL,
                    downloadURL: zipDownloadURL
                )

                if self.isVersion(remoteVersion, newerThan: self.currentVersion) {
                    self.promptForUpdate(release)
                } else if !silentIfUpToDate {
                    self.showInfoAlert(
                        title: "You're Up to Date",
                        message: "PlatoReader \(self.currentVersion) is the latest version."
                    )
                }
            }
        }.resume()
    }

    private func normalizeVersion(_ v: String) -> String {
        var s = v.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.lowercased().hasPrefix("v") {
            s = String(s.dropFirst())
        }
        return s
    }

    public func isVersion(_ remote: String, newerThan local: String) -> Bool {
        let rParts = normalizeVersion(remote).split(separator: ".").compactMap { Int($0) }
        let lParts = normalizeVersion(local).split(separator: ".").compactMap { Int($0) }
        let count = max(rParts.count, lParts.count)
        for i in 0..<count {
            let r = i < rParts.count ? rParts[i] : 0
            let l = i < lParts.count ? lParts[i] : 0
            if r != l { return r > l }
        }
        return false
    }

    private func promptForUpdate(_ release: AppReleaseInfo) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "PlatoReader \(release.version) is Available"
        var info = "You are currently running version \(currentVersion)."
        if !release.releaseNotes.isEmpty {
            let trimmed = release.releaseNotes.count > 500
                ? String(release.releaseNotes.prefix(500)) + "..."
                : release.releaseNotes
            info += "\n\nWhat's new:\n\(trimmed)"
        }
        alert.informativeText = info
        alert.alertStyle = .informational

        if let dlURL = release.downloadURL {
            alert.addButton(withTitle: "Update & Relaunch")
            alert.addButton(withTitle: "Later")
            if alert.runModal() == .alertFirstButtonReturn {
                downloadAndInstall(from: dlURL, version: release.version)
            }
        } else {
            alert.addButton(withTitle: "Open Download Page")
            alert.addButton(withTitle: "Later")
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(release.htmlURL)
            }
        }
    }

    private func downloadAndInstall(from url: URL, version: String) {
        session.downloadTask(with: url) { [weak self] tempZipURL, _, error in
            guard let self = self else { return }
            if let error = error {
                DispatchQueue.main.async {
                    self.showInfoAlert(title: "Download Failed", message: error.localizedDescription)
                }
                return
            }
            guard let tempZipURL = tempZipURL else {
                DispatchQueue.main.async {
                    self.showInfoAlert(title: "Download Failed", message: "Could not download the update archive.")
                }
                return
            }

            let workDir = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("PlatoReaderUpdate-\(UUID().uuidString)")
            let extractDir = workDir.appendingPathComponent("extracted")

            do {
                try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)
                let savedZip = workDir.appendingPathComponent("update.zip")
                try FileManager.default.moveItem(at: tempZipURL, to: savedZip)

                let unzip = Process()
                unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
                unzip.arguments = ["-xk", savedZip.path, extractDir.path]
                try unzip.run()
                unzip.waitUntilExit()

                guard unzip.terminationStatus == 0,
                      let newAppURL = self.findAppBundle(in: extractDir) else {
                    DispatchQueue.main.async {
                        self.showInfoAlert(title: "Install Failed", message: "The downloaded archive did not contain a valid PlatoReader.app.")
                    }
                    return
                }

                let targetAppURL = Bundle.main.bundleURL
                guard targetAppURL.pathExtension == "app" else {
                    DispatchQueue.main.async {
                        self.showInfoAlert(title: "Install Failed", message: "Could not determine the installed app path.")
                    }
                    return
                }

                DispatchQueue.main.async {
                    self.launchReplacerAndQuit(newApp: newAppURL, targetApp: targetAppURL, workDir: workDir)
                }
            } catch {
                DispatchQueue.main.async {
                    self.showInfoAlert(title: "Update Failed", message: error.localizedDescription)
                }
            }
        }.resume()
    }

    private func findAppBundle(in directory: URL) -> URL? {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
            return nil
        }
        for case let item as URL in enumerator {
            if item.lastPathComponent == "PlatoReader.app" {
                let execPath = item.appendingPathComponent("Contents/MacOS/PlatoReader").path
                if fm.isExecutableFile(atPath: execPath) {
                    return item
                }
            }
        }
        return nil
    }

    private func launchReplacerAndQuit(newApp: URL, targetApp: URL, workDir: URL) {
        let pid = ProcessInfo.processInfo.processIdentifier
        let parentDir = targetApp.deletingLastPathComponent().path
        let needsAdmin = !FileManager.default.isWritableFile(atPath: parentDir)

        let escapedNew = shellEscape(newApp.path)
        let escapedTarget = shellEscape(targetApp.path)
        let escapedWork = shellEscape(workDir.path)

        let swapCmd: String
        if needsAdmin {
            let inner = "rm -rf \(escapedTarget) && ditto \(escapedNew) \(escapedTarget)"
            let asEscaped = inner.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            swapCmd = "osascript -e 'do shell script \"\(asEscaped)\" with administrator privileges'"
        } else {
            swapCmd = "rm -rf \(escapedTarget) && ditto \(escapedNew) \(escapedTarget)"
        }

        let script = """
        #!/bin/sh
        while kill -0 \(pid) 2>/dev/null; do
          sleep 0.2
        done
        \(swapCmd)
        open \(escapedTarget)
        rm -rf \(escapedWork)
        """

        let scriptURL = workDir.appendingPathComponent("apply_update.sh")
        do {
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/bin/sh")
            proc.arguments = [scriptURL.path]
            proc.standardOutput = FileHandle.nullDevice
            proc.standardError = FileHandle.nullDevice
            proc.standardInput = FileHandle.nullDevice
            try proc.run()

            NSApp.terminate(nil)
        } catch {
            showInfoAlert(title: "Update Failed", message: error.localizedDescription)
        }
    }

    private func shellEscape(_ path: String) -> String {
        return "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func showInfoAlert(title: String, message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
