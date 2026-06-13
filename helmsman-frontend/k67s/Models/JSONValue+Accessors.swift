import Foundation

// Numeric, boolean, and array-index accessors for traversing Kubernetes
// objects. The base JSONValue only exposes string/object/array access.
extension JSONValue {
    /// Int from .int, a whole .double, or a numeric .string.
    var intValue: Int? {
        switch self {
        case .int(let v): v
        case .double(let v): Int(v)
        case .string(let s): Int(s)
        default: nil
        }
    }

    /// Double from .double, .int, or a numeric .string.
    var doubleValue: Double? {
        switch self {
        case .double(let v): v
        case .int(let v): Double(v)
        case .string(let s): Double(s)
        default: nil
        }
    }

    /// Bool only from .bool (K8s booleans are real JSON booleans).
    var boolValue: Bool? {
        if case .bool(let v) = self { return v }
        return nil
    }

    /// Index into an array, e.g. `object["spec"]?["containers"]?[0]`.
    subscript(index: Int) -> JSONValue? {
        if case .array(let arr) = self, arr.indices.contains(index) { return arr[index] }
        return nil
    }
}
