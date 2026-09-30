import XCTest
@testable import EnglishEngine

final class UserTranslationsTests: XCTestCase {
    func testParsesLinesAndSkipsCommentsAndBadLines() {
        let table = UserTranslations.parse("""
            # comment\twith a tab
            内核\tkernel
            仓库\trepository\twarehouse\tdepot

            坏行
            空译\t\t
             灰度环境 \t staging \t
            """)

        XCTAssertEqual(table, [
            "内核": ["kernel"],
            "仓库": ["repository", "warehouse"],
            "灰度环境": ["staging"],
        ])
    }

    func testMissingFileHasNoTranslations() throws {
        let translations = UserTranslations(fileURL: try temporaryFile())

        XCTAssertEqual(translations.count, 0)
        XCTAssertNil(translations.translations(for: "内核"))
    }

    func testLearnedTranslationsAreWrittenUnderOneHeader() throws {
        let url = try temporaryFile()
        let translations = UserTranslations(fileURL: url)

        translations.addLearned("灰度环境", translations: ["staging environment"])
        translations.addLearned("飞书文档", translations: ["Feishu Docs"])

        XCTAssertEqual(translations.translations(for: "灰度环境"), ["staging environment"])
        let content = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(content.hasPrefix(UserTranslations.header))
        XCTAssertEqual(content.components(separatedBy: UserTranslations.learnedHeader).count, 2)
        XCTAssertTrue(content.hasSuffix("灰度环境\tstaging environment\n飞书文档\tFeishu Docs\n"))
        XCTAssertEqual(UserTranslations(fileURL: url).translations(for: "飞书文档"), ["Feishu Docs"])
    }

    func testLearnedTranslationKeepsTheUsersLines() throws {
        let url = try temporaryFile()
        try "内核\tkernel".write(to: url, atomically: true, encoding: .utf8)
        let translations = UserTranslations(fileURL: url)

        translations.addLearned("灰度环境", translations: ["staging environment"])

        let reloaded = UserTranslations(fileURL: url)
        XCTAssertEqual(reloaded.translations(for: "内核"), ["kernel"])
        XCTAssertEqual(reloaded.translations(for: "灰度环境"), ["staging environment"])
    }

    func testEditsApplyOnReload() throws {
        let url = try temporaryFile()
        try "内核\tkernel\n".write(to: url, atomically: true, encoding: .utf8)
        let translations = UserTranslations(fileURL: url)

        try "内核\tOS kernel\n".write(to: url, atomically: true, encoding: .utf8)
        // File dates can have one-second resolution; make the edit unmistakably newer.
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(10)], ofItemAtPath: url.path)
        XCTAssertEqual(translations.translations(for: "内核"), ["kernel"], "not reread until asked")

        translations.reloadIfChanged()
        XCTAssertEqual(translations.translations(for: "内核"), ["OS kernel"])

        try FileManager.default.removeItem(at: url)
        translations.reloadIfChanged()
        XCTAssertNil(translations.translations(for: "内核"))
    }

    private func temporaryFile() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("UserTranslationsTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory.appendingPathComponent("user-translations.tsv")
    }
}
