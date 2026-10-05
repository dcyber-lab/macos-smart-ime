import Foundation

/// The motion setting: a fixed style, a new random style per commit, or no effect.
enum CommitEffectMotionChoice: Hashable, Sendable {
    case style(CommitEffectStyle)
    case random
    case off

    /// Settings order.
    static let allChoices: [CommitEffectMotionChoice] = CommitEffectStyle.allCases.map { .style($0) } + [.random, .off]

    init?(rawValue: String) {
        switch rawValue {
        case "random": self = .random
        case "off": self = .off
        default:
            guard let style = CommitEffectStyle(rawValue: rawValue) else {
                return nil
            }
            self = .style(style)
        }
    }

    var rawValue: String {
        switch self {
        case .style(let style): style.rawValue
        case .random: "random"
        case .off: "off"
        }
    }

    var title: String {
        switch self {
        case .style(let style): style.title
        case .random: "Random"
        case .off: "Off"
        }
    }
}

/// The palette setting: a fixed palette or a new random one per commit.
enum CommitEffectPaletteChoice: Hashable, Sendable {
    case palette(CommitEffectPalette)
    case random

    /// Settings order.
    static let allChoices: [CommitEffectPaletteChoice] = CommitEffectPalette.allCases.map { .palette($0) } + [.random]

    init?(rawValue: String) {
        if rawValue == "random" {
            self = .random
        } else if let palette = CommitEffectPalette(rawValue: rawValue) {
            self = .palette(palette)
        } else {
            return nil
        }
    }

    var rawValue: String {
        switch self {
        case .palette(let palette): palette.rawValue
        case .random: "random"
        }
    }

    var title: String {
        switch self {
        case .palette(let palette): palette.title
        case .random: "Random"
        }
    }
}

/// Commit effect settings in the input method's defaults domain, read on every commit so that
/// `defaults write lab.dcyber.inputmethod.smartime …` applies without restarting the input method.
struct CommitEffectSettings {
    static let motionKey = "CommitEffect"
    static let paletteKey = "CommitEffectPalette"
    static let defaultMotion = CommitEffectMotionChoice.style(.shatter)
    static let defaultPalette = CommitEffectPaletteChoice.palette(.rainbow)

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var motion: CommitEffectMotionChoice {
        get { defaults.string(forKey: Self.motionKey).flatMap(CommitEffectMotionChoice.init(rawValue:)) ?? Self.defaultMotion }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Self.motionKey) }
    }

    var palette: CommitEffectPaletteChoice {
        get { defaults.string(forKey: Self.paletteKey).flatMap(CommitEffectPaletteChoice.init(rawValue:)) ?? Self.defaultPalette }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Self.paletteKey) }
    }

    /// The style and palette for one commit, with random choices made; nil when effects are off or
    /// the user asked the system to reduce motion.
    func resolve<G: RandomNumberGenerator>(
        reduceMotion: Bool, using generator: inout G
    ) -> (style: CommitEffectStyle, palette: CommitEffectPalette)? {
        guard !reduceMotion else {
            return nil
        }
        let style: CommitEffectStyle
        switch motion {
        case .off: return nil
        case .style(let fixed): style = fixed
        case .random: style = CommitEffectStyle.allCases.randomElement(using: &generator)!
        }
        switch palette {
        case .palette(let fixed): return (style, fixed)
        case .random: return (style, CommitEffectPalette.allCases.randomElement(using: &generator)!)
        }
    }
}
