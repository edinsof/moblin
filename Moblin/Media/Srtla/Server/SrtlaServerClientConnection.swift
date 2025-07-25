// SRTLA is a bonding protocol on top of SRT.
// Designed by rationalsa for the BELABOX projecct.
// https://github.com/BELABOX/srtla

import Foundation
import Network

protocol SrtlaServerClientConnectionDelegate: AnyObject {
    func handlePacketFromSrtClient(_ connection: SrtlaServerClientConnection, packet: Data)
}

private let removeTimeout = 10.0
private let ackPacketLength = srtControlTypeSize + 2 + 10 * 4
private let connectionReceiveBatchSize = 100

struct AckPacket {
    var data: Data
    private var nextSnOffset: Int

    init() {
        data = createSrtlaPacket(type: .ack, length: ackPacketLength)
        nextSnOffset = srtControlTypeSize + 2
    }

    mutating func appendSequenceNumber(sn: UInt32) -> Bool {
        data.setUInt32Be(value: sn, offset: nextSnOffset)
        nextSnOffset += 4
        if nextSnOffset == ackPacketLength {
            nextSnOffset = srtControlTypeSize + 2
            return true
        } else {
            return false
        }
    }
}

class SrtlaServerClientConnection {
    var connection: NWConnection
    var latestReceivedTime = ContinuousClock.now
    var delegate: (any SrtlaServerClientConnectionDelegate)?
    private var ackPacket = AckPacket()

    init(connection: NWConnection) {
        self.connection = connection
        receivePackets()
    }

    func stop() {
        connection.cancel()
    }

    func isActive(now: ContinuousClock.Instant) -> Bool {
        return latestReceivedTime.duration(to: now) < .seconds(removeTimeout)
    }

    private func receivePackets() {
        connection.batch {
            for index in 0 ..< connectionReceiveBatchSize {
                connection.receiveMessage { data, _, _, error in
                    if let data, !data.isEmpty {
                        self.handlePacketFromClient(packet: data)
                    }
                    guard index == connectionReceiveBatchSize - 1 else {
                        return
                    }
                    if let error {
                        logger.info("srtla-server-client: Error \(error)")
                        return
                    }
                    self.receivePackets()
                }
            }
        }
    }

    private func handlePacketFromClient(packet: Data) {
        guard packet.count >= srtControlTypeSize else {
            logger.error("srtla-server-client: Packet too short (\(packet.count) bytes.")
            return
        }
        latestReceivedTime = .now
        if isSrtDataPacket(packet: packet) {
            handleDataPacket(packet: packet)
        } else {
            handleControlPacket(packet: packet)
        }
    }

    private func handleControlPacket(packet: Data) {
        let type = getSrtControlPacketType(packet: packet)
        if let type = SrtlaPacketType(rawValue: type) {
            handleSrtlaControlPacket(type: type, packet: packet)
        } else {
            handleSrtControlPacket(packet: packet)
        }
    }

    private func handleSrtlaControlPacket(type: SrtlaPacketType, packet: Data) {
        switch type {
        case .keepalive:
            handleSrtlaKeepalive(packet: packet)
        case .reg2:
            handleSrtlaReg2()
        default:
            logger.info("srtla-server-client: Unexpected packet \(type)")
        }
    }

    private func handleSrtControlPacket(packet: Data) {
        delegate?.handlePacketFromSrtClient(self, packet: packet)
    }

    private func handleSrtlaKeepalive(packet: Data) {
        sendPacket(packet: packet)
    }

    private func handleSrtlaReg2() {
        // Should probably check that group id matches.
        logger.debug("srtla-server-client: Sending reg 3 (connection registered)")
        let packet = createSrtlaPacket(type: .reg3, length: srtControlTypeSize)
        sendPacket(packet: packet)
    }

    private func handleDataPacket(packet: Data) {
        if ackPacket.appendSequenceNumber(sn: getSrtSequenceNumber(packet: packet)) {
            sendPacket(packet: ackPacket.data)
        }
        delegate?.handlePacketFromSrtClient(self, packet: packet)
    }

    func sendPacket(packet: Data) {
        connection.send(content: packet, completion: .idempotent)
    }
}
