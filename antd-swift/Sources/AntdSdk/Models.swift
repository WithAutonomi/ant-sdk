import Foundation

/// Health check result from the antd daemon.
public struct HealthStatus: Sendable, Equatable {
    public let ok: Bool
    public let network: String

    public init(ok: Bool, network: String) {
        self.ok = ok
        self.network = network
    }
}

/// Result of a put/create operation that stores data on the network.
public struct PutResult: Sendable, Equatable {
    public let cost: String
    public let address: String

    public init(cost: String, address: String) {
        self.cost = cost
        self.address = address
    }
}

/// Wallet address result.
public struct WalletAddress: Sendable, Equatable {
    public let address: String

    public init(address: String) {
        self.address = address
    }
}

/// Wallet balance result.
public struct WalletBalance: Sendable, Equatable {
    public let balance: String
    public let gasBalance: String

    public init(balance: String, gasBalance: String) {
        self.balance = balance
        self.gasBalance = gasBalance
    }
}

/// A single payment required for an upload.
public struct PaymentInfo: Sendable, Equatable {
    public let quoteHash: String
    public let rewardsAddress: String
    public let amount: String

    public init(quoteHash: String, rewardsAddress: String, amount: String) {
        self.quoteHash = quoteHash
        self.rewardsAddress = rewardsAddress
        self.amount = amount
    }
}

/// Result of preparing an upload for external signing.
public struct PrepareUploadResult: Sendable, Equatable {
    public let uploadId: String
    public let payments: [PaymentInfo]
    public let totalAmount: String
    public let dataPaymentsAddress: String
    public let paymentTokenAddress: String
    public let rpcUrl: String

    public init(uploadId: String, payments: [PaymentInfo], totalAmount: String, dataPaymentsAddress: String, paymentTokenAddress: String, rpcUrl: String) {
        self.uploadId = uploadId
        self.payments = payments
        self.totalAmount = totalAmount
        self.dataPaymentsAddress = dataPaymentsAddress
        self.paymentTokenAddress = paymentTokenAddress
        self.rpcUrl = rpcUrl
    }
}

/// Result of finalizing an externally-signed upload.
public struct FinalizeUploadResult: Sendable, Equatable {
    public let address: String
    public let chunksStored: Int64

    public init(address: String, chunksStored: Int64) {
        self.address = address
        self.chunksStored = chunksStored
    }
}
