import Foundation
import Observation
import StoreKit

@MainActor
@Observable
final class EntitlementStore {
    static let monthlyProductID = "samantha_key_monthly"

    private(set) var products: [Product] = []
    private(set) var hasAccess = false
    private(set) var isLoading = false
    var errorMessage: String?

    @ObservationIgnored
    nonisolated(unsafe) private var updatesTask: Task<Void, Never>?

    init() {
        updatesTask = listenForTransactions()
    }

    deinit {
        updatesTask?.cancel()
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        do {
            products = try await Product.products(for: [Self.monthlyProductID])
            hasAccess = await currentVerifiedSubscription() != nil
            AppGroupStore.setEntitlementActive(hasAccess)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func purchaseWeekly() async {
        guard let product = products.first else {
            await refresh()
            return
        }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try Self.checkVerified(verification)
                await transaction.finish()
                await refresh()
            case .pending, .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func restore() async {
        do {
            try await AppStore.sync()
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func currentEntitlementPayload() async -> EntitlementPayload? {
        guard let entitlement = await currentVerifiedSubscription() else { return nil }
        return EntitlementPayload(
            productID: entitlement.transaction.productID,
            originalTransactionID: String(entitlement.transaction.originalID),
            transactionID: String(entitlement.transaction.id),
            signedTransactionInfo: entitlement.jwsRepresentation,
            appAccountToken: nil
        )
    }

    private func currentVerifiedSubscription() async -> VerifiedSubscription? {
        for await result in Transaction.currentEntitlements {
            guard let transaction = try? Self.checkVerified(result) else { continue }
            guard transaction.productID == Self.monthlyProductID else { continue }
            if transaction.revocationDate == nil {
                return VerifiedSubscription(transaction: transaction, jwsRepresentation: result.jwsRepresentation)
            }
        }
        return nil
    }

    private func listenForTransactions() -> Task<Void, Never> {
        Task { [weak self] in
            for await result in Transaction.updates {
                guard let transaction = try? Self.checkVerified(result) else { continue }
                await transaction.finish()
                await self?.refresh()
            }
        }
    }

    private static func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let value):
            return value
        case .unverified:
            throw StoreError.failedVerification
        }
    }
}

private struct VerifiedSubscription {
    let transaction: Transaction
    let jwsRepresentation: String
}

enum StoreError: LocalizedError {
    case failedVerification

    var errorDescription: String? {
        "The App Store transaction could not be verified."
    }
}

struct EntitlementPayload: Codable {
    let productID: String
    let originalTransactionID: String
    let transactionID: String
    let signedTransactionInfo: String
    let appAccountToken: UUID?
}
