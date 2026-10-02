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
        _ = chip.handleKey(124) // right arrow
        XCTAssertEqual(events.first, "notes: offered")
        XCTAssertTrue(events[1].hasPrefix("notes: ready after"))
        XCTAssertEqual(events.last, "notes: dismissed by key 124")
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
              apply: { [unowned self] text, range in applied.append((text, range)); return applyWorks })
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
        XCTAssertEqual(settings.activeProvider(appleAvailable: true, codexFound: true), .apple)
        XCTAssertEqual(settings.activeProvider(appleAvailable: false, codexFound: true), .codex)
        XCTAssertNil(settings.activeProvider(appleAvailable: false, codexFound: false))
    }

    func testAChosenProviderIsNotReplaced() {
        let settings = AIAssistSettings(defaults: defaults)
        settings.provider = .codex
        XCTAssertEqual(settings.activeProvider(appleAvailable: true, codexFound: true), .codex)
        XCTAssertNil(settings.activeProvider(appleAvailable: true, codexFound: false))
        settings.provider = .apple
        XCTAssertNil(settings.activeProvider(appleAvailable: false, codexFound: true))
    }

    func testMenuOffersProvidersAndSaysWhereTextGoes() {
        let settings = AIAssistSettings(defaults: defaults)
        let action = #selector(NSObject.description)
        let items = AIAssistMenu.items(settings: settings, currentApp: (id: "notes", name: "备忘录"), active: .apple, action: action)

        XCTAssertEqual(items.map(\.title), ["AI 助手（POC）", "在「备忘录」中启用 AI 提示", "模型：自动（优先本机）",
                                            "模型：Apple Intelligence（本机）", "模型：Codex（会发给 OpenAI）", "当前：Apple Intelligence，在本机运行，不会发出"])
        XCTAssertEqual(items.filter { $0.state == .on }.map(\.title), ["模型：自动（优先本机）"])
        XCTAssertEqual(AIAssistMenu.command(from: [kIMKCommandMenuItemName: items[4]]), .provider(.codex))
        XCTAssertEqual(AIAssistMenu.command(from: [kIMKCommandMenuItemName: items[1]]), .toggleChips)
        XCTAssertTrue(AIAssistMenu.statusText(.codex, codexModel: "gpt-6-luna").contains("OpenAI"))
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

final class AIPromptCleaningTests: XCTestCase {
    func testPrefacesAreDroppedAndCodeOrEssaysRejected() {
        XCTAssertEqual(AIPrompt.cleanFreeText("Let me see the results.", source: "让我看看效果啊。"), "Let me see the results.")
        XCTAssertEqual(AIPrompt.cleanFreeText("Here is the translation:\n\nIt is necessary to add a timeout.", source: "这里需要加一个 timeout。"), "It is necessary to add a timeout.")
        XCTAssertEqual(AIPrompt.cleanFreeText("\"Ship it.\"", source: "发吧。"), "Ship it.")
        XCTAssertNil(AIPrompt.cleanFreeText("Here is a Python implementation:\n```python\ndef quick_sort(a): ...\n```", source: "帮我写一个排序算法。"))
        XCTAssertNil(AIPrompt.cleanFreeText(String(repeating: "A long essay about sorting. ", count: 20), source: "帮我写一个排序算法。"))
    }
}
