import Foundation

// Entry point - run the command line interface
func runMain() {
    Task {
        await MCPXCommand.main()
    }
    RunLoop.main.run()
}

runMain()