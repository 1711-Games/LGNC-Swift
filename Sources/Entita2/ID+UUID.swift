import Foundation
import LGNCore

public extension E2 {
    public typealias UUID = ID<Foundation.UUID>
}

public extension E2.ID where Value == UUID {
    public var string: String {
        return self.value.uuidString
    }

    public init(_ uuid: UUID = UUID()) {
        self.init(value: uuid)
    }

    public init?(_ string: String) {
        guard let uuid = UUID(uuidString: string) else {
            return nil
        }
        self.value = uuid
    }
}

extension E2.ID: Codable where Value == UUID {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let result = try container.decode(Data.self)
        
        guard result.count == 16 else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Attempted to decode UUID from invalid byte sequence."
                )
            )
        }
        self.init(UUID(uuid: [UInt8](result).cast()))
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        let bytes = LGNCore.getBytes(self.value)
        try container.encode(Data(bytes))
    }
}
