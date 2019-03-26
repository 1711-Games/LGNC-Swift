import Foundation // tmp
import LGNP
import NIO

internal extension LGNS {
    final class LGNPCoder: ChannelDuplexHandler {
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
            salt = Bytes(self.cryptor.salt.utf8)
            self.validateRequiredBitmask = validateRequiredBitmask
        }

        public func userInboundEventTriggered(ctx: ChannelHandlerContext, event: Any) {
            if event is IdleStateHandler.IdleStateEvent {
                ctx.fireErrorCaught(LGNS.E.Timeout)
            }
            ctx.fireUserInboundEventTriggered(event)
        }

        private func parseHeaderAndLength(from input: Bytes, _: ChannelHandlerContext) throws {
            messageLength = UInt32(
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
            var input = unwrapInboundIn(data)
            var updateBuffer = true

            switch state {
            case .start:
                buffer = input
                state = .waitingForHeader
                updateBuffer = false
                fallthrough
            case .waitingForHeader:
                if updateBuffer {
                    buffer.writeBuffer(&input)
                }

                if
                    buffer.readableBytes >= LGNPCoder.MESSAGE_HEADER_LENGTH,
                    let headerBytes = self.buffer.readBytes(length: LGNPCoder.MESSAGE_HEADER_LENGTH) {
                    do {
                        try parseHeaderAndLength(from: headerBytes, ctx)
                        state = .waitingForBody
                        fallthrough
                    } catch {
                        ctx.fireErrorCaught(error)
                        return
                    }
                }
            case .waitingForBody:
                if updateBuffer {
                    buffer.writeBuffer(&input)
                }

                if
                    buffer.readableBytes + LGNPCoder.MESSAGE_HEADER_LENGTH >= messageLength, // buffer size is at least stated bytes long
                    let bytes = self.buffer.readAllBytes() { // all other bytes are read from buffer
                    buffer = nil // clear buffer
                    // try to parse
                    do {
                        let message = try LGNP.decode(
                            body: bytes,
                            length: messageLength,
                            with: cryptor,
                            salt: salt
                        )
                        if message.containsError {
                            ctx.fireErrorCaught(LGNS.E.LGNPError(message.payloadAsString))
                            return
                        }
                        guard !validateRequiredBitmask || message.controlBitmask.isSuperset(of: requiredBitmask) else {
                            ctx.fireErrorCaught(LGNS.E.RequiredBitmaskNotSatisfied)
                            return
                        }
                        ctx.fireChannelRead(wrapInboundOut(message))

                        state = .start
                    } catch {
                        ctx.fireErrorCaught(error)
                    }
                }
            }
        }

        public func write(ctx: ChannelHandlerContext, data: NIOAny, promise: PromiseVoid?) {
            do {
                ctx.write(
                    wrapOutboundOut(
                        ctx.channel.allocator.allocateBuffer(
                            from: try LGNP.encode(
                                message: unwrapOutboundIn(data),
                                with: cryptor
                            )
                        )
                    ),
                    promise: promise
                )
            } catch {
                promise?.fail(error)
            }
        }
    }
}
