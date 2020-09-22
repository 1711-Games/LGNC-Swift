import LGNC
import LGNCore

func setupContract() {
    C1.guarantee { (request: C1.Request, _: LGNCore.Context) -> C1.Response in
        C1.Response(
            ok: [String?]([
                "stringField               : \(request.stringField)",
                "intField                  : \(request.intField)",
                "stringFieldWithValidations: \(request.stringFieldWithValidations)",
                "enumField                 : \(request.enumField)",
                "uuidField                 : \(request.uuidField)",
                "dateField                 : \(request.dateField)",
                "password1                 : \(request.password1)",
                "password2                 : \(request.password2)",
                "boolField                 : \(request.boolField)",
                "customField               : \(request.customField)",
                "listField                 : \(request.listField.descr)",
                "listCustomField           : \(request.listCustomField.map(\.description).descr)",
                "mapField                  : \(request.mapField.sorted(by: { $0.key < $1.key }).map { "\($0):\($1)" }.descr)", // dr_hax.exe
                "mapCustomField            : \(request.mapCustomField.descr)",
                request.optionalEnumField.map {
                "optionalEnumField         : \($0)"
                },
                request.optionalDateField.map {
                "optionalDateField         : \($0)"
                }
            ]).compactMap { $0 }
        )
    }

    C1.Request.validateStringFieldWithValidations { input, eventLoop in
        let result: C1.Request.CallbackValidatorStringFieldWithValidationsAllowedValues?

        switch input {
        case "first error":         result = .FirstCallbackError
        case "second error":        result = .SecondCallbackError
        case "short third error":   result = .E1711
        default: result = nil
        }

        return eventLoop.makeSucceededFuture(result)
    }

    C1.Request.validateDateField { input, eventLoop in
        let result: (String, Int)?

        switch input {
        case "1989-09-03 16:37:00.1711+03:00": result = ("It's my birthday :D", 200)
        case "2020-12-31 23:59:59.1711+03:00": result = ("It's New Year :D", 201)
        default: result = nil
        }

        return eventLoop.makeSucceededFuture(result)
    }

    C2.guarantee { (request, context) throws -> C2.Response in
        C2.Response(
            pronto: [
                "stringField   : \(request.stringField)",
                "cookie        : \(request.cookie.value)",
                request.optionalCookie.map {
                "optionalCookie: \($0.value)"
                }
            ].compactMap {$0},
            responseCookie: LGNC.Entity.Cookie(
                name: "got key \(request.cookie.name)",
                value: "got value \(request.cookie.value)"
            )
        )
    }
}
