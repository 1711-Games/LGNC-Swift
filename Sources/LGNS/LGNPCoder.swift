import LGNP
import NIO

internal extension LGNS {
    /// Decodes LGNP messages from a byte stream.
    ///
    /// Message boundaries come from the header: `HEAD` (4 bytes) + `SIZE` (4 bytes, `HEAD` size + headless size),
    /// so a message takes `SIZE + 4` bytes on the wire. Messages longer than `maximumMessageLength` are rejected as
    /// soon as the header is read, before buffering them. Decoding errors are passed down the pipeline
    /// (`errorCaught`), and the decoder stops: the connection is expected to be closed.
    struct LGNPDecoder: ByteToMessageDecoder {
        typealias InboundOut = LGNP.Message

        let cryptor: LGNP.Cryptor
        let requiredBitmask: LGNP.Message.ControlBitmask
        let validateRequiredBitmask: Bool
        let maximumMessageLength: Int

        mutating func decode(context: ChannelHandlerContext, buffer: inout ByteBuffer) throws -> DecodingState {
            guard
                buffer.readableBytes >= LGNP.MESSAGE_HEADER_LENGTH,
                let header = buffer.getBytes(at: buffer.readerIndex, length: LGNP.MESSAGE_HEADER_LENGTH)
            else {
                return .needMoreData
            }

            let size = try LGNP.validateMessageProtocolAndParseLength(from: header, checkMinimumMessageSize: false)
            let totalLength = Int(size) + LGNP.Message.Block.HEAD.size
            guard totalLength <= self.maximumMessageLength else {
                throw LGNP.E.InvalidMessageLength(
                    "Message length \(totalLength) exceeds the maximum of \(self.maximumMessageLength) bytes"
                )
            }
            guard buffer.readableBytes >= totalLength else {
                return .needMoreData
            }

            buffer.moveReaderIndex(forwardBy: LGNP.MESSAGE_HEADER_LENGTH)
            let body = buffer.readBytes(length: totalLength - LGNP.MESSAGE_HEADER_LENGTH)!

            let message = try LGNP.decodeHeadless(body: body, length: size, with: self.cryptor)
            if message.containsError {
                throw LGNS.E.LGNPError(message._payloadAsString)
            }
            guard !self.validateRequiredBitmask || message.controlBitmask.isSuperset(of: self.requiredBitmask) else {
                throw LGNS.E.RequiredBitmaskNotSatisfied
            }

            context.fireChannelRead(self.wrapInboundOut(message))
            return .continue
        }

        mutating func decodeLast(
            context: ChannelHandlerContext,
            buffer: inout ByteBuffer,
            seenEOF _: Bool
        ) throws -> DecodingState {
            while try self.decode(context: context, buffer: &buffer) == .continue {}
            return .needMoreData
        }
    }

    /// Encodes LGNP messages
    struct LGNPEncoder: MessageToByteEncoder {
        typealias OutboundIn = LGNP.Message

        let cryptor: LGNP.Cryptor

        func encode(data: LGNP.Message, out: inout ByteBuffer) throws {
            out.writeBytes(try LGNP.encode(message: data, with: self.cryptor))
        }
    }

    /// Turns idle events into `LGNS.E.Timeout` errors
    final class IdleTimeoutHandler: ChannelInboundHandler, Sendable {
        typealias InboundIn = NIOAny

        func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
            if event is IdleStateHandler.IdleStateEvent {
                context.fireErrorCaught(LGNS.E.Timeout)
            }
            context.fireUserInboundEventTriggered(event)
        }
    }

    /// Handlers of LGNP coding for a channel pipeline
    static func makeLGNPHandlers(
        cryptor: LGNP.Cryptor,
        requiredBitmask: LGNP.Message.ControlBitmask,
        validateRequiredBitmask: Bool
    ) -> [ChannelHandler] {
        [
            ByteToMessageHandler(
                LGNPDecoder(
                    cryptor: cryptor,
                    requiredBitmask: requiredBitmask,
                    validateRequiredBitmask: validateRequiredBitmask,
                    maximumMessageLength: Int(LGNP.MAXIMUM_MESSAGE_LENGTH)
                )
            ),
            MessageToByteHandler(LGNPEncoder(cryptor: cryptor)),
            IdleTimeoutHandler(),
        ]
    }
}
