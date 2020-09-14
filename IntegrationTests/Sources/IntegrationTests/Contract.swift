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
}
