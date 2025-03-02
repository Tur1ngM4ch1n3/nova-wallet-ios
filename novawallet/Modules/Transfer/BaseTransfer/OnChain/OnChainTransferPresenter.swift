import Foundation
import BigInt
import SubstrateSdk

class OnChainTransferPresenter {
    let chainAsset: ChainAsset

    let senderAccountAddress: AccountAddress

    private(set) var senderSendingAssetBalance: AssetBalance?
    private(set) var senderUtilityAssetBalance: AssetBalance?

    private(set) var recepientSendingAssetBalance: AssetBalance?
    private(set) var recepientUtilityAssetBalance: AssetBalance?

    private(set) var sendingAssetPrice: PriceData?
    private(set) var utilityAssetPrice: PriceData?

    private(set) var sendingAssetExistence: AssetBalanceExistence?
    private(set) var utilityAssetMinBalance: BigUInt?

    var senderUtilityBalanceCountingEd: BigUInt? {
        isUtilityTransfer ? senderSendingAssetBalance?.balanceCountingEd :
            senderUtilityAssetBalance?.balanceCountingEd
    }

    var senderUtilityAssetTransferable: BigUInt? {
        isUtilityTransfer ? senderSendingAssetBalance?.transferable : senderUtilityAssetBalance?.transferable
    }

    private(set) lazy var iconGenerator = PolkadotIconGenerator()

    private(set) var fee: FeeOutputModel?

    let networkViewModelFactory: NetworkViewModelFactoryProtocol
    let sendingBalanceViewModelFactory: BalanceViewModelFactoryProtocol
    let utilityBalanceViewModelFactory: BalanceViewModelFactoryProtocol?

    let dataValidatingFactory: TransferDataValidatorFactoryProtocol

    let logger: LoggerProtocol?

    var isUtilityTransfer: Bool {
        chainAsset.chain.utilityAssets().first?.assetId == chainAsset.asset.assetId
    }

    init(
        chainAsset: ChainAsset,
        networkViewModelFactory: NetworkViewModelFactoryProtocol,
        sendingBalanceViewModelFactory: BalanceViewModelFactoryProtocol,
        utilityBalanceViewModelFactory: BalanceViewModelFactoryProtocol?,
        senderAccountAddress: AccountAddress,
        dataValidatingFactory: TransferDataValidatorFactoryProtocol,
        logger: LoggerProtocol? = nil
    ) {
        self.chainAsset = chainAsset
        self.networkViewModelFactory = networkViewModelFactory
        self.sendingBalanceViewModelFactory = sendingBalanceViewModelFactory
        self.utilityBalanceViewModelFactory = utilityBalanceViewModelFactory
        self.senderAccountAddress = senderAccountAddress
        self.dataValidatingFactory = dataValidatingFactory
        self.logger = logger
    }

    func refreshFee() {
        fatalError("Child classes must implement this method")
    }

    func askFeeRetry() {
        fatalError("Child classes must implement this method")
    }

    func updateFee(_ newValue: FeeOutputModel?) {
        fee = newValue
    }

    func resetRecepientBalance() {
        recepientSendingAssetBalance = nil
        recepientUtilityAssetBalance = nil
    }

    func baseValidators(
        for sendingAmount: Decimal?,
        recepientAddress: AccountAddress?,
        utilityAssetInfo: AssetBalanceDisplayInfo,
        view: ControllerBackedProtocol?,
        selectedLocale: Locale
    ) -> [DataValidating] {
        var validators: [DataValidating] = [
            dataValidatingFactory.receiverMatchesChain(
                recepient: recepientAddress,
                chainFormat: chainAsset.chain.chainFormat,
                chainName: chainAsset.chain.name,
                locale: selectedLocale
            ),

            dataValidatingFactory.receiverDiffers(
                recepient: recepientAddress,
                sender: senderAccountAddress,
                locale: selectedLocale
            ),

            dataValidatingFactory.has(fee: fee?.value, locale: selectedLocale) { [weak self] in
                self?.refreshFee()
                return
            },

            dataValidatingFactory.canSpendAmountInPlank(
                balance: senderSendingAssetBalance?.transferable,
                spendingAmount: sendingAmount,
                asset: chainAsset.assetDisplayInfo,
                locale: selectedLocale
            ),

            dataValidatingFactory.canPayFeeSpendingAmountInPlank(
                balance: senderUtilityAssetTransferable,
                fee: fee?.value,
                spendingAmount: isUtilityTransfer ? sendingAmount : nil,
                asset: utilityAssetInfo,
                locale: selectedLocale
            ),

            dataValidatingFactory.notViolatingMinBalancePaying(
                fee: fee?.value,
                total: senderUtilityBalanceCountingEd,
                minBalance: isUtilityTransfer ? sendingAssetExistence?.minBalance : utilityAssetMinBalance,
                locale: selectedLocale
            ),

            dataValidatingFactory.receiverWillHaveAssetAccount(
                sendingAmount: sendingAmount,
                totalAmount: recepientSendingAssetBalance?.balanceCountingEd,
                minBalance: sendingAssetExistence?.minBalance,
                locale: selectedLocale
            ),

            dataValidatingFactory.receiverNotBlocked(
                recepientSendingAssetBalance?.blocked,
                locale: selectedLocale
            )
        ]

        if !isUtilityTransfer {
            let accountProviderValidation = dataValidatingFactory.receiverHasAccountProvider(
                utilityTotalAmount: recepientUtilityAssetBalance?.totalInPlank,
                utilityMinBalance: utilityAssetMinBalance,
                assetExistence: sendingAssetExistence,
                locale: selectedLocale
            )

            validators.append(accountProviderValidation)
        }

        let optFeeValidation = fee?.validationProvider?.getValidations(
            for: view,
            onRefresh: { [weak self] in
                self?.refreshFee()
            },
            locale: selectedLocale
        )

        if let feeValidation = optFeeValidation {
            validators.append(feeValidation)
        }

        return validators
    }

    func didReceiveSendingAssetSenderBalance(_ balance: AssetBalance) {
        senderSendingAssetBalance = balance
    }

    func didReceiveUtilityAssetSenderBalance(_ balance: AssetBalance) {
        senderUtilityAssetBalance = balance
    }

    func didReceiveSendingAssetRecepientBalance(_ balance: AssetBalance) {
        recepientSendingAssetBalance = balance
    }

    func didReceiveUtilityAssetRecepientBalance(_ balance: AssetBalance) {
        recepientUtilityAssetBalance = balance
    }

    func didReceiveFee(result: Result<FeeOutputModel, Error>) {
        switch result {
        case let .success(fee):
            self.fee = fee
        case .failure:
            askFeeRetry()
        }
    }

    func didReceiveSendingAssetPrice(_ priceData: PriceData?) {
        sendingAssetPrice = priceData
    }

    func didReceiveUtilityAssetPrice(_ priceData: PriceData?) {
        utilityAssetPrice = priceData
    }

    func didReceiveUtilityAssetMinBalance(_ value: BigUInt) {
        utilityAssetMinBalance = value
    }

    func didReceiveSendingAssetExistence(_ value: AssetBalanceExistence) {
        sendingAssetExistence = value
    }

    func didCompleteSetup() {}

    func didReceiveError(_: Error) {}
}
