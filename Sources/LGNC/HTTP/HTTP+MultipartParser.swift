import NIOHTTP1
import LGNCore
import LGNLog
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
    /// Parses a `multipart/form-data` body (RFC 7578). Malformed parts are skipped, never trap.
    ///
    /// Text fields become `String`s (parts with invalid UTF-8 are skipped), parts with a `Content-Type` header
    /// become ``LGNC/Entity/File``s.
    static func parseMultipartFormdata(boundary: String, input: Bytes) -> Entita.Dict {
        let logger = Logger.current

        let delimiter = Bytes(("--" + boundary).utf8)
        var output = [String: Any]()

        // Positions right after each delimiter
        var partStarts: [Int] = []
        var searchFrom = 0
        while searchFrom < input.count, let found = input[searchFrom...].firstRange(of: delimiter) {
            partStarts.append(found.upperBound)
            searchFrom = found.upperBound
        }
        guard partStarts.count >= 2 else {
            logger.debug("Multipart body contains less than two boundaries")
            return output
        }

        for (index, start) in partStarts.dropLast().enumerated() {
            // The part ends where the next delimiter begins (minus the delimiter's own preceding line break)
            var end = partStarts[index + 1] - delimiter.count
            var start = start
            // Closing delimiter `--boundary--`
            if input[start...].starts(with: [45, 45]) {
                break
            }
            if input[start...].starts(with: [13, 10]) {
                start += 2
            } else if input[start...].starts(with: [10]) {
                start += 1
            }
            if end >= start + 2, input[end - 2 ..< end] == [13, 10] {
                end -= 2
            } else if end >= start + 1, input[end - 1] == 10 {
                end -= 1
            }
            guard start <= end else {
                logger.debug("Empty multipart part")
                continue
            }
            let part = input[start ..< end]

            let separator: Range<Int>
            if let crlf = part.firstRange(of: [13, 10, 13, 10]) {
                separator = crlf
            } else if let lf = part.firstRange(of: [10, 10]) {
                separator = lf
            } else {
                logger.debug("Multipart part doesn't contain headers separator")
                continue
            }

            let headers = HTTPHeaders(
                String(decoding: part[..<separator.lowerBound], as: UTF8.self)
                    .split(whereSeparator: { $0 == "\n" || $0 == "\r\n" || $0 == "\r" })
                    .compactMap { rawHeader -> (String, String)? in
                        let components = rawHeader
                            .split(separator: ":", maxSplits: 1)
                            .map { $0.trimmingCharacters(in: .whitespaces) }
                        guard components.count == 2 else {
                            return nil
                        }
                        return (components[0], components[1])
                    }
            )
            let body = part[separator.upperBound...]

            guard let contentDisposition = headers.first(name: "Content-Disposition"),
                  contentDisposition.contains("form-data")
            else {
                logger.debug("Multipart part without form-data Content-Disposition")
                continue
            }
            let KVs = LGNCore.parseKV(from: contentDisposition)
            guard let name = KVs["name"] else {
                logger.debug("Content-Disposition does not contain 'name' value: \(contentDisposition)")
                continue
            }

            if let rawContentType = headers.first(name: "Content-Type") {
                guard let filename = KVs["filename"] else {
                    logger.debug("File does not contain filename: \(headers)")
                    continue
                }
                output[name] = LGNC.Entity.File(
                    filename: filename,
                    contentType: LGNCore.ContentType(rawValue: rawContentType),
                    body: Bytes(body)
                )
            } else {
                guard let value = String(validating: body, as: UTF8.self) else {
                    logger.debug("Multipart field '\(name)' is not valid UTF-8")
                    continue
                }
                output[name] = value
            }
        }

        return output
    }
}
