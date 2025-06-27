import Foundation
import MCP

protocol ServerSession {
    func checkClientCapability(_ capability: ClientCapabilities) -> Bool
    func listRoots() async throws -> ListRootsResult
}

class DefaultServerSession: ServerSession {
    func checkClientCapability(_ capability: ClientCapabilities) -> Bool {
        return true // Always allow capabilities in default implementation
    }
    
    func listRoots() async throws -> ListRootsResult {
        return ListRootsResult(roots: []) // Return empty list by default
    }
}

struct ClientCapabilities {
    let roots: RootsCapability
}

struct RootsCapability {}

struct ListRootsResult {
    let roots: [Root]
}

struct Root {
    let uri: URL
}



// MARK: - Error Types

enum MCPXError: Swift.Error, CustomStringConvertible {
    case invalidArguments(String)
    case accessDenied(String)
    case fileNotFound(String)
    case internalError(String)
    case methodNotFound(String)
    
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
        case .methodNotFound(let message):
            return "Error: Unknown tool: \(message)"
        }
    }

}

enum ServerMode {
    case filesystem
    case git
    case fetch(userAgent: String?, ignoreRobotsTxt: Bool, proxyUrl: String?)
}

class MCPXServer {
    private let allowedDirectories: [String]
    private let verbose: Bool
    private let mode: ServerMode
    private let filesystemTools: FilesystemTools?
    private var gitTools: GitTools!
    private var session: ServerSession?    

    private func listRepos() async -> [String] {
        let fromRoots = await listRoots()
        return fromRoots
    }

    private func listRoots() async -> [String] {
        guard let session = session else {
            return []
        }

        let rootsCapability = ClientCapabilities(roots: RootsCapability())
        guard session.checkClientCapability(rootsCapability) else {
            return []
        }

        do {
            let result: ListRootsResult = try await session.listRoots()
            let validRepoPaths = result.roots.compactMap { root -> String? in
                let path = root.uri.path
                guard FilesystemTools.isGitRepository(at: path) else {
                    return nil
                }
                return path
            }
            return validRepoPaths
        } catch {
            // Handle or log error if necessary
            return []
        }
    }

    init(allowedDirectories: [String], verbose: Bool = false, mode: ServerMode) {
        self.allowedDirectories = allowedDirectories
        self.verbose = verbose
        self.mode = mode
        self.session = nil
        
        // Initialize appropriate tools based on mode
        switch mode {
        case .filesystem:
            self.filesystemTools = FilesystemTools(allowedDirectories: allowedDirectories)
            self.gitTools = nil
        case .git:
            self.filesystemTools = nil
            let listReposFunc = { [weak self] () async -> [String] in
                return await self?.listRepos() ?? []
            }
            self.gitTools = GitTools(allowedDirectories: allowedDirectories, listRepos: listReposFunc)
        case .fetch:
            self.filesystemTools = nil
            self.gitTools = nil
        }
    }
    
    private var serverName: String {
        switch mode {
        case .filesystem:
            return "secure-filesystem-server"
        case .git:
            return "mcp-git"
        case .fetch:
            return "mcp-fetch"
        }
    }
    
    func run() async throws {
        let server = Server(
            name: serverName,
            version: "1.0.0",
            capabilities: .init(tools: .init())
        )
        
        // Register appropriate tool handlers based on mode
        switch mode {
        case .filesystem:
            await registerFilesystemHandlers(server)
        case .git:
            await registerGitHandlers(server)
        case .fetch(let userAgent, let ignoreRobotsTxt, let proxyUrl):
            await registerFetchHandlers(server, userAgent: userAgent, ignoreRobotsTxt: ignoreRobotsTxt, proxyUrl: proxyUrl)
        }
        
        // Run server with stdio transport
        let transport = StdioTransport()
        try await server.start(transport: transport)
        // Create a default session since we don't have access to server's session
        self.session = DefaultServerSession()
        await server.waitUntilCompleted()
    }
    
    private func registerFilesystemHandlers(_ server: Server) async {
        guard let tools = filesystemTools else { return }
        
        await server.withMethodHandler(ListTools.self) { [weak self] (_: ListTools.Parameters) in
            guard self != nil else {
                throw MCPXError.internalError("Server instance deallocated")
            }
            return ListTools.Result(tools: tools.getToolDefinitions())
        }
        
        await server.withMethodHandler(CallTool.self) { [weak self] (params: CallTool.Parameters) in
            guard let self = self else {
                throw MCPXError.internalError("Server instance deallocated")
            }
            
            let toolName = params.name
            let arguments = params.arguments ?? [:]
            
            if verbose {
                fputs("Handling filesystem tool call: \(toolName)\n", stderr)
            }
            
            do {
                if tools.canHandle(toolName) {
                    return try await tools.handleTool(toolName, arguments: arguments)
                } else {
                    throw MCPXError.methodNotFound("Unknown tool: \(toolName)")
                }
            } catch {
                let errorMessage = error is MCPXError ? error.localizedDescription : "Error: \(error.localizedDescription)"
                return CallTool.Result(content: [.text(errorMessage)], isError: true)
            }
        }
    }
    
    private func registerGitHandlers(_ server: Server) async {
        guard let tools = gitTools else { return }
        
        await server.withMethodHandler(ListTools.self) { [weak self] (_: ListTools.Parameters) in
            guard self != nil else {
                throw MCPXError.internalError("Server instance deallocated")
            }
            return ListTools.Result(tools: tools.getToolDefinitions())
        }
        
        await server.withMethodHandler(CallTool.self) { [weak self] (params: CallTool.Parameters) in
            guard let self = self else {
                throw MCPXError.internalError("Server instance deallocated")
            }
            
            let toolName = params.name
            let arguments = params.arguments ?? [:]
            
            if verbose {
                fputs("Handling git tool call: \(toolName)\n", stderr)
            }
            
            do {
                if tools.canHandle(toolName) {
                    return try await tools.handleTool(toolName, arguments: arguments)
                } else {
                    throw MCPXError.methodNotFound("Unknown tool: \(toolName)")
                }
            } catch {
                let errorMessage: String
                if let customError = error as? CustomStringConvertible {
                    errorMessage = customError.description
                } else {
                    errorMessage = "Error: \(error.localizedDescription)"
                }
                return CallTool.Result(content: [.text(errorMessage)], isError: true)
            }
        }
    }
    
    private func registerFetchHandlers(_ server: Server, userAgent: String?, ignoreRobotsTxt: Bool, proxyUrl: String?) async {
        let tools = FetchTools(userAgent: userAgent, ignoreRobotsTxt: ignoreRobotsTxt, proxyUrl: proxyUrl)
        
        await server.withMethodHandler(ListTools.self) { [weak self] (_: ListTools.Parameters) in
            guard self != nil else {
                throw MCPXError.internalError("Server instance deallocated")
            }
            return ListTools.Result(tools: tools.getToolDefinitions())
        }
        
        await server.withMethodHandler(CallTool.self) { [weak self] (params: CallTool.Parameters) in
            guard let self = self else {
                throw MCPXError.internalError("Server instance deallocated")
            }
            
            let toolName = params.name
            let arguments = params.arguments ?? [:]
            
            if verbose {
                fputs("Handling fetch tool call: \(toolName)\n", stderr)
            }
            
            do {
                if tools.canHandle(toolName) {
                    return try await tools.handleTool(toolName, arguments: arguments)
                } else {
                    throw MCPXError.methodNotFound("Unknown tool: \(toolName)")
                }
            } catch {
                let errorMessage = error is MCPXError ? error.localizedDescription : "Error: \(error.localizedDescription)"
                return CallTool.Result(content: [.text(errorMessage)], isError: true)
            }
        }
    }
}
