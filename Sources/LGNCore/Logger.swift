import Foundation

public extension LGNCore {
    static func log(_ message: String, prefix: String? = nil, file: String = #file, line: Int = #line) {
        let _file = file.split(separator: "/").last!
        let _prefix: String
        if let prefix = prefix {
            _prefix = " [\(prefix)]"
        } else {
            _prefix = ""
        }
        print("[\(Date().description.replacingOccurrences(of: " +0000", with: "")) @ \(_file):\(line)]\(_prefix): \(message)")
    }
}
