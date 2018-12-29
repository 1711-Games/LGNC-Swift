import Foundation
import LGNCore
import LGNP
import LGNS
import Entita
import SwiftMsgPack
import NIO

fileprivate extension LGNC {
    fileprivate struct Formatter {
        fileprivate static let formatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd kk:mm:ss.SSSSxxx"
            return formatter
        }()
    }
}

public extension Date {
    public var formatted: String {
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
    let byte1 = UInt8(input & 0xff)
    let byte2 = UInt8((input >> 8) & 0xff)
    let byte3 = UInt8((input >> 16) & 0xff)
    let byte4 = UInt8((input >> 24) & 0xff)
    return "\(byte4).\(byte3).\(byte2).\(byte1)"
}

private extension String {
    var wholeRange: NSRange {
        return NSRange(location: 0, length: self.count)
    }
    
    //TODO: Use ObjectiveCBridgeable or wait until NSRegularExpression has a swifty API
    var _ns: NSString {
        return self as NSString
    }
    
    func substringWithRange(_ range: NSRange) -> String {
        return self._ns.substring(with: range)
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
        matchedString = string.substringWithRange(checkingResult.range)
        captureGroups = checkingResult.ranges.dropFirst().map { range in
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
        if self.unicodeScalars.starts(with: prefix.unicodeScalars) {
            return String(self[self.index(self.startIndex, offsetBy: prefix.count)...])
        } else {
            return nil
        }
    }
    
    func containsDotDot() -> Bool {
        for idx in self.indices {
            if self[idx] == "." && idx < self.index(before: self.endIndex) && self[self.index(after: idx)] == "." {
                return true
            }
        }
        return false
    }
}
