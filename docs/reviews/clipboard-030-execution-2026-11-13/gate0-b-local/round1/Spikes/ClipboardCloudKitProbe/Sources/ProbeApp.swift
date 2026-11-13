import Darwin
import Foundation

enum ProbeError: Error {
    case usage, unsafePath, invalidMarker, invalidStore, itemTooLarge, assertion(String), timedOut
}

struct ProbeRun {
    struct Marker: Codable {
        let kind: String
        let id: UUID
    }

    let root: URL
    let id: UUID
    static let kind = "TidyTap.LocalCoreDataProbe.v1"

    static func create(at root: URL) throws -> ProbeRun {
        try validatePath(root)
        let fm = FileManager.default
        if fm.fileExists(atPath: root.path) {
            guard try fm.contentsOfDirectory(atPath: root.path).isEmpty else { throw ProbeError.unsafePath }
        } else {
            try fm.createDirectory(at: root, withIntermediateDirectories: false,
                                   attributes: [.posixPermissions: 0o700])
        }
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
        let run = ProbeRun(root: root, id: UUID())
        try JSONEncoder().encode(Marker(kind: kind, id: run.id))
            .write(to: root.appendingPathComponent("run-marker.json"), options: .withoutOverwriting)
        return run
    }

    static func openWriter(at root: URL, id: UUID) throws -> ProbeRun {
        try validatePath(root)
        try validateTree(root)
        let marker = try JSONDecoder().decode(Marker.self,
            from: Data(contentsOf: root.appendingPathComponent("run-marker.json")))
        guard marker.kind == kind, marker.id == id else { throw ProbeError.invalidMarker }
        return ProbeRun(root: root, id: id)
    }

    static func validatePath(_ url: URL) throws {
        guard url.isFileURL,
              url.standardizedFileURL.path == url.resolvingSymlinksInPath().standardizedFileURL.path else {
            throw ProbeError.unsafePath
        }
    }

    static func validateTree(_ root: URL) throws {
        try validatePath(root)
        let fm = FileManager.default
        let children = fm.enumerator(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey])
        var urls = [root]
        while let url = children?.nextObject() as? URL { urls.append(url) }
        for url in urls {
            guard try url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else {
                throw ProbeError.unsafePath
            }
            let attributes = try fm.attributesOfItem(atPath: url.path)
            guard let permissions = attributes[.posixPermissions] as? NSNumber,
                  let owner = attributes[.ownerAccountID] as? NSNumber,
                  permissions.intValue & 0o077 == 0, owner.uint32Value == getuid() else {
                throw ProbeError.unsafePath
            }
        }
    }
}

@main
@MainActor
struct ProbeApp {
    static func main() {
        umask(0o077)
        let args = Array(CommandLine.arguments.dropFirst())
        do {
            switch args.first {
            case "self-test" where args.count == 2:
                let run = try ProbeRun.create(at: URL(fileURLWithPath: args[1]).standardizedFileURL)
                try ProbeScenario.run(run)
            case "writer" where args.count == 4:
                guard let runID = UUID(uuidString: args[2]), let itemID = UUID(uuidString: args[3]) else {
                    throw ProbeError.usage
                }
                let run = try ProbeRun.openWriter(at: URL(fileURLWithPath: args[1]).standardizedFileURL, id: runID)
                let store = try ProbeStore(root: run.root, author: "local-writer")
                try store.insert(.text(plain: "synthetic-writer", rtf: nil, html: nil), id: itemID)
                try store.close()
            default:
                throw ProbeError.usage
            }
        } catch {
            let code: String
            switch error {
            case ProbeError.usage: code = "invalid-arguments"
            case ProbeError.unsafePath: code = "unsafe-path"
            case ProbeError.invalidMarker: code = "invalid-marker"
            case ProbeError.itemTooLarge: code = "item-too-large"
            case ProbeError.assertion(let id): code = "assertion-\(id)"
            case ProbeError.timedOut: code = "timeout"
            default: code = "storage-\((error as NSError).code)"
            }
            FileHandle.standardError.write(Data("probe-error: \(code)\n".utf8))
            if case ProbeError.usage = error { exit(64) }
            exit(1)
        }
    }
}
