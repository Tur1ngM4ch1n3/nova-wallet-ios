import Foundation

protocol AccountManagementFilterProtocol {
    func accountManagementSupports(wallet: MetaAccountModel, for chain: ChainModel) -> Bool
    func canAddAccount(to wallet: MetaAccountModel, chain: ChainModel) -> Bool
}

final class AccountManagementFilter: AccountManagementFilterProtocol {
    private lazy var supportedLedgerChains: Set<ChainModel.Id> = {
        let allIds = SupportedLedgerApp.all().map(\.chainId)
        return Set(allIds)
    }()

    func accountManagementSupports(wallet: MetaAccountModel, for chain: ChainModel) -> Bool {
        switch wallet.type {
        case .watchOnly, .paritySigner, .polkadotVault, .secrets, .proxy:
            return true
        case .ledger:
            return supportedLedgerChains.contains(chain.chainId)
        }
    }

    func canAddAccount(to wallet: MetaAccountModel, chain: ChainModel) -> Bool {
        switch wallet.type {
        case .watchOnly, .secrets, .proxy:
            return true
        case .paritySigner, .polkadotVault:
            return !chain.isEthereumBased
        case .ledger:
            return supportedLedgerChains.contains(chain.chainId)
        }
    }
}
