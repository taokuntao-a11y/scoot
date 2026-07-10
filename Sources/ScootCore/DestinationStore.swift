import Combine
import Foundation

public struct Destination: Codable, Identifiable, Sendable, Hashable {
    public let id: UUID
    public var name: String
    public var path: String

    public init(id: UUID = UUID(), name: String, path: String) {
        self.id = id
        self.name = name
        self.path = path
    }

    public var url: URL { URL(fileURLWithPath: path, isDirectory: true) }
}

@MainActor
public final class DestinationStore: ObservableObject {
    @Published public var destinations: [Destination] = []

    private let storageURL: URL

    public init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        let dir = appSupport.appendingPathComponent("Scoot")
        storageURL = dir.appendingPathComponent("destinations.json")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        load()
    }

    private func load() {
        guard let data = try? Data(contentsOf: storageURL),
              let decoded = try? JSONDecoder().decode([Destination].self, from: data)
        else { return }
        destinations = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(destinations) else { return }
        try? data.write(to: storageURL, options: .atomic)
    }

    public func add(url: URL) {
        let dest = Destination(name: url.lastPathComponent, path: url.path)
        destinations.append(dest)
        save()
    }

    public func remove(_ destination: Destination) {
        destinations.removeAll { $0.id == destination.id }
        save()
    }
}
