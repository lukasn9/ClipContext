import StoreKit
import Combine

@MainActor
class TipStore: ObservableObject {
    static let shared = TipStore()

    @Published var products: [Product] = []
    @Published var isPurchasing = false
    @Published private(set) var hasDonated: Bool = UserDefaults.standard.bool(forKey: "ClipContextHasDonated")

    static let kofiURL = URL(string: "https://ko-fi.com/lukasnagy")!

    static var isAppStore: Bool {
        guard let receiptURL = Bundle.main.appStoreReceiptURL else { return false }
        return FileManager.default.fileExists(atPath: receiptURL.path)
    }

    private let productIDs = [
        "com.LukasNagy.ClipContext.tip.small",
        "com.LukasNagy.ClipContext.tip.medium",
        "com.LukasNagy.ClipContext.tip.large",
    ]

    private init() {
        Task {
            for await result in Transaction.updates {
                guard let transaction = try? result.payloadValue else { continue }
                await transaction.finish()
                markDonated()
            }
        }
        Task { await loadProducts() }
    }

    func loadProducts() async {
        do {
            let fetched = try await Product.products(for: productIDs)
            products = fetched.sorted { $0.price < $1.price }
        } catch {
            // Products unavailable — UI falls back to showing nothing
        }
    }

    func purchase(_ product: Product) async throws -> Bool {
        isPurchasing = true
        defer { isPurchasing = false }

        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            let transaction = try verified(verification)
            await transaction.finish()
            markDonated()
            return true
        case .userCancelled, .pending:
            return false
        @unknown default:
            return false
        }
    }

    private func verified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified: throw TipStoreError.failedVerification
        case .verified(let value): return value
        }
    }

    func markDonatedExternally() {
        markDonated()
    }

    private func markDonated() {
        hasDonated = true
        UserDefaults.standard.set(true, forKey: "ClipContextHasDonated")
    }

    enum TipStoreError: Error {
        case failedVerification
    }
}
