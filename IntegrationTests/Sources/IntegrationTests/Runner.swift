import Foundation
import LGNCore
import LGNC
import Entita

func executeTestCase(under url: URL) -> (String, Bool) {
    let testName = url.lastPathComponent.replacingOccurrences(of: "test_", with: "")

    return (
        testName,
        {
            let manager = FileManager.default
            let profiler = LGNCore.Profiler.begin()
            do {
                print("Starting test '\(testName)'")

                let uriFile = url.appendingPathComponent("URI")
                guard manager.isReadableFile(atPath: uriFile.path) else {
                    throw E.FileNotFound("URI file not found under \(url.absoluteString)")
                }

                let requestFile = url.appendingPathComponent("Request.json")
                guard manager.isReadableFile(atPath: requestFile.path) else {
                    throw E.FileNotFound("Request file not found under \(url.absoluteString)")
                }

                let responseFile = url.appendingPathComponent("Response.json")
                guard manager.isReadableFile(atPath: responseFile.path) else {
                    throw E.FileNotFound("Response file not found under \(url.absoluteString)")
                }

                let fullURI = try String(contentsOf: uriFile, encoding: .utf8)
                guard
                    let request = try JSONSerialization.jsonObject(with: .init(contentsOf: requestFile)) as? Entita.Dict
                else {
                    throw E.JSONDecodeError("Could not decode JSON from request file")
                }
                let fullURIComponents = fullURI.components(separatedBy: "://")
                let transport: LGNCore.Transport
                let uri: String
                if fullURIComponents.count == 2 {
                    guard let _transport = LGNCore.Transport(from: fullURIComponents[0]) else {
                        throw E.JSONDecodeError("Invalid transport '\(fullURIComponents[0])' in URI '\(fullURI)'")
                    }
                    transport = _transport
                    uri = fullURIComponents[1]
                } else {
                    transport = .HTTP
                    uri = fullURI
                }

                guard let expectedResponse = try JSONSerialization
                    .jsonObject(with: .init(contentsOf: responseFile)) as? Entita.Dict
                else {
                    throw E.JSONDecodeError("Could not decode JSON from response file")
                }
                let expectedResponseJSON = try JSONSerialization.data(
                    withJSONObject: expectedResponse,
                    options: [.sortedKeys, .prettyPrinted]
                ).string

                var requestMeta: LGNC.Entity.Meta = [:]
                let metaFile = url.appendingPathComponent("Meta.json")
                if manager.isReadableFile(atPath: metaFile.path) {
                    guard let _meta = try JSONSerialization
                        .jsonObject(with: .init(contentsOf: metaFile)) as? LGNC.Entity.Meta
                    else {
                        throw E.JSONDecodeError("Found Meta.json file, but could not decode JSON from it")
                    }
                    requestMeta = _meta
                }

                let eventLoop = EmbeddedEventLoop()
                let response = S.executeContract(
                    URI: uri,
                    dict: request,
                    context: .init(
                        remoteAddr: "0.0.0.0",
                        clientAddr: "0.0.0.0",
                        userAgent: "",
                        locale: .enUS,
                        uuid: UUID(),
                        isSecure: false,
                        transport: transport,
                        meta: requestMeta,
                        eventLoop: eventLoop
                    )
                )
                eventLoop.run()
                let responseDict = try response.wait().getDictionary()
                let actualResponseJSON = try JSONSerialization.data(
                    withJSONObject: responseDict,
                    options: [.sortedKeys, .prettyPrinted]
                ).string

                guard actualResponseJSON == expectedResponseJSON else {
                    print(
                        """
                        Expected response does not match actual response.

                        EXPECTED:
                        \(expectedResponseJSON)

                        ACTUAL:
                        \(actualResponseJSON)
                        """
                    )
                    throw E.TestCaseFailed
                }

                print("Test '\(testName)' succeeded after \(profiler.end().rounded(toPlaces: 4))s")

                return true
            } catch {
                print("Test '\(testName)' FAILED after \(profiler.end().rounded(toPlaces: 4))s: \(error)")
            }

            return false
        }()
    )
}
