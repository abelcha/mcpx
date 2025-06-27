# Swift MCP Server - Implementation Instructions

## Project Goal
Reimplement the 3 core MCP servers (filesystem, git, fetch) as a single Swift binary called `mcpx`.

## Why Swift?
- Single binary deployment (no Node.js dependency)
- Native macOS performance
- Clean, modern syntax
- Excellent Foundation library for filesystem/networking
- First-class MCP Swift SDK available

## Architecture Overview

### Single Binary, Multiple Tools
```
mcpx
├── fs    (filesystem operations)
├── git   (git operations) 
└── fetch (HTTP requests)
```

### Command Structure
```bash
mcpx --allow-dir /path/to/project
# Exposes all three tool sets via MCP protocol
```

## Core Requirements

### 1. Filesystem Server (`fs`)
**Tools to implement:**
- `read_file` - Read file contents with UTF-8 encoding
- `write_file` - Create/overwrite files
- `list_directory` - List directory contents with [FILE]/[DIR] prefixes
- `create_directory` - Create directories recursively
- `move_file` - Move/rename files and directories
- `search_files` - Recursive file search with pattern matching
- `get_file_info` - File metadata (size, dates, permissions)

**Key APIs:**
- `FileManager.default` for directory operations
- `String(contentsOf:)` and `Data.write(to:)` for file I/O
- `FileManager.contentsOfDirectory(atPath:)` for listings

### 2. Git Server (`git`)
**Tools to implement:**
- `git_status` - Show working directory status
- `git_add` - Stage files
- `git_commit` - Create commits
- `git_push` - Push to remote
- `git_pull` - Pull from remote
- `git_log` - Show commit history
- `git_diff` - Show file differences
- `git_branch` - Branch operations

**Implementation approach:**
- Use `Process` to execute git commands
- Parse stdout/stderr for structured responses
- Handle git credential management

### 3. Fetch Server (`fetch`)
**Tools to implement:**
- `http_get` - GET requests with headers
- `http_post` - POST requests with body/headers
- `http_put` - PUT requests
- `http_delete` - DELETE requests

**Key APIs:**
- `URLSession` for HTTP requests
- `JSONSerialization` for JSON handling
- Proper error handling for network failures

## Project Structure
```
Sources/
├── SwiftMCP/
│   ├── main.swift           # Entry point
│   ├── MCPServer.swift      # MCP protocol handling
│   ├── FilesystemTools.swift
│   ├── GitTools.swift
│   └── FetchTools.swift
└── Package.swift
```

## Dependencies
```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/modelcontextprotocol/swift-sdk", from: "1.0.0")
]
```

## Security Requirements
- **Path validation** - Only allow operations within specified directories
- **Git safety** - Validate git commands to prevent injection
- **HTTP limits** - Reasonable timeouts and request size limits
- **Error handling** - Never expose internal system paths in errors

## MCP Protocol Integration
- Use the official Swift MCP SDK
- Implement `ListToolsRequestSchema` handler
- Implement `CallToolRequestSchema` handler
- Follow MCP tool schema patterns from Node.js versions

## Success Criteria
1. **Drop-in replacement** - Same MCP tool interface as Node.js versions
2. **Single binary** - No runtime dependencies
3. **Better performance** - Faster than Node.js equivalents
4. **Clean error messages** - User-friendly error handling
5. **Cross-platform** - Works on macOS and Linux

## Implementation Order
1. **Start with filesystem** - Core functionality, easiest to test
2. **Add fetch** - HTTP operations, good for testing network handling
3. **Finish with git** - Most complex due to subprocess management

## Testing Strategy
- Test against existing MCP clients (Claude Desktop)
- Compare output format with Node.js versions
- Test edge cases: large files, network failures, git errors
- Verify security boundaries work correctly

## Key Differences from Node.js Version
- **No async/await ceremony** - Use Swift's structured concurrency
- **Native error types** - Proper Swift error handling vs JavaScript exceptions
- **Type safety** - Compile-time guarantees vs runtime schema validation
- **Resource management** - Automatic memory management vs manual cleanup