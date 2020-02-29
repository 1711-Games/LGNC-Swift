# LGNS — LGN Server

## About
LGNS is a server which uses LGNP as exchange protocol. The idea behind it is to send less data (compared to HTTP[S]) and use less
middleware as LGNS doesn't require reverse proxy, directly listening port/socket and working with application code in the same runtime.

LGNS is built on top of Swift-NIO and powers LGN Contracts (LGNC), so if you'd like to know LGNS better, as it's preferred transport there,
you should check LGNC documentation.

LGNS doesn't have any form of routing, in fact, it only has one resolver which receives `LGNP.Message` and `LGNCore.Context` as input,
and expects an `EventLoopFuture<LGNP.Message?>` as output. That simple. It's up to programmer on how to route the request.

## Usage
Please see complete example:

```swift
import LGNS

// Just for convenience
let logger = Logger(label: "main")

// An event loop group to run server on
let eventLoopGroup: EventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)

// An instance of LGNP.Cryptor, which is used for encryption/decryption and HMAC signing of messages.
let cryptor = try LGNP.Cryptor(key: [1,2,3,4,5,6,7,8,9,0,1,2,3,4,5,6])

// A required control bitmask, which, in this particular case requires all messages to be signed with
// SHA512 HMAC signature, additionally messages must be encrypted (key above in Cryptor, same key must be used in
// all other services. And finally, messages must always be in MsgPack format. BTW, it's actually recommended
// in general, as it's more compact than JSON.
let requiredBitmask = LGNP.Message.ControlBitmask([.encrypted, .signatureSHA512, .contentTypeMsgPack])

// Instance of LGN Server with all previous credentials/options. Last argument is a resolver closure which must
// route the message to concrete action. It receives LGNP Message and context struct (see LGNCore documentation),
// and expects to return an EventLoopFuture with optional response LGNP Message as Value type.
let server: AnyServer = LGNS.Server(
    cryptor: cryptor,
    requiredBitmask: requiredBitmask,
    eventLoopGroup: eventLoopGroup
) { (message: LGNP.Message, context: LGNCore.Context) -> Future<LGNP.Message?> in
    guard
        let action: (LGNP.Message, LGNCore.Context) -> Future<LGNP.Message?> = MyCustomAppRouter.route(URI: message.URI)
    else {
        return context.eventLoop.makeSucceededFuture(nil)
    }

    return action(message, context)
}

// Next we define a trap function to be executed on INT or TERM signal. All servers that conform to AnyServer protocol
// must register themselves in SignalObserver class. When signal is caught, we inform SignalObserver with that signal,
// and it shuts down all registered servers.
let trap: @convention(c) (Int32) -> Void = { s in
    logger.info("Received signal \(s)")

    _  = try! SignalObserver.fire(signal: s).wait()

    logger.info("Server is down")
}
// This is where we register INT and TERM signal traps.
signal(SIGINT, trap)
signal(SIGTERM, trap)

// At this point server hasn't started yet, so we bind it to an address and wait for this process to complete.
// It's safe to call .wait() on EventLoopFuture on main thread, because we're not in EventLoop context.
try server.bind(to: .ip(host: "0.0.0.0", port: 1711)).wait()
logger.info("Server started")

// This call will block current thread (main) until server is down.
try server.waitForStop()
logger.info("Server stopped, exiting")
```

To test out the server bootstrap, try running `swift run` in command line. You will see something like:

```
2020-02-29T22:36:52+0300 info: LGNS Server: Trying to bind at 0.0.0.0:1711
2020-02-29T22:36:52+0300 info: LGNS Server: Succesfully started on 0.0.0.0:1711
2020-02-29T22:36:52+0300 info: Server started
```

If you press Ctrl+C, the server will stop:

```
^C2020-02-29T22:37:00+0300 info: Received signal 2
2020-02-29T22:37:00+0300 info: LGNS Server: Shutting down
2020-02-29T22:37:00+0300 info: LGNS Server: Goodbye
2020-02-29T22:37:00+0300 info: Server is down
2020-02-29T22:37:00+0300 info: Server stopped, bye
```

You're good :)

## FAQ

### Should I use bare LGNS?
You may :) Though, you might find it not powerful enough compared to classic HTTP servers. This is the weakness and strength of LGNS.

### What LGNS is best for?
Originally it was developed with internal game services communication in mind (both between instances of the same service, and for
interservice communication). Therefore simplicity and speed have been prioritized. But really it's suitable for any [micro]service architecture
which uses communication between services across public or private networks — let's call it S2S (service-to-service). This is where LGNS
really shines. It's totally not intended to work as C2S (customer-to-service), as it's an antipattern at its finest.

There is one more important aspect of LGNS you gotta know: since LGNP is one extremely simple protocol, and therefore doesn't have any
version negotiation mechanism (nor does it use TLS in favor of pre-distributed AES key across all clients), all system participants are tied
together more _than they could_. I'm quite sure this fact critically violates The Holy Cow of all theoretical architectors — the The Twelve-Factor
App methodology (probably even more than one paragraph). You may even call the system built with LGNS (or LGNC) a loosely coupled
(a distributed) monolith, if you'd like, however, real world has real challenges, that are rarely solved by idealistic methologies. Sorry about that
(no).


