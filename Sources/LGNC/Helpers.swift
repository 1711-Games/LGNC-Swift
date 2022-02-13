import Entita
import Foundation
import LGNCore
import LGNP
import LGNS
import NIO
import SwiftMsgPack

public extension EventLoopFuture {
    func map<NewValue>(
        _ keyPath: KeyPath<Value, NewValue>
    ) -> EventLoopFuture<NewValue> {
        self.map { (result: Value) -> NewValue in
            result[keyPath: keyPath]
        }
    }
}

fileprivate extension LGNC {
    struct Formatter {
        fileprivate static let formatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd kk:mm:ss.SSSSxxx"
            return formatter
        }()
    }
}

public extension Date {
    var formatted: String {
        return LGNC.Formatter.formatter.string(from: self)
    }
}

public func stringIpToInt(_ input: String) -> UInt32 {
    var result: UInt32 = 0
    var i = 0
    for part in input.split(separator: ".") {
        result |= UInt32(part)! << ((3 - i) * 8)
        i += 1
    }
    return result
}

public func intToIpString(_ input: UInt32) -> String {
    let byte1 = UInt8(input & 0xFF)
    let byte2 = UInt8((input >> 8) & 0xFF)
    let byte3 = UInt8((input >> 16) & 0xFF)
    let byte4 = UInt8((input >> 24) & 0xFF)
    return "\(byte4).\(byte3).\(byte2).\(byte1)"
}

private extension String {
    var wholeRange: NSRange {
        return NSRange(location: 0, length: count)
    }

    // TODO: Use ObjectiveCBridgeable or wait until NSRegularExpression has a swifty API
    var _ns: NSString {
        return self as NSString
    }

    func substringWithRange(_ range: NSRange) -> String {
        return _ns.substring(with: range)
    }
}

internal extension String {
    var isNumber: Bool {
        return !isEmpty && rangeOfCharacter(from: CharacterSet.decimalDigits.inverted) == nil
    }
}

private extension NSTextCheckingResult {
    var ranges: [NSRange] {
        var ranges = [NSRange]()
        for i in 0 ..< numberOfRanges {
            ranges.append(range(at: i))
        }
        return ranges
    }
}

public struct Match {
    public let matchedString: String
    public let captureGroups: [String]

    public init(baseString string: String, checkingResult: NSTextCheckingResult) {
        self.matchedString = string.substringWithRange(checkingResult.range)
        self.captureGroups = checkingResult.ranges.dropFirst().map { range in
            range.location == NSNotFound ? "" : string.substringWithRange(range)
        }
    }
}

public struct Regex {
    public let pattern: String
    public let options: NSRegularExpression.Options

    fileprivate let matcher: NSRegularExpression

    public init?(pattern: String, options: NSRegularExpression.Options = []) {
        guard let matcher = try? NSRegularExpression(pattern: pattern, options: options) else {
            return nil
        }

        self.matcher = matcher
        self.pattern = pattern
        self.options = options
    }

    public func match(_ string: String, options: NSRegularExpression.MatchingOptions = [], range: NSRange? = .none) -> Bool {
        let range = range ?? string.wholeRange

        return matcher.numberOfMatches(in: string, options: options, range: range) != 0
    }

    public func matches(_ string: String, options: NSRegularExpression.MatchingOptions = [], range: NSRange? = .none) -> [Match] {
        let range = range ?? string.wholeRange

        return matcher.matches(in: string, options: options, range: range).map { Match(baseString: string, checkingResult: $0)
        }
    }
}

internal extension String {
    func chopPrefix(_ prefix: String) -> String? {
        if unicodeScalars.starts(with: prefix.unicodeScalars) {
            return String(self[self.index(self.startIndex, offsetBy: prefix.count)...])
        } else {
            return nil
        }
    }

    func containsDotDot() -> Bool {
        for idx in indices {
            if self[idx] == "." && idx < index(before: endIndex) && self[self.index(after: idx)] == "." {
                return true
            }
        }
        return false
    }
}

internal protocol Flattenable {
    var flattened: Any? { get }
}

extension Optional: Flattenable {
    var flattened: Any? {
        switch self {
        case .some(let x as Flattenable): return x.flattened
        case .some(let x): return x
        case .none: return nil
        }
    }
}
