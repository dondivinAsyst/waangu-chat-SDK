import Foundation

/// Mini Surface Framework for conversational UI
/// Provides lightweight UI surfaces without local business logic
public actor MiniSurfaceFramework {
    
    public static let shared = MiniSurfaceFramework()
    
    private var registeredSurfaces: [String: MiniSurface] = [:]
    
    private init() {}
    
    public struct MiniSurface: Sendable {
        public let id: String
        public let type: SurfaceType
        public let title: String
        public let content: String
        public let actions: [SurfaceAction]
        public let metadata: [String: String]
        public let createdAt: Date
        
        public init(
            id: String = UUID().uuidString,
            type: SurfaceType,
            title: String,
            content: String,
            actions: [SurfaceAction] = [],
            metadata: [String: String] = [:]
        ) {
            self.id = id
            self.type = type
            self.title = title
            self.content = content
            self.actions = actions
            self.metadata = metadata
            self.createdAt = Date()
        }
    }
    
    public struct SurfaceAction: Sendable {
        public let id: String
        public let label: String
        public let actionId: String
        public let parameters: [String: String]
        
        public init(
            id: String = UUID().uuidString,
            label: String,
            actionId: String,
            parameters: [String: String] = [:]
        ) {
            self.id = id
            self.label = label
            self.actionId = actionId
            self.parameters = parameters
        }
    }
    
    public enum SurfaceType: String, Sendable {
        case banner = "BANNER"
        case card = "CARD"
        case modal = "MODAL"
        case sheet = "SHEET"
        case tooltip = "TOOLTIP"
    }
    
    /// Registers a mini surface
    public func registerSurface(_ surface: MiniSurface) {
        registeredSurfaces[surface.id] = surface
    }
    
    /// Gets a surface by ID
    public func getSurface(_ id: String) -> MiniSurface? {
        registeredSurfaces[id]
    }
    
    /// Creates a banner surface
    public func createBannerSurface(
        title: String,
        content: String,
        actionLabel: String? = nil,
        actionId: String? = nil
    ) -> MiniSurface {
        var actions: [SurfaceAction] = []
        if let actionLabel = actionLabel, let actionId = actionId {
            actions.append(SurfaceAction(label: actionLabel, actionId: actionId))
        }
        
        let surface = MiniSurface(
            type: .banner,
            title: title,
            content: content,
            actions: actions
        )
        registerSurface(surface)
        return surface
    }
    
    /// Creates a card surface
    public func createCardSurface(
        title: String,
        content: String,
        actions: [SurfaceAction] = []
    ) -> MiniSurface {
        let surface = MiniSurface(
            type: .card,
            title: title,
            content: content,
            actions: actions
        )
        registerSurface(surface)
        return surface
    }
    
    /// Creates a tooltip surface
    public func createTooltipSurface(
        title: String,
        content: String
    ) -> MiniSurface {
        let surface = MiniSurface(
            type: .tooltip,
            title: title,
            content: content
        )
        registerSurface(surface)
        return surface
    }
    
    /// Creates a modal surface
    public func createModalSurface(
        title: String,
        content: String,
        actions: [SurfaceAction]
    ) -> MiniSurface {
        let surface = MiniSurface(
            type: .modal,
            title: title,
            content: content,
            actions: actions
        )
        registerSurface(surface)
        return surface
    }
    
    /// Gets all registered surfaces
    public func getAllSurfaces() -> [MiniSurface] {
        Array(registeredSurfaces.values)
    }
    
    /// Gets surfaces by type
    public func getSurfacesByType(_ type: SurfaceType) -> [MiniSurface] {
        registeredSurfaces.values.filter { $0.type == type }
    }
    
    /// Removes a surface
    public func removeSurface(_ id: String) {
        registeredSurfaces.removeValue(forKey: id)
    }
}
