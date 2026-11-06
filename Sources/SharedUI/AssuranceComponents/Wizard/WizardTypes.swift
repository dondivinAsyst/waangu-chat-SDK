import SwiftUI

// MARK: - Shared Form State

/// Every wizard step reads/writes from a single untyped dictionary.
/// This keeps cross-step data accessible without coupling step views.
public typealias WizardFormState = [String: Any]

// MARK: - Validation Result

public enum WizardValidationResult: Equatable {
    case valid
    case invalid(field: String, message: String)

    var isValid: Bool {
        if case .valid = self { return true }
        return false
    }

    public static func == (lhs: WizardValidationResult, rhs: WizardValidationResult) -> Bool {
        switch (lhs, rhs) {
        case (.valid, .valid):
            return true
        case let (.invalid(lf, lm), .invalid(rf, rm)):
            return lf == rf && lm == rm
        default:
            return false
        }
    }
}

// MARK: - Step Configuration Protocol

/// Contract every wizard step must satisfy.
/// The framework operates exclusively through this — no hard-coded fields.
public protocol WizardStepConfiguration: Identifiable {
    var id: String { get }
    var title: String { get }
    var subtitle: String? { get }
    var visibilityCondition: (WizardFormState) -> Bool { get }
    var validate: (WizardFormState) -> [WizardValidationResult] { get }

    func makeBody(
        formState: Binding<WizardFormState>,
        validationErrors: [WizardValidationResult]
    ) -> AnyView

    /// Returns review items for this step. Override in `SimpleWizardStep` or
    /// provide a `reviewItems` closure to `WizardStep` to auto-populate reviews.
    func buildReviewItems(state: WizardFormState) -> [WizardReviewItem]
}

extension WizardStepConfiguration {
    func buildReviewItems(state: WizardFormState) -> [WizardReviewItem] { [] }
}

// MARK: - Generic Step Builder

/// The primary building block: inject any SwiftUI view via a closure.
public struct WizardStep<Content: View>: WizardStepConfiguration {
    public let id: String
    public let title: String
    public let subtitle: String?
    public let visibilityCondition: (WizardFormState) -> Bool
    public let validate: (WizardFormState) -> [WizardValidationResult]
    private let content: (Binding<WizardFormState>, [WizardValidationResult]) -> Content
    private let _reviewItemsBuilder: ((WizardFormState, String) -> [WizardReviewItem])?

    public init(
        id: String,
        title: String,
        subtitle: String? = nil,
        visibilityCondition: @escaping (WizardFormState) -> Bool = { _ in true },
        validate: @escaping (WizardFormState) -> [WizardValidationResult] = { _ in [.valid] },
        reviewItems: ((WizardFormState, String) -> [WizardReviewItem])? = nil,
        @ViewBuilder content: @escaping (Binding<WizardFormState>, [WizardValidationResult]) -> Content
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.visibilityCondition = visibilityCondition
        self.validate = validate
        self._reviewItemsBuilder = reviewItems
        self.content = content
    }

    public func makeBody(
        formState: Binding<WizardFormState>,
        validationErrors: [WizardValidationResult]
    ) -> AnyView {
        AnyView(content(formState, validationErrors))
    }

    public func buildReviewItems(state: WizardFormState) -> [WizardReviewItem] {
        _reviewItemsBuilder?(state, id) ?? []
    }
}

// MARK: - Type-Erased Wrapper

/// Allows heterogeneous step types to live in a single array.
public struct AnyWizardStep: WizardStepConfiguration {
    private let wrapped: any WizardStepConfiguration

    public var id: String { wrapped.id }
    public var title: String { wrapped.title }
    public var subtitle: String? { wrapped.subtitle }
    public var visibilityCondition: (WizardFormState) -> Bool { wrapped.visibilityCondition }
    public var validate: (WizardFormState) -> [WizardValidationResult] { wrapped.validate }

    public init(_ step: any WizardStepConfiguration) {
        self.wrapped = step
    }

    public func makeBody(
        formState: Binding<WizardFormState>,
        validationErrors: [WizardValidationResult]
    ) -> AnyView {
        wrapped.makeBody(formState: formState, validationErrors: validationErrors)
    }

    public func buildReviewItems(state: WizardFormState) -> [WizardReviewItem] {
        wrapped.buildReviewItems(state: state)
    }
}

// MARK: - Review Item

public struct WizardReviewItem: Identifiable {
    public let id = UUID()
    public let label: String
    public let value: String
    public let stepID: String
    public var sectionTitle: String = ""
    public init(label: String, value: String, stepID: String, sectionTitle: String? = nil) {
        self.label = label
        self.value = value
        self.stepID = stepID
        self.sectionTitle = sectionTitle ?? ""
    }
}

// MARK: - Picker Option (for step-view helpers)

struct PickerOption: Identifiable {
    let id: String
    let label: String

    init(_ id: String, _ label: String) {
        self.id = id
        self.label = label
    }
}

// MARK: - Binding Helpers

public extension Binding where Value == WizardFormState {
    func string(for key: String) -> Binding<String> {
        Binding<String>(
            get: { self.wrappedValue[key] as? String ?? "" },
            set: { self.wrappedValue[key] = $0 }
        )
    }
    func integer(for key: String) -> Binding<Int> {
        Binding<Int>(
            get: { self.wrappedValue[key] as? Int ?? 0 },
            set: { self.wrappedValue[key] = $0 }
        )
    }

    func stringArray(for key: String) -> Binding<[String]> {
        Binding<[String]>(
            get: { self.wrappedValue[key] as? [String] ?? [] },
            set: { self.wrappedValue[key] = $0 }
        )
    }

    func bool(for key: String, default defaultValue: Bool = false) -> Binding<Bool> {
        Binding<Bool>(
            get: { self.wrappedValue[key] as? Bool ?? defaultValue },
            set: { self.wrappedValue[key] = $0 }
        )
    }

    func date(for key: String, default defaultValue: Date = Date()) -> Binding<Date> {
        Binding<Date>(
            get: { self.wrappedValue[key] as? Date ?? defaultValue },
            set: { self.wrappedValue[key] = $0 }
        )
    }
}

// MARK: - Dictionary Read Helpers

public extension Dictionary where Key == String, Value == Any {
    func string(_ key: String) -> String {
        self[key] as? String ?? ""
    }

    func stringArray(_ key: String) -> [String] {
        self[key] as? [String] ?? []
    }

    func bool(_ key: String) -> Bool {
        self[key] as? Bool ?? false
    }

    func date(_ key: String) -> Date? {
        self[key] as? Date
    }
}

// MARK: - Validation Array Helpers

public extension Array where Element == WizardValidationResult {
    func errorMessage(for fieldKey: String) -> String? {
        compactMap {
            if case .invalid(let field, let message) = $0, field == fieldKey {
                return message
            }
            return nil
        }.first
    }
}
