import Foundation
import SubstrateSdk
import RobinHood

protocol ParaStkPreferredCollatorFactoryProtocol {
    func createPreferredCollatorWrapper() -> CompoundOperationWrapper<DisplayAddress?>
}

final class ParaStkPreferredCollatorFactory {
    let chain: ChainModel
    let connection: JSONRPCEngine
    let runtimeService: RuntimeCodingServiceProtocol
    let identityOperationFactory: IdentityOperationFactoryProtocol
    let collatorService: ParachainStakingCollatorServiceProtocol
    let rewardService: ParaStakingRewardCalculatorServiceProtocol
    let operationQueue: OperationQueue

    init(
        chain: ChainModel,
        connection: JSONRPCEngine,
        runtimeService: RuntimeCodingServiceProtocol,
        collatorService: ParachainStakingCollatorServiceProtocol,
        rewardService: ParaStakingRewardCalculatorServiceProtocol,
        identityOperationFactory: IdentityOperationFactoryProtocol,
        operationQueue: OperationQueue
    ) {
        self.chain = chain
        self.connection = connection
        self.runtimeService = runtimeService
        self.rewardService = rewardService
        self.collatorService = collatorService
        self.identityOperationFactory = identityOperationFactory
        self.operationQueue = operationQueue
    }

    private func createResultWrapper(
        dependingOn mergeOperation: BaseOperation<AccountId?>
    ) -> CompoundOperationWrapper<DisplayAddress?> {
        OperationCombiningService<DisplayAddress?>.compoundNonOptionalWrapper(
            operationManager: OperationManager(operationQueue: operationQueue)
        ) {
            let optAccountId = try mergeOperation.extractNoCancellableResultData()

            guard let accountId = optAccountId else {
                return CompoundOperationWrapper.createWithResult(nil)
            }

            let identityWrapper = self.identityOperationFactory.createIdentityWrapper(
                for: { [accountId] },
                engine: self.connection,
                runtimeService: self.runtimeService,
                chainFormat: self.chain.chainFormat
            )

            let mappingOperation = ClosureOperation<DisplayAddress?> {
                let identities = try identityWrapper.targetOperation.extractNoCancellableResultData()
                let address = try accountId.toAddress(using: self.chain.chainFormat)
                let name = identities[address]?.displayName

                return DisplayAddress(address: address, username: name ?? "")
            }

            mappingOperation.addDependency(identityWrapper.targetOperation)

            return CompoundOperationWrapper(
                targetOperation: mappingOperation,
                dependencies: identityWrapper.allOperations
            )
        }
    }
}

extension ParaStkPreferredCollatorFactory: ParaStkPreferredCollatorFactoryProtocol {
    func createPreferredCollatorWrapper() -> CompoundOperationWrapper<DisplayAddress?> {
        let preferredCollators = StakingConstants.preferredValidatorIds(for: chain)

        guard !preferredCollators.isEmpty else {
            return CompoundOperationWrapper.createWithResult(nil)
        }

        let collatorsSet = Set(preferredCollators)

        let collatorsOperation = collatorService.fetchInfoOperation()
        let rewardOperation = rewardService.fetchCalculatorOperation()

        let mergeOperation = ClosureOperation<AccountId?> {
            let collators = try collatorsOperation.extractNoCancellableResultData().collators
            let rewardsCalculator = try rewardOperation.extractNoCancellableResultData()

            let optCollator = collators
                .filter { collatorsSet.contains($0.accountId) }
                .sorted { col1, col2 in
                    let optApr1 = try? rewardsCalculator.calculateAPR(for: col1.accountId)
                    let optApr2 = try? rewardsCalculator.calculateAPR(for: col2.accountId)

                    if let apr1 = optApr1, let apr2 = optApr2 {
                        return apr1 > apr2
                    } else if optApr1 != nil {
                        return true
                    } else {
                        return false
                    }
                }
                .first

            return optCollator?.accountId
        }

        mergeOperation.addDependency(collatorsOperation)
        mergeOperation.addDependency(rewardOperation)

        let resultWrapper = createResultWrapper(dependingOn: mergeOperation)
        resultWrapper.addDependency(operations: [mergeOperation])

        let dependencies = [collatorsOperation, rewardOperation] + [mergeOperation] +
            resultWrapper.dependencies

        return CompoundOperationWrapper(targetOperation: resultWrapper.targetOperation, dependencies: dependencies)
    }
}
