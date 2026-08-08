import Foundation




enum DiagnosticsRedactor {
    


    // MARK: - Public

    static func redact(_ text: String) -> String {

        var result = text

        result = redactContainerIdentifiers(in: result)
        if result.contains("/Users/") ||
           result.contains("/Library/") {

            result = redactUserPaths(in: result)

        }

        result = redactKnownLocations(in: result)
        result = redactBundleIdentifiers(in: result)
        if result.contains(".") {

            result = redactKnownFileNames(in: result)

        }
        if result.contains("Task") ||
           result.contains("task") ||
           result.contains("title") {

            result = redactTaskFields(in: result)

        }
        
                
        return result
    }
    
    private static func redactKnownLocations(
        in text: String
    ) -> String {

        var result = text

        let mappings: [(String, String)] = [

            ("TaskAttachments", "[Cloud Attachments]"),
            ("TaskAttachments_Trash", "[Cloud Trash]"),
            ("DocumentAssets", "[Document Assets]"),
            ("WalletAssets", "[Wallet Assets]"),
            ("GroupContainersAlias", "[App Group]"),
            ("Mobile Documents", "[Mobile Documents]"),
            ("Library/Containers", "[Sandbox]")

        ]

        for (source, destination) in mappings {

            result = result.replacingOccurrences(
                of: source,
                with: destination
            )

        }

        return result

    }
    
    
    private static func redactKnownFileNames(
        in text: String
    ) -> String {

        var result = text

        let pattern = #"[^\s/]+\.(jpg|jpeg|png|heic|gif|pdf|doc|docx|xls|xlsx|zip|txt|m4a|mp3|mov|mp4)"#

        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive]
        ) else {
            return result
        }

        let matches = regex.matches(
            in: result,
            range: NSRange(result.startIndex..., in: result)
        )

        for match in matches.reversed() {

            guard
                let range = Range(match.range, in: result)
            else {
                continue
            }

            let original = String(result[range])
            let replacement = redactFileName(original)

            result.replaceSubrange(
                range,
                with: replacement
            )

        }

        return result

    }
    
    
    private static func redactTaskFields(
        in text: String
    ) -> String {

        var result = text

        let fields = [
            "Task:",
            "Task :",
            "Task Title:",
            "Task Title :",
            "task=",
            "task =",
            "title=",
            "title ="
        ]

        for field in fields {

            guard let range = result.range(of: field) else {
                continue
            }

            let suffix = result[range.upperBound...]

            guard let end = suffix.firstIndex(of: "\n") else {
                result.replaceSubrange(
                    range.upperBound...,
                    with: " [redacted]"
                )
                continue
            }

            result.replaceSubrange(
                range.upperBound..<end,
                with: " [redacted]"
            )

        }

        return result

    }
    
    
    
    
    
}

// MARK: - Private

private extension DiagnosticsRedactor {

    static func redactContainerIdentifiers(
        in text: String
    ) -> String {

        text
            .replacingOccurrences(
                of: "iCloud~corradini~armando~",
                with: "iCloud~***~***~"
            )
            .replacingOccurrences(
                of: "iCloud.corradini.armando.",
                with: "iCloud.***.***."
            )

    }

    static func redactBundleIdentifiers(
        in text: String
    ) -> String {

        text
            .replacingOccurrences(
                of: "corradini.armando.",
                with: "***.***."
            )

    }

    static func redactUserPaths(
        in text: String
    ) -> String {

        var result = text

        let replacements: [(String, String)] = [

            ("/Library/Mobile Documents/", "/[Mobile Documents]/"),

            ("/Library/GroupContainersAlias/", "/[App Group]/"),

            ("/Library/Containers/", "/[Sandbox]/")

        ]

        for (source, destination) in replacements {

            result = result.replacingOccurrences(
                of: source,
                with: destination
            )

        }

        let pattern = #"/Users/[^/]+"#

        if let regex = try? NSRegularExpression(
            pattern: pattern
        ) {

            result = regex.stringByReplacingMatches(
                in: result,
                range: NSRange(
                    result.startIndex...,
                    in: result
                ),
                withTemplate: "/Users/***"
            )

        }

        return result

    }

    static func redactFileName(
        _ fileName: String
    ) -> String {

        guard !fileName.isEmpty else {
            return fileName
        }

        let ext = URL(fileURLWithPath: fileName)
            .pathExtension

        if ext.isEmpty {
            return "[File]"
        }

        return "[File].\(ext.lowercased())"

    }
    
    
}
