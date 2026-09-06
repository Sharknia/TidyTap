import Darwin
import Foundation

enum TidyTapProduct {
    static let appBundleIdentifier = "com.sharknia.TidyTap"
    static let helperBundleIdentifier = "com.sharknia.TidyTap.Helper"
    static let agentPlistName = "com.sharknia.TidyTap.Agent.plist"
    static let helperExecutablePath = "Contents/MacOS/TidyTapHelper"
    static let workerLaunchNonceEnvironmentKey = "TIDYTAP_WORKER_LAUNCH_NONCE"

    static func workerLockURL(
        preferencesSuite: String = appBundleIdentifier
    ) -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(preferencesSuite, isDirectory: true)
            .appendingPathComponent("worker.lock")
    }
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
