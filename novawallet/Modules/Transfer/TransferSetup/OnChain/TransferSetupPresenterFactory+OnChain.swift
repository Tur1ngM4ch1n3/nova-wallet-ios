import Foundation
import SoraFoundation

extension TransferSetupPresenterFactory {
    // swiftlint:disable:next function_body_length
    func createOnChainPresenter(
        for chainAsset: ChainAsset,
        initialState: TransferSetupInputState,
        view: TransferSetupChildViewProtocol
    ) -> TransferSetupChildPresenterProtocol? {
        guard
            let selectedAccountAddress = wallet.fetch(for: chainAsset.chain.accountRequest())?.toAddress(),
            let currencyManager = CurrencyManager.shared else {
            return nil
        }

        let optInteractor: (OnChainTransferBaseInteractor & OnChainTransferSetupInteractorInputProtocol)?
        let wireframe: OnChainTransferSetupWireframeProtocol

        let localizationManager = LocalizationManager.shared

        let networkViewModelFactory = NetworkViewModelFactory()
        let chainAssetViewModelFactory = ChainAssetViewModelFactory(networkViewModelFactory: networkViewModelFactory)
        let priceAssetInfoFactory = PriceAssetInfoFactory(currencyManager: currencyManager)
        let sendingBalanceViewModelFactory = BalanceViewModelFactory(
            targetAssetInfo: chainAsset.assetDisplayInfo,
            priceAssetInfoFactory: priceAssetInfoFactory
        )

        let utilityBalanceViewModelFactory: BalanceViewModelFactoryProtocol?

        if
            let utilityAsset = chainAsset.chain.utilityAssets().first,
            utilityAsset.assetId != chainAsset.asset.assetId {
            let utilityAssetInfo = utilityAsset.displayInfo(with: chainAsset.chain.icon)
            utilityBalanceViewModelFactory = BalanceViewModelFactory(
                targetAssetInfo: utilityAssetInfo,
                priceAssetInfoFactory: priceAssetInfoFactory
            )
        } else {
            utilityBalanceViewModelFactory = nil
        }

        if chainAsset.asset.isAnyEvm {
            let evmWireframe = EvmOnChainTransferSetupWireframe(transferCompletion: transferCompletion)
            wireframe = evmWireframe

            let assetInfo = chainAsset.chain.utilityAssetDisplayInfo() ?? chainAsset.assetDisplayInfo
            let validationProviderFactory = EvmValidationProviderFactory(
                presentable: evmWireframe,
                balanceViewModelFactory: utilityBalanceViewModelFactory ?? sendingBalanceViewModelFactory,
                assetInfo: assetInfo
            )

            optInteractor = createEvmInteractor(for: chainAsset, validationProviderFactory: validationProviderFactory)
        } else {
            wireframe = OnChainTransferSetupWireframe(transferCompletion: transferCompletion)
            optInteractor = createSubstrateInteractor(for: chainAsset)
        }

        guard let interactor = optInteractor else {
            return nil
        }

        let dataValidatingFactory = TransferDataValidatorFactory(
            presentable: wireframe,
            assetDisplayInfo: chainAsset.assetDisplayInfo,
            utilityAssetInfo: chainAsset.chain.utilityAssets().first?.displayInfo,
            priceAssetInfoFactory: priceAssetInfoFactory
        )

        let phishingRepository = SubstrateRepositoryFactory().createPhishingRepository()
        let phishingValidatingFactory = PhishingAddressValidatorFactory(
            repository: phishingRepository,
            presentable: wireframe,
            operationQueue: OperationManagerFacade.sharedDefaultQueue
        )

        let presenter = OnChainTransferSetupPresenter(
            interactor: interactor,
            wireframe: wireframe,
            chainAsset: chainAsset,
            initialState: initialState,
            chainAssetViewModelFactory: chainAssetViewModelFactory,
            networkViewModelFactory: networkViewModelFactory,
            sendingBalanceViewModelFactory: sendingBalanceViewModelFactory,
            utilityBalanceViewModelFactory: utilityBalanceViewModelFactory,
            senderAccountAddress: selectedAccountAddress,
            dataValidatingFactory: dataValidatingFactory,
            phishingValidatingFactory: phishingValidatingFactory,
            localizationManager: localizationManager,
            logger: Logger.shared
        )

        presenter.view = view
        dataValidatingFactory.view = view
        phishingValidatingFactory.view = view
        interactor.presenter = presenter

        return presenter
    }

    private func createSubstrateInteractor(for chainAsset: ChainAsset) -> OnChainTransferSetupInteractor? {
        let chain = chainAsset.chain
        let asset = chainAsset.asset

        guard
            let selectedAccount = wallet.fetch(for: chain.accountRequest()),
            let runtimeProvider = chainRegistry.getRuntimeProvider(for: chain.chainId),
            let connection = chainRegistry.getConnection(for: chain.chainId),
            let currencyManager = CurrencyManager.shared else {
            return nil
        }

        let repositoryFactory = SubstrateRepositoryFactory(storageFacade: storageFacade)

        let walletRemoteSubscriptionService = WalletServiceFacade.sharedRemoteSubscriptionService

        let walletRemoteSubscriptionWrapper = WalletRemoteSubscriptionWrapper(
            remoteSubscriptionService: walletRemoteSubscriptionService,
            chainRegistry: chainRegistry,
            repositoryFactory: repositoryFactory,
            eventCenter: EventCenter.shared,
            operationQueue: OperationManagerFacade.sharedDefaultQueue,
            logger: Logger.shared
        )

        let extrinsicService = ExtrinsicServiceFactory(
            runtimeRegistry: runtimeProvider,
            engine: connection,
            operationManager: OperationManagerFacade.sharedManager,
            userStorageFacade: UserDataStorageFacade.shared
        ).createService(account: selectedAccount, chain: chain)

        return OnChainTransferSetupInteractor(
            selectedAccount: selectedAccount,
            chain: chain,
            asset: asset,
            runtimeService: runtimeProvider,
            feeProxy: ExtrinsicFeeProxy(),
            extrinsicService: extrinsicService,
            walletRemoteWrapper: walletRemoteSubscriptionWrapper,
            walletLocalSubscriptionFactory: WalletLocalSubscriptionFactory.shared,
            priceLocalSubscriptionFactory: PriceProviderFactory.shared,
            substrateStorageFacade: SubstrateDataStorageFacade.shared,
            currencyManager: currencyManager,
            operationQueue: OperationManagerFacade.sharedDefaultQueue
        )
    }

    private func createEvmInteractor(
        for chainAsset: ChainAsset,
        validationProviderFactory: EvmValidationProviderFactoryProtocol
    ) -> EvmOnChainTransferSetupInteractor? {
        let chain = chainAsset.chain
        let asset = chainAsset.asset

        guard
            let selectedAccount = wallet.fetch(for: chain.accountRequest()),
            let connection = chainRegistry.getOneShotConnection(for: chain.chainId),
            let currencyManager = CurrencyManager.shared else {
            return nil
        }

        let operationQueue = OperationManagerFacade.sharedDefaultQueue

        let operationFactory = EvmWebSocketOperationFactory(connection: connection)

        let gasLimitProvider = EvmGasLimitProviderFactory.createGasLimitProvider(
            for: asset,
            operationFactory: operationFactory,
            operationQueue: operationQueue,
            logger: Logger.shared
        )

        let nonceProvider = EvmDefaultNonceProvider(operationFactory: operationFactory)

        let extrinsicService = EvmTransactionService(
            accountId: selectedAccount.accountId,
            operationFactory: operationFactory,
            maxPriorityGasPriceProvider: EvmMaxPriorityGasPriceProvider(operationFactory: operationFactory),
            defaultGasPriceProvider: EvmLegacyGasPriceProvider(operationFactory: operationFactory),
            gasLimitProvider: gasLimitProvider,
            nonceProvider: nonceProvider,
            chain: chain,
            operationQueue: operationQueue
        )

        return EvmOnChainTransferSetupInteractor(
            selectedAccount: selectedAccount,
            chain: chain,
            asset: asset,
            feeProxy: EvmTransactionFeeProxy(),
            extrinsicService: extrinsicService,
            validationProviderFactory: validationProviderFactory,
            walletLocalSubscriptionFactory: WalletLocalSubscriptionFactory.shared,
            priceLocalSubscriptionFactory: PriceProviderFactory.shared,
            currencyManager: currencyManager,
            operationQueue: operationQueue
        )
    }
}
