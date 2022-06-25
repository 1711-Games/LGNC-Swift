import LGNCore
import LGNLog
import Entita

public typealias Meta = LGNC.Entity.Meta
public typealias CanonicalCompositeRequest = Swift.Result<Entity, Error>
public typealias CanonicalStructuredContractResponse = (response: Entity, meta: Meta)

/// A type erased contract
public protocol AnyContract {
    /// Canonical form of contract body (guarantee) type
    typealias CanonicalGuaranteeBody = (CanonicalCompositeRequest) async throws -> ContractExecutionResult

    /// URI of contract, must be unique for service
    static var URI: String { get }

    /// Indicates whether contract can be invoked with HTTP GET method (and respective GET params)
    static var isGETSafe: Bool { get }

    /// Allowed transports for contract, must not be empty
    static var transports: [LGNCore.Transport] { get }

    /// Preferred transport to be used by client if no transport is provided, see default implementation
    static var preferredTransport: LGNCore.Transport { get }

    /// Allowed content types of request for contract, must not be empty
    static var contentTypes: [LGNCore.ContentType] { get }

    /// Preferred content type of request for contract, see default implementation
    static var preferredContentType: LGNCore.ContentType { get }

    /// Indicates whether this contract returns response in structured form (i.e. an API contract in JSON/MsgPack format)
    static var isResponseStructured: Bool { get }

    /// A computed property returning `true` if contract is guaranteed
    static var isGuaranteed: Bool { get }

    /// Contract guarantee closure body (must not be set directly)
    static var _guaranteeBody: Optional<Self.CanonicalGuaranteeBody> { get set }

    /// An internal method for invoking contract with given raw dict (context is available via `LGNCore.Context.current`), not to be used directly
    static func _invoke(with dict: Entita.Dict) async throws -> ContractExecutionResult
}

public extension AnyContract {
    static var isResponseStructured: Bool {
        true
    }

    static var isWebSocketTransportAvailable: Bool {
        self.transports.contains(.WebSocket)
    }

    static var isWebSocketOnly: Bool {
        self.transports == [.WebSocket]
    }

    static var isGETSafe: Bool { false }

    static var preferredTransport: LGNCore.Transport {
        guard self.transports.count > 0 else {
            Logger.current.error("Empty transports in contract \(Self.self), returning .LGNS")
            return .LGNS
        }

        if self.transports.contains(.LGNS) {
            return .LGNS
        }

        return .HTTP
    }

    static var preferredContentType: LGNCore.ContentType {
        guard self.transports.count > 0 else {
            Logger.current.error("Empty content-types in contract \(Self.self), returning .JSON")
            return .JSON
        }

        if Self.preferredTransport == .LGNS && self.contentTypes.contains(.MsgPack) {
            return .MsgPack
        }

        return .JSON
    }

    static var isGuaranteed: Bool {
        self._guaranteeBody != nil
    }
}
