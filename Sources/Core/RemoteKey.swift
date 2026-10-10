import Foundation

/// A brand-agnostic remote button. Each driver maps these onto whatever its TV speaks.
enum RemoteKey: Hashable, Sendable {
    case power
    case up, down, left, right, select
    case back, home, menu, info, input, search
    case volumeUp, volumeDown, mute
    case channelUp, channelDown
    case playPause, rewind, fastForward
    case backspace, enter, exit
    case digit(Int)

    var accessibilityName: String {
        switch self {
        case .power: "Power"
        case .up: "Up"
        case .down: "Down"
        case .left: "Left"
        case .right: "Right"
        case .select: "OK"
        case .back: "Back"
        case .home: "Home"
        case .menu: "Menu"
        case .info: "Info"
        case .input: "Input"
        case .search: "Search"
        case .volumeUp: "Volume up"
        case .volumeDown: "Volume down"
        case .mute: "Mute"
        case .channelUp: "Channel up"
        case .channelDown: "Channel down"
        case .playPause: "Play or pause"
        case .rewind: "Rewind"
        case .fastForward: "Fast forward"
        case .backspace: "Delete"
        case .enter: "Enter"
        case .exit: "Exit"
        case .digit(let n): "\(n)"
        }
    }
}
