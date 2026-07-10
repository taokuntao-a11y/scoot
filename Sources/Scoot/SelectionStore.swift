import Combine
import Foundation

/// Shared selection state between FileListView and DestinationGridView.
@MainActor
final class SelectionStore: ObservableObject {
    @Published var selection: Set<URL> = []
}
