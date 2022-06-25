import Entita

public struct ContractExecutionResult {
    public enum Result {
        case Structured(Entity)
        case Binary(LGNC.Entity.File, HTTP.ContentDisposition?)
    }

    public let result: Self.Result
    public internal(set) var meta: Meta

    public init(result: Self.Result, meta: Meta = [:]) {
        self.result = result
        self.meta = meta
    }

    public init(result: LGNC.Entity.Result, meta: Meta = [:]) {
        self.init(result: .Structured(result), meta: meta)
    }
}
