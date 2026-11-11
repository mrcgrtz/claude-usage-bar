import Foundation

// MARK: - Usage API model

struct Usage: Decodable {
    let limits: [Limit]
    let spend: Spend?

    struct Limit: Decodable {
        let kind: String
        let percent: Double?
        let resets_at: String?
        /// What a scoped limit counts, for example the usage of one model.
        let scope: Scope?

        /// The name of the limit in the menu, for example "Weekly (Fable)" for the weekly limit of one model.
        var label: String {
            switch kind {
            case "session":
                return String(localized: "5-hour")
            case "weekly_all":
                return String(localized: "Weekly")
            case "weekly_scoped":
                guard let name = scope?.name else { return String(localized: "Weekly (scoped)") }
                return String(localized: "Weekly (\(name))")
            default:
                return kind.replacingOccurrences(of: "_", with: " ")
            }
        }
    }

    struct Scope: Decodable {
        let model: Name?
        let surface: Name?

        var name: String? {
            model?.display_name ?? surface?.display_name
        }
    }

    struct Name: Decodable {
        let display_name: String?
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

extension Usage.Limit {
    private enum CodingKeys: String, CodingKey {
        case kind, percent, resets_at, scope
    }

    // A new format of the scope must not stop the app from showing the other values.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(String.self, forKey: .kind)
        percent = try container.decodeIfPresent(Double.self, forKey: .percent)
        resets_at = try container.decodeIfPresent(String.self, forKey: .resets_at)
        scope = try? container.decodeIfPresent(Usage.Scope.self, forKey: .scope)
    }
}

extension Double {
    /// A percentage from 0 to 100 in the number format of the Mac, for example "42 %" in German.
    var percentText: String {
        (self / 100).formatted(.percent.precision(.fractionLength(0)))
    }
}
