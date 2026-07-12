import Foundation

/// What the resource detail pane is currently displaying.
struct DetailFocus {
    let resource: ResourceType
    let row: TablePayload.Row
    /// Non-nil when drilled into a related pod; holds the parent workload row.
    let parent: TablePayload.Row?
}
