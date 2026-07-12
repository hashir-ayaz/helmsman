import SwiftUI

/// Routes to a kind-specific overview, then appends shared labels/annotations.
struct ResourceOverview: View {
    let object: JSONValue
    var podEvents: [ResourceDetailModel.PodRelatedEvent] = []
    var isLoadingPodEvents = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            kindOverview
            CommonMetadataSection(object: object)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var kindOverview: some View {
        switch object["kind"]?.stringValue {
        case "Pod":
            PodOverview(object: object, events: podEvents, isLoadingEvents: isLoadingPodEvents)
        case "Deployment", "StatefulSet", "DaemonSet", "ReplicaSet":
            WorkloadOverview(object: object)
        case "Service": ServiceOverview(object: object)
        case "Endpoints": EndpointsOverview(object: object)
        case "Job": JobOverview(object: object)
        case "CronJob": CronJobOverview(object: object)
        case "ConfigMap", "Secret": ConfigOverview(object: object)
        case "ResourceQuota": ResourceQuotaOverview(object: object)
        case "ServiceAccount": ServiceAccountOverview(object: object)
        case "ClusterRole": ClusterRoleOverview(object: object)
        case "ClusterRoleBinding": ClusterRoleBindingOverview(object: object)
        case "Role": RoleOverview(object: object)
        case "RoleBinding": RoleBindingOverview(object: object)
        case "Node": NodeOverview(object: object)
        case "Event": EventOverview(object: object)
        default: GenericOverview(object: object)
        }
    }
}

/// Labels (chips) + annotations (key/value text), shown for every kind.
struct CommonMetadataSection: View {
    let object: JSONValue

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let labels = object["metadata"]?["labels"]?.objectValue, !labels.isEmpty {
                DetailSection(title: "Labels (\(labels.count))") {
                    KeyValueChips(pairs: labels)
                }
            }
            if let annotations = object["metadata"]?["annotations"]?.objectValue, !annotations.isEmpty {
                DetailSection(title: "Annotations (\(annotations.count))") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(annotations.keys.sorted(), id: \.self) { key in
                            VStack(alignment: .leading, spacing: 1) {
                                Text(key).font(.caption2).foregroundStyle(.secondary)
                                Text(annotations[key]?.displayString ?? "")
                                    .font(.system(.caption2, design: .monospaced))
                                    .lineLimit(3)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
            }
        }
    }
}
