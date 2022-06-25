import Foundation
import LGNLog

public extension LGNCore {
    /// A simple tool for profiling.
    /// Must be owned only by respective `ChannelHandler` (HTTP or LGNS) and `LGNCore.Context`
    final class Profiler: @unchecked Sendable {
        public struct Milestone: CustomStringConvertible, Sendable {
            public let lastMilestone: String
            public let elapsed: Float
            public let delta: Float

            public var description: String {
                "\(self.elapsed.rounded(toPlaces: 4))s (\(self.delta.rounded(toPlaces: 4))s since '\(self.lastMilestone)')"
            }
        }

        fileprivate let start: Double
        fileprivate var milestone: Double
        fileprivate var milestoneName: String

        public init(start: Double = Date().timeIntervalSince1970) {
            self.start = start
            self.milestone = start
            self.milestoneName = "profiler created"
        }

        deinit {
            self.mark("deinit")
        }

        @discardableResult
        public func mark(_ milestone: String? = nil, file: String = #file, line: UInt = #line) -> Milestone {
            let previousMilestone = self.milestone
            self.milestone = Date().timeIntervalSince1970

            let previousMilestoneName = self.milestoneName
            let source = "\(file.split(separator: "/").last!):\(line)"
            self.milestoneName = milestone ?? source

            let result = Milestone(
                lastMilestone: previousMilestoneName,
                elapsed: Float(self.milestone - self.start),
                delta: Float(self.milestone - previousMilestone)
            )

            LGNCore.Context.current.logger.trace("Profiler: '\(self.milestoneName)' @ '\(source)': \(result)")

            return result
        }
    }

//    static func profiled(_ closure: () throws -> Void) rethrows -> Float {
//        let profiler = Profiler.begin()
//        try closure()
//        return profiler.end()
//    }
}
