import Foundation
import SwiftUI

/// Saved connections, persisted as JSON in ~/Library/Application Support/MacRDP/connections.json.
@MainActor
final class ConnectionStore: ObservableObject {
    @Published private(set) var connections: [Connection] = []

    let fileURL: URL

    init(directory: URL? = nil) {
        let dir = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacRDP", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("connections.json")
        load()
    }

    var groups: [String] {
        Array(Set(connections.map(\.group).filter { !$0.isEmpty })).sorted()
    }

    func connection(id: UUID) -> Connection? { connections.first { $0.id == id } }

    func upsert(_ c: Connection) {
        if let i = connections.firstIndex(where: { $0.id == c.id }) {
            connections[i] = c
        } else {
            connections.append(c)
        }
        save()
    }

    func delete(_ ids: Set<UUID>) {
        for id in ids {
            Keychain.delete(account: id.uuidString)
            Keychain.delete(account: id.uuidString + ".gateway")
        }
        connections.removeAll { ids.contains($0.id) }
        save()
    }

    func duplicate(_ c: Connection) -> Connection {
        var copy = c
        copy.id = UUID()
        copy.friendlyName = (c.friendlyName.isEmpty ? c.host : c.friendlyName) + " 拷貝"
        copy.lastConnected = nil
        if let p = Keychain.password(account: c.keychainAccount) {
            Keychain.setPassword(p, account: copy.keychainAccount)
        }
        upsert(copy)
        return copy
    }

    func markConnected(_ id: UUID) {
        guard let i = connections.firstIndex(where: { $0.id == id }) else { return }
        connections[i].lastConnected = Date()
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        connections = (try? JSONDecoder.iso.decode([Connection].self, from: data)) ?? []
    }

    private func save() {
        guard let data = try? JSONEncoder.iso.encode(connections) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

extension JSONEncoder {
    static var iso: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }
}

extension JSONDecoder {
    static var iso: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
