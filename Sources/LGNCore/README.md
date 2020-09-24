# LGNCore

## About
This is a core module containing all shared tools required by all other LGNC-Swift modules.

In particular, it has following useful tools:
* [`LGNCore.Config`](#lgncoreconfig-usage), a simple class for managing application config (by default loads `$ENV`).
* [`LGNCore.i18n`](#lgncorei18n-usage), a tool for translating strings, comes with two builtin backends: `DummyTranslator`, which doesn't do anything at all except for proxying all input with respective optional interpolation, and `FactoryTranslator`, which holds an in memory translation registry.
* [`LGNCore.Profiler`](#lgncoreprofiler-usage), a very simple tool for profiling your code.
* [`LGNCore.AppEnv`](#lgncoreappenv-usage) for managing application environment (local, dev, qa, stage, production)
* [`LGNCore.Context`](#lgncorecontext-usage), a simple structure for holding request and response context details like event loop, logger, remote address, locale etc. Heavily used in LGNC (todo link).
* [`LGNCore.Logger`](#lgncorelogger-usage), a custom backend for SSWG `Logging` logger with pretty output
* Minor tools:
* * `AnyServer`, a protocol used in LGNS and LGNC for defining general server interface (`AnyServer.swift`)
* * Various unsafe `Array<UInt8>` extensions for casting anything to bytes and back ([`BytesTrickery.swift`](#bytes-trickery-usage))
* * A polyfill version of `precondition` function which prints error message even if product is built in RELEASE mode, an extension for `Foundation.UUID` which initializes an UUID instance with `Array<UInt8>` (`Helpers.swift`)
* * An extension for `NIO.EventLoop.makeSucceededFuture` which does not take any parameters and returns a new `EventLoopFuture<Void>`.

Additionally, this module defines following typealises:
* `typealias Byte = UInt8`
* `typealias Bytes = [Byte]`

## `LGNCore.Config` usage
In order to use this class you have to define an `enum` with all config keys. Example:

```swift
public enum ConfigKeys: String, AnyConfigKey {
    case KEY
    case SALT
    case LOG_LEVEL
    case HTTP_PORT
    case PRIVATE_IP
    case REGISTER_TO_CONSUL
}
```

Then you try to init the config. `main.swift` is not the worst place for it, as it doesn't require `try` calls to be wrapped with `do catch`:

```swift
let config = try LGNCore.Config<ConfigKeys>(
    env: AppEnv.detect() // see documentation on `LGNCore.AppEnv` below,
    rawConfig: ProcessInfo.processInfo.environment, // this is optional, you may provide any `[AnyHashable: String]` input here
    localConfig: [
        .KEY: "sdfdfg",
        .SALT: "mysecretsalt",
        .LOG_LEVEL: "trace",
        .HTTP_PORT: "8081",
        .PRIVATE_IP: "127.0.0.1",
        .REGISTER_TO_CONSUL: "false",
    ]
)
```

`localConfig` argument contains default config entries for `local` app environment, or else it exits the application with respective message if one or more config entries are missing from config. Then you use config like this:

```swift
let cryptor = try LGNP.Cryptor(salt: config[.SALT], key: config[.KEY])
```

Please notice that subscript with enum keys returns non-optional string value. It's because all keys are expected to be present in initialized config, and if not, there is something very wrong with `LGNCore.Config`, and should be reported. However, if it happens, the return value will be something like `__HTTP_PORT__MISSING`. But again, it should not happen at all.

Additionally you can try to get a config value by string key name:

```swift
let HTTPPort: String? = config["HTTP_PORT"]
```

This call returns optional string because of obvious reasons.

## `LGNCore.i18n` usage
i18n component is initialized in following way:

```swift
typealias Phrase = LGNCore.i18n.Phrase

let phrases: [LGNCore.i18n.Locale: Phrases] = [
    .ruRU: [
        "Comment must be less than {Length} characters long": Phrase(
            one: "Комментарий должен быть не короче {Length} символа",
            few: "Комментарий должен быть не короче {Length} символов",
            many: "Комментарий должен быть не короче {Length} символов",
            other: "Комментарий должен быть не короче {Length} символа"
        ),
        "Fields must be identical": "Поля должны быть идентичны",
        "Invalid date format (valid format: {format})": "Неправильный формат даты (правильный формат: {format})",
    ],
    .enUS: [:],
]

LGNCore.i18n.translator = LGNCore.i18n.FactoryTranslator(
    phrases: phrases,
    allowedLocales: [.enUS, .ruRU]
)
```

And then use it like this:

```swift
let translatedString: String = LGNCore.i18n.tr(
    "Comment must be less than {Length} characters long",
    .ruRU,
    ["Length": 10]
)
```

Of course it looks a little bit cumbersome, so you may define a handy extension:

```swift
public extension String {
    @inlinable func tr(_ locale: LGNCore.i18n.Locale, _ interpolations: [String: Any] = [:]) -> String {
        LGNCore.i18n.tr(self, locale, interpolations)
    }
}
```

and thus use it like this:

```swift
let translated = "Fields must be identical".tr(context.locale)
```

If you do not initialize the translator, `tr` will do nothing except for interpolations, so it's quite safe to use uninitialized translator.

## `LGNCore.Profiler` usage
Extremely simple:

```swift
let profiler = LGNCore.Profiler.begin()
// some heavy work
let time: Float = profiler.end()
```

You might also want to round the result to something reasonable like `0.322`.

Another case:

```swift
let time: Float = LGNCore.profiled {
    // some heavy work
}
```

## `LGNCore.AppEnv` usage
By default it's implied that you store your app config, including `APP_ENV` value, in `$ENV`. In this case you initialize your `APP_ENV` like this:

```swift
let APP_ENV = AppEnv.detect()
```

In case it's done in other way, you should pass a `[String: String]` dictionary:

```swift
let APP_ENV = AppEnv.detect(from: dictionary)
```

There are five levels of app environment:

```
local
dev
qa
stage
production
```

On macOS the result value defaults to `.local` if no `APP_ENV` is provided in environment. Otherwise it exits the application with an error, because `APP_ENV` must always be provided explicitly in non-local environment.

## `LGNCore.Context` usage
`LGNCore.Context` is a simple struct holding essential request or response data, such as:

1. `remoteAddr` — network address from which this request physically came from. It might not be actual client address, but rather last proxy server address.
2. `clientAddr` — actual end client address (see details in LGNS and LGNC modules on how this field is populated).
3. `clientID` — an optional field holding client unique ID (used only in LGNS, see details in readme).
4. `userAgent` — a user agent, nuff said.
5. `locale` — user locale of request or response (see details in LGNS and LGNC).
6. `uuid` — a unique identifier of this request (in UUID v4 format)
7. `isSecure` — indicates whether request has been encrypted/signed (only relevant for LGNS, not for HTTPS)
8. `transport` — request transport (LGNS, HTTP)
9. `eventLoop` — and `EventLoop` on which this request is being processed
10. `logger` — logger for current request (already contains `uuid` as `requestID` in metadata)

## `LGNCore.Logger` usage
LGNCore comes with custom Logger backend implementation which produces following output (human-readable date, file in which log message has been emitted and JSON formatting of metadata):

```swift
LoggingSystem.bootstrap(LGNCore.Logger.init)

let myLogger = Logger(label: "test")

myLogger.info("Some test message", metadata: ["foo": "bar", "requestID": "\(UUID())"])

// Output will be
// [2020-02-18 14:38:48 @ main:8] [info] [F41988B9-1ED7-4AAC-9827-588D077B81F9]: Some test message (metadata: {"foo":"bar"})
```

Please notice that `requestID` was extracted from metadata and put in front of the rest of the message.

Additionally, you may also set a default log level for ALL further loggers:

```swift
LGNCore.Logger.logLevel = .trace
```

Or, using previously initialized config:

```swift
let defaultLogger = Logger(label: "LGNCore.Default")

guard let logLevel = Logger.Level(string: config[.LOG_LEVEL]) else {
    defaultLogger.critical("Invalid LOG_LEVEL value: \(config[.LOG_LEVEL])")
    fatalError()
}

LGNCore.Logger.logLevel = logLevel
```

## Bytes trickery usage
**Attention: following tools are a pathway to many abilities some consider to be unnatural.**

Say, you want to convert your string or integer variable into an array of bytes for further sending over network. You should do following:

```swift
let myString = "Hello world"
let myInteger: Int64 = 322

let myStringBytes: Bytes = LGNCore.getBytes(myString) // [72, 101, 108, 108, 111, 32, 119, 111, 114, 108, 100]
let myIntegerBytes: Bytes = LGNCore.getBytes(myInteger) // [66, 1, 0, 0, 0, 0, 0, 0]
```

Now while operation above is relatively safe, operation below isn't that safe and might crash your application:

```swift
let myStringUnpacked: String = try myStringBytes.cast() // "Hello world"
let myIntegerUnpacked: Int = try myIntegerBytes.cast() // 322
```

Remark: in reality, you can convert literally anything to bytes (and back again) with this function, yet, it becomes utterly unsafe to do that with anything other than scalars. This is not a serialization mechanism. Please use proper serialization like `Codable`.

Additionally there is an internal yet public extension for byte array which converts it to ASCII string:

```swift
Bytes([72, 101, 108, 108, 111, 32, 119, 111, 114, 108, 100])._string // "Hello world"
```

Even though `_string` implementation contains force unwrap `!`, I personally don't consider it unsafe, because I haven't yet encountered a single crash while using it (and I used it a lot, like a lot). But you shouldn't rely on it in real production environment. Please, only use it for development, it's really handy.
