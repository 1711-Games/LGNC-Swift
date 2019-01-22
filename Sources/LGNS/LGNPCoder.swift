import Foundation // tmp
import LGNP
import NIO

internal extension LGNS {
    internal final class LGNPCoder: ChannelDuplexHandler {
        fileprivate enum State {
            case start, waitingForHeader, waitingForBody
        }
        
        typealias InboundIn = ByteBuffer
        typealias InboundOut = LGNP.Message
        typealias OutboundIn = LGNP.Message
        typealias OutboundOut = ByteBuffer

        internal static let MINIMUM_MESSAGE_LENGTH = 1024
        internal static let MESSAGE_HEADER_LENGTH = Int(LGNP.MESSAGE_HEADER_LENGTH)

        private var buffer: ByteBuffer!
        private var messageLength: UInt32!
        private var state: State = .start

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
            ctx.close(promise: nil)
            ctx.fireErrorCaught(error)
        }

        public func channelRead(ctx: ChannelHandlerContext, data: NIOAny) {
            var input = self.unwrapInboundIn(data)
            var updateBuffer = true

            switch self.state {
            case .start:
                self.buffer = input
                self.state = .waitingForHeader
                updateBuffer = false
                fallthrough
            case .waitingForHeader:
                if updateBuffer {
                    self.buffer.write(buffer: &input)
                }

                if let headerBytes = self.buffer.readBytes(length: LGNPCoder.MESSAGE_HEADER_LENGTH) {
                    do {
                        try self.parseHeaderAndLength(from: headerBytes, ctx)
                        self.state = .waitingForBody
                        fallthrough
                    } catch LGNP.E.TooShortHeaderToParse {
                        // pass
                    } catch {
                        ctx.fireErrorCaught(error)
                        return
                    }
                }
            case .waitingForBody:
                if updateBuffer {
                    self.buffer.write(buffer: &input)
                }

                if
                    self.buffer.readableBytes + LGNPCoder.MESSAGE_HEADER_LENGTH >= self.messageLength, // buffer size is at least stated bytes long
                    let bytes = self.buffer.readAllBytes() // all other bytes are read from buffer
                {
                    self.buffer = nil // clear buffer
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
                        
                        self.state = .start
                    } catch {
                        ctx.fireErrorCaught(error)
                    }
                }
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
