import Foundation

struct ModelPreparationLifecycle: Equatable {
    enum State: Equatable {
        case idle
        case preparing(tier: ModelTier, generation: Int)
        case failed(tier: ModelTier, message: String)
    }

    private(set) var state: State = .idle
    private(set) var generation = 0

    var preparingTier: ModelTier? {
        guard case .preparing(let tier, _) = state else { return nil }
        return tier
    }

    func error(for tier: ModelTier) -> String? {
        guard case .failed(let failedTier, let message) = state, failedTier == tier else { return nil }
        return message
    }

    mutating func begin(tier: ModelTier, force: Bool = false) -> Int? {
        if !force, case .preparing(let currentTier, _) = state, currentTier == tier {
            return nil
        }

        generation += 1
        state = .preparing(tier: tier, generation: generation)
        return generation
    }

    mutating func complete(tier: ModelTier, generation requestedGeneration: Int) -> Bool {
        guard case .preparing(tier, requestedGeneration) = state else { return false }
        state = .idle
        return true
    }

    mutating func fail(
        tier: ModelTier,
        generation requestedGeneration: Int,
        message: String
    ) -> Bool {
        guard case .preparing(tier, requestedGeneration) = state else { return false }
        state = .failed(tier: tier, message: message)
        return true
    }

    mutating func reset() {
        generation += 1
        state = .idle
    }
}
