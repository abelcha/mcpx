import Foundation
import MCP

enum FilesystemError: Swift.Error, CustomStringConvertible {
    case invalidArguments(String)
    case accessDenied(String)
    case fileNotFound(String)
    case internalError(String)
    
    var description: String {
        switch self {
        case .invalidArguments(let message):
            return "Error: Invalid arguments for \(message)"
        case .accessDenied(let message):
            return "Error: \(message)"
        case .fileNotFound(let message):
            return "Error: \(message)"
        case .internalError(let message):
            return "Error: \(message)"
        }
    }
}

class FilesystemTools {
    private let allowedDirectories: [String]
    
    init(allowedDirectories: [String]) {
        self.allowedDirectories = allowedDirectories
    }
    
    // Helper functions for path handling
    static func expandTilde(_ filepath: String) -> String {
        if filepath.hasPrefix("~/") || filepath == "~" {
            return (FileManager.default.homeDirectoryForCurrentUser.path as NSString)
                .appendingPathComponent(String(filepath.dropFirst(2)))
        }
        return filepath
    }
    
    static func isGitRepository(at path: String) -> Bool {
        let gitDirPath = (path as NSString).appendingPathComponent(".git")
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: gitDirPath, isDirectory: &isDirectory) && isDirectory.boolValue
    }
    
    private func normalizePath(_ p: String) -> String {
        return (p as NSString).standardizingPath
    }
    
    private func isAbsolutePath(_ path: String) -> Bool {
        return (path as NSString).isAbsolutePath
    }
    
    private func resolvePath(_ base: String, _ relative: String) -> String {
        return (base as NSString).appendingPathComponent(relative)
    }
    
    func canHandle(_ toolName: String) -> Bool {
        return [
            "read_file",
            "read_multiple_files", 
            "write_file",
            "edit_file",
            "create_directory",
            "list_directory",
            "list_directory_with_sizes",
            "directory_tree",
            "move_file",
            "search_files",
            "get_file_info",
            "list_allowed_directories"
        ].contains(toolName)
    }
    
    func getToolDefinitions() -> [Tool] {
        return [
            Tool(
                name: "read_file",
                description: "Read the complete contents of a file from the file system. Handles various text encodings and provides detailed error messages if the file cannot be read. Use this tool when you need to examine the contents of a single file. Use the 'head' parameter to read only the first N lines of a file, or the 'tail' parameter to read only the last N lines of a file. Only works within allowed directories.",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "path": ["type": "string", "description": "Path to the file to read"],
                        "tail": ["type": "integer", "description": "If provided, returns only the last N lines of the file"],
                        "head": ["type": "integer", "description": "If provided, returns only the first N lines of the file"]
                    ],
                    "required": ["path"]
                ]
            ),
            Tool(
                name: "read_multiple_files",
                description: "Read the contents of multiple files simultaneously. This is more efficient than reading files one by one when you need to analyze or compare multiple files. Each file's content is returned with its path as a reference. Failed reads for individual files won't stop the entire operation. Only works within allowed directories.",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "paths": [
                            "type": "array",
                            "items": ["type": "string"],
                            "description": "Array of file paths to read"
                        ]
                    ],
                    "required": ["paths"]
                ]
            ),
            Tool(
                name: "write_file",
                description: "Create a new file or completely overwrite an existing file with new content. Use with caution as it will overwrite existing files without warning. Handles text content with proper encoding. Only works within allowed directories.",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "path": ["type": "string", "description": "Path to the file to write"],
                        "content": ["type": "string", "description": "Content to write to the file"]
                    ],
                    "required": ["path", "content"]
                ]
            ),
            Tool(
                name: "edit_file",
                description: "Make line-based edits to a text file. Each edit replaces exact line sequences with new content. Returns a git-style diff showing the changes made. Only works within allowed directories.",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "path": ["type": "string", "description": "Path to the file to edit"],
                        "edits": [
                            "type": "array",
                            "items": [
                                "type": "object",
                                "properties": [
                                    "oldText": ["type": "string", "description": "Text to search for - must match exactly"],
                                    "newText": ["type": "string", "description": "Text to replace with"]
                                ],
                                "required": ["oldText", "newText"]
                            ]
                        ],
                        "dryRun": ["type": "boolean", "description": "Preview changes using git-style diff format", "default": false]
                    ],
                    "required": ["path", "edits"]
                ]
            ),
            Tool(
                name: "create_directory",
                description: "Create a new directory or ensure a directory exists. Can create multiple nested directories in one operation. If the directory already exists, this operation will succeed silently. Perfect for setting up directory structures for projects or ensuring required paths exist. Only works within allowed directories.",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "path": ["type": "string", "description": "Path to the directory to create"]
                    ],
                    "required": ["path"]
                ]
            ),
            Tool(
                name: "list_directory",
                description: "Get a detailed listing of all files and directories in a specified path. Results clearly distinguish between files and directories with [FILE] and [DIR] prefixes. This tool is essential for understanding directory structure and finding specific files within a directory. Only works within allowed directories.",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "path": ["type": "string", "description": "Path to the directory to list"]
                    ],
                    "required": ["path"]
                ]
            ),
            Tool(
                name: "list_directory_with_sizes",
                description: "Get a detailed listing of all files and directories in a specified path, including sizes. Results clearly distinguish between files and directories with [FILE] and [DIR] prefixes. This tool is useful for understanding directory structure and finding specific files within a directory. Only works within allowed directories.",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "path": ["type": "string", "description": "Path to the directory to list"],
                        "sortBy": ["type": "string", "enum": ["name", "size"], "description": "Sort entries by name or size", "default": "name"]
                    ],
                    "required": ["path"]
                ]
            ),
            Tool(
                name: "directory_tree",
                description: "Get a recursive tree view of files and directories as a JSON structure. Each entry includes 'name', 'type' (file/directory), and 'children' for directories. Files have no children array, while directories always have a children array (which may be empty). The output is formatted with 2-space indentation for readability. Only works within allowed directories.",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "path": ["type": "string", "description": "Path to the directory to get tree for"]
                    ],
                    "required": ["path"]
                ]
            ),
            Tool(
                name: "move_file",
                description: "Move or rename files and directories. Can move files between directories and rename them in a single operation. If the destination exists, the operation will fail. Works across different directories and can be used for simple renaming within the same directory. Both source and destination must be within allowed directories.",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "source": ["type": "string", "description": "Source path to move from"],
                        "destination": ["type": "string", "description": "Destination path to move to"]
                    ],
                    "required": ["source", "destination"]
                ]
            ),
            Tool(
                name: "search_files",
                description: "Recursively search for files and directories matching a pattern. Searches through all subdirectories from the starting path. The search is case-insensitive and matches partial names. Returns full paths to all matching items. Great for finding files when you don't know their exact location. Only searches within allowed directories.",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "path": ["type": "string", "description": "Starting path for the search"],
                        "pattern": ["type": "string", "description": "Search pattern to match against file/directory names"],
                        "excludePatterns": [
                            "type": "array",
                            "items": ["type": "string"],
                            "description": "Patterns to exclude from search results",
                            "default": []
                        ]
                    ],
                    "required": ["path", "pattern"]
                ]
            ),
            Tool(
                name: "get_file_info",
                description: "Retrieve detailed metadata about a file or directory. Returns comprehensive information including size, creation time, last modified time, permissions, and type. This tool is perfect for understanding file characteristics without reading the actual content. Only works within allowed directories.",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "path": ["type": "string", "description": "Path to get information about"]
                    ],
                    "required": ["path"]
                ]
            ),
            Tool(
                name: "list_allowed_directories",
                description: "Returns the list of directories that this server is allowed to access. Use this to understand which directories are available before trying to access files.",
                inputSchema: [
                    "type": "object",
                    "properties": [:],
                    "required": []
                ]
            )
        ]
    }
    
    func handleTool(_ toolName: String, arguments: [String: Any]) async throws -> CallTool.Result {
        switch toolName {
        case "read_file":
            return try await readFile(arguments)
        case "read_multiple_files":
            return try await readMultipleFiles(arguments)
        case "write_file":
            return try await writeFile(arguments)
        case "edit_file":
            return try await editFile(arguments)
        case "create_directory":
            return try await createDirectory(arguments)
        case "list_directory":
            return try await listDirectory(arguments)
        case "list_directory_with_sizes":
            return try await listDirectoryWithSizes(arguments)
        case "directory_tree":
            return try await directoryTree(arguments)
        case "get_file_info":
            return try await getFileInfo(arguments)
        case "move_file":
            return try await moveFile(arguments)
        case "search_files":
            return try await searchFiles(arguments)
        case "list_allowed_directories":
            return try await listAllowedDirectories(arguments)
        default:
            throw FilesystemError.internalError("Unknown filesystem tool: \(toolName)")
        }
    }
}

// MARK: - Path Validation

extension FilesystemTools {
    private func validatePath(_ requestedPath: String) throws -> String {
        let expandedPath = FilesystemTools.expandTilde(requestedPath)
        let absolute = isAbsolutePath(expandedPath) ? 
            expandedPath :
            resolvePath(FileManager.default.currentDirectoryPath, expandedPath)
        
        let normalizedRequested = normalizePath(absolute)
        
        // Check if path is within allowed directories
        let isAllowed = allowedDirectories.contains { dir in 
            normalizedRequested.hasPrefix(dir)
        }
        
        guard isAllowed else {
            throw FilesystemError.accessDenied("Access denied - path outside allowed directories: \(absolute) not in \(allowedDirectories.joined(separator: ", "))")
        }
        
        // Handle symlinks by checking their real path
        do {
            let realPath = try FileManager.default.destinationOfSymbolicLink(atPath: absolute)
            let normalizedReal = URL(fileURLWithPath: realPath).standardized.path
            let isRealPathAllowed = allowedDirectories.contains { allowedDir in
                normalizedReal.hasPrefix(allowedDir)
            }
            if !isRealPathAllowed {
                throw FilesystemError.accessDenied("Access denied - symlink target outside allowed directories")
            }
            return realPath
        } catch CocoaError.fileReadNoSuchFile {
            // For new files that don't exist yet, verify parent directory
            let parentDir = URL(fileURLWithPath: absolute).deletingLastPathComponent().path
            do {
                let realParentPath = try FileManager.default.destinationOfSymbolicLink(atPath: parentDir)
                let normalizedParent = URL(fileURLWithPath: realParentPath).standardized.path
                let isParentAllowed = allowedDirectories.contains { allowedDir in
                    normalizedParent.hasPrefix(allowedDir)
                }
                if !isParentAllowed {
                    throw FilesystemError.accessDenied("Access denied - parent directory outside allowed directories")
                }
                return absolute
            } catch {
                if FileManager.default.fileExists(atPath: parentDir) {
                    return absolute
                } else {
                    throw FilesystemError.fileNotFound("Parent directory does not exist: \(parentDir)")
                }
            }
        } catch {
            // Not a symlink, return the original path
            return absolute
        }
    }
}

// MARK: - Tool Implementations

extension FilesystemTools {
    private func readFile(_ arguments: [String: Any]) async throws -> CallTool.Result {
        guard let path = arguments["path"] as? String else {
            throw FilesystemError.invalidArguments("Missing required 'path' parameter")
        }
        
        let validPath = try validatePath(path)
        let head = arguments["head"] as? Int
        let tail = arguments["tail"] as? Int
        
        if head != nil && tail != nil {
            throw FilesystemError.invalidArguments("Cannot specify both head and tail parameters simultaneously")
        }
        
        do {
            if let tail = tail {
                let content = try await tailFile(validPath, numLines: tail)
                return CallTool.Result(
                     content: [.text(content)]
                 )
            } else if let head = head {
                let content = try await headFile(validPath, numLines: head)
                return CallTool.Result(
                     content: [.text(content)]
                 )
            } else {
                let content = try String(contentsOfFile: validPath, encoding: .utf8)
                return CallTool.Result(
                    content: [.text(content)]
                )
            }
        } catch {
            throw FilesystemError.fileNotFound("Could not read file: \(error.localizedDescription)")
        }
    }
    
    private func readMultipleFiles(_ arguments: [String: Any]) async throws -> CallTool.Result {
        guard let paths = arguments["paths"] as? [String] else {
            throw FilesystemError.invalidArguments("Missing required 'paths' parameter")
        }
        
        var results: [String] = []
        
        for path in paths {
            do {
                let validPath = try validatePath(path)
                let content = try String(contentsOfFile: validPath, encoding: .utf8)
                results.append("\(path):\n\(content)\n")
            } catch {
                results.append("\(path): Error - \(error.localizedDescription)")
            }
        }
        
        return CallTool.Result(
             content: [.text(results.joined(separator: "\n---\n"))]
         )
    }
    
    private func writeFile(_ arguments: [String: Any]) async throws -> CallTool.Result {
        guard let path = arguments["path"] as? String,
              let content = arguments["content"] as? String else {
            throw FilesystemError.invalidArguments("Missing required 'path' or 'content' parameters")
        }
        
        let validPath = try validatePath(path)
        
        do {
            try content.write(toFile: validPath, atomically: true, encoding: .utf8)
            return CallTool.Result(
                 content: [.text("Successfully wrote to \(path)")]
             )
        } catch {
            throw FilesystemError.internalError("Could not write file: \(error.localizedDescription)")
        }
    }
    
    private func editFile(_ arguments: [String: Any]) async throws -> CallTool.Result {
        guard let path = arguments["path"] as? String,
              let editsArray = arguments["edits"] as? [[String: Any]] else {
            throw FilesystemError.invalidArguments("Missing required 'path' or 'edits' parameters")
        }
        
        let dryRun = arguments["dryRun"] as? Bool ?? false
        let validPath = try validatePath(path)
        
        // Parse edits
        var edits: [(oldText: String, newText: String)] = []
        for editDict in editsArray {
            guard let oldText = editDict["oldText"] as? String,
                  let newText = editDict["newText"] as? String else {
                throw FilesystemError.invalidArguments("Invalid edit format")
            }
            edits.append((oldText: oldText, newText: newText))
        }
        
        do {
            let originalContent = try String(contentsOfFile: validPath, encoding: .utf8)
            let modifiedContent = try applyEdits(to: originalContent, edits: edits)
            
            if !dryRun {
                try modifiedContent.write(toFile: validPath, atomically: true, encoding: .utf8)
            }
            
            let diff = createDiff(original: originalContent, modified: modifiedContent, filename: path)
            return CallTool.Result(
                 content: [.text(diff)]
             )
        } catch {
            throw FilesystemError.internalError("Could not edit file: \(error.localizedDescription)")
        }
    }
    
    private func createDirectory(_ arguments: [String: Any]) async throws -> CallTool.Result {
        guard let path = arguments["path"] as? String else {
            throw FilesystemError.invalidArguments("Missing required 'path' parameter")
        }
        
        let validPath = try validatePath(path)
        
        do {
            try FileManager.default.createDirectory(atPath: validPath, withIntermediateDirectories: true)
            return CallTool.Result(
                 content: [.text("Successfully created directory \(path)")]
             )
        } catch {
            throw FilesystemError.internalError("Could not create directory: \(error.localizedDescription)")
        }
    }
    
    private func listDirectory(_ arguments: [String: Any]) async throws -> CallTool.Result {
        guard let path = arguments["path"] as? String else {
            throw MCPXError.invalidArguments("Missing required 'path' parameter")
        }
        
        let validPath = try validatePath(path)
        
        do {
            let contents = try FileManager.default.contentsOfDirectory(atPath: validPath)
            var formatted: [String] = []
            
            for item in contents.sorted() {
                let itemPath = (validPath as NSString).appendingPathComponent(item)
                var isDirectory: ObjCBool = false
                FileManager.default.fileExists(atPath: itemPath, isDirectory: &isDirectory)
                
                let prefix = isDirectory.boolValue ? "[DIR]" : "[FILE]"
                formatted.append("\(prefix) \(item)")
            }
            
            return CallTool.Result(
                 content: [.text(formatted.joined(separator: "\n"))]
             )
        } catch {
            throw FilesystemError.internalError("Could not list directory: \(error.localizedDescription)")
        }
    }
    
    private func directoryTree(_ arguments: [String: Any]) async throws -> CallTool.Result {
        guard let path = arguments["path"] as? String else {
            throw MCPXError.invalidArguments("Missing required 'path' parameter")
        }
        
        let validPath = try validatePath(path)
        
        do {
            let tree = try buildDirectoryTree(at: validPath)
            let jsonData = try JSONSerialization.data(withJSONObject: tree, options: [.prettyPrinted])
            let jsonString = String(data: jsonData, encoding: .utf8) ?? "[]"
            
            return CallTool.Result(
                 content: [.text(jsonString)]
             )
        } catch {
            throw FilesystemError.internalError("Could not build directory tree: \(error.localizedDescription)")
        }
    }
    
    private func moveFile(_ arguments: [String: Any]) async throws -> CallTool.Result {
        guard let source = arguments["source"] as? String,
              let destination = arguments["destination"] as? String else {
            throw MCPXError.invalidArguments("Missing required 'source' or 'destination' parameters")
        }
        
        let validSource = try validatePath(source)
        let validDestination = try validatePath(destination)
        
        do {
            try FileManager.default.moveItem(atPath: validSource, toPath: validDestination)
            return CallTool.Result(
                 content: [.text("Successfully moved \(source) to \(destination)")]
             )
        } catch {
            throw FilesystemError.internalError("Could not move file: \(error.localizedDescription)")
        }
    }
    
    private func searchFiles(_ arguments: [String: Any]) async throws -> CallTool.Result {
        guard let path = arguments["path"] as? String,
              let pattern = arguments["pattern"] as? String else {
            throw MCPXError.invalidArguments("Missing required 'path' or 'pattern' parameters")
        }
        
        let excludePatterns = arguments["excludePatterns"] as? [String] ?? []
        let validPath = try validatePath(path)
        
        do {
            let results = try searchFilesRecursively(at: validPath, pattern: pattern, excludePatterns: excludePatterns)
            let resultText = results.isEmpty ? "No matches found" : results.joined(separator: "\n")
            
            return CallTool.Result(
                 content: [.text(resultText)]
             )
        } catch {
            throw FilesystemError.internalError("Could not search files: \(error.localizedDescription)")
        }
    }
    
    private func getFileInfo(_ arguments: [String: Any]) async throws -> CallTool.Result {
        guard let path = arguments["path"] as? String else {
            throw MCPXError.invalidArguments("Missing required 'path' parameter")
        }
        
        let validPath = try validatePath(path)
        
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: validPath)
            let url = URL(fileURLWithPath: validPath)
            let resourceValues = try url.resourceValues(forKeys: [
                .isDirectoryKey,
                .isRegularFileKey,
                .fileSizeKey,
                .creationDateKey,
                .contentModificationDateKey,
                .contentAccessDateKey
            ])
            
            var info: [String] = []
            info.append("size: \(resourceValues.fileSize ?? 0)")
            info.append("created: \(resourceValues.creationDate?.description ?? "unknown")")
            info.append("modified: \(resourceValues.contentModificationDate?.description ?? "unknown")")
            info.append("accessed: \(resourceValues.contentAccessDate?.description ?? "unknown")")
            info.append("isDirectory: \(resourceValues.isDirectory ?? false)")
            info.append("isFile: \(resourceValues.isRegularFile ?? false)")
            
            if let posixPermissions = attributes[.posixPermissions] as? NSNumber {
                let permissions = String(format: "%o", posixPermissions.intValue)
                info.append("permissions: \(permissions)")
            }
            
            return CallTool.Result(
                 content: [.text(info.joined(separator: "\n"))]
             )
        } catch {
            throw FilesystemError.internalError("Could not get file info: \(error.localizedDescription)")
        }
    }
    
    private func listAllowedDirectories(_ arguments: [String: Any]) async throws -> CallTool.Result {
        let dirList = "Allowed directories:\n" + allowedDirectories.joined(separator: "\n")
        return CallTool.Result(
             content: [.text(dirList)]
         )
    }
}

// MARK: - Helper Functions

extension FilesystemTools {
    private func applyEdits(to content: String, edits: [(oldText: String, newText: String)]) throws -> String {
        var modifiedContent = content
        
        for edit in edits {
            guard modifiedContent.contains(edit.oldText) else {
                throw FilesystemError.invalidArguments("Could not find exact match for edit: \(edit.oldText)")
            }
            modifiedContent = modifiedContent.replacingOccurrences(of: edit.oldText, with: edit.newText)
        }
        
        return modifiedContent
    }
    
    private func createDiff(original: String, modified: String, filename: String) -> String {
        // Simple diff implementation - in a real implementation you might want a more sophisticated diff
        let originalLines = original.components(separatedBy: .newlines)
        let modifiedLines = modified.components(separatedBy: .newlines)
        
        var diff = "```diff\n"
        diff += "--- \(filename)\n"
        diff += "+++ \(filename)\n"
        
        let maxLines = max(originalLines.count, modifiedLines.count)
        for i in 0..<maxLines {
            let originalLine = i < originalLines.count ? originalLines[i] : ""
            let modifiedLine = i < modifiedLines.count ? modifiedLines[i] : ""
            
            if originalLine != modifiedLine {
                if !originalLine.isEmpty {
                    diff += "-\(originalLine)\n"
                }
                if !modifiedLine.isEmpty {
                    diff += "+\(modifiedLine)\n"
                }
            }
        }
        
        diff += "```\n"
        return diff
    }
    
    private func buildDirectoryTree(at path: String) throws -> [[String: Any]] {
        let contents = try FileManager.default.contentsOfDirectory(atPath: path)
        var tree: [[String: Any]] = []
        
        for item in contents.sorted() {
            let itemPath = (path as NSString).appendingPathComponent(item)
            var isDirectory: ObjCBool = false
            FileManager.default.fileExists(atPath: itemPath, isDirectory: &isDirectory)
            
            var entry: [String: Any] = [
                "name": item,
                "type": isDirectory.boolValue ? "directory" : "file"
            ]
            
            if isDirectory.boolValue {
                do {
                    let validItemPath = try validatePath(itemPath)
                    entry["children"] = try buildDirectoryTree(at: validItemPath)
                } catch {
                    // Skip directories we can't access
                    entry["children"] = []
                }
            }
            
            tree.append(entry)
        }
        
        return tree
    }
    
    private func searchFilesRecursively(at path: String, pattern: String, excludePatterns: [String]) throws -> [String] {
        var results: [String] = []
        let contents = try FileManager.default.contentsOfDirectory(atPath: path)
        
        for item in contents {
            let itemPath = (path as NSString).appendingPathComponent(item)
            
            // Check exclude patterns with glob pattern support
            let shouldExclude = excludePatterns.contains { excludePattern in
                let globPattern = excludePattern.contains("*") ? excludePattern : "**/\(excludePattern)/**"
                return matchesGlob(item, pattern: globPattern)
            }
            
            if shouldExclude {
                continue
            }
            
            // Check if item matches pattern
            if item.localizedCaseInsensitiveContains(pattern) {
                results.append(itemPath)
            }
            
            // Recurse into directories
            var isDirectory: ObjCBool = false
            FileManager.default.fileExists(atPath: itemPath, isDirectory: &isDirectory)
            
            if isDirectory.boolValue {
                do {
                    let validItemPath = try validatePath(itemPath)
                    let subResults = try searchFilesRecursively(at: validItemPath, pattern: pattern, excludePatterns: excludePatterns)
                    results.append(contentsOf: subResults)
                } catch {
                    // Skip directories we can't access
                    continue
                }
            }
        }
        
        return results
    }
    
    private func matchesGlob(_ string: String, pattern: String) -> Bool {
        // Simple glob pattern matching
        // Convert glob pattern to regex
        var regexPattern = pattern
            .replacingOccurrences(of: ".", with: "\\.")
            .replacingOccurrences(of: "*", with: ".*")
            .replacingOccurrences(of: "?", with: ".")
        
        // Handle ** for recursive directory matching
        regexPattern = regexPattern.replacingOccurrences(of: ".*.*/", with: "(.*/)?")
        
        do {
            let regex = try NSRegularExpression(pattern: "^\(regexPattern)$", options: [.caseInsensitive])
            let range = NSRange(location: 0, length: string.utf16.count)
            return regex.firstMatch(in: string, options: [], range: range) != nil
        } catch {
            // If regex fails, fall back to simple contains check
            return string.lowercased().contains(pattern.lowercased())
        }
    }
    
    private func headFile(_ path: String, numLines: Int) async throws -> String {
        let fileHandle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
        defer { fileHandle.closeFile() }
        
        var lines: [String] = []
        var buffer = ""
        let chunkSize = 1024
        
        while lines.count < numLines {
            let data = fileHandle.readData(ofLength: chunkSize)
            if data.isEmpty { break }
            
            guard let chunk = String(data: data, encoding: .utf8) else { break }
            buffer += chunk
            
            if let newlineIndex = buffer.lastIndex(of: "\n") {
                let completeText = String(buffer[..<newlineIndex])
                buffer = String(buffer[buffer.index(after: newlineIndex)...])
                
                let newLines = completeText.components(separatedBy: "\n")
                for line in newLines {
                    lines.append(line)
                    if lines.count >= numLines { break }
                }
            }
        }
        
        if !buffer.isEmpty && lines.count < numLines {
            lines.append(buffer)
        }
        
        return lines.joined(separator: "\n")
    }
    
    private func tailFile(_ path: String, numLines: Int) async throws -> String {
        let fileHandle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
        defer { fileHandle.closeFile() }
        
        let fileSize = fileHandle.seekToEndOfFile()
        if fileSize == 0 { return "" }
        
        var lines: [String] = []
        var position = fileSize
        let chunkSize: UInt64 = 1024
        var remainingText = ""
        
        while position > 0 && lines.count < numLines {
            let readSize = min(chunkSize, position)
            position -= readSize
            
            fileHandle.seek(toFileOffset: position)
            let data = fileHandle.readData(ofLength: Int(readSize))
            
            guard let chunk = String(data: data, encoding: .utf8) else { continue }
            let chunkText = chunk + remainingText
            
            let chunkLines = chunkText.components(separatedBy: "\n")
            
            if position > 0 {
                remainingText = chunkLines.first ?? ""
                let linesToAdd = Array(chunkLines.dropFirst())
                for line in linesToAdd.reversed() {
                    lines.insert(line, at: 0)
                    if lines.count >= numLines { break }
                }
            } else {
                for line in chunkLines.reversed() {
                    lines.insert(line, at: 0)
                    if lines.count >= numLines { break }
                }
            }
        }
        
        return Array(lines.prefix(numLines)).joined(separator: "\n")
    }
    
    private func listDirectoryWithSizes(_ arguments: [String: Any]) async throws -> CallTool.Result {
        guard let path = arguments["path"] as? String else {
            throw MCPXError.invalidArguments("Missing required 'path' parameter")
        }
        
        let validPath = try validatePath(path)
        let sortBy = arguments["sortBy"] as? String ?? "name"
        
        do {
            let contents = try FileManager.default.contentsOfDirectory(atPath: validPath)
            var items: [(name: String, isDirectory: Bool, size: Int64, mtime: Date)] = []
            
            for item in contents {
                let itemPath = URL(fileURLWithPath: validPath).appendingPathComponent(item).path
                do {
                    let attributes = try FileManager.default.attributesOfItem(atPath: itemPath)
                    let isDirectory = (attributes[.type] as? FileAttributeType) == .typeDirectory
                    let size = attributes[.size] as? Int64 ?? 0
                    let mtime = attributes[.modificationDate] as? Date ?? Date(timeIntervalSince1970: 0)
                    items.append((name: item, isDirectory: isDirectory, size: size, mtime: mtime))
                } catch {
                    items.append((name: item, isDirectory: false, size: 0, mtime: Date(timeIntervalSince1970: 0)))
                }
            }
            
            // Sort based on sortBy parameter
            switch sortBy {
            case "size":
                items.sort { $0.size > $1.size }
            case "name":
                items.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            default:
                items.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            }
            
            // Format the output with proper spacing
            let formattedEntries = items.map { item in
                let prefix = item.isDirectory ? "[DIR]" : "[FILE]"
                let paddedName = item.name.padding(toLength: 30, withPad: " ", startingAt: 0)
                let sizeStr = item.isDirectory ? "" : formatSize(item.size).padding(toLength: 10, withPad: " ", startingAt: 0)
                return "\(prefix) \(paddedName) \(sizeStr)"
            }
            
            // Add summary
            let totalFiles = items.filter { !$0.isDirectory }.count
            let totalDirs = items.filter { $0.isDirectory }.count
            let totalSize = items.reduce(0) { sum, item in
                sum + (item.isDirectory ? 0 : item.size)
            }
            
            let summary = [
                "",
                "Total: \(totalFiles) files, \(totalDirs) directories",
                "Combined size: \(formatSize(totalSize))"
            ]
            
            let output = (formattedEntries + summary).joined(separator: "\n")
            
            return CallTool.Result(
                content: [.text(output)]
            )
        } catch {
            throw FilesystemError.fileNotFound("Could not list directory: \(error.localizedDescription)")
        }
    }
    
    private func formatSize(_ bytes: Int64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        if bytes == 0 { return "0 B" }
        
        let i = Int(log(Double(bytes)) / log(1024.0))
        if i == 0 { return "\(bytes) \(units[i])" }
        
        let size = Double(bytes) / pow(1024.0, Double(i))
        return String(format: "%.2f %@", size, units[i])
    }
}
