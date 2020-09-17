import LGNC
import LGNCore

func setupContract() {
    C.guarantee { (request: C.Request, _: LGNCore.Context) -> C.Response in
        C.Response(
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
                }
            ]).compactMap { $0 }
        )
    }

    C.Request.validateStringFieldWithValidations { input, eventLoop in
        let result: C.Request.CallbackValidatorStringFieldWithValidationsAllowedValues?
        switch input {
        case "first error":         result = .FirstCallbackError
        case "second error":        result = .SecondCallbackError
        case "short third error":   result = .E1711
        default: result = nil
        }
        return eventLoop.makeSucceededFuture(result)
    }

    C.Request.validateDateField { input, eventLoop in
        let result: (String, Int)?
        switch input {
        case "1989-09-03 16:37:00.1711+03:00": result = ("It's my birthday :D", 200)
        case "2020-12-31 23:59:59.1711+03:00": result = ("It's New Year :D", 201)
        default: result = nil
        }
        return eventLoop.makeSucceededFuture(result)
    }
}
