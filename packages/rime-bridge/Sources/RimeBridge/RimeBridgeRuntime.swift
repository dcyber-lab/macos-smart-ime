import Foundation
import CLibrime
import SharedModels

public final class RimeBridgeRuntime {
    nonisolated(unsafe) private static var sharedRuntime: RimeBridgeRuntime?

    let api: UnsafeMutablePointer<RimeApi>
    private let configuration: RimeBridgeConfiguration
    private let storage: CStringStorage

    public static func shared(configuration: RimeBridgeConfiguration) throws -> RimeBridgeRuntime {
        if let sharedRuntime {
            return sharedRuntime
        }

        let runtime = try RimeBridgeRuntime(configuration: configuration)
        sharedRuntime = runtime
        return runtime
    }

    private init(configuration: RimeBridgeConfiguration) throws {
        guard let api = rime_get_api() else {
            throw RimeBridgeError.apiUnavailable
        }

        self.api = api
        self.configuration = configuration
        self.storage = CStringStorage(configuration: configuration)

        try prepareDirectories()
        initializeRuntime()
    }

    public func makeSession(defaultSchemaID: String) throws -> RimeBridgeSession {
        let sessionID = api.pointee.create_session()
        guard sessionID != 0 else {
            throw RimeBridgeError.sessionCreationFailed
        }

        let session = RimeBridgeSession(api: api, sessionID: sessionID)
        if !defaultSchemaID.isEmpty {
            _ = defaultSchemaID.withCString { api.pointee.select_schema(sessionID, $0) }
        }
        configureDefaultOptions(for: sessionID)
        return session
    }

    private func prepareDirectories() throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            atPath: configuration.userDataDirectory,
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            atPath: configuration.prebuiltDataDirectory,
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            atPath: configuration.stagingDirectory,
            withIntermediateDirectories: true
        )
    }

    private func initializeRuntime() {
        var traits = storage.makeTraits()
        api.pointee.setup(&traits)
        api.pointee.initialize(&traits)
        if api.pointee.start_maintenance(True) != 0 {
            api.pointee.join_maintenance_thread()
        }
    }

    private func configureDefaultOptions(for sessionID: RimeSessionId) {
        "zh_simp".withCString { api.pointee.set_option(sessionID, $0, True) }
        "zh_trad".withCString { api.pointee.set_option(sessionID, $0, False) }
        "zh_tw".withCString { api.pointee.set_option(sessionID, $0, False) }
        "zh_hk".withCString { api.pointee.set_option(sessionID, $0, False) }
    }
}

public final class RimeBridgeSession {
    private let api: UnsafeMutablePointer<RimeApi>
    private let sessionID: RimeSessionId

    init(api: UnsafeMutablePointer<RimeApi>, sessionID: RimeSessionId) {
        self.api = api
        self.sessionID = sessionID
    }

    func process(keyCode: Int32, mask: Int32) -> Bool {
        api.pointee.process_key(sessionID, keyCode, mask) != 0
    }

    func readCommitText() -> String? {
        var commit = RimeCommit()
        commit.data_size = structDataSize(of: RimeCommit.self)
        defer {
            _ = api.pointee.free_commit(&commit)
        }

        guard api.pointee.get_commit(sessionID, &commit) != 0, let text = commit.text else {
            return nil
        }

        return String(cString: text)
    }

    func currentState(recentText: String) -> CompositionState {
        var state = CompositionState(mode: .chinese, recentText: recentText)

        if let getInput = api.pointee.get_input, let input = getInput(sessionID) {
            state.rawInput = String(cString: input)
        }

        var status = RimeStatus()
        status.data_size = structDataSize(of: RimeStatus.self)
        defer {
            _ = api.pointee.free_status(&status)
        }
        if api.pointee.get_status(sessionID, &status) != 0, status.is_ascii_mode != 0 {
            state.mode = .english
        }

        var context = RimeContext()
        context.data_size = structDataSize(of: RimeContext.self)
        defer {
            _ = api.pointee.free_context(&context)
        }

        guard api.pointee.get_context(sessionID, &context) != 0 else {
            return state
        }

        if let preedit = context.composition.preedit {
            state.compositionText = String(cString: preedit)
        }
        if context.menu.highlighted_candidate_index >= 0 {
            state.selectedCandidateIndex = Int(context.menu.highlighted_candidate_index)
        }
        state.candidatePageIndex = Int(context.menu.page_no)
        state.isLastCandidatePage = context.menu.is_last_page != 0
        state.candidates = mapCandidates(from: context.menu)
        return state
    }

    func reset() {
        api.pointee.clear_composition(sessionID)
    }

    func selectCandidateOnCurrentPage(index: Int) -> Bool {
        api.pointee.select_candidate_on_current_page(sessionID, index) != 0
    }

    func highlightCandidateOnCurrentPage(index: Int) -> Bool {
        guard let highlightCandidate = api.pointee.highlight_candidate_on_current_page else {
            return false
        }

        return highlightCandidate(sessionID, index) != 0
    }

    public func destroy() {
        _ = api.pointee.destroy_session(sessionID)
    }

    private func mapCandidates(from menu: RimeMenu) -> [Candidate] {
        guard menu.num_candidates > 0, let candidates = menu.candidates else {
            return []
        }

        return (0..<Int(menu.num_candidates)).compactMap { index in
            let candidate = candidates[index]
            guard let text = candidate.text else {
                return nil
            }

            return Candidate(text: String(cString: text), source: .rime)
        }
    }
}

enum RimeBridgeError: Error {
    case apiUnavailable
    case sessionCreationFailed
}

private final class CStringStorage {
    private let sharedDataDirectory: UnsafeMutablePointer<CChar>
    private let userDataDirectory: UnsafeMutablePointer<CChar>
    private let prebuiltDataDirectory: UnsafeMutablePointer<CChar>
    private let stagingDirectory: UnsafeMutablePointer<CChar>
    private let appName: UnsafeMutablePointer<CChar>
    private let distributionName: UnsafeMutablePointer<CChar>
    private let distributionCodeName: UnsafeMutablePointer<CChar>
    private let distributionVersion: UnsafeMutablePointer<CChar>

    init(configuration: RimeBridgeConfiguration) {
        sharedDataDirectory = strdup(configuration.sharedDataDirectory)
        userDataDirectory = strdup(configuration.userDataDirectory)
        prebuiltDataDirectory = strdup(configuration.prebuiltDataDirectory)
        stagingDirectory = strdup(configuration.stagingDirectory)
        appName = strdup(configuration.appName)
        distributionName = strdup(configuration.distributionName)
        distributionCodeName = strdup(configuration.distributionCodeName)
        distributionVersion = strdup(configuration.distributionVersion)
    }

    deinit {
        free(sharedDataDirectory)
        free(userDataDirectory)
        free(prebuiltDataDirectory)
        free(stagingDirectory)
        free(appName)
        free(distributionName)
        free(distributionCodeName)
        free(distributionVersion)
    }

    func makeTraits() -> RimeTraits {
        var traits = RimeTraits()
        traits.data_size = structDataSize(of: RimeTraits.self)
        traits.shared_data_dir = UnsafePointer(sharedDataDirectory)
        traits.user_data_dir = UnsafePointer(userDataDirectory)
        traits.distribution_name = UnsafePointer(distributionName)
        traits.distribution_code_name = UnsafePointer(distributionCodeName)
        traits.distribution_version = UnsafePointer(distributionVersion)
        traits.app_name = UnsafePointer(appName)
        traits.prebuilt_data_dir = UnsafePointer(prebuiltDataDirectory)
        traits.staging_dir = UnsafePointer(stagingDirectory)
        return traits
    }
}

private func structDataSize<T>(of type: T.Type) -> Int32 {
    Int32(MemoryLayout<T>.size - MemoryLayout<Int32>.size)
}
