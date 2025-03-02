import Foundation
import SoraFoundation
import SubstrateSdk
import RobinHood

struct ParaStkSelectCollatorsViewFactory {
    static func createView(
        with state: ParachainStakingSharedStateProtocol,
        delegate: ParaStkSelectCollatorsDelegate
    ) -> ParaStkSelectCollatorsViewProtocol? {
        guard
            let interactor = createInteractor(for: state),
            let currencyManager = CurrencyManager.shared else {
            return nil
        }

        let chainAsset = state.stakingOption.chainAsset

        let wireframe = ParaStkSelectCollatorsWireframe(sharedState: state)
        let priceAssetInfoFactory = PriceAssetInfoFactory(currencyManager: currencyManager)

        let balanceViewModelFactory = BalanceViewModelFactory(
            targetAssetInfo: chainAsset.assetDisplayInfo,
            priceAssetInfoFactory: priceAssetInfoFactory
        )

        let localizationManager = LocalizationManager.shared

        let preferredCollators = Set(StakingConstants.preferredValidatorIds(for: chainAsset.chain))

        let presenter = ParaStkSelectCollatorsPresenter(
            interactor: interactor,
            wireframe: wireframe,
            delegate: delegate,
            preferredCollators: preferredCollators,
            chainAsset: chainAsset,
            balanceViewModelFactory: balanceViewModelFactory,
            localizationManager: localizationManager,
            logger: Logger.shared
        )

        let view = ParaStkSelectCollatorsViewController(
            presenter: presenter,
            localizationManager: localizationManager
        )

        presenter.view = view
        interactor.presenter = presenter

        return view
    }

    private static func createInteractor(
        for state: ParachainStakingSharedStateProtocol
    ) -> ParaStkSelectCollatorsInteractor? {
        let chainAsset = state.stakingOption.chainAsset

        let collatorService = state.collatorService
        let rewardEngineService = state.rewardCalculationService

        let chain = chainAsset.chain

        let chainRegistry = ChainRegistryFacade.sharedRegistry

        guard
            let connection = chainRegistry.getConnection(for: chain.chainId),
            let runtimeProvider = chainRegistry.getRuntimeProvider(for: chain.chainId),
            let currencyManager = CurrencyManager.shared else {
            return nil
        }

        let operationQueue = OperationManagerFacade.sharedDefaultQueue
        let operationManager = OperationManager(operationQueue: operationQueue)

        let requestFactory = StorageRequestFactory(
            remoteFactory: StorageKeyFactory(),
            operationManager: operationManager
        )

        let identityOperationFactory = IdentityOperationFactory(requestFactory: requestFactory)

        let collatorOperationFactory = ParaStkCollatorsOperationFactory(
            requestFactory: requestFactory,
            identityOperationFactory: identityOperationFactory
        )

        return ParaStkSelectCollatorsInteractor(
            chainAsset: chainAsset,
            collatorService: collatorService,
            rewardService: rewardEngineService,
            connection: connection,
            runtimeProvider: runtimeProvider,
            collatorOperationFactory: collatorOperationFactory,
            priceLocalSubscriptionFactory: PriceProviderFactory.shared,
            currencyManager: currencyManager,
            operationQueue: operationQueue
        )
    }
}
