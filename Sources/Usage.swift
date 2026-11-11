import Foundation

// MARK: - Usage API model

struct Usage: Decodable {
    let limits: [Limit]
    let spend: Spend?

    struct Limit: Decodable {
        let kind: String
        let percent: Double?
        let resets_at: String?
    }

    struct Spend: Decodable {
        let enabled: Bool?
        let used: Money?
        let limit: Money?
    }

    struct Money: Decodable {
        let amount_minor: Double
        let exponent: Int
        let currency: String?

        var amount: Double {
            amount_minor / pow(10, Double(exponent))
        }

        var formatted: String {
            guard let currency else {
                return amount.formatted(.number.precision(.fractionLength(exponent)))
            }
            return amount.formatted(.currency(code: currency).precision(.fractionLength(exponent)))
        }
    }

    /// The used percentage of a limit, or nil when the API did not send it.
    func percent(_ limit: Rule.Limit) -> Double? {
        switch limit {
        case .session, .weekly:
            return limits.first { $0.kind == limit.rawValue }?.percent
        case .extra:
            guard let spend, spend.enabled == true, let used = spend.used, let cap = spend.limit, cap.amount > 0 else {
                return nil
            }
            return used.amount / cap.amount * 100
        }
    }
}

extension Double {
    /// A percentage from 0 to 100 in the number format of the Mac, for example "42 %" in German.
    var percentText: String {
        (self / 100).formatted(.percent.precision(.fractionLength(0)))
    }
}
