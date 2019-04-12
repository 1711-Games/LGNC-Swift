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

        #if os(macOS)
            Logger(label: "LGNCore.AppEnv").info("Falling back to \(self.local) environment")
            return .local
        #else
            Logger(label: "LGNCore.AppEnv").info("APP_ENV must be set explicitly in non-macOS environment")
            exit(1)
        #endif
    }
}
