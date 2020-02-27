# LGNP

## About
LGNP stands for LGN Protocol. It's an application protocol for sending compact packets of binary data (messages) across public or private network. It's somewhat similar to HTTP: it has rudimentary form of HTTP headers (as control bitmask and optional meta section), it supports keep-alive, and also some other things. LGNP supports end-to-end encryption (AES GCM) and HMAC.

The main purpose of LGNP is exchanging small messages between services. Surprisingly, you don't need all power of HTTP for that simple task :) LGNP is heavily used in LGNS (LGN Server).

## Specification
This section explains LGNP MK8 format, specification and recommendations on effective parsing.

LGNP message consists of following blocks (placed in logical order):

* `HEAD` — message header. It's always static — just four bytes of ASCII `LGNP` (or just `Array<UInt8>([76, 71, 78, 80])`). Any message that starts not from these bytes must be considered invalid.
* `SIZE` — 4 bytes of message size in LE (little-endian) `UInt32` (this value should include size of `HEAD` and `SIZE` blocks). Message that is less than this value must be considered invalid. Larger message may be considered invalid, or valid after trimming.
* `UUID` — 16 bytes of v4 UUID. Same UUID may be reused when responding to a message. 
* `BMSK` — 2 bytes of control bitmask in LE `UInt16`, see respective section below on control bitmasks.
* `SIGN` — (optional, if stated in `BMSK`) some number of bytes of HMAC-signature (depends of algo), computed as `HMAC<algo>(URI + MSZE + META + BODY + UUID, KEY)`.
* `URI` — some number of bytes of URI and a terminating `NUL` byte.
* `MSZE` — (optional, if stated in `BMSK`) 4 bytes of meta section size in LE `UInt32`
* `META` — (optional, if stated in `BMSK`) some number of bytes of meta section (size is specified in `MSZE`), see details in respective section.
* `BODY` — some number of payload bytes (size is `SIZE` minus size of every preceeding block, e.g. `BODY` is the rest of message trimming after `SIZE`)

Sections starting from `SIGN` (uncluding one) may be encrypted with AES (GCM) using external secret key and first 12 bytes of `UUID` as nonce, encrypted payload is followed by tag. Sections starting from `URI` (including one) are hashed into `SIGN` (before encryption).

Possible failfast scenarios:
* message size is less than 28 bytes 
* `HEAD` isn't `LGNP` bytes
* `UUID` isn't a v4 UUID

## Control bitmask (`MBSK` block)
Control bitmask is a 2 bytes block which holds a bitmask with various flags related to current message. Possible values are:
* `0 << 0 (0)` — default params (no signature, no encryption, no compression, no explicit content type)
* `1 << 0 (1)` — keep connection alive after this message
* `1 << 1 (2)` — message contains AES-encrypted section
* `1 << 2 (4)` — message is GZIP-compressed
* `1 << 3 (8)` — message contains meta section
* `1 << 4 (16)` — message contains protocol error response
* `1 << 5 (32)` — SHA256 signature (32 bytes)
* `1 << 6 (64)` — SHA384 signature (48 bytes)
* `1 << 7 (128)` — SHA512 signature (64 bytes)
* `1 << 8 (256)` — reserved
* `1 << 9 (512)` — reserved
* `1 << 10 (1024)` — reserved
* `1 << 11 (2048)` — payload is plain text (binary safe)
* `1 << 12 (4096)` — payload is MsgPack
* `1 << 13 (8192)` — payload is JSON
* `1 << 14 (16384)` — payload is XML
* `1 << 15 (2^15)` — reserved
* `1 << 16 (2^16)` — reserved

## Meta section
Meta section is introduced in order to send additional arbitrary data, but in a logically separated way from payload. LGNS uses it for sending various info like client address, remote address, locale, user agent etc as lines (separated by `NL` octet, `0x10`) of `NUL`-separated key-value pairs. Example: `0x00 0x255 KEY 0x00 VALUE 0x10 ANOTHERKEY 0x00 ANOTHERVALUE 0x10` (spaces for readability). `NUL` and `0x255` octets in the beginning are added for failfast check.

## Limitations
LGNP message cannot be larger than 4 gigabytes (due to `SIZE` max size which is `UInt32.max`, hence 4,294,967,295 bytes).

## Swift API usage
You don't really have to implement this specification yourself unless you want to implement LGNP in other language :) If we're talking Swift, it's rather simple to use.

First you create a message instance:

```swift
let message = LGNP.Message(
    URI: "foo",
    payload: Bytes([1,2,3]),
    meta: Bytes([4,5,6]), // optional
    controlBitmask: [.contentTypePlainText, .signatureSHA256],
    uuid: UUID() // may be omitted
)
```

You don't have to set `.containsMeta` flag into control bitmask if you explicitly set the meta.

Then you would like to encode this message to bytes. First, you need a Cryptor, which is just a reusable helper for encryption:

```swift
let cryptor = try LGNP.Cryptor(key: "1234567890123456")

// or using bytes key

let cryptor = try LGNP.Cryptor(key: Bytes([1,2,3,4,5,6,7,8,9,0,1,2,3,4,5,6])
```

Key must be 16 or 24 or 32 bytes long. 

And the final step is encoding the message:

```swift
let encoded: Bytes = try LGNP.encode(message: message, with: cryptor)
```

It does encryption and HMAC signing for you, don't worry :)

In order to decode a message from bytes, you do following:

```swift
let decoded: LGNP.Message = try LGNP.decode(body: bytes, with: cryptor)
```
