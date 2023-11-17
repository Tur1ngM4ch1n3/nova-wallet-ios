import Foundation

enum TransactionType: String, CaseIterable, Equatable {
    case incoming = "INCOMING"
    case outgoing = "OUTGOING"
    case reward = "REWARD"
    case slash = "SLASH"
    case extrinsic = "EXTRINSIC"
    case poolReward = "POOL REWARD"
    case poolSlash = "POOL SLASH"
    case swap = "SWAP"
}
