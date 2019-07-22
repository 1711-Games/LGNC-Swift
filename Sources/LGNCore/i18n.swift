import Foundation
import Logging

public extension LGNCore {
    enum i18n {
        public static var translator: LGNCTranslator = DummyTranslator()

        @inlinable public static func tr(
            _ key: String,
            _ locale: LGNCore.i18n.Locale,
            _ interpolations: [String: Any] = [:]
        ) -> String {
            return self.translator.tr(key, locale, interpolations)
        }
    }
}

public protocol LGNCTranslator {
    var allowedLocales: LGNCore.i18n.AllowedLocales { get }

    func tr(
        _ key: String,
        _ locale: LGNCore.i18n.Locale,
        _ interpolations: [String: Any]
    ) -> String
}

public extension LGNCore.i18n {
    struct DummyTranslator: LGNCTranslator {
        public let allowedLocales: LGNCore.i18n.AllowedLocales = []

        public init() {}

        @inlinable public func tr(
            _ key: String,
            _ locale: Locale,
            _ interpolations: [String: Any]
        ) -> String {
            return interpolate(input: key, interpolations: interpolations)
        }
    }
}

@usableFromInline internal func interpolate(input: String, interpolations: [String: Any]) -> String {
    var result = input

    // Early exit if there are no placeholders
    if !input.contains("{") || interpolations.isEmpty {
        return result
    }

    for (name, value) in interpolations {
        result = result.replacingOccurrences(of: "{\(name)}", with: "\(value)")
    }

    return result
}

public extension LGNCore.i18n {
    struct FactoryTranslator: LGNCTranslator {
        public let allowedLocales: LGNCore.i18n.AllowedLocales

        internal var logger = Logger(label: "LGNCore.FactoryTranslator")
        internal var phrases: [Locale: Phrases]

        public init(
            phrases: [Locale: Phrases],
            allowedLocales: LGNCore.i18n.AllowedLocales
        ) {
            self.phrases = phrases
            self.allowedLocales = allowedLocales
        }

        public func tr(
            _ key: String,
            _ locale: LGNCore.i18n.Locale,
            _ interpolations: [String : Any]
        ) -> String {
            guard let phrase = self.phrases[locale]?[key] else {
                return interpolate(input: key, interpolations: interpolations)
            }

            let translation: String
            if phrase.isPlural {
                var numericInterpolation: Int?
                for (_, value) in interpolations {
                    if let int = value as? Int {
                        numericInterpolation = int
                        break
                    }
                }
                if let numericInterpolation = numericInterpolation {
                    translation = self.choosePlural(key: key, phrase: phrase, locale: locale, num: numericInterpolation)
                } else {
                    translation = phrase.other
                }
            } else {
                translation = phrase.other
            }

            return interpolate(input: translation, interpolations: interpolations)
        }

        internal func choosePlural(key: String, phrase: Phrase, locale: Locale, num: Int) -> String {
            let result: String?

            switch locale {
            case .enUS:
                result = num == 1 ? phrase.one : phrase.other
            case .ruRU, .ukUA:
                let mod10 = num % 10
                let mod100 = num % 100

                if mod10 == 1 && mod100 != 11 {
                    result = phrase.one
                } else if (2...4).contains(mod10) && !(12...14).contains(mod100) {
                    result = phrase.few
                } else if mod10 == 0 || (5...9).contains(mod10) || (12...14).contains(mod100) {
                    result = phrase.many
                } else {
                    result = phrase.other
                }
            default:
                self.logger.notice(
                    "Pluralization for given locale isn't yet imlemented",
                    metadata: [
                        "locale": "\(locale)",
                        "key": "\(key)",
                    ]
                )

                result = phrase.other
            }

            return result ?? phrase.other
        }
    }
}

public extension LGNCore.i18n {
    typealias AllowedLocales = [Locale]
    typealias Phrases = [String: Phrase]

    struct Phrase: Codable, ExpressibleByStringLiteral {
        public let zero: String?
        public let one: String?
        public let two: String?
        public let few: String?
        public let many: String?
        public let other: String

        public let isPlural: Bool

        public init(
            zero: String? = nil,
            one: String? = nil,
            two: String? = nil,
            few: String? = nil,
            many: String? = nil,
            other: String
        ) {
            self.zero = zero
            self.one = one
            self.two = two
            self.few = few
            self.many = many
            self.other = other

            self.isPlural = zero != nil || one != nil || two != nil || few != nil || many != nil
        }

        public init(_ other: String) {
            self.init(other: other)
        }

        public init(stringLiteral: String) {
            self.init(other: stringLiteral)
        }
    }

    enum Locale: String {
        case afZA = "af-ZA"
        case amET = "am-ET"
        case arAE = "ar-AE"
        case arBH = "ar-BH"
        case arDZ = "ar-DZ"
        case arEG = "ar-EG"
        case arIQ = "ar-IQ"
        case arJO = "ar-JO"
        case arKW = "ar-KW"
        case arLB = "ar-LB"
        case arLY = "ar-LY"
        case arMA = "ar-MA"
        case arnCL = "arn-CL"
        case arOM = "ar-OM"
        case arQA = "ar-QA"
        case arSA = "ar-SA"
        case arSY = "ar-SY"
        case arTN = "ar-TN"
        case arYE = "ar-YE"
        case asIN = "as-IN"
        case azCyrlAZ = "az-Cyrl-AZ"
        case azLatnAZ = "az-Latn-AZ"
        case baRU = "ba-RU"
        case beBY = "be-BY"
        case bgBG = "bg-BG"
        case bnBD = "bn-BD"
        case bnIN = "bn-IN"
        case boCN = "bo-CN"
        case brFR = "br-FR"
        case bsCyrlBA = "bs-Cyrl-BA"
        case bsLatnBA = "bs-Latn-BA"
        case caES = "ca-ES"
        case coFR = "co-FR"
        case csCZ = "cs-CZ"
        case cyGB = "cy-GB"
        case daDK = "da-DK"
        case deAT = "de-AT"
        case deCH = "de-CH"
        case deDE = "de-DE"
        case deLI = "de-LI"
        case deLU = "de-LU"
        case dsbDE = "dsb-DE"
        case dvMV = "dv-MV"
        case elGR = "el-GR"
        case en029 = "en-029"
        case enAU = "en-AU"
        case enBZ = "en-BZ"
        case enCA = "en-CA"
        case enGB = "en-GB"
        case enIE = "en-IE"
        case enIN = "en-IN"
        case enJM = "en-JM"
        case enMY = "en-MY"
        case enNZ = "en-NZ"
        case enPH = "en-PH"
        case enSG = "en-SG"
        case enTT = "en-TT"
        case enUS = "en-US"
        case enZA = "en-ZA"
        case enZW = "en-ZW"
        case esAR = "es-AR"
        case esBO = "es-BO"
        case esCL = "es-CL"
        case esCO = "es-CO"
        case esCR = "es-CR"
        case esDO = "es-DO"
        case esEC = "es-EC"
        case esES = "es-ES"
        case esGT = "es-GT"
        case esHN = "es-HN"
        case esMX = "es-MX"
        case esNI = "es-NI"
        case esPA = "es-PA"
        case esPE = "es-PE"
        case esPR = "es-PR"
        case esPY = "es-PY"
        case esSV = "es-SV"
        case esUS = "es-US"
        case esUY = "es-UY"
        case esVE = "es-VE"
        case etEE = "et-EE"
        case euES = "eu-ES"
        case faIR = "fa-IR"
        case fiFI = "fi-FI"
        case filPH = "fil-PH"
        case foFO = "fo-FO"
        case frBE = "fr-BE"
        case frCA = "fr-CA"
        case frCH = "fr-CH"
        case frFR = "fr-FR"
        case frLU = "fr-LU"
        case frMC = "fr-MC"
        case fyNL = "fy-NL"
        case gaIE = "ga-IE"
        case gdGB = "gd-GB"
        case glES = "gl-ES"
        case gswFR = "gsw-FR"
        case guIN = "gu-IN"
        case haLatnNG = "ha-Latn-NG"
        case heIL = "he-IL"
        case hiIN = "hi-IN"
        case hrBA = "hr-BA"
        case hrHR = "hr-HR"
        case hsbDE = "hsb-DE"
        case huHU = "hu-HU"
        case hyAM = "hy-AM"
        case idID = "id-ID"
        case igNG = "ig-NG"
        case iiCN = "ii-CN"
        case isIS = "is-IS"
        case itCH = "it-CH"
        case itIT = "it-IT"
        case iuCansCA = "iu-Cans-CA"
        case iuLatnCA = "iu-Latn-CA"
        case jaJP = "ja-JP"
        case kaGE = "ka-GE"
        case kkKZ = "kk-KZ"
        case klGL = "kl-GL"
        case kmKH = "km-KH"
        case knIN = "kn-IN"
        case kokIN = "kok-IN"
        case koKR = "ko-KR"
        case kyKG = "ky-KG"
        case lbLU = "lb-LU"
        case loLA = "lo-LA"
        case ltLT = "lt-LT"
        case lvLV = "lv-LV"
        case miNZ = "mi-NZ"
        case mkMK = "mk-MK"
        case mlIN = "ml-IN"
        case mnMN = "mn-MN"
        case mnMongCN = "mn-Mong-CN"
        case mohCA = "moh-CA"
        case mrIN = "mr-IN"
        case msBN = "ms-BN"
        case msMY = "ms-MY"
        case mtMT = "mt-MT"
        case nbNO = "nb-NO"
        case neNP = "ne-NP"
        case nlBE = "nl-BE"
        case nlNL = "nl-NL"
        case nnNO = "nn-NO"
        case nsoZA = "nso-ZA"
        case ocFR = "oc-FR"
        case orIN = "or-IN"
        case paIN = "pa-IN"
        case plPL = "pl-PL"
        case prsAF = "prs-AF"
        case psAF = "ps-AF"
        case ptBR = "pt-BR"
        case ptPT = "pt-PT"
        case qutGT = "qut-GT"
        case quzBO = "quz-BO"
        case quzEC = "quz-EC"
        case quzPE = "quz-PE"
        case rmCH = "rm-CH"
        case roRO = "ro-RO"
        case ruRU = "ru-RU"
        case rwRW = "rw-RW"
        case sahRU = "sah-RU"
        case saIN = "sa-IN"
        case seFI = "se-FI"
        case seNO = "se-NO"
        case seSE = "se-SE"
        case siLK = "si-LK"
        case skSK = "sk-SK"
        case slSI = "sl-SI"
        case smaNO = "sma-NO"
        case smaSE = "sma-SE"
        case smjNO = "smj-NO"
        case smjSE = "smj-SE"
        case smnFI = "smn-FI"
        case smsFI = "sms-FI"
        case sqAL = "sq-AL"
        case srCyrlBA = "sr-Cyrl-BA"
        case srCyrlCS = "sr-Cyrl-CS"
        case srCyrlME = "sr-Cyrl-ME"
        case srCyrlRS = "sr-Cyrl-RS"
        case srLatnBA = "sr-Latn-BA"
        case srLatnCS = "sr-Latn-CS"
        case srLatnME = "sr-Latn-ME"
        case srLatnRS = "sr-Latn-RS"
        case svFI = "sv-FI"
        case svSE = "sv-SE"
        case swKE = "sw-KE"
        case syrSY = "syr-SY"
        case taIN = "ta-IN"
        case teIN = "te-IN"
        case tgCyrlTJ = "tg-Cyrl-TJ"
        case thTH = "th-TH"
        case tkTM = "tk-TM"
        case tnZA = "tn-ZA"
        case trTR = "tr-TR"
        case ttRU = "tt-RU"
        case tzmLatnDZ = "tzm-Latn-DZ"
        case ugCN = "ug-CN"
        case ukUA = "uk-UA"
        case urPK = "ur-PK"
        case uzCyrlUZ = "uz-Cyrl-UZ"
        case uzLatnUZ = "uz-Latn-UZ"
        case viVN = "vi-VN"
        case woSN = "wo-SN"
        case xhZA = "xh-ZA"
        case yoNG = "yo-NG"
        case zhCN = "zh-CN"
        case zhHK = "zh-HK"
        case zhMO = "zh-MO"
        case zhSG = "zh-SG"
        case zhTW = "zh-TW"
        case zuZA = "zu-ZA"

        public static let `default`: Locale = .enUS

        public init(maybeLocale: String?, allowedLocales: AllowedLocales, default: Locale = Locale.default) {
            guard
                let rawLocale = maybeLocale,
                let instance = Locale(rawValue: rawLocale),
                allowedLocales.contains(instance)
            else {
                self = `default`
                return
            }
            self = instance
        }

        public var foundationLocale: Foundation.Locale {
            return Foundation.Locale(identifier: self.rawValue.replacingOccurrences(of: "-", with: "_"))
        }
    }
}
