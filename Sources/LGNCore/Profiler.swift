import Foundation

public extension LGNCore {
    /// A simple tool for profiling
    struct Profiler {
        internal var start: TimeInterval = Date().timeIntervalSince1970

        /// Begins and returns a profiler
        public static func begin() -> Profiler {
            return Profiler()
        }

        /// Stops an active profiler and returns result time in seconds
        public func end() -> Float {
            var end = Date().timeIntervalSince1970
            end -= start
            return Float(end)
        }
    }

    static func profiled(_ closure: () throws -> Void) rethrows -> Float {
        let profiler = Profiler.begin()
        try closure()
        return profiler.end()
    }
}
