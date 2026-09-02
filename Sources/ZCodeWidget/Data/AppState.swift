import Foundation
import Combine

/// App-wide state shared between the hidden View menu (⌘1…⌘6) and the panel.
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()
    @Published var selectedTab: SidebarTab = .tokens
}
