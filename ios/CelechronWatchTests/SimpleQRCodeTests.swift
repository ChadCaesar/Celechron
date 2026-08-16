import CoreGraphics
import Foundation
import ImageIO
import Vision

private struct ReferenceFixture: Decodable {
    let payload: String
    let version: Int
    let rows: [String]
}

private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        return value ^ (value >> 31)
    }
}

@main
private enum SimpleQRCodeTests {
    private static var failureCount = 0
    private static var assertionCount = 0

    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            fatalError("Usage: SimpleQRCodeTests <reference_matrices.json>")
        }

        let fixtureURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let fixtures = try JSONDecoder().decode(
            [ReferenceFixture].self,
            from: Data(contentsOf: fixtureURL)
        )

        testReferenceMatrices(fixtures)
        testVersionAndByteBoundaries()
        testQuietZoneAndDeterminism()
        testUnicodeByteBoundaries()
        testVisionDecoding()
        testSeededRandomPayloads()

        if failureCount == 0 {
            print("✅ SimpleQRCode: \(assertionCount) assertions passed")
        } else {
            print("❌ SimpleQRCode: \(failureCount) of \(assertionCount) assertions failed")
            Foundation.exit(EXIT_FAILURE)
        }
    }

    // Exact matrices come from package:qr, independently used by the iPhone app.
    // Equality validates data packing, padding, Reed–Solomon, function patterns,
    // format information, alignment patterns, placement, and mask application.
    private static func testReferenceMatrices(_ fixtures: [ReferenceFixture]) {
        expect(fixtures.map(\.version) == [1, 2, 3], "fixtures cover versions 1–3")

        for fixture in fixtures {
            guard let matrix = SimpleQRCode.matrix(from: fixture.payload) else {
                fail("v\(fixture.version) fixture unexpectedly rejected")
                continue
            }
            let rawRows = matrix.dropFirst().dropLast().map { row in
                row.dropFirst().dropLast().map { $0 ? "1" : "0" }.joined()
            }
            expect(
                rawRows == fixture.rows,
                "v\(fixture.version) matches independent module-for-module fixture"
            )
        }
    }

    private static func testVersionAndByteBoundaries() {
        let cases: [(length: Int, expectedSide: Int)] = [
            (0, 23), (1, 23), (14, 23),
            (15, 27), (26, 27),
            (27, 31), (42, 31),
        ]
        for item in cases {
            let payload = String(repeating: "A", count: item.length)
            let matrix = SimpleQRCode.matrix(from: payload)
            expect(matrix?.count == item.expectedSide, "\(item.length)-byte version boundary")
            expect(matrix?.allSatisfy { $0.count == item.expectedSide } == true, "square matrix at \(item.length) bytes")
        }

        let overlong = String(repeating: "A", count: 43)
        expect(SimpleQRCode.matrix(from: overlong) == nil, "43-byte payload is rejected, not truncated")
        expect(SimpleQRCode.maximumPayloadByteCount == 42, "published capacity remains 42 bytes")
    }

    private static func testQuietZoneAndDeterminism() {
        for payload in ["", "1", String(repeating: "A", count: 15), String(repeating: "B", count: 42)] {
            guard let matrix = SimpleQRCode.matrix(from: payload) else {
                fail("quiet-zone payload unexpectedly rejected")
                continue
            }
            let side = matrix.count
            var quietZoneIsWhite = true
            for y in 0 ..< side {
                for x in 0 ..< side where y < 1 || y >= side - 1 || x < 1 || x >= side - 1 {
                    quietZoneIsWhite = quietZoneIsWhite && !matrix[y][x]
                }
            }
            expect(quietZoneIsWhite, "one-module quiet zone for \(payload.utf8.count)-byte payload")
            expect(SimpleQRCode.matrix(from: payload) == matrix, "deterministic output for \(payload.utf8.count)-byte payload")
        }
    }

    private static func testUnicodeByteBoundaries() {
        // One CJK scalar is three UTF-8 bytes. Capacity must be based on encoded
        // bytes rather than Swift Character count.
        let cases: [(count: Int, expectedSide: Int?)] = [
            (4, 23),  // 12 bytes, Version 1
            (5, 27),  // 15 bytes, Version 2
            (8, 27),  // 24 bytes, Version 2
            (9, 31),  // 27 bytes, Version 3
            (14, 31), // 42 bytes, Version 3
            (15, nil), // 45 bytes, rejected
        ]
        for item in cases {
            let payload = String(repeating: "界", count: item.count)
            let matrix = SimpleQRCode.matrix(from: payload)
            expect(matrix?.count == item.expectedSide, "Unicode boundary at \(payload.utf8.count) UTF-8 bytes")
        }
    }

    private static func testVisionDecoding() {
        let payloads = [
            "1",
            "12345678901234",
            "1234567890123456",
            "12345678901234567890123456",
            "123456789012345678901234567890123456789012",
            "校园卡付款码",
            "😀🚀付款",
            "e\u{301}",
        ]

        for payload in payloads {
            guard let matrix = SimpleQRCode.matrix(from: payload) else {
                fail("Vision payload unexpectedly rejected: \(payload)")
                continue
            }
            for scale in [3, 6] {
                expect(
                    decodeWithVision(matrix, scale: scale) == payload,
                    "Vision round-trip at \(scale) px/module for \(payload.utf8.count) bytes"
                )
            }
        }
    }

    private static func testSeededRandomPayloads() {
        var generator = SeededGenerator(seed: 0xCE1EC4A0)
        let alphabet = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._~:/?#[]@!$&'()*+,;=")

        // Every supported byte length receives at least one deterministic property test.
        for length in 1 ... SimpleQRCode.maximumPayloadByteCount {
            let payload = String((0 ..< length).map { _ in alphabet.randomElement(using: &generator)! })
            guard let matrix = SimpleQRCode.matrix(from: payload) else {
                fail("random \(length)-byte payload unexpectedly rejected")
                continue
            }
            expect(
                decodeWithVision(matrix, scale: 6) == payload,
                "seeded random Vision round-trip at \(length) bytes"
            )
        }
    }

    private static func decodeWithVision(_ matrix: [[Bool]], scale: Int) -> String? {
        guard let image = makeImage(matrix, scale: scale) else { return nil }
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]
        let handler = VNImageRequestHandler(cgImage: image, orientation: .up)
        do {
            try handler.perform([request])
            return request.results?.first?.payloadStringValue
        } catch {
            return nil
        }
    }

    private static func makeImage(_ matrix: [[Bool]], scale: Int) -> CGImage? {
        let side = matrix.count * scale
        var pixels = [UInt8](repeating: 255, count: side * side)
        for y in matrix.indices {
            for x in matrix[y].indices where matrix[y][x] {
                for pixelY in 0 ..< scale {
                    for pixelX in 0 ..< scale {
                        pixels[(y * scale + pixelY) * side + x * scale + pixelX] = 0
                    }
                }
            }
        }

        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(
            width: side,
            height: side,
            bitsPerComponent: 8,
            bitsPerPixel: 8,
            bytesPerRow: side,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        assertionCount += 1
        if !condition() {
            failureCount += 1
            print("FAIL: \(message)")
        }
    }

    private static func fail(_ message: String) {
        expect(false, message)
    }
}
