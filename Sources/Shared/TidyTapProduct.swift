import Darwin
import AppKit
import Foundation
import Security

enum TidyTapProduct {
    static let appBundleIdentifier = "com.sharknia.TidyTap"
    static let helperBundleIdentifier = "com.sharknia.TidyTap.Helper"
    static let agentPlistName = "com.sharknia.TidyTap.Agent.plist"
    static let helperExecutablePath = "Contents/MacOS/TidyTapHelper"
    static let legacyHelperBundlePath = "Contents/Library/LoginItems/TidyTapHelper.app"
    static let legacyHelperExecutablePath =
        "Contents/Library/LoginItems/TidyTapHelper.app/Contents/MacOS/TidyTapHelper"
    static let workerLaunchNonceEnvironmentKey = "TIDYTAP_WORKER_LAUNCH_NONCE"
    static let backgroundUpdateEnvironmentKey = "TIDYTAP_BACKGROUND_UPDATE_HOST"
    static let installedAppURL = URL(fileURLWithPath: "/Applications/TidyTap.app", isDirectory: true)

    static func isInstalledCopy(_ appURL: URL, allowDevelopment: Bool = false) -> Bool {
        allowDevelopment || appURL.standardizedFileURL.resolvingSymlinksInPath() ==
            installedAppURL.standardizedFileURL.resolvingSymlinksInPath()
    }

    /// Ignore ad-hoc development copies when arbitrating production processes.
    /// Released older copies share the installed app's designated requirement.
    static func isSameSignedApp(_ app: NSRunningApplication) -> Bool {
        guard app.bundleIdentifier == appBundleIdentifier else { return false }
        var installedCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(installedAppURL as CFURL, SecCSFlags(), &installedCode) == errSecSuccess,
              let installedCode else { return false }
        var requirement: SecRequirement?
        guard SecCodeCopyDesignatedRequirement(installedCode, SecCSFlags(), &requirement) == errSecSuccess,
              let requirement else { return false }
        var runningCode: SecCode?
        let attributes = [kSecGuestAttributePid as String: NSNumber(value: app.processIdentifier)] as CFDictionary
        guard SecCodeCopyGuestWithAttributes(nil, attributes, SecCSFlags(), &runningCode) == errSecSuccess,
              let runningCode else { return false }
        return SecCodeCheckValidity(runningCode, SecCSFlags(), requirement) == errSecSuccess
    }

    static func appLockURL(preferencesSuite: String = appBundleIdentifier) -> URL {
        workerLockURL(preferencesSuite: preferencesSuite)
            .deletingLastPathComponent()
            .appendingPathComponent("app.lock")
    }

    static func workerLockURL(
        preferencesSuite: String = appBundleIdentifier
    ) -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(preferencesSuite, isDirectory: true)
            .appendingPathComponent("worker.lock")
    }

    static func clipboardHistoryDirectory(preferencesSuite: String = appBundleIdentifier) -> URL {
        workerLockURL(preferencesSuite: preferencesSuite)
            .deletingLastPathComponent()
            .appendingPathComponent("clipboard-history", isDirectory: true)
    }
}

/// Small, private diagnostic trail for clipboard-history paste attempts.
/// It may contain a bounded preview of the user's search and copied text.
enum TidyTapClipboardPasteLog {
    static let maximumFileBytes = 128 * 1024
    static let maximumLineBytes = 1_024

    static var directory: URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/TidyTap", isDirectory: true)
    }

    static func append(_ event: String, in directory: URL? = nil) {
        let directory = directory ?? self.directory
        let files = FileManager.default
        do {
            try files.createDirectory(
                at: directory, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try files.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        } catch { return }

        let lockPath = directory.appendingPathComponent("clipboard-paste.lock").path
        let lockFD = open(lockPath, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard lockFD >= 0 else { return }
        defer { close(lockFD) }
        guard flock(lockFD, LOCK_EX) == 0 else { return }
        defer { flock(lockFD, LOCK_UN) }
        guard fchmod(lockFD, 0o600) == 0 else { return }

        let sanitized = event.replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let prefix = "\(formatter.string(from: Date())) pid=\(getpid()) "
        let available = max(0, maximumLineBytes - prefix.utf8.count - 4)
        let truncated = String(decoding: sanitized.utf8.prefix(available), as: UTF8.self)
        let line = Data((prefix + truncated + "\n").utf8)
        guard line.count <= maximumLineBytes else { return }

        let active = directory.appendingPathComponent("clipboard-paste.log")
        let previous = directory.appendingPathComponent("clipboard-paste.log.1")
        var logFD = open(active.path, O_CREAT | O_WRONLY | O_APPEND | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard logFD >= 0 else { return }
        defer { if logFD >= 0 { close(logFD) } }
        guard fchmod(logFD, 0o600) == 0 else { return }
        var info = stat()
        guard fstat(logFD, &info) == 0 else { return }
        if Int(info.st_size) + line.count > maximumFileBytes {
            close(logFD)
            logFD = -1
            if info.st_size <= maximumFileBytes && rename(active.path, previous.path) == 0 {
                logFD = open(active.path, O_CREAT | O_WRONLY | O_APPEND | O_CLOEXEC | O_NOFOLLOW, 0o600)
            } else {
                logFD = open(active.path, O_CREAT | O_WRONLY | O_TRUNC | O_CLOEXEC | O_NOFOLLOW, 0o600)
            }
            guard logFD >= 0, fchmod(logFD, 0o600) == 0 else { return }
        }
        line.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            var offset = 0
            while offset < bytes.count {
                let written = Darwin.write(logFD, base.advanced(by: offset), bytes.count - offset)
                guard written > 0 else { return }
                offset += written
            }
        }
    }
}

/// Confirmed local retention and size bounds. Deletion controls are decided separately.
enum TidyTapClipboardPolicy {
    static let retention: TimeInterval = 7 * 24 * 60 * 60
    static let maximumEntries = 100
    static let maximumBytes = 50 * 1024 * 1024
    static let maximumItemBytes = 10 * 1024 * 1024
}

/// Written only after the worker owns `worker.lock`. A launcher must still
/// revalidate every field against the kernel before trusting this record.
struct TidyTapWorkerLockOwner: Equatable, Hashable {
    struct ProcessIdentity: Equatable, Hashable {
        let processIdentifier: pid_t
        let startSeconds: UInt64
        let startMicroseconds: UInt64
    }

    enum Readiness: String {
        case starting
        case acknowledged
        case stopping
        case finished
    }

    let processIdentifier: pid_t
    let startSeconds: UInt64
    let startMicroseconds: UInt64
    let readiness: Readiness
    let launchNonce: UUID?

    private static let prefix = "TIDYTAP-WORKER-2"

    static func current() -> Self? {
        process(processIdentifier: getpid())
    }

    static func process(processIdentifier: pid_t) -> Self? {
        var info = proc_bsdinfo()
        let expectedSize = MemoryLayout<proc_bsdinfo>.size
        let actualSize = proc_pidinfo(
            processIdentifier,
            PROC_PIDTBSDINFO,
            0,
            &info,
            Int32(expectedSize)
        )
        guard actualSize == expectedSize else { return nil }
        return Self(
            processIdentifier: processIdentifier,
            startSeconds: info.pbi_start_tvsec,
            startMicroseconds: info.pbi_start_tvusec,
            readiness: .starting,
            launchNonce: nil
        )
    }

    var encoded: Data {
        let nonce = launchNonce?.uuidString ?? "-"
        let value =
            "\(Self.prefix) \(processIdentifier) \(startSeconds) \(startMicroseconds) " +
            "\(readiness.rawValue) \(nonce)\n"
        return Data(value.utf8)
    }

    var processIdentity: ProcessIdentity {
        ProcessIdentity(
            processIdentifier: processIdentifier,
            startSeconds: startSeconds,
            startMicroseconds: startMicroseconds
        )
    }

    init?(encoded data: Data) {
        guard let value = String(data: data, encoding: .utf8) else { return nil }
        let fields = value.split(whereSeparator: \Character.isWhitespace)
        guard fields.count == 6,
              fields[0] == Substring(Self.prefix),
              let processIdentifier = pid_t(fields[1]), processIdentifier > 0,
              let startSeconds = UInt64(fields[2]),
              let startMicroseconds = UInt64(fields[3]),
              let readiness = Readiness(rawValue: String(fields[4])) else {
            return nil
        }
        let launchNonce: UUID?
        if fields[5] == "-" {
            launchNonce = nil
        } else {
            guard let parsed = UUID(uuidString: String(fields[5])) else { return nil }
            launchNonce = parsed
        }
        self.init(
            processIdentifier: processIdentifier,
            startSeconds: startSeconds,
            startMicroseconds: startMicroseconds,
            readiness: readiness,
            launchNonce: launchNonce
        )
    }

    init(
        processIdentifier: pid_t,
        startSeconds: UInt64,
        startMicroseconds: UInt64,
        readiness: Readiness = .starting,
        launchNonce: UUID? = nil
    ) {
        self.processIdentifier = processIdentifier
        self.startSeconds = startSeconds
        self.startMicroseconds = startMicroseconds
        self.readiness = readiness
        self.launchNonce = launchNonce
    }

    func recording(readiness: Readiness, launchNonce: UUID?) -> Self {
        Self(
            processIdentifier: processIdentifier,
            startSeconds: startSeconds,
            startMicroseconds: startMicroseconds,
            readiness: readiness,
            launchNonce: launchNonce
        )
    }
}
