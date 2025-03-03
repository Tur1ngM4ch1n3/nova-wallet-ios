import Foundation

protocol BaseErrorPresentable {
    func presentAmountTooHigh(from view: ControllerBackedProtocol, locale: Locale?)
    func presentFeeNotReceived(from view: ControllerBackedProtocol, locale: Locale?)
    func presentFeeTooHigh(from view: ControllerBackedProtocol, balance: String, fee: String, locale: Locale?)
    func presentExtrinsicFailed(from view: ControllerBackedProtocol, locale: Locale?)
    func presentInvalidAddress(from view: ControllerBackedProtocol, chainName: String, locale: Locale?)

    func presentExistentialDepositWarning(
        from view: ControllerBackedProtocol,
        action: @escaping () -> Void,
        locale: Locale?
    )

    func presentIsSystemAccount(
        from view: ControllerBackedProtocol?,
        onContinue: @escaping () -> Void,
        locale: Locale?
    )

    func presentMinBalanceViolated(from view: ControllerBackedProtocol, locale: Locale?)
}

extension BaseErrorPresentable where Self: AlertPresentable & ErrorPresentable {
    func presentAmountTooHigh(from view: ControllerBackedProtocol, locale: Locale?) {
        let message = R.string.localizable
            .commonNotEnoughBalanceMessage(preferredLanguages: locale?.rLanguages)
        let title = R.string.localizable.commonErrorGeneralTitle(preferredLanguages: locale?.rLanguages)
        let closeAction = R.string.localizable.commonClose(preferredLanguages: locale?.rLanguages)

        present(message: message, title: title, closeAction: closeAction, from: view)
    }

    func presentFeeNotReceived(from view: ControllerBackedProtocol, locale: Locale?) {
        let message = R.string.localizable.feeNotYetLoadedMessage(preferredLanguages: locale?.rLanguages)
        let title = R.string.localizable.feeNotYetLoadedTitle(preferredLanguages: locale?.rLanguages)
        let closeAction = R.string.localizable.commonClose(preferredLanguages: locale?.rLanguages)

        present(message: message, title: title, closeAction: closeAction, from: view)
    }

    func presentExtrinsicFailed(from view: ControllerBackedProtocol, locale: Locale?) {
        let message = R.string.localizable.commonTransactionFailed(preferredLanguages: locale?.rLanguages)
        let title = R.string.localizable.commonErrorGeneralTitle(preferredLanguages: locale?.rLanguages)
        let closeAction = R.string.localizable.commonClose(preferredLanguages: locale?.rLanguages)

        present(message: message, title: title, closeAction: closeAction, from: view)
    }

    func presentFeeTooHigh(from view: ControllerBackedProtocol, balance: String, fee: String, locale: Locale?) {
        let message = R.string.localizable.commonNotEnoughFeeMessage_v380(
            fee,
            balance,
            preferredLanguages: locale?.rLanguages
        )

        let title = R.string.localizable.commonNotEnoughFeeTitle(preferredLanguages: locale?.rLanguages)
        let closeAction = R.string.localizable.commonClose(preferredLanguages: locale?.rLanguages)

        present(message: message, title: title, closeAction: closeAction, from: view)
    }

    func presentExistentialDepositWarning(
        from view: ControllerBackedProtocol,
        action: @escaping () -> Void,
        locale: Locale?
    ) {
        let title = R.string.localizable
            .commonExistentialWarningTitle(preferredLanguages: locale?.rLanguages)
        let message = R.string.localizable
            .commonExistentialWarningMessage_v2_2_0(preferredLanguages: locale?.rLanguages)

        presentWarning(
            for: title,
            message: message,
            action: action,
            view: view,
            locale: locale
        )
    }

    func presentWarning(
        for title: String,
        message: String,
        action: @escaping () -> Void,
        view: ControllerBackedProtocol,
        locale: Locale?
    ) {
        let proceedTitle = R.string.localizable
            .commonProceed(preferredLanguages: locale?.rLanguages)
        let proceedAction = AlertPresentableAction(title: proceedTitle) {
            action()
        }

        let closeTitle = R.string.localizable
            .commonCancel(preferredLanguages: locale?.rLanguages)

        let viewModel = AlertPresentableViewModel(
            title: title,
            message: message,
            actions: [proceedAction],
            closeAction: closeTitle
        )

        present(
            viewModel: viewModel,
            style: .alert,
            from: view
        )
    }

    func presentInvalidAddress(from view: ControllerBackedProtocol, chainName: String, locale: Locale?) {
        let title = R.string.localizable.commonValidationInvalidAddressTitle(
            preferredLanguages: locale?.rLanguages
        )

        let message = R.string.localizable.commonInvalidAddressFormat(
            chainName,
            preferredLanguages: locale?.rLanguages
        )

        let closeAction = R.string.localizable.commonClose(preferredLanguages: locale?.rLanguages)

        present(message: message, title: title, closeAction: closeAction, from: view)
    }

    func presentIsSystemAccount(
        from view: ControllerBackedProtocol?,
        onContinue: @escaping () -> Void,
        locale: Locale?
    ) {
        let title = R.string.localizable.sendSystemAccountTitle(preferredLanguages: locale?.rLanguages)
        let message = R.string.localizable.sendSystemAccountMessage(preferredLanguages: locale?.rLanguages)

        let continueAction = AlertPresentableAction(
            title: R.string.localizable.commonContinue(preferredLanguages: locale?.rLanguages),
            style: .destructive
        ) {
            onContinue()
        }

        let viewModel = AlertPresentableViewModel(
            title: title,
            message: message,
            actions: [continueAction],
            closeAction: R.string.localizable.commonCancel(preferredLanguages: locale?.rLanguages)
        )

        present(viewModel: viewModel, style: .alert, from: view)
    }

    func presentMinBalanceViolated(from view: ControllerBackedProtocol, locale: Locale?) {
        let title = R.string.localizable.amountTooLow(preferredLanguages: locale?.rLanguages)
        let message = R.string.localizable.walletFeeOverExistentialDeposit(
            preferredLanguages: locale?.rLanguages
        )

        let closeAction = R.string.localizable.commonClose(preferredLanguages: locale?.rLanguages)

        present(message: message, title: title, closeAction: closeAction, from: view)
    }
}
