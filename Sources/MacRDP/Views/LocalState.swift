import SwiftUI

/// Drop-in replacement for `@State`.
/// Recent SDKs implement `@State` as a macro whose plugin ships only with Xcode, so a build with
/// just the Command Line Tools fails. This wrapper keeps the project buildable with `swift build`.
@propertyWrapper
struct Local<Value>: DynamicProperty {
    final class Box: ObservableObject {
        @Published var value: Value
        init(_ value: Value) { self.value = value }
    }

    @StateObject private var box: Box

    init(wrappedValue: Value) {
        _box = StateObject(wrappedValue: Box(wrappedValue))
    }

    var wrappedValue: Value {
        get { box.value }
        nonmutating set { box.value = newValue }
    }

    var projectedValue: Binding<Value> {
        Binding(get: { box.value }, set: { box.value = $0 })
    }
}
