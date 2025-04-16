import Foundation
import RawStructuredFieldValues

protocol ComponentProvider {
    // Derived, for requests
    func getMethod() -> String
    func getAuthority() -> String
    func getScheme() -> String
    func getTargetUri() -> String
    func getRequestTarget() -> String
    func getPath() -> String
    func getQuery() -> String
    func getQueryParam(name: String) -> String?
    func hasBody() -> Bool

    // Derived, for responses
    func getStatus() -> String

    // Fields
    func hasField(name: String) -> Bool
    func getField(name: String) -> String?

    // Static method declaration (no body)
    static func combineFieldValues(fields: [String]?) -> String?
    func getComponentValue(componentIdentifier: String) -> String?
}
