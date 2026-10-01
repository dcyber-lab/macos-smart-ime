import XCTest
import UserData

final class SentenceFingerprintTests: XCTestCase {
    private let salt = Data(repeating: 7, count: 32)

    func testNormalizationIgnoresCaseAndSpacing() {
        XCTAssertEqual(SentenceFingerprint.make("  Ship  it  NOW ", salt: salt), SentenceFingerprint.make("ship it now", salt: salt))
    }

    func testSaltChangesTheFingerprint() {
        XCTAssertNotEqual(SentenceFingerprint.make("这个功能下周上线", salt: salt), SentenceFingerprint.make("这个功能下周上线", salt: Data(repeating: 8, count: 32)))
    }

    func testShortSentencesHaveNoFingerprint() {
        XCTAssertNil(SentenceFingerprint.make("好的", salt: salt))
        XCTAssertNotNil(SentenceFingerprint.make("好的收到谢谢", salt: salt))
    }

    func testFingerprintDoesNotContainTheText() {
        let fingerprint = SentenceFingerprint.make("hello world again", salt: salt)!
        XCTAssertEqual(fingerprint.count, 32)
        XCTAssertFalse(fingerprint.contains("hello"))
    }
}
