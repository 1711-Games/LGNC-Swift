public enum Entita {
    public typealias Dict = [String: Any]

    /// Controls whether `keyDictionary` is used when packing/unpacking the entity
    ///
    /// `false` by default
    public static var KEY_DICTIONARIES_ENABLED = false
    public static let DEFAULT_ID_LABEL = "ID"
}
