import Foundation
import MCP

enum GitError: Swift.Error, CustomStringConvertible {
    case invalidArguments(String)
    case commandFailed(String)
    case internalError(String)
    
    var description: String {
        switch self {
        case .invalidArguments(let message):
            return "Error: Invalid arguments for \(message)"
        case .commandFailed(let message):
            return "Error: Git command failed: \(message)"
        case .internalError(let message):
            return "Error: \(message)"
        }
    }
}

class GitTools {
    private let allowedDirectories: [String]
    private let listRepos: () async -> [String]

    init(allowedDirectories: [String], listRepos: @escaping () async -> [String]) {
        self.allowedDirectories = allowedDirectories
        self.listRepos = listRepos
    }
    
    func canHandle(_ toolName: String) -> Bool {
        return [
            "git_status",
            "git_diff_unstaged",
            "git_diff_staged",
            "git_diff",
            "git_commit",
            "git_add",
            "git_reset",
            "git_log",
            "git_create_branch",
            "git_checkout",
            "git_show",
            "git_init",
            "list_repos"
        ].contains(toolName)
    }
    
    func getToolDefinitions() -> [Tool] {
        return [
            Tool(
                name: "git_status",
                description: "Shows the working tree status",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "repo_path": ["type": "string", "description": "Path to Git repository"]
                    ],
                    "required": ["repo_path"]
                ]
            ),
            Tool(
                name: "git_diff_unstaged",
                description: "Shows changes in the working directory that are not yet staged",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "repo_path": ["type": "string", "description": "Path to Git repository"]
                    ],
                    "required": ["repo_path"]
                ]
            ),
            Tool(
                name: "git_diff_staged",
                description: "Shows changes that are staged for commit",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "repo_path": ["type": "string", "description": "Path to Git repository"]
                    ],
                    "required": ["repo_path"]
                ]
            ),
            Tool(
                name: "git_diff",
                description: "Shows differences between branches or commits",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "repo_path": ["type": "string", "description": "Path to Git repository"],
                        "target": ["type": "string", "description": "Target branch or commit to compare with"]
                    ],
                    "required": ["repo_path", "target"]
                ]
            ),
            Tool(
                name: "git_commit",
                description: "Records changes to the repository",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "repo_path": ["type": "string", "description": "Path to Git repository"],
                        "message": ["type": "string", "description": "Commit message"]
                    ],
                    "required": ["repo_path", "message"]
                ]
            ),
            Tool(
                name: "git_add",
                description: "Adds file contents to the staging area",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "repo_path": ["type": "string", "description": "Path to Git repository"],
                        "files": ["type": "array", "items": ["type": "string"], "description": "Array of file paths to stage"]
                    ],
                    "required": ["repo_path", "files"]
                ]
            ),
            Tool(
                name: "git_reset",
                description: "Unstages all staged changes",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "repo_path": ["type": "string", "description": "Path to Git repository"]
                    ],
                    "required": ["repo_path"]
                ]
            ),
            Tool(
                name: "git_log",
                description: "Shows the commit logs",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "repo_path": ["type": "string", "description": "Path to Git repository"],
                        "max_count": ["type": "integer", "description": "Maximum number of commits to show", "default": 10]
                    ],
                    "required": ["repo_path"]
                ]
            ),
            Tool(
                name: "git_create_branch",
                description: "Creates a new branch from an optional base branch",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "repo_path": ["type": "string", "description": "Path to Git repository"],
                        "branch_name": ["type": "string", "description": "Name of the new branch"],
                        "base_branch": ["type": "string", "description": "Starting point for the new branch"]
                    ],
                    "required": ["repo_path", "branch_name"]
                ]
            ),
            Tool(
                name: "git_checkout",
                description: "Switches branches",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "repo_path": ["type": "string", "description": "Path to Git repository"],
                        "branch_name": ["type": "string", "description": "Name of branch to checkout"]
                    ],
                    "required": ["repo_path", "branch_name"]
                ]
            ),
            Tool(
                name: "git_show",
                description: "Shows the contents of a commit",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "repo_path": ["type": "string", "description": "Path to Git repository"],
                        "revision": ["type": "string", "description": "The revision (commit hash, branch name, tag) to show"]
                    ],
                    "required": ["repo_path", "revision"]
                ]
            ),
            Tool(
                name: "git_init",
                description: "Initialize a new Git repository",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "repo_path": ["type": "string", "description": "Path to directory to initialize git repo"]
                    ],
                    "required": ["repo_path"]
                ]
            ),
            Tool(
                name: "list_repos",
                description: "List available Git repositories",
                inputSchema: ["type": "object", "properties": [:]]
            )
        ]
    }
    
    func handleTool(_ toolName: String, arguments: [String: Any]) async throws -> CallTool.Result {
        if toolName == "list_repos" {
            let repos = await listRepos()
            let content = repos.joined(separator: "\n")
            return CallTool.Result(content: [.text(content)])
        }

        guard let repoPath = arguments["repo_path"] as? String else {
            throw GitError.invalidArguments("Missing required 'repo_path' parameter")
        }
        
        // Validate repo path is within allowed directories
        let validPath = try validatePath(repoPath)
        
        switch toolName {
        case "git_status":
            let output = try await gitStatus(validPath)
            return CallTool.Result(content: [.text(output)])
            
        case "git_diff_unstaged":
            let output = try await gitDiffUnstaged(validPath)
            return CallTool.Result(content: [.text(output)])
            
        case "git_diff_staged":
            let output = try await gitDiffStaged(validPath)
            return CallTool.Result(content: [.text(output)])
            
        case "git_diff":
            guard let target = arguments["target"] as? String else {
                throw GitError.invalidArguments("Missing required 'target' parameter")
            }
            let output = try await gitDiff(validPath, target: target)
            return CallTool.Result(content: [.text(output)])
            
        case "git_commit":
            guard let message = arguments["message"] as? String else {
                throw GitError.invalidArguments("Missing required 'message' parameter")
            }
            let output = try await gitCommit(validPath, message: message)
            return CallTool.Result(content: [.text(output)])
            
        case "git_add":
            guard let files = arguments["files"] as? [String] else {
                throw GitError.invalidArguments("Missing required 'files' parameter")
            }
            let output = try await gitAdd(validPath, files: files)
            return CallTool.Result(content: [.text(output)])
            
        case "git_reset":
            let output = try await gitReset(validPath)
            return CallTool.Result(content: [.text(output)])
            
        case "git_log":
            let maxCount = arguments["max_count"] as? Int ?? 10
            let output = try await gitLog(validPath, maxCount: maxCount)
            return CallTool.Result(content: [.text(output)])
            
        case "git_create_branch":
            guard let branchName = arguments["branch_name"] as? String else {
                throw GitError.invalidArguments("Missing required 'branch_name' parameter")
            }
            let baseBranch = arguments["base_branch"] as? String
            let output = try await gitCreateBranch(validPath, branchName: branchName, baseBranch: baseBranch)
            return CallTool.Result(content: [.text(output)])
            
        case "git_checkout":
            guard let branchName = arguments["branch_name"] as? String else {
                throw GitError.invalidArguments("Missing required 'branch_name' parameter")
            }
            let output = try await gitCheckout(validPath, branchName: branchName)
            return CallTool.Result(content: [.text(output)])
            
        case "git_show":
            guard let revision = arguments["revision"] as? String else {
                throw GitError.invalidArguments("Missing required 'revision' parameter")
            }
            let output = try await gitShow(validPath, revision: revision)
            return CallTool.Result(content: [.text(output)])
            
        case "git_init":
            let output = try await gitInit(validPath)
            return CallTool.Result(content: [.text(output)])

            
        default:
            throw GitError.internalError("Unknown git tool: \(toolName)")
        }
    }
    
    private func validatePath(_ path: String) throws -> String {
        let absolute = (path as NSString).standardizingPath
        
        // Check if path is within allowed directories
        let isAllowed = allowedDirectories.contains { dir in
            absolute.hasPrefix(dir)
        }
        
        guard isAllowed else {
            throw GitError.invalidArguments("Access denied - path outside allowed directories: \(absolute)")
        }
        
        return absolute
    }
    

    
    private func runGitCommand(_ args: [String], at path: String) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: path)
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        try process.run()
        process.waitUntilExit()
        
        let outputData = try outputPipe.fileHandleForReading.readToEnd() ?? Data()
        let errorData = try errorPipe.fileHandleForReading.readToEnd() ?? Data()
        
        let output = String(data: outputData, encoding: .utf8) ?? ""
        let error = String(data: errorData, encoding: .utf8) ?? ""
        
        if process.terminationStatus != 0 {
            let debugInfo = "[GIT DEBUG] Args: \(args)\nPath: \(path)\nExit: \(process.terminationStatus)\nStdout: \(output)\nStderr: \(error)"
            throw GitError.commandFailed(debugInfo)
        }
        
        return output.isEmpty ? error : output
    }
    
    private func gitStatus(_ path: String) async throws -> String {
        return try await runGitCommand(["status"], at: path)
    }
    
    private func gitDiffUnstaged(_ path: String) async throws -> String {
        return try await runGitCommand(["diff"], at: path)
    }
    
    private func gitDiffStaged(_ path: String) async throws -> String {
        return try await runGitCommand(["diff", "--cached"], at: path)
    }
    
    private func gitDiff(_ path: String, target: String) async throws -> String {
        
        return try await runGitCommand(["diff", target], at: path)
    }
    
    private func gitCommit(_ path: String, message: String) async throws -> String {
        _ = try await runGitCommand(["commit", "-m", message], at: path)
        let hash = try await runGitCommand(["rev-parse", "HEAD"], at: path).trimmingCharacters(in: .whitespacesAndNewlines)
        return "Changes committed successfully with hash \(hash)"
    }
    
    private func gitAdd(_ path: String, files: [String]) async throws -> String {
        
        let output = try await runGitCommand(["add"] + files, at: path)
        return output.isEmpty ? "Files staged successfully" : output
    }
    
    private func gitReset(_ path: String) async throws -> String {
        let output = try await runGitCommand(["reset"], at: path)
        return output.isEmpty ? "All staged changes reset" : output
    }
    
    private func gitLog(_ path: String, maxCount: Int) async throws -> String {
        let format = "--pretty=format:Commit: %H%nAuthor: %an <%ae>%nDate: %ad%nMessage: %s%n"
        let output = try await runGitCommand(["log", "-n", String(maxCount), format], at: path)
        return "Commit history:\n\(output)"
    }
    
    private func gitCreateBranch(_ path: String, branchName: String, baseBranch: String?) async throws -> String {
        
        var args = ["branch", branchName]
        if let base = baseBranch {
            args.append(base)
        }
        let output = try await runGitCommand(args, at: path)

        if !output.isEmpty {
            return output
        }

        if let base = baseBranch {
            return "Created branch '\(branchName)' from '\(base)'"
        } else {
            return "Created branch '\(branchName)' from current HEAD"
        }
    }
    
    private func gitCheckout(_ path: String, branchName: String) async throws -> String {
        
        let output = try await runGitCommand(["checkout", branchName], at: path)
        return output.isEmpty ? "Switched to branch '\(branchName)'" : output
    }
    
    private func gitShow(_ path: String, revision: String) async throws -> String {
        
        let format = "--pretty=format:Commit: %H%nAuthor: %an <%ae>%nDate: %ad%nMessage: %s%n"
        let output = try await runGitCommand(["show", "--patch", format, revision], at: path)
        return output
    }
    
    private func gitInit(_ path: String) async throws -> String {
        if !FileManager.default.fileExists(atPath: path) {
            try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        }
        let output = try await runGitCommand(["init"], at: path)
        return "Initialized empty Git repository in \(path)\n\(output)"
    }
}
