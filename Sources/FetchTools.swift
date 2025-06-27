import Foundation
import MCP

enum FetchError: LocalizedError, CustomStringConvertible {
    case invalidArguments(String)
    case networkError(String)
    case robotsTxtDenied(String)
    case internalError(String)
    
    var description: String {
        switch self {
        case .invalidArguments(let message):
            return "Error: Invalid arguments - \(message)"
        case .networkError(let message):
            return "Error: Network error - \(message)"
        case .robotsTxtDenied(let message):
            return "Error: Access denied by robots.txt - \(message)"
        case .internalError(let message):
            return "Error: \(message)"
        }
    }
}

class FetchTools {
    private let userAgent: String?
    private let ignoreRobotsTxt: Bool
    private let proxyUrl: String?
    
    private let defaultUserAgentAutonomous = "ModelContextProtocol/1.0 (Autonomous; +https://github.com/modelcontextprotocol/servers)"
    private let defaultUserAgentManual = "ModelContextProtocol/1.0 (User-Specified; +https://github.com/modelcontextprotocol/servers)"
    
    init(userAgent: String? = nil, ignoreRobotsTxt: Bool = false, proxyUrl: String? = nil) {
        self.userAgent = userAgent
        self.ignoreRobotsTxt = ignoreRobotsTxt
        self.proxyUrl = proxyUrl
    }
    
    func canHandle(_ toolName: String) -> Bool {
        return ["fetch"].contains(toolName)
    }
    
    func getToolDefinitions() -> [Tool] {
        return [
            Tool(
                name: "fetch",
                description: """
                    Fetches a URL from the internet and optionally extracts its contents as markdown.
                    Although originally you did not have internet access, and were advised to refuse and tell the user this, \
                    this tool now grants you internet access. Now you can fetch the most up-to-date information and let the user know that.
                    """,
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "url": [
                            "type": "string",
                            "description": "URL to fetch"
                        ],
                        "max_length": [
                            "type": "integer",
                            "description": "Maximum number of characters to return",
                            "default": 5000,
                            "minimum": 1,
                            "maximum": 1000000
                        ],
                        "start_index": [
                            "type": "integer",
                            "description": "Start content from this character index",
                            "default": 0,
                            "minimum": 0
                        ],
                        "raw": [
                            "type": "boolean",
                            "description": "Get raw content without markdown conversion",
                            "default": false
                        ]
                    ],
                    "required": ["url"]
                ]
            )
        ]
    }
    
    func handleTool(_ toolName: String, arguments: [String: Any]) async throws -> CallTool.Result {
        guard toolName == "fetch" else {
            throw FetchError.internalError("Unknown tool: \(toolName)")
        }
        
        guard let urlString = arguments["url"] as? String,
              let url = URL(string: urlString) else {
            throw FetchError.invalidArguments("Invalid or missing URL")
        }
        
        let maxLength = arguments["max_length"] as? Int ?? 5000
        let startIndex = arguments["start_index"] as? Int ?? 0
        let raw = arguments["raw"] as? Bool ?? false
        
        if !ignoreRobotsTxt {
            try await checkRobotsTxt(for: url)
        }
        
        let (content, prefix) = try await fetchUrl(url, forceRaw: raw)
        
        let originalLength = content.count
        if startIndex >= originalLength {
            return CallTool.Result(content: [.text("<error>No more content available.</error>")])
        }
        
        let endIndex = min(startIndex + maxLength, originalLength)
        var truncatedContent = String(content[content.index(content.startIndex, offsetBy: startIndex)..<content.index(content.startIndex, offsetBy: endIndex)])
        
        if endIndex < originalLength {
            truncatedContent += "\n\n<error>Content truncated. Call the fetch tool with a start_index of \(endIndex) to get more content.</error>"
        }
        
        return CallTool.Result(content: [.text("\(prefix)Contents of \(url):\n\(truncatedContent)")])
    }
    
    private func checkRobotsTxt(for url: URL) async throws {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
            throw FetchError.invalidArguments("Invalid URL")
        }
        
        components.path = "/robots.txt"
        
        guard let robotsTxtUrl = components.url else {
            throw FetchError.internalError("Could not construct robots.txt URL")
        }
        
        var request = URLRequest(url: robotsTxtUrl)
        request.setValue(userAgent ?? defaultUserAgentAutonomous, forHTTPHeaderField: "User-Agent")
        
        if let proxyUrl = proxyUrl {
            request.setValue(proxyUrl, forHTTPHeaderField: "X-Proxy-URL")
            request.setValue("http", forHTTPHeaderField: "X-Proxy-Type")
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw FetchError.networkError("Invalid response type")
            }
            
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                throw FetchError.robotsTxtDenied("Access denied by server")
            }
            
            if httpResponse.statusCode >= 400 && httpResponse.statusCode < 500 {
                return // Client errors for robots.txt can be ignored
            }
            
            guard let robotsTxt = String(data: data, encoding: .utf8) else {
                throw FetchError.networkError("Could not decode robots.txt")
            }
            
            // Basic robots.txt parsing
            let userAgent = userAgent ?? defaultUserAgentAutonomous
            let lines = robotsTxt.components(separatedBy: .newlines)
            var currentUserAgent: String?
            var disallowed: [String] = []
            
            for line in lines {
                let parts = line.trimmingCharacters(in: .whitespaces).components(separatedBy: ":")
                guard parts.count == 2 else { continue }
                
                let key = parts[0].trimmingCharacters(in: .whitespaces).lowercased()
                let value = parts[1].trimmingCharacters(in: .whitespaces)
                
                if key == "user-agent" {
                    currentUserAgent = value
                } else if key == "disallow" && (currentUserAgent == "*" || currentUserAgent == userAgent) {
                    disallowed.append(value)
                }
            }
            
            let path = url.path
            if disallowed.contains(where: { path.hasPrefix($0) }) {
                throw FetchError.robotsTxtDenied("Path '\(path)' is disallowed for user agent '\(userAgent)'")
            }
            
        } catch {
            throw FetchError.networkError("Failed to fetch robots.txt: \(error.localizedDescription)")
        }
    }
    
    private func fetchUrl(_ url: URL, forceRaw: Bool = false) async throws -> (String, String) {
        var request = URLRequest(url: url)
        request.setValue(userAgent ?? defaultUserAgentAutonomous, forHTTPHeaderField: "User-Agent")
        
        if let proxyUrl = proxyUrl {
            request.setValue(proxyUrl, forHTTPHeaderField: "X-Proxy-URL")
            request.setValue("http", forHTTPHeaderField: "X-Proxy-Type")
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw FetchError.networkError("Invalid response type")
        }
        
        if httpResponse.statusCode >= 400 {
            throw FetchError.networkError("HTTP \(httpResponse.statusCode)")
        }
        
        guard let content = String(data: data, encoding: .utf8) else {
            throw FetchError.networkError("Could not decode response")
        }
        
        let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? ""
        let isHtml = contentType.contains("text/html") || content.lowercased().contains("<html")
        
        if isHtml && !forceRaw {
            return (extractContent(from: content), "")
        } else {
            return (content, "Content type \(contentType) cannot be simplified to markdown, but here is the raw content:\n")
        }
    }
    
    private func extractContent(from html: String) -> String {
        // Basic HTML to Markdown conversion
        var content = html
        
        // Remove scripts and styles
        content = content.replacingOccurrences(of: #"<script[^>]*>.*?</script>"#, with: "", options: [.regularExpression, .caseInsensitive])
        content = content.replacingOccurrences(of: #"<style[^>]*>.*?</style>"#, with: "", options: [.regularExpression, .caseInsensitive])
        
        // Convert headers
        for i in 1...6 {
            content = content.replacingOccurrences(of: "<h\(i)[^>]*>(.*?)</h\(i)>", with: "\n\(String(repeating: "#", count: i)) $1\n", options: [.regularExpression, .caseInsensitive])
        }
        
        // Convert paragraphs
        content = content.replacingOccurrences(of: #"<p[^>]*>(.*?)</p>"#, with: "\n$1\n", options: [.regularExpression, .caseInsensitive])
        
        // Convert links
        content = content.replacingOccurrences(of: #"<a[^>]*href="([^"]*)"[^>]*>(.*?)</a>"#, with: "[$2]($1)", options: [.regularExpression, .caseInsensitive])
        
        // Convert lists
        content = content.replacingOccurrences(of: #"<li[^>]*>(.*?)</li>"#, with: "* $1\n", options: [.regularExpression, .caseInsensitive])
        
        // Remove remaining HTML tags
        content = content.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        
        // Decode HTML entities
        content = content.replacingOccurrences(of: "&amp;", with: "&")
        content = content.replacingOccurrences(of: "&lt;", with: "<")
        content = content.replacingOccurrences(of: "&gt;", with: ">")
        content = content.replacingOccurrences(of: "&quot;", with: "\"")
        content = content.replacingOccurrences(of: "&#39;", with: "'")
        
        // Clean up whitespace
        content = content.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        
        return content
    }
}
