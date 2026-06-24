# SwiftUI State Rules

**Status:** Canonical
**Scope:** Owned SwiftUI code in `Apps/` and UI-supporting packages under
`Packages/`.

## Purpose

Allnighter uses SwiftUI's Observation model for app-owned UI state. Do not write
new Combine-era observation code and do not preserve it when touching owned UI
state. The default answer is `@Observable`, plain Swift properties, and the
small set of SwiftUI wrappers that compose with Observation.

This is not about chasing the newest Swift point release. It is about avoiding
old state architecture that makes views noisy, indirect, and easy to drift from
the core contracts.

## Required Pattern

- Model objects that drive SwiftUI updates use `@Observable`.
- Observable UI models read or mutated by views are `@MainActor` unless there is
  a documented non-main-actor owner.
- A view-owned observable reference uses `@State private var model = Model()`.
- A model owned by a parent, coordinator, or app root is passed as a plain
  property: `let model: Model` or `var model: Model`.
- A child view that needs bindings into an observable model uses `@Bindable`.
- App-wide injected state uses typed Observation environment:
  `@Environment(Model.self) private var model`.
- Simple local value state still uses `@State`.
- Views send intents. Durable run truth, worker status, team membership, and
  network/session state live in the owning core/app model, not in view-local
  shadow state.

## Forbidden In Owned UI Code

These are blocked by `scripts/check_swiftui_state.sh`:

- `ObservableObject`
- `@ObservedObject`
- `@StateObject`
- `@EnvironmentObject`
- `@Published`
- `objectWillChange`
- `import Combine` for SwiftUI view state
- Swift 5 language-mode settings in owned app/package targets

If a third-party Apple or SDK API still requires one of these patterns, isolate
it behind a tiny adapter with a comment that names the external requirement and
keep the old wrapper out of app-facing views. Do not add a broad exception just
to keep old local code alive.

## Migration Recipe

```swift
// Old
final class Store: ObservableObject {
    @Published var title = ""
}

struct Surface: View {
    @StateObject private var store = Store()
}

// New
@MainActor
@Observable
final class Store {
    var title = ""
}

struct Surface: View {
    @State private var store = Store()
}
```

For injected state:

```swift
struct Row: View {
    let store: Store
}
```

For editable child bindings:

```swift
struct Editor: View {
    @Bindable var store: Store

    var body: some View {
        TextField("Title", text: $store.title)
    }
}
```

## Proof

Run the state-pattern gate before closing SwiftUI work:

```text
bash scripts/check_swiftui_state.sh
```

The full green wall also runs it through `bash scripts/check.sh`.
