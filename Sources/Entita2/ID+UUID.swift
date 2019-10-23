import Foundation
import LGNCore

public extension E2 {
    typealias UUID = ID<Foundation.UUID>
}

public extension E2.ID where Value == UUID {
    var string: String {
        value.uuidString
    }

    init(_ uuid: UUID = UUID()) {
        self.init(value: uuid)
    }

    init?(_ string: String) {
        guard let uuid = UUID(uuidString: string) else {
            return nil
        }
        value = uuid
    }
}

extension E2.ID: Codable where Value == UUID {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let result = try container.decode(Data.self)

        self.init(UUID(uuid: try [UInt8](result).cast()))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        let bytes = LGNCore.getBytes(value)
        try container.encode(Data(bytes))
    }
}
