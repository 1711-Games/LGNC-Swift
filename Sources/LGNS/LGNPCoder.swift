import Foundation // tmp
import LGNP
import NIO

internal extension LGNS {
    internal final class LGNPCoder: ChannelDuplexHandler {
        typealias InboundIn = ByteBuffer
        typealias InboundOut = LGNP.Message
        typealias OutboundIn = LGNP.Message
        typealias OutboundOut = ByteBuffer

        private static let MINIMUM_MESSAGE_LENGTH = 1024

        private var buf: ByteBuffer!
        private var messageLength: UInt32?

        private let cryptor: LGNP.Cryptor
        private let requiredBitmask: LGNP.Message.ControlBitmask
        private let salt: Bytes
        private let validateRequiredBitmask: Bool

        public init(
            cryptor: LGNP.Cryptor,
            requiredBitmask: LGNP.Message.ControlBitmask = .defaultValues,
            validateRequiredBitmask: Bool = true
        ) {
            self.cryptor = cryptor
            self.requiredBitmask = requiredBitmask
            self.salt = Bytes(self.cryptor.salt.utf8)
            self.validateRequiredBitmask = validateRequiredBitmask
        }

        public func userInboundEventTriggered(ctx: ChannelHandlerContext, event: Any) {
            if event is IdleStateHandler.IdleStateEvent {
                ctx.fireErrorCaught(LGNS.E.Timeout)
            }
            ctx.fireUserInboundEventTriggered(event)
        }

        private func parseHeaderAndLength(from input: Bytes, _: ChannelHandlerContext) throws {
            self.messageLength = UInt32(
                try LGNP.validateMessageProtocolAndParseLength(
                    from: input,
                    checkMinimumMessageSize: false
                )
            )
        }

        public func errorCaught(ctx: ChannelHandlerContext, error: Error) {
            print("error: \(error)")
            ctx.close(promise: nil)
            ctx.fireErrorCaught(error)
        }

        public func channelRead(ctx: ChannelHandlerContext, data: NIOAny) {
            var input = self.unwrapInboundIn(data)
            // fresh start, no buffer yet
            if self.buf == nil {
                // try to read message header and allocate exact buffer size
                if let headerBytes = input.readBytes(length: Int(LGNP.MESSAGE_HEADER_LENGTH)) {
                    do {
                        // allocate full buffer
                        try self.parseHeaderAndLength(from: headerBytes, ctx)
                        self.buf = ctx.channel.allocator.buffer(capacity: Int(self.messageLength!))
                        let bytes = input.readAllBytes()
                        self.buf.write(bytes: headerBytes)
                        self.buf.write(bytes: bytes ?? [])
                    } catch {
                        // print("error occured while trying to parse length")
                        ctx.fireErrorCaught(error)
                        return
                    }
                } else if let chunkBytes = input.readAllBytes() {
                    self.buf = ctx.channel.allocator.buffer(capacity: LGNPCoder.MINIMUM_MESSAGE_LENGTH)
                    self.buf.write(bytes: chunkBytes)
                }
            } else if let chunkBytes = input.readAllBytes() {
                self.buf.write(bytes: chunkBytes)
            }
            if self.messageLength == nil, let headerBytes = self.buf.readBytes(length: LGNP.MESSAGE_HEADER_LENGTH) {
                do {
                    try self.parseHeaderAndLength(from: headerBytes, ctx)
                } catch LGNP.E.TooShortHeaderToParse {
                    // pass
                } catch {
                    ctx.fireErrorCaught(error)
                    return
                }
            }
            if
                let messageLength = self.messageLength, // there is header length parsed
                self.buf.readableBytes >= messageLength, // buffer size is at least stated bytes long
                let _ = self.buf.readBytes(length: LGNP.MESSAGE_HEADER_LENGTH), // ignore header bytes
                let bytes = self.buf.readAllBytes() // all other bytes are read from buffer
            {
                self.buf = nil // clear buffer
                // try to parse
                do {
                    let message = try LGNP.decode(
                        body: bytes,
                        length: messageLength,
                        with: self.cryptor,
                        salt: self.salt
                    )
                    if message.containsError {
                        ctx.fireErrorCaught(LGNS.E.LGNPError(message.payloadAsString))
                        return
                    }
                    guard !self.validateRequiredBitmask || message.controlBitmask.isSuperset(of: self.requiredBitmask) else {
                        ctx.fireErrorCaught(LGNS.E.RequiredBitmaskNotSatisfied)
                        return
                    }
                    ctx.fireChannelRead(self.wrapInboundOut(message))
                } catch {
                    ctx.fireErrorCaught(error)
                }
            } else {
                print("still waiting")
            }
        }

        public func write(ctx: ChannelHandlerContext, data: NIOAny, promise: PromiseVoid?) {
            do {
                ctx.write(
                    self.wrapOutboundOut(
                        ctx.channel.allocator.allocateBuffer(
                            from: try LGNP.encode(
                                message: self.unwrapOutboundIn(data),
                                with: self.cryptor
                            )
                        )
                    ),
                    promise: promise
                )
            } catch {
                promise?.fail(error: error)
            }
        }
    }
}
