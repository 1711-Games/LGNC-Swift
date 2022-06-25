import Foundation
import ArgumentParser
import LGNC
import LGNCore

typealias S = Services.First
typealias C1 = Services.First.Contracts.DoThings
typealias C2 = Services.First.Contracts.DoCompletelyOtherThings

LoggingSystem.bootstrap(LGNCore.Logger.init)
LGNCore.Logger.logLevel = .error
LGNC.ALLOW_ALL_TRANSPORTS = true

enum E: Error {
    case FileNotFound(String)
    case JSONDecodeError(String)
    case TestCaseFailed
}

struct Execute: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "LGNC Integration Tests",
        abstract: "Runs LGNC integration tests"
    )

    @Option(name: .long, help: "Directory with all integration tests")
    var testsDirectory: String

    lazy var testsDirectoryURL: URL = URL(fileURLWithPath: self.testsDirectory, isDirectory: true)

    mutating func validate() throws {
        guard FileManager.default.isReadableFile(atPath: self.testsDirectory) else {
            throw ValidationError(
                "Invalid input directory '\(self.testsDirectory)' (doesn't exist or is not readable)"
            )
        }
        let testsDirectoryURL = URL(fileURLWithPath: self.testsDirectory, isDirectory: true)
        guard try testsDirectoryURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
            throw ValidationError(
                "Invalid input directory '\(self.testsDirectory)' (isn't a directory)"
            )
        }

        self.testsDirectoryURL = testsDirectoryURL
    }

    mutating func run() async throws {
        setupContract()

        print("About to execute tests under \(self.testsDirectory)")

        let testCasesResults: [(String, Bool)] = try await FileManager.default
            .contentsOfDirectory(at: self.testsDirectoryURL, includingPropertiesForKeys: [.isDirectoryKey])
            .filter { try $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true }
            .filter { $0.lastPathComponent.starts(with: "test_") }
            .sorted(by: { $0.absoluteString < $1.absoluteString })
            .map(executeTestCase(under:))

        print(
            """

            Test results: \
            \(testCasesResults.filter { $1 }.count) succeeded, \
            \(testCasesResults.filter { !$1 }.count) failed.

            \(testCasesResults
                .map { name, result in "[\(result ? "OK" : "FAIL")] \(name)" }
                .joined(separator: "\n")
            )
            """
        )

        if testCasesResults.filter({ !$1 }).count > 0 {
            print("There are failed cases")
            Foundation.exit(1)
        }
    }
}

Execute.main()
