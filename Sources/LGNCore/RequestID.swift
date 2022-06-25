public extension LGNCore {

    /// A random request ID.
    ///
    /// Attention: this value is random, but not random enough to be used in sensitive cryptographic operations.
    /// This RequestID has `2.8 * 10^28` of possible combinations, whereas UUID v4 got  `5.3 * 10^38`, which is a little more combinations
    /// (it's not 10 times more, it's 10 zeroes more)
    /// Still, this is acceptable risk since it's only to be used as request ID and nothing more.
    ///
    /// Why not UUID though? The root issue with it is its formatting: you can't select the whole thing with just a double click.
    /// However, removing hyphen wouldn't really help, as it's still extremely long (because of hex).
    /// This structure, however, is still 16 bytes and the alphabet is `a-zA-Z0-9` (instead of, well, hex),
    /// which makes it a bit shorter and a bit more readable (and memorable, UUIDs are more alike)
    struct RequestID {
        // Underlying structure, 16 bytes
        public typealias Value = (
            Byte, Byte, Byte, Byte,
            Byte, Byte, Byte, Byte,
            Byte, Byte, Byte, Byte,
            Byte, Byte, Byte, Byte
        )

        public enum E: Error {
            // The allowed alphabet is `a-zA-Z0-9`, hence not all 0-255 ASCII bytes are permitted
            case ValueContainsInvalidBytes(String)

            // Input contains not 16 bytes
            case InvalidInputSize
        }

        public static let rawAlphabet = Set<Character>([
            "0", "1", "2", "3", "4",
            "5", "6", "7", "8", "9",
            "a", "b", "c", "d", "e",
            "f", "g", "h", "i", "j",
            "k", "l", "m", "n", "o",
            "p", "q", "r", "s", "t",
            "u", "v", "w", "x", "y",
            "z",
            "A", "B", "C", "D", "E",
            "F", "G", "H", "I", "J",
            "K", "L", "M", "N", "O",
            "P", "Q", "R", "S", "T",
            "U", "V", "W", "X", "Y",
            "Z",
        ])

        public static let alphabet = Set<Byte>(Self.rawAlphabet.map { character in Bytes(character.utf8).first! })

        // Underlying value
        public let value: Value

        // String representation of the value
        @inlinable
        public var string: String {
            String(bytes: Self.getBytesFrom(value: self.value), encoding: .ascii)!
        }

        @usableFromInline
        internal static func getBytesFrom(value: Value) -> Bytes {
            Bytes([
                value.0, value.1, value.2, value.3,
                value.4, value.5, value.6, value.7,
                value.8, value.9, value.10, value.11,
                value.12, value.13, value.14, value.15,
            ])
        }

        // Creates an instance of RequestID from raw 16 bytes `Value`
        public init(value: Value) throws {
            guard Self.alphabet.isSuperset(of: Self.getBytesFrom(value: value)) else {
                throw E.ValueContainsInvalidBytes(String(bytes: Self.getBytesFrom(value: value), encoding: .ascii)!)
            }
            self.value = value
        }

        // Creates an instance of RequestID from arbitrary byte array (there must be exactly 16 bytes in it)
        public init(bytes: Bytes) throws {
            guard bytes.count == MemoryLayout<Value>.size else {
                throw E.InvalidInputSize
            }
            try self.init(
                value: (
                    bytes[0], bytes[1], bytes[2], bytes[3],
                    bytes[4], bytes[5], bytes[6], bytes[7],
                    bytes[8], bytes[9], bytes[10], bytes[11],
                    bytes[12], bytes[13], bytes[14], bytes[15]
                )
            )
        }

        // Generates a random RequestID
        public init() {
            let alphabet = Self.alphabet

            try! self.init(bytes: (0..<MemoryLayout<Value>.size).map { _ in alphabet.randomElement()! })
        }
    }
}

extension LGNCore.RequestID: CustomStringConvertible {
    public var description: String {
        self.string
    }
}

extension LGNCore.RequestID: CustomReflectable {
    public var customMirror: Mirror {
        Mirror(
            self,
            children: [(label: String?, value: Any)](),
            displayStyle: .struct
        )
    }
}

extension LGNCore.RequestID: Equatable {
    public static func == (lhs: LGNCore.RequestID, rhs: LGNCore.RequestID) -> Bool {
        lhs.string == rhs.string
    }
}
