import Foundation

enum VocabularyPackType: String, CaseIterable, Identifiable, Codable, Sendable {
    case tech = "tech"
    case medical = "medical"
    case legal = "legal"
    case brands = "brands"
    case names = "names"

    var id: Self { self }

    var displayName: String {
        switch self {
        case .tech: return "Tech"
        case .medical: return "Medical"
        case .legal: return "Legal"
        case .brands: return "Brands"
        case .names: return "Names"
        }
    }

    var blurb: String {
        switch self {
        case .tech: return "Programming, cloud, and developer tools."
        case .medical: return "Medications, conditions, and clinical terms."
        case .legal: return "Litigation, contract, and court terminology."
        case .brands: return "Company, product, and app names."
        case .names: return "Common first names and surnames."
        }
    }

    var fixesCount: Int {
        switch self {
        case .tech: return 76
        case .medical: return 87
        case .legal: return 32
        case .brands: return 106
        case .names: return 90
        }
    }

    var examples: String {
        switch self {
        case .tech: return "AngularJS, Bazel, Blazor, async..."
        case .medical: return "Celexa, Fosamax, Humira..."
        case .legal: return "FERPA, NLRB, accord..."
        case .brands: return "ASUS, Adyen, Aetna..."
        case .names: return "Acosta, Adeline, Aguirre..."
        }
    }
}
