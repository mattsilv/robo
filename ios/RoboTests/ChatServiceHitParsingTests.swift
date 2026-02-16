import XCTest
@testable import Robo

#if canImport(FoundationModels)
@available(iOS 26, *)
final class ChatServiceHitParsingTests: XCTestCase {

    func testParseHitResults_BulletFormat() {
        // Test the original bullet format that the tool outputs
        let content = """
        Created availability poll: Ski Trip

        • Vince: https://robo.app/hit/abc123
        • E: https://robo.app/hit/def456
        • Turtle: https://robo.app/hit/ghi789

        Share each link with the corresponding person. They can pick their available times in their browser.
        """

        let results = extractHitResults(from: content)

        XCTAssertEqual(results.count, 3)
        XCTAssertEqual(results[0].name, "Vince")
        XCTAssertEqual(results[0].url, "https://robo.app/hit/abc123")
        XCTAssertEqual(results[1].name, "E")
        XCTAssertEqual(results[1].url, "https://robo.app/hit/def456")
        XCTAssertEqual(results[2].name, "Turtle")
        XCTAssertEqual(results[2].url, "https://robo.app/hit/ghi789")
    }

    func testParseHitResults_MarkdownFormat() {
        // Test if the model returns markdown-formatted links
        let content = """
        I've created an availability poll for your ski trip!

        - [Vince](https://robo.app/hit/abc123)
        - [E](https://robo.app/hit/def456)
        - [Turtle](https://robo.app/hit/ghi789)

        Share these links with each person.
        """

        let results = extractHitResults(from: content)

        XCTAssertGreaterThan(results.count, 0, "Should extract URLs even in markdown format")
    }

    func testParseHitResults_PlainTextFormat() {
        // Test if the model just includes URLs without bullets
        let content = """
        Here are the links:

        Vince: https://robo.app/hit/abc123
        E: https://robo.app/hit/def456
        Turtle: https://robo.app/hit/ghi789
        """

        let results = extractHitResults(from: content)

        XCTAssertGreaterThan(results.count, 0, "Should extract URLs even in plain text format")
    }

    // Helper function that mimics the parsing logic
    private func extractHitResults(from content: String) -> [(name: String, url: String)] {
        var results: [(name: String, url: String)] = []

        // Strategy 1: Try regex to find all robo.app/hit URLs with context
        let pattern = "(?:•|\\-|\\*|\\d+\\.)\\s*([^:\\n]+):\\s*(https://robo\\.app/hit/[a-zA-Z0-9\\-]+)"
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let nsContent = content as NSString
            let matches = regex.matches(in: content, range: NSRange(location: 0, length: nsContent.length))

            for match in matches {
                if match.numberOfRanges == 3 {
                    let nameRange = match.range(at: 1)
                    let urlRange = match.range(at: 2)

                    if nameRange.location != NSNotFound, urlRange.location != NSNotFound {
                        let name = nsContent.substring(with: nameRange).trimmingCharacters(in: .whitespaces)
                        let url = nsContent.substring(with: urlRange)
                        results.append((name: name, url: url))
                    }
                }
            }
        }

        // Strategy 2: Fallback - find any robo.app/hit URLs
        if results.isEmpty {
            let urlPattern = "https://robo\\.app/hit/[a-zA-Z0-9\\-]+"
            if let urlRegex = try? NSRegularExpression(pattern: urlPattern, options: []) {
                let nsContent = content as NSString
                let urlMatches = urlRegex.matches(in: content, range: NSRange(location: 0, length: nsContent.length))

                for urlMatch in urlMatches {
                    let url = nsContent.substring(with: urlMatch.range)

                    // Try to find a name near this URL
                    let searchStart = max(0, urlMatch.range.location - 50)
                    let searchRange = NSRange(location: searchStart, length: urlMatch.range.location - searchStart)
                    let context = nsContent.substring(with: searchRange)

                    let lines = context.components(separatedBy: CharacterSet.newlines)
                    if let lastLine = lines.last {
                        let cleaned = lastLine
                            .replacingOccurrences(of: "•", with: "")
                            .replacingOccurrences(of: "-", with: "")
                            .replacingOccurrences(of: "*", with: "")
                            .replacingOccurrences(of: ":", with: "")
                            .trimmingCharacters(in: .whitespaces)

                        let name = cleaned.isEmpty ? "Link" : cleaned
                        results.append((name: name, url: url))
                    }
                }
            }
        }

        return results
    }
}
#endif
