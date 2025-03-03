import Foundation
import BigInt

protocol EvmTransactionFeeProxyDelegate: AnyObject {
    func didReceiveFee(result: Result<EvmFeeModel, Error>, for identifier: TransactionFeeId)
}

protocol EvmTransactionFeeProxyProtocol: AnyObject {
    var delegate: EvmTransactionFeeProxyDelegate? { get set }

    func estimateFee(
        using service: EvmTransactionServiceProtocol,
        reuseIdentifier: TransactionFeeId,
        setupBy closure: @escaping EvmTransactionBuilderClosure
    )
}

final class EvmTransactionFeeProxy: TransactionFeeProxy<EvmFeeModel> {
    weak var delegate: EvmTransactionFeeProxyDelegate?

    private func handle(result: Result<EvmFeeModel, Error>, for identifier: TransactionFeeId) {
        update(result: result, for: identifier)

        delegate?.didReceiveFee(result: result, for: identifier)
    }
}

extension EvmTransactionFeeProxy: EvmTransactionFeeProxyProtocol {
    func estimateFee(
        using service: EvmTransactionServiceProtocol,
        reuseIdentifier: TransactionFeeId,
        setupBy closure: @escaping EvmTransactionBuilderClosure
    ) {
        if let state = getCachedState(for: reuseIdentifier) {
            if case let .loaded(result) = state {
                delegate?.didReceiveFee(result: result, for: reuseIdentifier)
            }

            return
        }

        setCachedState(.loading, for: reuseIdentifier)

        service.estimateFee(closure, runningIn: .main) { [weak self] result in
            self?.handle(result: result, for: reuseIdentifier)
        }
    }
}
