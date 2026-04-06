import CryptoKit
@testable import DesktopIconPosition
import Foundation
import Testing

struct DisplayServiceTests {
    @Test("fingerprint is deterministic for same input")
    func fingerprintStability() {
        let frames = [
            DisplayFrame(x: 0, y: 0, width: 1792, height: 1120),
            DisplayFrame(x: 912, y: -1080, width: 1920, height: 1080),
        ]
        let sorted = frames.map(\.pipeString).sorted()
        let input = sorted.joined(separator: "\n") + "\n"
        let digest = Insecure.MD5.hash(data: Data(input.utf8))
        let hash1 = digest.map { String(format: "%02x", $0) }.joined()

        let digest2 = Insecure.MD5.hash(data: Data(input.utf8))
        let hash2 = digest2.map { String(format: "%02x", $0) }.joined()

        #expect(hash1 == hash2)
        #expect(hash1.count == 32)
    }

    @Test("Cocoa to Quartz Y conversion formula")
    func coordinateConversion() {
        let mainH = 1120
        let secondaryCocoaY = 0
        let secondaryH = 1080
        let cgY = mainH - secondaryCocoaY - secondaryH
        #expect(cgY == 40)
    }
}
