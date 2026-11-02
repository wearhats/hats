import Foundation

public struct HatsError: Error, Equatable, CustomStringConvertible, Sendable {
    public enum Kind: Sendable, Equatable {
        case usage
        case notFound
        case conflict
        case environment
        case io
    }

    public let kind: Kind
    public let message: String
    public let hint: String?

    public init(_ kind: Kind, _ message: String, hint: String? = nil) {
        self.kind = kind
        self.message = message
        self.hint = hint
    }

    public var description: String { message }
}

extension HatsError: LocalizedError {
    public var errorDescription: String? { message }
}
