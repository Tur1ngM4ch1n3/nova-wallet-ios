import Foundation

final class StashState: BaseStakingState {
    private(set) var stashItem: StashItem
    private(set) var totalReward: TotalRewardItem?
    private(set) var payee: Staking.RewardDestinationArg?
    private(set) var ledgerInfo: StakingLedger?
    private(set) var bagListNode: BagList.Node?

    init(
        stateMachine: StakingStateMachineProtocol,
        commonData: StakingStateCommonData,
        stashItem: StashItem,
        ledgerInfo: StakingLedger?,
        totalReward: TotalRewardItem?,
        bagListNode: BagList.Node?
    ) {
        self.stashItem = stashItem
        self.ledgerInfo = ledgerInfo
        self.totalReward = totalReward
        self.bagListNode = bagListNode

        super.init(stateMachine: stateMachine, commonData: commonData)
    }

    override func accept(visitor: StakingStateVisitorProtocol) {
        visitor.visit(state: self)
    }

    override func process(stashItem: StashItem?) {
        if let stashItem = stashItem {
            self.stashItem = stashItem

            stateMachine?.transit(to: self)
        } else {
            guard let stateMachine = stateMachine else {
                return
            }

            let newState = InitialStakingState(
                stateMachine: stateMachine,
                commonData: commonData
            )

            stateMachine.transit(to: newState)
        }
    }

    override func process(ledgerInfo: StakingLedger?) {
        self.ledgerInfo = ledgerInfo

        stateMachine?.transit(to: self)
    }

    override func process(nomination: Nomination?) {
        guard let stateMachine = stateMachine else {
            return
        }

        let newState: StakingStateProtocol

        if let ledgerInfo = ledgerInfo, let nomination = nomination {
            newState = NominatorState(
                stateMachine: stateMachine,
                commonData: commonData,
                stashItem: stashItem,
                ledgerInfo: ledgerInfo,
                nomination: nomination,
                totalReward: totalReward,
                payee: payee,
                bagListNode: bagListNode
            )
        } else if let nomination = nomination {
            newState = PendingNominatorState(
                stateMachine: stateMachine,
                commonData: commonData,
                stashItem: stashItem,
                ledgerInfo: nil,
                nomination: nomination,
                totalReward: totalReward,
                payee: payee,
                bagListNode: bagListNode
            )
        } else {
            newState = PendingValidatorState(
                stateMachine: stateMachine,
                commonData: commonData,
                stashItem: stashItem,
                ledgerInfo: ledgerInfo,
                prefs: nil,
                totalReward: totalReward,
                payee: payee
            )
        }

        stateMachine.transit(to: newState)
    }

    override func process(validatorPrefs: ValidatorPrefs?) {
        guard let stateMachine = stateMachine else {
            return
        }

        let newState: StakingStateProtocol

        if let ledgerInfo = ledgerInfo, let prefs = validatorPrefs {
            newState = ValidatorState(
                stateMachine: stateMachine,
                commonData: commonData,
                stashItem: stashItem,
                ledgerInfo: ledgerInfo,
                prefs: prefs,
                totalReward: totalReward,
                payee: payee
            )
        } else if let prefs = validatorPrefs {
            newState = PendingValidatorState(
                stateMachine: stateMachine,
                commonData: commonData,
                stashItem: stashItem,
                ledgerInfo: nil,
                prefs: prefs,
                totalReward: totalReward,
                payee: payee
            )
        } else {
            newState = PendingNominatorState(
                stateMachine: stateMachine,
                commonData: commonData,
                stashItem: stashItem,
                ledgerInfo: ledgerInfo,
                nomination: nil,
                totalReward: totalReward,
                payee: payee,
                bagListNode: bagListNode
            )
        }

        stateMachine.transit(to: newState)
    }

    override func process(totalReward: TotalRewardItem?) {
        self.totalReward = totalReward

        stateMachine?.transit(to: self)
    }

    override func process(payee: Staking.RewardDestinationArg?) {
        self.payee = payee

        stateMachine?.transit(to: self)
    }

    override func process(bagListNode: BagList.Node?) {
        self.bagListNode = bagListNode

        stateMachine?.transit(to: self)
    }
}
