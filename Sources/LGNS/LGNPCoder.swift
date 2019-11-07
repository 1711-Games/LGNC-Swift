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
        internal static let MESSAGE_HEADER_LENGTH = LGNP.MESSAGE_HEADER_LENGTH

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
            self.salt = self.cryptor.salt
            self.validateRequiredBitmask = validateRequiredBitmask
        }

        public func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
            if event is IdleStateHandler.IdleStateEvent {
                context.fireErrorCaught(LGNS.E.Timeout)
            }
            context.fireUserInboundEventTriggered(event)
        }

        private func parseHeaderAndLength(from input: Bytes, _: ChannelHandlerContext) throws {
            self.messageLength = UInt32(
                try LGNP.validateMessageProtocolAndParseLength(
                    from: input,
                    checkMinimumMessageSize: false
                )
            )
        }

        public func errorCaught(context: ChannelHandlerContext, error: Error) {
            context.close(promise: nil)
            context.fireErrorCaught(error)
        }

        public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
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
                        try self.parseHeaderAndLength(from: headerBytes, context)
                        state = .waitingForBody
                        fallthrough
                    } catch {
                        context.fireErrorCaught(error)
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
                        let message = try LGNP.decodeHeadless(
                            body: bytes,
                            length: messageLength,
                            with: cryptor,
                            salt: salt
                        )
                        if message.containsError {
                            context.fireErrorCaught(LGNS.E.LGNPError(message._payloadAsString))
                            return
                        }
                        guard !validateRequiredBitmask || message.controlBitmask.isSuperset(of: requiredBitmask) else {
                            context.fireErrorCaught(LGNS.E.RequiredBitmaskNotSatisfied)
                            return
                        }
                        context.fireChannelRead(wrapInboundOut(message))

                        state = .start
                    } catch {
                        context.fireErrorCaught(error)
                    }
                }
            }
        }

        public func write(context: ChannelHandlerContext, data: NIOAny, promise: PromiseVoid?) {
            do {
                context.write(
                    self.wrapOutboundOut(
                        context.channel.allocator.allocateBuffer(
                            from: try LGNP.encode(
                                message: self.unwrapOutboundIn(data),
                                with: self.cryptor
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
