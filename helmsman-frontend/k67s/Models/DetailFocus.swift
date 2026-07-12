import Foundation

/// What the resource detail pane is currently displaying.
struct DetailFocus {
    let resource: ResourceType
    let row: TablePayload.Row
    /// Parent row when drilled from another resource's detail (workload, Service, Ingress, etc.).
    let parent: TablePayload.Row?
    /// Parent resource type when it differs from the sidebar list resource (e.g. Ingress → Service).
    let parentResource: ResourceType?
    /// Preserved parent when drilling past an intermediate focus (e.g. Ingress → Service → Pod).
    let anchorParent: TablePayload.Row?
    let anchorParentResource: ResourceType?

    init(
        resource: ResourceType,
        row: TablePayload.Row,
        parent: TablePayload.Row? = nil,
        parentResource: ResourceType? = nil,
        anchorParent: TablePayload.Row? = nil,
        anchorParentResource: ResourceType? = nil
    ) {
        self.resource = resource
        self.row = row
        self.parent = parent
        self.parentResource = parentResource
        self.anchorParent = anchorParent
        self.anchorParentResource = anchorParentResource
    }
}
