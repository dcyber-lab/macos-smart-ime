import XCTest
import UserData

final class PrivacyFilterTests: XCTestCase {
    func testOrdinarySentencesAreAllowed() {
        for sentence in ["这个功能下周上线。", "Let's sync tomorrow at 3pm.", "版本号 v2.3 已发布", "会议改到 10 月 8 号", "deploy the k8s cluster"] {
            XCTAssertTrue(PrivacyFilter.allowsSentence(sentence), sentence)
        }
    }

    func testSensitiveSentencesAreDroppedWhole() {
        for sentence in [
            "验证码是 482913。",
            "我的手机号13800138000",
            "发到 alex.chen@example.com 吧",
            "看这个 https://example.com/a?token=x",
            "链接 www.example.com/path",
            "key 是 sk-proj-AbC123dEf456GhI789jKl",
        ] {
            XCTAssertFalse(PrivacyFilter.allowsSentence(sentence), sentence)
        }
    }

    func testLongPlainWordsAreNotTokens() {
        XCTAssertTrue(PrivacyFilter.allowsSentence("internationalization is hard"))
    }

    func testAppRules() {
        XCTAssertTrue(PrivacyFilter.allowsApp("com.tinyspeck.slackmacgap", userExcluded: []))
        XCTAssertFalse(PrivacyFilter.allowsApp("com.apple.Terminal", userExcluded: []))
        XCTAssertFalse(PrivacyFilter.allowsApp("com.1password.1password", userExcluded: []))
        XCTAssertFalse(PrivacyFilter.allowsApp("com.runningwithcrayons.Alfred", userExcluded: []), "launcher search terms are not sentences")
        XCTAssertFalse(PrivacyFilter.allowsApp("com.tencent.xinWeChat", userExcluded: ["com.tencent.xinWeChat"]))
        XCTAssertTrue(PrivacyFilter.allowsApp("com.apple.Terminal", userExcluded: [], userAllowed: ["com.apple.Terminal"]))
        XCTAssertFalse(PrivacyFilter.allowsApp("com.apple.Terminal", userExcluded: ["com.apple.Terminal"], userAllowed: ["com.apple.Terminal"]))
        XCTAssertFalse(PrivacyFilter.allowsApp(nil, userExcluded: []))
        XCTAssertFalse(PrivacyFilter.allowsApp("", userExcluded: []))
    }
}
