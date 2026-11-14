import Foundation

/// Chemistry molar mass and atomic weight calculator: `molar mass of C6H12O6`, `molecular weight of H2O`.
enum CalcChemistry {
    static func evaluate(query: String) -> CalcResult? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let formulaText = extractFormula(from: trimmed) else { return nil }
        guard let mass = calculateMolarMass(of: formulaText) else { return nil }

        let formatted = formatMass(mass)
        let display = "\(formatted) g/mol"
        return CalcResult(
            expression: trimmed,
            sourceBadge: String(localized: "Chemistry"),
            targetBadge: String(localized: "Molar Mass"),
            payload: .value(display: display, copyText: display),
            canChain: true
        )
    }

    private static func extractFormula(from query: String) -> String? {
        var lower = query.lowercased()
        if lower.hasPrefix("the ") {
            lower = String(lower.dropFirst(4)).trimmingCharacters(in: .whitespaces)
        }
        let prefixes = [
            "molar mass of ", "molar mass ",
            "molecular weight of ", "molecular weight ",
            "molecular mass of ", "molecular mass ",
            "atomic mass of ", "atomic mass ",
            "atomic weight of ", "atomic weight ",
            "mw of ", "mw "
        ]
        for prefix in prefixes {
            if lower.hasPrefix(prefix) {
                let formula = query.suffix(lower.count).dropFirst(prefix.count).trimmingCharacters(in: .whitespacesAndNewlines)
                if !formula.isEmpty { return formula }
            }
        }
        return nil
    }

    private static func formatMass(_ mass: Double) -> String {
        let rounded = (mass * 1000).rounded() / 1000
        if rounded.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", rounded)
        }
        var str = String(format: "%.3f", rounded)
        while str.hasSuffix("0") && str.contains(".") {
            str.removeLast()
        }
        if str.hasSuffix(".") { str.removeLast() }
        return str
    }

    /// Evaluates chemical formula string or common compound name.
    static func calculateMolarMass(of rawInput: String) -> Double? {
        let input = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = input.lowercased()
        if let mapped = commonCompounds[lower] {
            return parseFormula(mapped)
        }
        if let weight = elementWeights[input] {
            return weight
        }
        if let elementSymbol = elementNameMap[lower], let weight = elementWeights[elementSymbol] {
            return weight
        }
        return parseFormula(input)
    }

    /// Parses a chemical formula supporting elements, numbers, parentheses, and hydration (e.g. `CuSO4*5H2O`).
    private static func parseFormula(_ formula: String) -> Double? {
        // Handle hydration: CuSO4*5H2O or CuSO4.5H2O or CuSO4·5H2O
        let parts = formula.components(separatedBy: CharacterSet(charactersIn: "*·•"))
        if parts.count > 1 {
            var total = 0.0
            for (idx, part) in parts.enumerated() {
                let trimmed = part.trimmingCharacters(in: .whitespaces)
                if idx == 0 {
                    guard let m = parseSingleFormula(trimmed) else { return nil }
                    total += m
                } else {
                    // Could lead with a multiplier e.g. 5H2O
                    var numStr = ""
                    var rest = trimmed[...]
                    while let first = rest.first, first.isNumber {
                        numStr.append(first)
                        rest = rest.dropFirst()
                    }
                    let multiplier = Double(numStr) ?? 1.0
                    guard let m = parseSingleFormula(String(rest)) else { return nil }
                    total += multiplier * m
                }
            }
            return total
        }
        return parseSingleFormula(formula)
    }

    private static func parseSingleFormula(_ formula: String) -> Double? {
        let scalars = Array(formula.unicodeScalars)
        var index = 0
        return parseSubFormula(scalars, index: &index, depth: 0)
    }

    private static func parseSubFormula(_ scalars: [Unicode.Scalar], index: inout Int, depth: Int) -> Double? {
        var totalMass = 0.0

        while index < scalars.count {
            let ch = scalars[index]

            if ch == "(" || ch == "[" {
                index += 1
                guard let innerMass = parseSubFormula(scalars, index: &index, depth: depth + 1) else {
                    return nil
                }
                var multiplier = 1
                if index < scalars.count && isDigit(scalars[index]) {
                    multiplier = parseNumber(scalars, index: &index)
                }
                totalMass += innerMass * Double(multiplier)
            } else if ch == ")" || ch == "]" {
                guard depth > 0 else { return nil }
                index += 1
                return totalMass
            } else if isUpper(ch) {
                var symbol = String(ch)
                index += 1
                if index < scalars.count && isLower(scalars[index]) {
                    symbol.append(Character(scalars[index]))
                    index += 1
                }
                guard let weight = elementWeights[symbol] else { return nil }
                var count = 1
                if index < scalars.count && isDigit(scalars[index]) {
                    count = parseNumber(scalars, index: &index)
                }
                totalMass += weight * Double(count)
            } else if ch == " " {
                index += 1
            } else {
                return nil
            }
        }

        if depth > 0 { return nil } // Unmatched opening paren
        return totalMass > 0 ? totalMass : nil
    }

    private static func parseNumber(_ scalars: [Unicode.Scalar], index: inout Int) -> Int {
        var num = 0
        while index < scalars.count && isDigit(scalars[index]) {
            num = num * 10 + Int(scalars[index].value - Unicode.Scalar("0").value)
            index += 1
        }
        return max(1, num)
    }

    private static func isDigit(_ s: Unicode.Scalar) -> Bool {
        s >= "0" && s <= "9"
    }

    private static func isUpper(_ s: Unicode.Scalar) -> Bool {
        s >= "A" && s <= "Z"
    }

    private static func isLower(_ s: Unicode.Scalar) -> Bool {
        s >= "a" && s <= "z"
    }

    // MARK: - Tables

    private static let elementNameMap: [String: String] = [
        "hydrogen": "H", "helium": "He", "lithium": "Li", "beryllium": "Be", "boron": "B",
        "carbon": "C", "nitrogen": "N", "oxygen": "O", "fluorine": "F", "neon": "Ne",
        "sodium": "Na", "magnesium": "Mg", "aluminum": "Al", "aluminium": "Al", "silicon": "Si",
        "phosphorus": "P", "sulfur": "S", "chlorine": "Cl", "argon": "Ar", "potassium": "K",
        "calcium": "Ca", "scandium": "Sc", "titanium": "Ti", "vanadium": "V", "chromium": "Cr",
        "manganese": "Mn", "iron": "Fe", "cobalt": "Co", "nickel": "Ni", "copper": "Cu",
        "zinc": "Zn", "gallium": "Ga", "germanium": "Ge", "arsenic": "As", "selenium": "Se",
        "bromine": "Br", "krypton": "Kr", "rubidium": "Rb", "strontium": "Sr", "yttrium": "Y",
        "zirconium": "Zr", "niobium": "Nb", "molybdenum": "Mo", "technetium": "Tc", "ruthenium": "Ru",
        "rhodium": "Rh", "palladium": "Pd", "silver": "Ag", "cadmium": "Cd", "indium": "In",
        "tin": "Sn", "antimony": "Sb", "tellurium": "Te", "iodine": "I", "xenon": "Xe",
        "cesium": "Cs", "caesium": "Cs", "barium": "Ba", "lanthanum": "La", "cerium": "Ce",
        "praseodymium": "Pr", "neodymium": "Nd", "promethium": "Pm", "samarium": "Sm", "europium": "Eu",
        "gadolinium": "Gd", "terbium": "Tb", "dysprosium": "Dy", "holmium": "Ho", "erbium": "Er",
        "thulium": "Tm", "ytterbium": "Yb", "lutetium": "Lu", "hafnium": "Hf", "tantalum": "Ta",
        "tungsten": "W", "rhenium": "Re", "osmium": "Os", "iridium": "Ir", "platinum": "Pt",
        "gold": "Au", "mercury": "Hg", "thallium": "Tl", "lead": "Pb", "bismuth": "Bi",
        "radium": "Ra", "uranium": "U", "plutonium": "Pu"
    ]

    private static let commonCompounds: [String: String] = [
        "water": "H2O", "glucose": "C6H12O6", "sucrose": "C12H22O11", "sugar": "C12H22O11",
        "cane sugar": "C12H22O11", "salt": "NaCl", "table salt": "NaCl", "ethanol": "C2H5OH",
        "alcohol": "C2H5OH", "methanol": "CH3OH", "methane": "CH4", "carbon dioxide": "CO2",
        "carbon monoxide": "CO", "ammonia": "NH3", "sulfuric acid": "H2SO4", "hydrochloric acid": "HCl",
        "nitric acid": "HNO3", "acetic acid": "CH3COOH", "vinegar": "CH3COOH", "acetone": "C3H6O",
        "caffeine": "C8H10N4O2", "aspirin": "C9H8O4", "baking soda": "NaHCO3", "benzene": "C6H6",
        "propane": "C3H8", "butane": "C4H10", "rust": "Fe2O3"
    ]

    private static let elementWeights: [String: Double] = [
        "H": 1.008, "He": 4.0026, "Li": 6.94, "Be": 9.0122, "B": 10.81,
        "C": 12.011, "N": 14.007, "O": 15.999, "F": 18.998, "Ne": 20.180,
        "Na": 22.990, "Mg": 24.305, "Al": 26.982, "Si": 28.085, "P": 30.974,
        "S": 32.06, "Cl": 35.45, "Ar": 39.95, "K": 39.098, "Ca": 40.078,
        "Sc": 44.956, "Ti": 47.867, "V": 50.942, "Cr": 51.996, "Mn": 54.938,
        "Fe": 55.845, "Co": 58.933, "Ni": 58.693, "Cu": 63.546, "Zn": 65.38,
        "Ga": 69.723, "Ge": 72.630, "As": 74.922, "Se": 78.971, "Br": 79.904,
        "Kr": 83.798, "Rb": 85.468, "Sr": 87.62, "Y": 88.906, "Zr": 91.224,
        "Nb": 92.906, "Mo": 95.95, "Tc": 98.0, "Ru": 101.07, "Rh": 102.91,
        "Pd": 106.42, "Ag": 107.87, "Cd": 112.41, "In": 114.82, "Sn": 118.71,
        "Sb": 121.76, "Te": 127.60, "I": 126.90, "Xe": 131.29, "Cs": 132.91,
        "Ba": 137.33, "La": 138.91, "Ce": 140.12, "Pr": 140.91, "Nd": 144.24,
        "Pm": 145.0, "Sm": 150.36, "Eu": 151.96, "Gd": 157.25, "Tb": 158.93,
        "Dy": 162.50, "Ho": 164.93, "Er": 167.26, "Tm": 168.93, "Yb": 173.05,
        "Lu": 174.97, "Hf": 178.49, "Ta": 180.95, "W": 183.84, "Re": 186.21,
        "Os": 190.23, "Ir": 192.22, "Pt": 195.08, "Au": 196.97, "Hg": 200.59,
        "Tl": 204.38, "Pb": 207.2, "Bi": 208.98, "Po": 209.0, "At": 210.0,
        "Rn": 222.0, "Fr": 223.0, "Ra": 226.0, "Ac": 227.0, "Th": 232.04,
        "Pa": 231.04, "U": 238.03, "Np": 237.0, "Pu": 244.0, "Am": 243.0,
        "Cm": 247.0, "Bk": 247.0, "Cf": 251.0, "Es": 252.0, "Fm": 257.0,
        "Md": 258.0, "No": 259.0, "Lr": 266.0, "Rf": 267.0, "Db": 268.0,
        "Sg": 269.0, "Bh": 270.0, "Hs": 270.0, "Mt": 278.0, "Ds": 281.0,
        "Rg": 282.0, "Cn": 285.0, "Nh": 286.0, "Fl": 289.0, "Mc": 290.0,
        "Lv": 293.0, "Ts": 294.0, "Og": 294.0
    ]
}
