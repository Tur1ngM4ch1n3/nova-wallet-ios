import Foundation
import RobinHood
import SubstrateSdk

protocol SubqueryHistoryOperationFactoryProtocol {
    func createOperation(
        address: String,
        count: Int,
        cursor: String?
    ) -> BaseOperation<SubqueryHistoryData>
}

final class SubqueryHistoryOperationFactory {
    let url: URL
    let filter: WalletHistoryFilter
    let assetId: String?
    let hasPoolStaking: Bool

    init(url: URL, filter: WalletHistoryFilter, assetId: String?, hasPoolStaking: Bool) {
        self.url = url
        self.filter = filter
        self.assetId = assetId
        self.hasPoolStaking = hasPoolStaking
    }

    private func prepareExtrinsicInclusionFilter() -> String {
        """
        {
          and: [
            {
                  extrinsic: {isNull: false}
            },
            {
              not: {
                and: [
                    { extrinsic: { contains: {module: "balances"} } },
                    {
                        or: [
                         { extrinsic: {contains: {call: "transfer"} } },
                         { extrinsic: {contains: {call: "transferKeepAlive"} } },
                         { extrinsic: {contains: {call: "forceTransfer"} } },
                         { extrinsic: {contains: {call: "transferAll"} } },
                         { extrinsic: {contains: {call: "transferAllowDeath"} } }
                      ]
                    }
                ]
               }
            }
          ]
        }
        """
    }

    private func prepareAssetIdFilter(_ assetId: String) -> String {
        """
        {
            assetTransfer: { contains: {assetId: \"\(assetId)\"} }
        }
        """
    }

    private func prepareFilter() -> String {
        var filterStrings: [String] = []

        if filter.contains(.extrinsics) {
            filterStrings.append(prepareExtrinsicInclusionFilter())
        }

        if filter.contains(.rewardsAndSlashes) {
            var childFilters: [SubqueryFilter] = [SubqueryIsNotNullFilter(fieldName: "reward")]

            if hasPoolStaking {
                childFilters.append(SubqueryIsNotNullFilter(fieldName: "poolReward"))
            }

            let filter = SubqueryInnerFilter(inner:
                SubqueryCompoundFilter.or(childFilters)
            )
            filterStrings.append(filter.rawSubqueryFilter())
        }

        if filter.contains(.transfers) {
            if let assetId = assetId {
                filterStrings.append(prepareAssetIdFilter(assetId))
            } else {
                filterStrings.append("{ transfer: { isNull: false } }")
            }
        }

        if filter.contains(.swaps) {
            if let assetId = assetId {
                filterStrings.append(prepareAssetIdFilter(assetId))
            } else {
                filterStrings.append("{ swap: { isNull: false } }")
            }
        }

        return filterStrings.joined(separator: ",")
    }

    private func prepareQueryForAddress(
        _ address: String,
        count: Int,
        cursor: String?
    ) -> String {
        let after = cursor.map { "\"\($0)\"" } ?? "null"
        let transferField = assetId != nil ? "assetTransfer" : "transfer"
        let filterString = prepareFilter()
        let poolRewardField = hasPoolStaking ? "poolReward" : ""
        return """
        {
            historyElements(
                 after: \(after),
                 first: \(count),
                 orderBy: TIMESTAMP_DESC,
                 filter: {
                     address: { equalTo: \"\(address)\"},
                     or: [
                        \(filterString)
                     ]
                 }
             ) {
                 pageInfo {
                     startCursor,
                     endCursor
                 },
                 nodes {
                     id
                     blockNumber
                     extrinsicIdx
                     extrinsicHash
                     timestamp
                     address
                     reward
                     extrinsic
                     \(transferField)
                     \(poolRewardField)
                     swap
                 }
             }
        }
        """
    }
}

extension SubqueryHistoryOperationFactory: SubqueryHistoryOperationFactoryProtocol {
    func createOperation(
        address: String,
        count: Int,
        cursor: String?
    ) -> BaseOperation<SubqueryHistoryData> {
        let queryString = prepareQueryForAddress(address, count: count, cursor: cursor)

        let requestFactory = BlockNetworkRequestFactory {
            var request = URLRequest(url: self.url)

            let info = JSON.dictionaryValue(["query": JSON.stringValue(queryString)])
            request.httpBody = try JSONEncoder().encode(info)
            request.setValue(
                HttpContentType.json.rawValue,
                forHTTPHeaderField: HttpHeaderKey.contentType.rawValue
            )

            request.httpMethod = HttpMethod.post.rawValue
            return request
        }

        let resultFactory = AnyNetworkResultFactory<SubqueryHistoryData> { data in
            let response = try JSONDecoder().decode(
                SubqueryResponse<SubqueryHistoryData>.self,
                from: data
            )

            switch response {
            case let .errors(error):
                throw error
            case let .data(response):
                return response
            }
        }

        let operation = NetworkOperation(requestFactory: requestFactory, resultFactory: resultFactory)

        return operation
    }
}
