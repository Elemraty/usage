import Foundation

/// Very small dot-path JSON reader: "a.b[0].c" style paths over Foundation JSON objects
/// (NSDictionary / NSArray / NSNumber / NSString trees from JSONSerialization).
enum JSONPath {
    /// A path may list several alternatives separated by "|" — useful when an API's
    /// exact field name isn't known; the first one that resolves wins.
    private static func candidates(_ path: String) -> [String] {
        path.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    static func value(in root: Any, path: String) -> Any? {
        for candidate in candidates(path) {
            if let v = singleValue(in: root, path: candidate) { return v }
        }
        return nil
    }

    static func double(in root: Any, path: String) -> Double? {
        for candidate in candidates(path) {
            guard let v = singleValue(in: root, path: candidate) else { continue }
            if let n = v as? NSNumber { return n.doubleValue }
            if let s = v as? String, let d = Double(s) { return d }
        }
        return nil
    }

    static func string(in root: Any, path: String) -> String? {
        for candidate in candidates(path) {
            guard let v = singleValue(in: root, path: candidate) else { continue }
            if let s = v as? String { return s }
            if let n = v as? NSNumber { return n.stringValue }
        }
        return nil
    }

    private static func singleValue(in root: Any, path: String) -> Any? {
        guard !path.isEmpty else { return root }
        var current: Any = root
        for rawSegment in path.split(separator: ".") {
            let segment = String(rawSegment)
            let (key, indices) = parseSegment(segment)
            if let key = key {
                guard let dict = current as? [String: Any], let next = dict[key] else { return nil }
                current = next
            }
            for idx in indices {
                guard let arr = current as? [Any], idx >= 0, idx < arr.count else { return nil }
                current = arr[idx]
            }
        }
        return current
    }

    /// "foo[0][1]" -> ("foo", [0, 1]); "[2]" -> (nil, [2]); "foo" -> ("foo", [])
    private static func parseSegment(_ segment: String) -> (String?, [Int]) {
        var key: String? = nil
        var indices: [Int] = []
        var chars = Substring(segment)
        if let bracketStart = chars.firstIndex(of: "[") {
            let keyPart = String(chars[chars.startIndex..<bracketStart])
            if !keyPart.isEmpty { key = keyPart }
            chars = chars[bracketStart...]
            while let open = chars.firstIndex(of: "["), let close = chars.firstIndex(of: "]") {
                let numStr = chars[chars.index(after: open)..<close]
                if let n = Int(numStr) { indices.append(n) }
                chars = chars[chars.index(after: close)...]
            }
        } else {
            key = segment
        }
        return (key, indices)
    }
}
