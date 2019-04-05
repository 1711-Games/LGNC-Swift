import Foundation
import Logging
import NIO

public typealias Future = EventLoopFuture
public typealias Promise = EventLoopPromise

public struct LGNCore {}

public enum AppEnv: String, CaseIterable {
    case local
    case dev
    case qa
    case stage
    case production

    public static let prod: AppEnv = .production

    public static func detect(from env: [String: String] = ProcessInfo.processInfo.environment) -> AppEnv {
        if let rawEnv = env["APP_ENV"], let env = self.init(rawValue: rawEnv) {
            return env
        }

        Logger(label: "LGNCore.AppEnv").info("Falling back to \(self.local) environment")

        return .local
    }
}
