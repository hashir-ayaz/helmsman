import SwiftUI

struct JobOverview: View {
    let object: JSONValue

    var body: some View {
        DetailSection(title: "Overview") {
            VStack(alignment: .leading, spacing: 4) {
                if let completions = object["spec"]?["completions"]?.displayString {
                    DetailRow(label: "Completions", value: completions)
                }
                if let parallelism = object["spec"]?["parallelism"]?.displayString {
                    DetailRow(label: "Parallelism", value: parallelism)
                }
                DetailRow(label: "Active", value: object["status"]?["active"]?.displayString ?? "0")
                DetailRow(label: "Succeeded", value: object["status"]?["succeeded"]?.displayString ?? "0")
                DetailRow(label: "Failed", value: object["status"]?["failed"]?.displayString ?? "0")
                if let suspend = object["spec"]?["suspend"]?.boolValue {
                    DetailRow(label: "Suspended", value: suspend ? "Yes" : "No")
                }
                if let start = object["status"]?["startTime"]?.stringValue {
                    DetailRow(label: "Started", value: start)
                }
                if let owner = K8s.controlledBy(object) {
                    DetailRow(label: "Controlled By", value: owner)
                }
            }
        }

        if let conditions = object["status"]?["conditions"]?.arrayValue, !conditions.isEmpty {
            DetailSection(title: "Conditions") { ConditionsList(conditions: conditions) }
        }
    }
}

struct CronJobOverview: View {
    let object: JSONValue

    var body: some View {
        DetailSection(title: "Overview") {
            VStack(alignment: .leading, spacing: 4) {
                if let schedule = object["spec"]?["schedule"]?.stringValue {
                    DetailRow(label: "Schedule", value: schedule)
                }
                if let tz = object["spec"]?["timeZone"]?.stringValue {
                    DetailRow(label: "Time Zone", value: tz)
                }
                if let suspend = object["spec"]?["suspend"]?.boolValue {
                    DetailRow(label: "Suspended", value: suspend ? "Yes" : "No")
                }
                if let policy = object["spec"]?["concurrencyPolicy"]?.stringValue {
                    DetailRow(label: "Concurrency", value: policy)
                }
                if let last = object["status"]?["lastScheduleTime"]?.stringValue {
                    DetailRow(label: "Last Schedule", value: last)
                }
                if let active = object["status"]?["active"]?.arrayValue {
                    DetailRow(label: "Active Jobs", value: "\(active.count)")
                }
                if let age = K8s.age(from: object["metadata"]?["creationTimestamp"]?.stringValue) {
                    DetailRow(label: "Age", value: age)
                }
            }
        }
    }
}
