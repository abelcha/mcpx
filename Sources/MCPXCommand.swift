import ArgumentParser
import MCP
import Foundation

struct MCPXCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mcpx",
        abstract: "MCP Server",
        version: "1.0.0",
        subcommands: [Git.self, Filesystem.self]
    )
}

// MARK: - Filesystem Subcommand
extension MCPXCommand {
    struct Filesystem: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "fs",
            abstract: "Start the filesystem MCP server"
        )
        
        @Option(name: .long, help: "Allowed directory for filesystem operations (can be specified multiple times)")
        var allowDir: [String] = []
        
        @Flag(name: .long, help: "Enable verbose logging")
        var verbose: Bool = false
        
        func validate() throws {
            if allowDir.isEmpty {
                throw ValidationError("At least one --allow-dir must be specified")
            }
        }
        
        func run() async throws {
            let normalizedDirs = try allowDir.map { dir in
                let expandedPath = FilesystemTools.expandTilde(dir)
                let url = URL(fileURLWithPath: expandedPath)
                let resolvedURL = url.resolvingSymlinksInPath()
                
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: resolvedURL.path, isDirectory: &isDirectory),
                      isDirectory.boolValue else {
                    throw ValidationError("Directory does not exist or is not accessible: \(dir)")
                }
                
                return resolvedURL.path
            }
            
            if verbose {
                fputs("mcpx filesystem server starting...\n", stderr)
                fputs("Allowed directories: \(normalizedDirs.joined(separator: ", "))\n", stderr)
            }
            
            let server = MCPXServer(allowedDirectories: normalizedDirs, verbose: verbose, mode: .filesystem)
            try await server.run()
        }
    }
}

// MARK: - Git Subcommand
extension MCPXCommand {
    struct Git: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "git",
            abstract: "Start the Git MCP server"
        )
        
        @Option(name: [.short, .long], help: "Git repository path")
        var repository: String?
        
        @Flag(name: .long, help: "Enable verbose logging")
        var verbose: Bool = false
        
        func validate() throws {
            if let repository = repository {
                let expandedPath = FilesystemTools.expandTilde(repository)
                let url = URL(fileURLWithPath: expandedPath)
                let resolvedURL = url.resolvingSymlinksInPath()
                
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: resolvedURL.path, isDirectory: &isDirectory),
                      isDirectory.boolValue else {
                    throw ValidationError("Repository path does not exist or is not accessible: \(repository)")
                }
            }
        }
        
        func run() async throws {
            var allowedDirs: [String] = []
            
            if let repository = repository {
                let expandedPath = FilesystemTools.expandTilde(repository)
                let url = URL(fileURLWithPath: expandedPath)
                let resolvedURL = url.resolvingSymlinksInPath()
                allowedDirs = [resolvedURL.path]
            } else {
                allowedDirs = []
            }
            
            if verbose {
                fputs("MCP Git Server - Git functionality for MCP\n", stderr)
                if let repository = repository {
                    fputs("Repository path: \(repository)\n", stderr)
                }
            } else {
                allowedDirs = []
                if verbose {
                    fputs("MCP Git Server - Git functionality for MCP\n", stderr)
                    fputs("No repository path specified, using client capabilities for repository discovery\n", stderr)
                }
            }
            
            let server = MCPXServer(allowedDirectories: allowedDirs, verbose: verbose, mode: .git)
            try await server.run()
        }
    }
}

// MARK: - Fetch Subcommand
extension MCPXCommand {
    struct Fetch: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "fetch",
            abstract: "Start the HTTP fetch MCP server"
        )
        
        @Option(name: .long, help: "Custom User-Agent string")
        var userAgent: String?
        
        @Flag(name: .long, help: "Ignore robots.txt restrictions")
        var ignoreRobotsTxt: Bool = false
        
        @Option(name: .long, help: "Proxy URL to use for requests")
        var proxyUrl: String?
        
        @Flag(name: .long, help: "Enable verbose logging")
        var verbose: Bool = false
        
        func run() async throws {
            if verbose {
                fputs("mcpx fetch server starting...\n", stderr)
                if let userAgent = userAgent {
                    fputs("User-Agent: \(userAgent)\n", stderr)
                }
                if ignoreRobotsTxt {
                    fputs("Ignoring robots.txt restrictions\n", stderr)
                }
                if let proxyUrl = proxyUrl {
                    fputs("Using proxy: \(proxyUrl)\n", stderr)
                }
            }
            
            let server = MCPXServer(
                allowedDirectories: [],
                verbose: verbose,
                mode: .fetch(
                    userAgent: userAgent,
                    ignoreRobotsTxt: ignoreRobotsTxt,
                    proxyUrl: proxyUrl
                )
            )
            try await server.run()
        }
    }
}
