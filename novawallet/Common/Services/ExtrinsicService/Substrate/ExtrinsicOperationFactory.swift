import Foundation
import RobinHood
import SubstrateSdk
import IrohaCrypto
import BigInt

protocol ExtrinsicOperationFactoryProtocol {
    var connection: JSONRPCEngine { get }

    func estimateFeeOperation(
        _ closure: @escaping ExtrinsicBuilderIndexedClosure,
        indexes: IndexSet
    ) -> CompoundOperationWrapper<FeeIndexedExtrinsicResult>

    func submit(
        _ closure: @escaping ExtrinsicBuilderIndexedClosure,
        signer: SigningWrapperProtocol,
        indexes: IndexSet
    ) -> CompoundOperationWrapper<SubmitIndexedExtrinsicResult>

    func buildExtrinsic(
        _ closure: @escaping ExtrinsicBuilderClosure,
        signer: SigningWrapperProtocol
    ) -> CompoundOperationWrapper<String>
}

extension ExtrinsicOperationFactoryProtocol {
    func estimateFeeOperation(
        _ closure: @escaping ExtrinsicBuilderIndexedClosure,
        numberOfExtrinsics: Int
    ) -> CompoundOperationWrapper<FeeIndexedExtrinsicResult> {
        estimateFeeOperation(closure, indexes: IndexSet(0 ..< numberOfExtrinsics))
    }

    func submit(
        _ closure: @escaping ExtrinsicBuilderIndexedClosure,
        signer: SigningWrapperProtocol,
        numberOfExtrinsics: Int
    ) -> CompoundOperationWrapper<SubmitIndexedExtrinsicResult> {
        submit(closure, signer: signer, indexes: IndexSet(0 ..< numberOfExtrinsics))
    }

    func estimateFeeOperation(
        _ closure: @escaping ExtrinsicBuilderClosure
    ) -> CompoundOperationWrapper<ExtrinsicFeeProtocol> {
        let wrapperClosure: ExtrinsicBuilderIndexedClosure = { builder, _ in
            try closure(builder)
        }

        let feeOperation = estimateFeeOperation(
            wrapperClosure,
            numberOfExtrinsics: 1
        )

        let resultMappingOperation = ClosureOperation<ExtrinsicFeeProtocol> {
            guard let result = try feeOperation.targetOperation.extractNoCancellableResultData()
                .results.first?.result else {
                throw BaseOperationError.unexpectedDependentResult
            }

            return try result.get()
        }

        resultMappingOperation.addDependency(feeOperation.targetOperation)

        return CompoundOperationWrapper(
            targetOperation: resultMappingOperation,
            dependencies: feeOperation.allOperations
        )
    }

    func submit(
        _ closure: @escaping ExtrinsicBuilderClosure,
        signer: SigningWrapperProtocol
    ) -> CompoundOperationWrapper<String> {
        let wrapperClosure: ExtrinsicBuilderIndexedClosure = { builder, _ in
            try closure(builder)
        }

        let submitOperation = submit(
            wrapperClosure,
            signer: signer,
            numberOfExtrinsics: 1
        )

        let resultMappingOperation = ClosureOperation<String> {
            guard let result = try submitOperation.targetOperation.extractNoCancellableResultData()
                .results.first?.result else {
                throw BaseOperationError.unexpectedDependentResult
            }

            return try result.get()
        }

        resultMappingOperation.addDependency(submitOperation.targetOperation)

        return CompoundOperationWrapper(
            targetOperation: resultMappingOperation,
            dependencies: submitOperation.allOperations
        )
    }
}

final class ExtrinsicOperationFactory: BaseExtrinsicOperationFactory {
    let chain: ChainModel
    let customExtensions: [ExtrinsicExtension]
    let eraOperationFactory: ExtrinsicEraOperationFactoryProtocol
    let senderResolvingFactory: ExtrinsicSenderResolutionFactoryProtocol

    init(
        chain: ChainModel,
        runtimeRegistry: RuntimeCodingServiceProtocol,
        customExtensions: [ExtrinsicExtension],
        engine: JSONRPCEngine,
        senderResolvingFactory: ExtrinsicSenderResolutionFactoryProtocol,
        eraOperationFactory: ExtrinsicEraOperationFactoryProtocol = MortalEraOperationFactory(),
        operationManager: OperationManagerProtocol
    ) {
        self.chain = chain
        self.senderResolvingFactory = senderResolvingFactory
        self.customExtensions = customExtensions
        self.eraOperationFactory = eraOperationFactory

        super.init(
            runtimeRegistry: runtimeRegistry,
            engine: engine,
            operationManager: operationManager,
            usesStateCallForFee: chain.feeViaRuntimeCall
        )
    }

    private func createNonceOperation(
        in chain: ChainModel,
        accountIdClosure: @escaping () throws -> AccountId
    ) -> BaseOperation<UInt32> {
        let operation = JSONRPCListOperation<UInt32>(
            engine: engine,
            method: RPCMethod.getExtrinsicNonce
        )

        operation.configurationBlock = {
            do {
                let accountId = try accountIdClosure()
                let address = try accountId.toAddress(using: chain.chainFormat)
                operation.parameters = [address]
            } catch {
                operation.result = .failure(error)
            }
        }

        return operation
    }

    private func createBlockHashOperation(
        connection: JSONRPCEngine,
        for numberClosure: @escaping () throws -> BlockNumber
    ) -> BaseOperation<String> {
        let requestOperation = JSONRPCListOperation<String>(
            engine: connection,
            method: RPCMethod.getBlockHash
        )

        requestOperation.configurationBlock = {
            do {
                let blockNumber = try numberClosure()
                requestOperation.parameters = [blockNumber.toHex()]
            } catch {
                requestOperation.result = .failure(error)
            }
        }

        return requestOperation
    }

    private func createPartialBuildersWrapper(
        customClosure: @escaping ExtrinsicBuilderIndexedClosure,
        indexes: [Int],
        chain: ChainModel,
        customExtensions: [ExtrinsicExtension],
        codingFactoryOperation: BaseOperation<RuntimeCoderFactoryProtocol>
    ) -> CompoundOperationWrapper<[ExtrinsicBuilderProtocol]> {
        let genesisBlockOperation = createBlockHashOperation(connection: engine, for: { 0 })

        let eraWrapper = eraOperationFactory.createOperation(from: engine, runtimeService: runtimeRegistry)

        let eraBlockOperation = createBlockHashOperation(connection: engine) {
            try eraWrapper.targetOperation.extractNoCancellableResultData().blockNumber
        }

        eraBlockOperation.addDependency(eraWrapper.targetOperation)

        let partialBuildersOperation = ClosureOperation<[ExtrinsicBuilderProtocol]> {
            let codingFactory = try codingFactoryOperation.extractNoCancellableResultData()
            let genesisHash = try genesisBlockOperation.extractNoCancellableResultData()
            let era = try eraWrapper.targetOperation.extractNoCancellableResultData().extrinsicEra
            let eraBlockHash = try eraBlockOperation.extractNoCancellableResultData()

            let runtimeJsonContext = codingFactory.createRuntimeJsonContext()

            return try indexes.map { index in
                var builder: ExtrinsicBuilderProtocol = ExtrinsicBuilder(
                    specVersion: codingFactory.specVersion,
                    transactionVersion: codingFactory.txVersion,
                    genesisHash: genesisHash
                )
                .with(runtimeJsonContext: runtimeJsonContext)
                .with(era: era, blockHash: eraBlockHash)

                if let defaultTip = chain.defaultTip {
                    builder = builder.with(tip: defaultTip)
                }

                for customExtension in customExtensions {
                    builder = builder.adding(extrinsicExtension: customExtension)
                }

                return try customClosure(builder, index)
            }
        }

        let dependencies = [genesisBlockOperation] + eraWrapper.allOperations + [eraBlockOperation]

        dependencies.forEach { partialBuildersOperation.addDependency($0) }

        return CompoundOperationWrapper(targetOperation: partialBuildersOperation, dependencies: dependencies)
    }

    private func createExtrinsicsOperation(
        dependingOn nonceOperation: BaseOperation<UInt32>,
        senderResolutionOperation: BaseOperation<ExtrinsicSenderBuilderResolution>,
        codingFactoryOperation: BaseOperation<RuntimeCoderFactoryProtocol>,
        signingClosure: @escaping (Data, ExtrinsicSigningContext) throws -> Data
    ) -> BaseOperation<ExtrinsicsCreationResult> {
        ClosureOperation<ExtrinsicsCreationResult> {
            let nonce = try nonceOperation.extractNoCancellableResultData()
            let (senderResolution, builders) = try senderResolutionOperation.extractNoCancellableResultData()
            let codingFactory = try codingFactoryOperation.extractNoCancellableResultData()

            let extrinsics: [Data] = try builders.enumerated().map { index, partialBuilder in
                var builder = partialBuilder.with(nonce: nonce + UInt32(index))
                let account = MultiAddress.accoundId(senderResolution.account.accountId)
                builder = try builder
                    .with(address: account)
                    .with(signaturePayloadFormat: senderResolution.account.type.signaturePayloadFormat)

                let context = ExtrinsicSigningContext.Substrate(
                    senderResolution: senderResolution,
                    calls: builder.getCalls()
                )

                builder = try builder.signing(
                    with: signingClosure,
                    context: context,
                    codingFactory: codingFactory
                )

                return try builder.build(encodingBy: codingFactory.createEncoder(), metadata: codingFactory.metadata)
            }

            return (extrinsics, senderResolution)
        }
    }

    override func createExtrinsicWrapper(
        customClosure: @escaping ExtrinsicBuilderIndexedClosure,
        indexes: [Int],
        signingClosure: @escaping (Data, ExtrinsicSigningContext) throws -> Data
    ) -> CompoundOperationWrapper<ExtrinsicsCreationResult> {
        let codingFactoryOperation = runtimeRegistry.fetchCoderFactoryOperation()

        let partialBuildersWrapper = createPartialBuildersWrapper(
            customClosure: customClosure,
            indexes: indexes,
            chain: chain,
            customExtensions: customExtensions,
            codingFactoryOperation: codingFactoryOperation
        )

        partialBuildersWrapper.addDependency(operations: [codingFactoryOperation])

        let senderResolverWrapper = senderResolvingFactory.createWrapper()
        let senderResolutionOperation = ClosureOperation<ExtrinsicSenderBuilderResolution> {
            let builders = try partialBuildersWrapper.targetOperation.extractNoCancellableResultData()
            let resolver = try senderResolverWrapper.targetOperation.extractNoCancellableResultData()
            let codingFactory = try codingFactoryOperation.extractNoCancellableResultData()

            return try resolver.resolveSender(wrapping: builders, codingFactory: codingFactory)
        }

        senderResolutionOperation.addDependency(partialBuildersWrapper.targetOperation)
        senderResolutionOperation.addDependency(senderResolverWrapper.targetOperation)
        senderResolutionOperation.addDependency(codingFactoryOperation)

        let nonceOperation = createNonceOperation(in: chain) {
            let (senderResolution, _) = try senderResolutionOperation.extractNoCancellableResultData()
            return senderResolution.account.accountId
        }

        nonceOperation.addDependency(senderResolutionOperation)

        let extrinsicsOperation = createExtrinsicsOperation(
            dependingOn: nonceOperation,
            senderResolutionOperation: senderResolutionOperation,
            codingFactoryOperation: codingFactoryOperation,
            signingClosure: signingClosure
        )

        extrinsicsOperation.addDependency(nonceOperation)
        extrinsicsOperation.addDependency(senderResolutionOperation)
        extrinsicsOperation.addDependency(codingFactoryOperation)

        let dependencies = [codingFactoryOperation] + partialBuildersWrapper.allOperations +
            senderResolverWrapper.allOperations + [senderResolutionOperation, nonceOperation]

        return CompoundOperationWrapper(targetOperation: extrinsicsOperation, dependencies: dependencies)
    }

    override func createDummySigner(for cryptoType: MultiassetCryptoType) throws -> DummySigner {
        try DummySigner(cryptoType: cryptoType)
    }
}
