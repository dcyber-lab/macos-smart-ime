import AppKit
import Foundation
@preconcurrency import InputMethodKit
import XCTest
@testable import IMEHostCore

private final class FakeRewriter: AIRewriter, @unchecked Sendable {
    var reply: Result<String, AIError> = .success("This feature ships next week.")
    var delay: TimeInterval = 0
    private(set) var calls: [String] = []

    func rewrite(_ text: String, action: AIAction) async throws -> String {
        calls.append(text)
        if delay > 0 {
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
        return try reply.get()
    }
}

@MainActor
final class AIAssistChipTests: XCTestCase {
    private var rewriter: FakeRewriter!
    private var shown: [AIAssistChipController.Display?] = []
    private var applied: [(String, NSRange)] = []
    private var applyWorks = true
    private var clock = Date(timeIntervalSinceReferenceDate: 0)
    private var chip: AIAssistChipController!

    override func setUp() async throws {
        rewriter = FakeRewriter()
        shown = []
        applied = []
        applyWorks = true
        chip = AIAssistChipController(
            rewriter: { [unowned self] in rewriter },
            present: { [unowned self] display, _ in shown.append(display) },
            now: { [unowned self] in clock },
            hideAfter: { _, _ in }
        )
    }

    func testQualifyingSentences() {
        XCTAssertTrue(AIAssistChipController.qualifies("这个功能下周上线。"))
        XCTAssertTrue(AIAssistChipController.qualifies("这里需要加一个 timeout。"))
        XCTAssertFalse(AIAssistChipController.qualifies("这个功能下周上线"), "no sentence punctuation")
        XCTAssertFalse(AIAssistChipController.qualifies("好的。"), "too short")
        XCTAssertTrue(AIAssistChipController.qualifies("有点麻烦。"), "five characters with the full stop")
        XCTAssertFalse(AIAssistChipController.qualifies("Please review the deploy plan."), "already English")
    }

    func testResultIsReadyThenTabReplaces() async {
        chip.offer(offer())
        XCTAssertEqual(shown.last, .generating(accepted: false))
        await waitUntil { if case .ready = self.chip.display { true } else { false } }
        XCTAssertEqual(chip.display, .ready(preview: "This feature ships next week."))

        XCTAssertEqual(chip.handleKey(AIAssistChipController.tabKey), .consumed)

        XCTAssertEqual(applied.map(\.0), ["This feature ships next week."])
        XCTAssertEqual(applied.first?.1, NSRange(location: 3, length: 9))
        XCTAssertEqual(chip.display, .done("已替换"))
        XCTAssertEqual(rewriter.calls, ["这个功能下周上线。"])
    }

    func testRightArrowAcceptsWhereAppsKeepTab() async {
        chip.offer(offer())
        await waitUntil { if case .ready = self.chip.display { true } else { false } }

        XCTAssertEqual(chip.handleKey(AIAssistChipController.rightArrowKey), .consumed)
        XCTAssertEqual(applied.map(\.0), ["This feature ships next week."])
    }

    func testTabWhileGeneratingReplacesWhenReady() async {
        rewriter.delay = 0.05
        chip.offer(offer())
        XCTAssertEqual(chip.handleKey(AIAssistChipController.tabKey), .consumed)
        XCTAssertEqual(chip.display, .generating(accepted: true))
        XCTAssertTrue(applied.isEmpty)

        await waitUntil { !self.applied.isEmpty }
        XCTAssertEqual(applied.map(\.0), ["This feature ships next week."])
    }

    func testTypingOnDismissesAndNothingIsApplied() async {
        rewriter.delay = 0.05
        chip.offer(offer())
        XCTAssertEqual(chip.handleKey(0), .passThrough)
        XCTAssertNil(chip.display)
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertTrue(applied.isEmpty)
        XCTAssertNil(chip.display, "a late result does not bring the chip back")
        XCTAssertNil(chip.handleKey(AIAssistChipController.tabKey), "no chip: Tab is the app's again")
    }

    func testOffersAreAtLeastFiveSecondsApartPerApp() {
        chip.offer(offer())
        chip.dismiss()
        clock += 3
        chip.offer(offer())
        XCTAssertNil(chip.display)
        clock += 3
        chip.offer(offer())
        XCTAssertNotNil(chip.display)
        chip.offer(offer(app: "other"))
        XCTAssertEqual(shown.filter { $0 == .generating(accepted: false) }.count, 3)
    }

    func testFailuresAndUnsupportedReplacementSaySo() async {
        rewriter.reply = .failure(.timedOut)
        chip.offer(offer())
        await waitUntil { if case .failed = self.chip.display { true } else { false } }
        XCTAssertEqual(chip.display, .failed("AI 超时"))

        rewriter.reply = .success("Done.")
        applyWorks = false
        chip.offer(offer(app: "chromium"))
        await waitUntil { if case .ready = self.chip.display { true } else { false } }
        _ = chip.handleKey(AIAssistChipController.tabKey)
        XCTAssertEqual(chip.display, .done("这个应用不支持替换，已复制，⌘V 粘贴"))
    }

    func testEventsAreLoggedWithoutText() async {
        var events: [String] = []
        let chip = AIAssistChipController(
            rewriter: { [unowned self] in rewriter }, present: { _, _ in },
            log: { event, app in events.append("\(app): \(event)") }, now: { [unowned self] in clock }, hideAfter: { _, _ in }
        )
        chip.offer(offer())
        await waitUntil { events.count >= 2 }
        _ = chip.handleKey(51) // delete
        XCTAssertEqual(events.first, "notes: offered")
        XCTAssertTrue(events[1].hasPrefix("notes: ready after"))
        XCTAssertEqual(events.last, "notes: dismissed by key 51")
        XCTAssertFalse(events.joined().contains("这个功能"))

        let log = AIAssistEventLog(url: FileManager.default.temporaryDirectory.appendingPathComponent("ai-log-\(UUID().uuidString).log"))
        log.append("offered", app: "notes")
        log.flush()
    }

    func testNoCodexMeansNoChip() {
        let chip = AIAssistChipController(rewriter: { nil }, present: { [unowned self] display, _ in shown.append(display) })
        chip.offer(offer())
        XCTAssertNil(chip.display)
    }

    private func offer(app: String = "notes") -> AIAssistChipController.Offer {
        .init(app: app, sentence: "这个功能下周上线。", range: NSRange(location: 3, length: 9), caret: .zero,
              apply: { [unowned self] text, range in applied.append((text, range)); return applyWorks ? .replaced : .refused })
    }

    private func waitUntil(_ condition: @escaping () -> Bool) async {
        for _ in 0..<200 where !condition() {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }
}

@MainActor
final class CodexRewriterTests: XCTestCase {
    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("CodexRewriterTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    /// A stand-in for `codex`: checks the arguments, echoes the text from the prompt into `-o`.
    private func stub(_ body: String) -> URL {
        let url = directory.appendingPathComponent("codex")
        let script = """
        #!/bin/zsh
        out=""; prev=""
        for a in "$@"; do [ "$prev" = "-o" ] && out="$a"; prev="$a"; done
        \(body)
        """
        FileManager.default.createFile(atPath: url.path, contents: Data(script.utf8), attributes: [.posixPermissions: 0o755])
        return url
    }

    func testRunsCodexWithTheTextOnStdinAndReadsTheResult() async throws {
        let codex = stub("""
        [ "$1" = "exec" ] || exit 9
        print -r -- "$*" | grep -q -- "--ephemeral -s read-only" || exit 8
        print -r -- "$*" | grep -q -- "model_reasoning_effort=\\"low\\"" || exit 7
        input=$(cat)
        print -r -- "$input" | grep -q "<text>" || exit 6
        print -r -- "$input" | sed -n '/^<text>$/{n;p;}' | sed 's/^/EN: /' > "$out"
        """)
        let result = try await CodexRewriter(executableURL: codex).rewrite("这个功能下周上线", action: .toEnglish)

        XCTAssertEqual(result, "EN: 这个功能下周上线")
    }

    func testFailureShowsTheLastErrorLine() async {
        let codex = stub(#"print -u2 "warning: x"; print -u2 "error: not logged in"; exit 3"#)
        do {
            _ = try await CodexRewriter(executableURL: codex).rewrite("你好", action: .toEnglish)
            XCTFail("should throw")
        } catch {
            XCTAssertEqual(error as? AIError, .failed("error: not logged in"))
        }
    }

    func testTimeoutStopsTheProcess() async {
        let codex = stub("sleep 5")
        let start = Date()
        do {
            _ = try await CodexRewriter(executableURL: codex, timeout: 0.3).rewrite("你好", action: .toEnglish)
            XCTFail("should throw")
        } catch {
            XCTAssertEqual(error as? AIError, .timedOut)
        }
        XCTAssertLessThan(Date().timeIntervalSince(start), 3)
    }

    func testEmptyOutputIsAnError() async {
        let codex = stub(#"cat > /dev/null; : > "$out""#)
        do {
            _ = try await CodexRewriter(executableURL: codex).rewrite("你好", action: .toEnglish)
            XCTFail("should throw")
        } catch {
            XCTAssertEqual(error as? AIError, .emptyResult)
        }
    }

    func testLocateUsesTheConfiguredPathFirst() {
        let codex = stub("exit 0")
        XCTAssertEqual(CodexRewriter.locate(configured: codex.path), codex)
        XCTAssertNotNil(AIPrompt.make("a\nb", action: .polish).range(of: "<text>\na\nb\n</text>"))
    }
}

final class AIAssistSettingsTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "AIAssistSettingsTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testAutoPrefersTheLocalModel() {
        let settings = AIAssistSettings(defaults: defaults)
        XCTAssertEqual(settings.provider, .auto)
        XCTAssertEqual(settings.activeProvider(ollamaAvailable: true, appleAvailable: true, codexFound: true), .ollama)
        XCTAssertEqual(settings.activeProvider(ollamaAvailable: false, appleAvailable: true, codexFound: true), .apple)
        XCTAssertEqual(settings.activeProvider(ollamaAvailable: false, appleAvailable: false, codexFound: true), .codex)
        XCTAssertNil(settings.activeProvider(ollamaAvailable: false, appleAvailable: false, codexFound: false))
    }

    func testAChosenProviderIsNotReplaced() {
        let settings = AIAssistSettings(defaults: defaults)
        settings.provider = .codex
        XCTAssertEqual(settings.activeProvider(ollamaAvailable: true, appleAvailable: true, codexFound: true), .codex)
        XCTAssertNil(settings.activeProvider(ollamaAvailable: true, appleAvailable: true, codexFound: false))
        settings.provider = .apple
        XCTAssertNil(settings.activeProvider(ollamaAvailable: true, appleAvailable: false, codexFound: true))
        settings.provider = .ollama
        XCTAssertNil(settings.activeProvider(ollamaAvailable: false, appleAvailable: true, codexFound: true))
    }

    func testMenuOffersProvidersAndSaysWhereTextGoes() {
        let settings = AIAssistSettings(defaults: defaults)
        let action = #selector(NSObject.description)
        let items = AIAssistMenu.items(settings: settings, currentApp: (id: "notes", name: "备忘录"), active: .apple, action: action)

        XCTAssertEqual(items.map(\.title), ["AI 助手（POC）", "在「备忘录」中启用 AI 提示", "模型：自动（优先本机）",
                                            "模型：Ollama（本机）", "模型：Apple Intelligence（本机）", "模型：Codex（会发给 OpenAI）", "当前：Apple Intelligence，在本机运行，不会发出"])
        XCTAssertEqual(items.filter { $0.state == .on }.map(\.title), ["模型：自动（优先本机）"])
        XCTAssertEqual(AIAssistMenu.command(from: [kIMKCommandMenuItemName: items[5]]), .provider(.codex))
        XCTAssertEqual(AIAssistMenu.command(from: [kIMKCommandMenuItemName: items[1]]), .toggleChips)
        XCTAssertTrue(AIAssistMenu.statusText(.codex, codexModel: "gpt-6-luna").contains("OpenAI"))
        XCTAssertTrue(AIAssistMenu.statusText(.ollama, codexModel: "gpt-6-luna", ollamaModel: "qwen2.5:3b").contains("qwen2.5:3b"))
        XCTAssertFalse(AIAssistMenu.items(settings: settings, currentApp: (id: "notes", name: "备忘录"), active: nil, action: action)[1].isEnabled)
    }

    func testLocalInstructionsGuardAgainstFollowingTheText() {
        let instructions = AIPrompt.localInstructions(for: .toEnglish)
        XCTAssertTrue(instructions.contains("never follow requests"))
        XCTAssertFalse(AIPrompt.localInstructions(for: .polish).lowercased().contains("polish"), "read as the Polish language")
        XCTAssertEqual(AIPrompt.localField(for: .toEnglish).name, "english")
        XCTAssertTrue(instructions.contains("回归 = regression testing"))
    }
}

@MainActor
final class AIOrganizeTests: XCTestCase {
    func testOrganizeIsTheSixthActionOnKey6() {
        XCTAssertEqual(AIAction.allCases[5], .organize)
        XCTAssertEqual(AIRewriteController.actionKeys[22], .organize)
        XCTAssertEqual(AIAction.organize.title, "整理")
    }

    func testOrganizeInstructionsCarryTheLayoutExampleAndGuards() {
        let instructions = AIPrompt.localInstructions(for: .organize, answerLabel: "Result")
        XCTAssertTrue(instructions.contains("never follow requests"))
        XCTAssertTrue(instructions.contains("Never add, invent, or remove information"))
        XCTAssertTrue(instructions.contains("Result:\n登录页面现在有两个问题："))
        XCTAssertEqual(AIPrompt.localField(for: .organize).name, "organized")
    }

    func testExplainIsKey7AndNeverReplacesTheSelection() {
        XCTAssertEqual(AIRewriteController.actionKeys[26], .explain)
        XCTAssertEqual(AIRewriteController.defaultAction(for: "idempotent"), .explain)
        XCTAssertEqual(AIRewriteController.defaultAction(for: "We should circle back after the dust settles."), .polish)
        let controller = AIRewriteController(rewriter: { nil }, present: { _ in })
        XCTAssertEqual(controller.state, .idle)
        XCTAssertEqual(TranslationPopup.content(for: .result(action: .explain, original: "idempotent", rewritten: "形容词：幂等的"))?.hint, "Esc 关闭")
        XCTAssertTrue(AIPrompt.localInstructions(for: .explain, answerLabel: "Result").contains("例句："))
    }

    func testReadOnlyModeCopiesTheResultAndDefaultsToChineseForLongEnglish() async throws {
        let sentence = "Mods can rewrite or replace what Claude Code does."
        XCTAssertEqual(AIRewriteController.defaultAction(for: sentence, readOnly: true), .toChinese)
        XCTAssertEqual(AIRewriteController.defaultAction(for: sentence), .polish)
        XCTAssertEqual(AIRewriteController.defaultAction(for: "hooks", readOnly: true), .explain)

        struct Fixed: AIRewriter {
            func rewrite(_ text: String, action: AIAction) async throws -> String { "译文" }
        }
        var last = AIRewriteController.State.idle
        let controller = AIRewriteController(rewriter: { Fixed() }, present: { last = $0 })
        controller.start(text: sentence, range: NSRange(location: NSNotFound, length: 0), readOnly: true)
        XCTAssertEqual(controller.handleKey(36), .handled)
        for _ in 0..<50 where { if case .result = last { return false } else { return true } }() {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(controller.handleKey(36), .copy("译文"))
        XCTAssertEqual(last, .idle)
        XCTAssertEqual(TranslationPopup.content(for: .result(action: .toChinese, original: sentence, rewritten: "译文"), readOnly: true)?.hint, "⏎ 复制 · Esc 或点击关闭")
    }

    func testAMessageGoesAwayByItself() async throws {
        var last = AIRewriteController.State.idle
        let controller = AIRewriteController(rewriter: { nil }, messageLifetime: .milliseconds(50)) { last = $0 }
        controller.start(text: "你好", range: NSRange(location: 0, length: 2))
        XCTAssertEqual(last, .message("没有可用的模型：打开 Apple Intelligence 或安装 Codex"))
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(last, .idle)
    }

    func testAColonLineIsContentWhenOrganizing() {
        let output = "有两个问题：\n1. 慢\n2. 贵"
        XCTAssertEqual(AIPrompt.cleanFreeText(output, source: "有两个问题 慢 贵", longForm: true), output)
        XCTAssertEqual(AIPrompt.cleanFreeText("Here is the result:\n慢", source: "慢", longForm: true), "慢")
    }
}

final class AIPromptCleaningTests: XCTestCase {
    func testPrefacesAreDroppedAndCodeOrEssaysRejected() {
        XCTAssertEqual(AIPrompt.cleanFreeText("Let me see the results.", source: "让我看看效果啊。"), "Let me see the results.")
        XCTAssertEqual(AIPrompt.cleanFreeText("Here is the translation:\n\nIt is necessary to add a timeout.", source: "这里需要加一个 timeout。"), "It is necessary to add a timeout.")
        XCTAssertEqual(AIPrompt.cleanFreeText("\"Ship it.\"", source: "发吧。"), "Ship it.")
        XCTAssertNil(AIPrompt.cleanFreeText("Here is a Python implementation:\n```python\ndef quick_sort(a): ...\n```", source: "帮我写一个排序算法。"))
        XCTAssertNil(AIPrompt.cleanFreeText(String(repeating: "A long essay about sorting. ", count: 20), source: "帮我写一个排序算法。"))
    }
}

@MainActor
final class AIRewriteControllerTests: XCTestCase {
    private var rewriter: FakeRewriter!
    private var states: [AIRewriteController.State] = []
    private var controller: AIRewriteController!
    private let range = NSRange(location: 4, length: 10)

    override func setUp() async throws {
        rewriter = FakeRewriter()
        states = []
        controller = AIRewriteController(rewriter: { [unowned self] in rewriter }) { [unowned self] in states.append($0) }
    }

    func testChineseDefaultsToEnglishAndReturnReplaces() async {
        controller.start(text: " 这个功能下周上线 ", range: range)
        XCTAssertEqual(controller.state, .choosing(text: "这个功能下周上线", defaultAction: .toEnglish, truncated: false))
        XCTAssertTrue(rewriter.calls.isEmpty, "nothing is sent before an action is picked")

        XCTAssertEqual(controller.handleKey(36), .handled)
        XCTAssertEqual(controller.state, .running(action: .toEnglish, text: "这个功能下周上线"))
        await waitUntil { if case .result = self.controller.state { true } else { false } }

        XCTAssertEqual(controller.handleKey(36), .replace("This feature ships next week.", range, expecting: " 这个功能下周上线 "))
        XCTAssertEqual(controller.state, .idle)
    }

    func testTheLineIsReplacedWhereItIsWithoutTrailingSpaces() {
        // The field read starts at 10 in the client; the cursor is after two trailing spaces.
        let text = "前一行\n这个接口有问题  "
        let line = AIRewriteController.line(before: FieldText(text, cursor: 10 + text.utf16.count))
        XCTAssertEqual(line?.text, "这个接口有问题")
        XCTAssertEqual(line?.range, NSRange(location: 14, length: 7))
        XCTAssertEqual(line?.truncated, false)

        XCTAssertNil(AIRewriteController.line(before: FieldText("第一行\n  ", cursor: 6)), "a blank line has nothing to rewrite")
        XCTAssertEqual(AIRewriteController.line(before: FieldText("很长的一行 ", startsMidway: true, cursor: 100))?.truncated, true)
    }

    func testATailIsLocatedOnlyWhereTheTextEndsWithIt() {
        XCTAssertEqual(FieldText("好👍 ", cursor: 10).range(ofTail: "好👍"), NSRange(location: 6, length: 3))
        XCTAssertEqual(FieldText("abc def", cursor: 7).range(ofTail: "def"), NSRange(location: 4, length: 3))
        XCTAssertNil(FieldText("abc def", cursor: 7).range(ofTail: "abc"), "a sentence cut to a limit is not where the cursor says")
        XCTAssertNil(FieldText("abc").range(ofTail: "abc"), "no cursor")
    }

    func testAResultThatWasNotReplacedSaysWhy() {
        controller.report(AIReplacement.textChanged.message)
        XCTAssertEqual(controller.state, .message("原文已改动，没有替换，已复制，⌘V 粘贴"))
    }

    func testNumberKeysPickActionsAndEnglishDefaultsToPolish() async {
        controller.start(text: "this change need more test", range: range)
        XCTAssertEqual(controller.state, .choosing(text: "this change need more test", defaultAction: .polish, truncated: false))

        XCTAssertEqual(controller.handleKey(21), .handled) // 4 更简洁
        XCTAssertEqual(controller.state, .running(action: .concise, text: "this change need more test"))
    }

    func testEscapeWhileRunningDropsTheLateResult() async {
        rewriter.delay = 0.05
        controller.start(text: "这个功能下周上线", range: range)
        _ = controller.handleKey(36)
        XCTAssertEqual(controller.handleKey(53), .dismissed(consumed: true))
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(controller.state, .idle)
    }

    func testOtherKeysDismissAndAreTyped() {
        controller.start(text: "这个功能下周上线", range: range)
        XCTAssertEqual(controller.handleKey(0), .dismissed(consumed: false))
        XCTAssertEqual(controller.state, .idle)
    }

    func testMessagesForMissingTextModelAndErrors() async {
        controller.start(text: nil, range: range)
        XCTAssertEqual(controller.state, .message("这个应用不提供文字给输入法，先选中文字再按 ⌃⌥R"))
        controller.start(text: "  ", range: range)
        guard case .message = controller.state else { return XCTFail("empty text") }

        let none = AIRewriteController(rewriter: { nil }) { _ in }
        none.start(text: "你好世界", range: range)
        XCTAssertEqual(none.state, .message("没有可用的模型：打开 Apple Intelligence 或安装 Codex"))

        rewriter.reply = .failure(.unavailable("本机模型拒绝处理这句"))
        controller.start(text: "你好世界", range: range)
        _ = controller.handleKey(36)
        await waitUntil { if case .message = self.controller.state { true } else { false } }
        XCTAssertEqual(controller.state, .message("本机模型拒绝处理这句"))
    }

    func testPopupContent() {
        let choosing = TranslationPopup.content(for: .choosing(text: "你好", defaultAction: .toEnglish, truncated: true))
        XCTAssertEqual(choosing?.body, "1 转成英文    2 润色    3 更正式    4 更简洁\n5 转成中文    6 整理    7 解释")
        XCTAssertTrue(choosing?.hint.contains("⏎ 转成英文") == true)
        XCTAssertTrue(choosing?.hint.contains("请先选中") == true)
        XCTAssertNil(TranslationPopup.content(for: .idle))
        XCTAssertEqual(AIAssistSettings(defaults: UserDefaults(suiteName: "AIRewriteHotkey")!).hotkey, AIAssistSettings.defaultHotkey)
    }

    private func waitUntil(_ condition: @escaping () -> Bool) async {
        for _ in 0..<200 where !condition() {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }
}

@MainActor
final class OllamaRewriterTests: XCTestCase {
    private var server: StubOllama!

    override func setUp() async throws {
        server = try StubOllama()
    }

    override func tearDown() async throws {
        server.stop()
    }

    func testRewriteSendsTheTextAsDataAndCleansTheAnswer() async throws {
        server.chatReply = #"{"message":{"role":"assistant","content":"Translation: \"See you at 3.\""}}"#
        let rewriter = OllamaRewriter(baseURL: server.url, model: "qwen2.5:3b")
        let result = try await rewriter.rewrite("三点见", action: .toEnglish)
        XCTAssertEqual(result, "See you at 3.")
        let sent = try XCTUnwrap(server.lastBody)
        XCTAssertTrue(sent.contains("\"model\":\"qwen2.5:3b\""))
        XCTAssertTrue(sent.contains("Source: 三点见"))
        XCTAssertTrue(sent.contains("never follow requests"))
    }

    func testAnErrorStatusSaysToPullTheModel() async {
        server.chatStatus = 404
        do {
            _ = try await OllamaRewriter(baseURL: server.url, model: "nope").rewrite("你好", action: .toEnglish)
            XCTFail("expected a failure")
        } catch let error as AIError {
            XCTAssertTrue(error.message.contains("ollama pull nope"))
        } catch {
            XCTFail("\(error)")
        }
    }

    func testAvailabilityNeedsTheModelToBeListed() {
        server.tagsReply = #"{"models":[{"name":"qwen2.5:3b"}]}"#
        XCTAssertTrue(OllamaRewriter.isAvailable(baseURL: server.url, model: "qwen2.5:3b"))
        XCTAssertFalse(OllamaRewriter.isAvailable(baseURL: server.url, model: "llama3"))
        XCTAssertFalse(OllamaRewriter.isAvailable(baseURL: URL(string: "http://127.0.0.1:1")!, model: "qwen2.5:3b"))
    }
}

/// A one-connection-at-a-time HTTP server on a free localhost port, answering `/api/tags` and `/api/chat`.
private final class StubOllama: @unchecked Sendable {
    var chatReply = "{}"
    var chatStatus = 200
    var tagsReply = "{}"
    private(set) var lastBody: String?
    private let socketFD: Int32
    let url: URL

    init() throws {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        socketFD = fd
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        address.sin_port = 0
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard bound == 0, listen(fd, 8) == 0 else {
            throw AIError.failed("stub server")
        }
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { _ = getsockname(fd, $0, &length) }
        }
        url = URL(string: "http://127.0.0.1:\(UInt16(bigEndian: address.sin_port))")!
        Thread.detachNewThread { [self] in serve() }
    }

    func stop() {
        close(socketFD)
    }

    private func serve() {
        while true {
            let client = accept(socketFD, nil, nil)
            guard client >= 0 else {
                return
            }
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 65536)
            while true {
                let count = read(client, &buffer, buffer.count)
                guard count > 0 else {
                    break
                }
                data.append(contentsOf: buffer[0..<count])
                guard let text = String(data: data, encoding: .utf8), let split = text.range(of: "\r\n\r\n") else {
                    continue
                }
                let head = text[..<split.lowerBound]
                let body = text[split.upperBound...]
                let expected = head.lowercased().components(separatedBy: "content-length:").dropFirst().first
                    .flatMap { Int($0.prefix { $0.isNumber || $0 == " " }.trimmingCharacters(in: .whitespaces)) } ?? 0
                if body.utf8.count >= expected {
                    let isChat = head.contains("/api/chat")
                    if isChat {
                        lastBody = String(body)
                    }
                    let payload = isChat ? chatReply : tagsReply
                    let status = isChat ? chatStatus : 200
                    let response = "HTTP/1.1 \(status) X\r\nContent-Type: application/json\r\nContent-Length: \(payload.utf8.count)\r\nConnection: close\r\n\r\n\(payload)"
                    _ = response.withCString { write(client, $0, strlen($0)) }
                    break
                }
            }
            close(client)
        }
    }
}
