import Foundation

public extension LGNCore {
    public struct Profiler {
        internal var start: TimeInterval = Date().timeIntervalSince1970

        public static func begin() -> Profiler {
            return Profiler()
        }

        public func end() -> Float {
            var end = Date().timeIntervalSince1970
            end -= start
            return Float(end)
        }
    }

    public static func profiled(_ closure: () throws -> Void) rethrows -> Float {
        let profiler = Profiler.begin()
        try closure()
        return profiler.end()
    }
}
