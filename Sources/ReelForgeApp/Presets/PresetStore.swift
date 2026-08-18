import Foundation

enum PresetStore {
    static func load() throws -> [Preset] {
        if let dir = PresetCatalog.bundledDirectory() {
            return try PresetCatalog.load(from: dir)
        }
        if let dir = PresetCatalog.sourceTreeDirectory() {
            return try PresetCatalog.load(from: dir)
        }
        throw PresetCatalogError.directoryMissing
    }
}
