import Foundation

// MARK: - TriggerCorrelation Typealias
// Re-exports EpisodeLogger.TriggerCorrelation as a top-level type for convenient access.
// The canonical definition lives inside EpisodeLogger (Services/EpisodeLogger.swift)
// where it is tightly coupled to the SQLite CRUD implementation.
typealias TriggerCorrelation = EpisodeLogger.TriggerCorrelation
