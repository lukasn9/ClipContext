import Foundation

struct ClipAction: Identifiable {
    let id: String
    let label: String
    let systemImage: String
    let transform: (String) -> String
}

let allActions: [ClipAction] = [
    ClipAction(id: "trimWhitespace",    label: String(localized: "Trim Whitespace"),        systemImage: "arrow.left.and.right",               transform: { $0.trimmingCharacters(in: .whitespacesAndNewlines) }),
    ClipAction(id: "lowercase",         label: String(localized: "Lowercase"),              systemImage: "textformat.size.smaller",            transform: { $0.lowercased() }),
    ClipAction(id: "capitalize",        label: String(localized: "Capitalize"),             systemImage: "textformat",                         transform: { $0.capitalized }),
    ClipAction(id: "extractURL",        label: String(localized: "Extract URL"),            systemImage: "link",                               transform: clipExtractFirstURL),
    ClipAction(id: "removeExtraSpaces", label: String(localized: "Remove extra spaces"),    systemImage: "space",                              transform: { $0.replacingOccurrences(of: " {2,}", with: " ", options: .regularExpression) }),
    ClipAction(id: "removeEmptyLines",  label: String(localized: "Remove empty lines"),     systemImage: "minus",                              transform: clipRemoveEmptyLines),
    ClipAction(id: "joinLines",         label: String(localized: "Join lines into one"),    systemImage: "arrow.down.left.and.arrow.up.right", transform: clipJoinLines),
    ClipAction(id: "linesToCSV",        label: String(localized: "Lines to CSV"),           systemImage: "tablecells",                         transform: clipLinesToCSV),
    ClipAction(id: "removeTracking",    label: String(localized: "Remove tracking params"), systemImage: "xmark.shield",                       transform: clipRemoveTrackingParameters),
    ClipAction(id: "translate",         label: String(localized: "Translate"),              systemImage: "translate",                          transform: { $0 }),
]

extension [ClipAction] {
    func action(id: String) -> ClipAction? { first { $0.id == id } }
}

// MARK: - Transform implementations

func clipExtractFirstURL(_ text: String) -> String {
    guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return text }
    let matches = detector.matches(in: text, range: NSRange(text.startIndex..., in: text))
    if let match = matches.first, let range = Range(match.range, in: text) {
        return String(text[range])
    }
    return text
}

func clipRemoveEmptyLines(_ text: String) -> String {
    text.components(separatedBy: .newlines)
        .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        .joined(separator: "\n")
}

func clipJoinLines(_ text: String) -> String {
    text.components(separatedBy: .newlines)
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
        .joined(separator: " ")
}

func clipLinesToCSV(_ text: String) -> String {
    text.components(separatedBy: .newlines)
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
        .joined(separator: ", ")
}

func clipRemoveTrackingParameters(_ text: String) -> String {
    let trackingParams: Set<String> = [
        "utm_source", "utm_medium", "utm_campaign", "utm_term", "utm_content", "utm_id",
        "fbclid", "gclid", "dclid", "msclkid", "igshid", "mc_cid", "mc_eid", "_ga", "_gl"
    ]
    guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return text }
    let matches = detector.matches(in: text, range: NSRange(text.startIndex..., in: text))
    var result = text
    for match in matches.reversed() {
        guard let range = Range(match.range, in: text),
              let url = match.url,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { continue }
        components.queryItems = components.queryItems?.filter { !trackingParams.contains($0.name.lowercased()) }
        if components.queryItems?.isEmpty == true { components.queryItems = nil }
        guard let cleanURL = components.url?.absoluteString else { continue }
        result.replaceSubrange(range, with: cleanURL)
    }
    return result
}
