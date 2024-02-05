import Foundation
import SubstrateSdk

extension CallMetadata {
    func isArgumentTypeOf(_ name: String, closure: (String) -> Bool) -> Bool {
        mapArgumentTypeOf(name, closure: { closure($0) }, defaultValue: false)
    }

    func mapOptionalArgumentTypeOf<T>(_ name: String, closure: (String) throws -> T) rethrows -> T? {
        guard let argument = arguments.first(where: { $0.name == name }) else {
            return nil
        }

        return try closure(argument.type)
    }

    func mapArgumentTypeOf<T>(_ name: String, closure: (String) throws -> T, defaultValue: T) rethrows -> T {
        guard let argument = arguments.first(where: { $0.name == name }) else {
            return defaultValue
        }

        return try closure(argument.type)
    }

    func hasArgument(named value: String) -> Bool {
        arguments.contains { $0.name == value }
    }
}
