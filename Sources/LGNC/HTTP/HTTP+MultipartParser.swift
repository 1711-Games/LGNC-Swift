import NIOHTTP1
import LGNCore
import Entita

extension HTTPHeaders {
    func getMultipartBoundary() -> String? {
        guard let header = self.first(name: "Content-Type"), header.starts(with: "multipart/form-data") else {
            return nil
        }
        return LGNCore.parseKV(from: header)["boundary"]
    }
}

extension HTTP {
    static func parseMultipartFormdata(boundary: String, input: Bytes) -> Entita.Dict {
        let logger = Logger.current

        let boundary = Bytes(("--" + boundary).utf8)
        let boundaryLength = boundary.count
        let inputLength = input.count
        var range = 0...
        var output = [String: Any]()
        while true {
            guard let firstOccurenceBoundary = input.firstRange(of: boundary, in: range)?.upperBound else {
                logger.debug("No first boundary found in range \(range)")
                break
            }
            guard firstOccurenceBoundary + boundaryLength < inputLength else {
                logger.debug("Reached the end of input, break")
                break
            }
            guard let secondOccurenceBoundary = input
                .firstRange(of: boundary, in: firstOccurenceBoundary...)?
                .lowerBound
            else {
                logger.debug("No second boundary found in range \(firstOccurenceBoundary...) (length: \(input.count))")
                break
            }
            range = secondOccurenceBoundary...
            let partRange = (firstOccurenceBoundary + 1)...(secondOccurenceBoundary - 2)
            let part = input[partRange]
            guard let partsSeparator = part.firstRange(of: [10, 10]) else {
                logger.debug("Part doesn't contain two newlines: \(part._string)")
                continue
            }
            let headers = HTTPHeaders(
                part[..<partsSeparator.lowerBound]
                    ._string
                    .components(separatedBy: "\n")
                    .compactMap { (rawHeader: String) -> (key: String, value: String)? in
                        let components = rawHeader
                            .split(separator: ":", maxSplits: 1)
                            .map { $0.trimmingCharacters(in: .whitespaces) }
                        guard components.count == 2 else {
                            logger.debug("Somehow header contains not two components: \(rawHeader)")
                            return nil
                        }
                        return (key: components[0], value: components[1])
                    }
            )
            let body = part[partsSeparator.upperBound...]
            guard let contentDisposition = headers.first(name: "Content-Disposition") else {
                logger.debug("No Content-Disposition header")
                continue
            }
            guard contentDisposition.contains("form-data") else {
                logger.debug("Content-Disposition does not contain 'form-data' value: \(contentDisposition)")
                continue
            }

            let KVs = LGNCore.parseKV(from: contentDisposition)
            guard let name = KVs["name"] else {
                logger.debug("Content-Disposition does not contain 'name' value: \(contentDisposition)")
                continue
            }

            let isFile: Bool
            let rawContentType: String
            if let _rawContentType = headers.first(name: "Content-Type") {
                isFile = true
                rawContentType = _rawContentType
            } else {
                isFile = false
                rawContentType = LGNCore.ContentType.TextPlain.type
            }
            let contentType = LGNCore.ContentType(rawValue: rawContentType)

            let result: Any

            if isFile {
                guard let filename = KVs["filename"] else {
                    logger.debug("File does not contain filename: \(headers)")
                    continue
                }
                result = LGNC.Entity.File(filename: filename, contentType: contentType, body: Bytes(body))
            } else /* String */ {
                result = String(bytes: body, encoding: .utf8)!
            }

            output[name] = result
        }

        return output
    }
}
