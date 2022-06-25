# LGNC-Swift

![LGNC-Swift Logo](./logo.png)

LGNC stands for LGN Contracts. It's a simple yet powerful tool for building services.
Please refer to [main repository](https://github.com/1711-Games/LGNC) for details on LGNC Schema format.
In this repository we'll focus on Swift API.

## Usage

First things first, you want to generate boilerplate code from your schema. This is done using
[LGNBuilder](https://github.com/1711-Games/LGNBuilder), a codegen tool. For detailed documentation
please refer to LGNBuilder repository.

Say, you've cloned the LGNBuilder to `~/work/LGNBuilder`, have your schema in `~/work/myproject/schema`,
and your Swift service lies under `~/work/myproject/swiftservice`. In that case codegen command would look like this:
```bash
~/work/LGNBuilder/Scripts/generate \
    --lang Swift \
    --input ~/work/myproject/schema \
    --output ~/work/myproject/swiftservice/Sources/Service/Generated
```

It is recommended not to mix generated code with actual service code, therefore I've put generated code
into `Generated` directory. Alternatively, you could create a library target for LGNC boilerplate,
but it's not necessary.

> **NB**: generation command should work identically both on macOS and Linux. However, since you work with Swift,
> it's more convenient to do codegen on macOS. It's not prohibited to commit generated code to your repository,
> as long as you don't edit it. Still, integrating LGNC (and LGNBuilder) with your CI process is totally possible.

After you've generated the code, you are left with following file structure like this (given that you have two
services):

```
Sources/Service/Generated/Core.swift
Sources/Service/Generated/First.swift
Sources/Service/Generated/Second.swift
```

`Core.swift` file contains base stuff and shared entities which are used by both services,
defined in `First.swift` and `Second.swift` files respectively.

## Structure of generated code

In Swift your code is organized in following way:

```swift
enum Services {
  enum Shared {
    class Entity1: ContractEntity { ... }
  }

  enum First: Service {
    // arbitrary data
    static let info: [String: String]

    // default ports for service transports
    static let transports: [LGNCore.Transport: Int]

    enum Contracts {
      enum DoSomething: Contract {
        // contract request, in this case — concrete class
        class Request: ContractEntity {
          ...

          enum CallbackValidatorNameAllowedValues: String, CallbackWithAllowedValuesRepresentable {
            case SomeValidationError = "Something went wrong"
          }

          ...

          let name: String
          let email: String

          ...

          // sets a custom validator for `Request.name` field, which must only return
          // an `EventLoopFuture<CallbackValidatorNameAllowedValues?>` (a future to an enum case or `nil`)
          static func validateName(
              _ callback: @escaping Validation.CallbackWithAllowedValues<CallbackValidatorNameAllowedValues>.Callback
          )

          // sets a custom validator for `Request.email` field, which may return
          // an `EventLoopFuture<[(code: Int, message: String)]?>`
          static func validateEmail(_ callback: @escaping Validation.Callback<String>.Callback)
        }

        // contract response, in this case — a shared entity
        typealias Response = Services.Shared.Entity1

        // contract URI, defaults to contract name, hence `Contract1`
        static let URI: String

        // allowed transports for contract
        static let transports: [LGNCore.Transport]

        // allowed content types for contract
        static let contentTypes: [LGNCore.ContentType]

        // accepts a complete guarantee closure, which returns an `EventLoopFuture` with a tuple of response and meta
        static func guarantee(
          closure: (Request, LGNCore.Context) -> EventLoopFuture<(response: Response, meta: Meta)>
        )

        // accepts a shortened guarantee closure, which returns an `EventLoopFuture` with just a response
        static func guarantee(
          closure: (Request, LGNCore.Context) -> EventLoopFuture<Response>
        )

        // accepts a shortened non-NIO guarantee closure, which returns a tuple of a response and meta
        static func guarantee(
          closure: (Request, LGNCore.Context) throws -> (response: Response, meta: Meta)
        )

        // accepts the shortest guarantee closure, which only returns a response, see notes below
        static func guarantee(
          closure: (Request, LGNCore.Context) throws -> Response
        )
      }

      // following static methods are just aliases of `DoSomething` contract respective guarantee methods
      static func guaranteeDoSomethingContract(closure: @escaping Self.FutureClosureWithMeta)
      static func guaranteeDoSomethingContract(closure: @escaping Self.FutureClosure)
      static func guaranteeDoSomethingContract(closure: @escaping Self.NonFutureClosure)
      static func guaranteeDoSomethingContract(closure: @escaping Self.NonFutureClosureWithMeta)

      // following methods are just an aliases of a respective validation methods
      static func validateContractDoSomethingFieldName(
        callback: @escaping Validation.CallbackWithAllowedValues
          <DoSomething.Request.CallbackValidatorNameAllowedValues>.Callback
      )
      static func validateContractDoSomethingEmail(_ callback: @escaping Validation.Callback<String>.Callback)

      // executes `DoSomething` contract on remote node
      public static func executeDoSomethingContract(
        at address: LGNCore.Address,
        with request: DoSomething.Request,
        using client: LGNCClient
      ) -> EventLoopFuture<DoSomething.Response>
    }
  }
  
  enum Second: Service { ... }
}
```
