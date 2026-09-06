# Working agreement — echno-ios

Conventions for anyone, human or agent, working in this repository.

---

## Start of every session

Run the suite before writing anything. A green baseline is what makes a later
failure mean something.

```bash
swift test          # EchnoKit logic — fast, no simulator
xcodebuild -project echno-ios.xcodeproj -scheme echno-ios \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build
```

If the baseline is red, fix that first and say so. Do not build on top of a
failing suite, and do not describe a suite as passing without having run it.

No flags, no trust prompts, no per-machine setup: the OpenAPI client is
generated ahead of time by `Scripts/sync-openapi.sh` and committed, so nothing
runs a build-tool plugin. See ``EchnoAPI`` below.

---

## Test-driven development

**Write the failing test first.** For every behaviour change:

1. Write a test that expresses the requirement and watch it fail for the right
   reason. A test that passes before the change tests nothing.
2. Write the smallest change that makes it pass.
3. Refactor with the test as the safety net.

Rules that follow from that:

- **Logic lives where it can be tested.** Domain rules, validation, mapping and
  parsing belong in `Sources/EchnoKit`, reachable by `swift test` without a
  simulator. Do not put testable logic in a SwiftUI view or in the app target —
  if a rule matters enough to be right, it matters enough to be reachable.
- **Test behaviour, not implementation.** Assert on the outcome a user or caller
  would observe, so a refactor does not rewrite the suite.
- **Derive expected values; do not hardcode magic numbers.** A hand-computed
  constant is the thing most likely to be wrong, and a wrong constant reads as a
  bug in the code under test. Build expectations from components.
- **One reason to fail per test**, with a name that states the requirement.
- **A bug fix starts with the test that reproduces it.**
- Use swift-testing (`@Test`, `@Suite`, `#expect`, `#require`), not XCTest.

### What must be tested

| Must | Need not |
|---|---|
| Validation and business rules | SwiftUI layout and styling |
| DTO ↔ domain mapping, especially unwrapping | Generated `EchnoAPI` code |
| Date, enum and number parsing | Pure pass-through wrappers |
| Auth: token expiry, refresh, exemptions | Colour and spacing constants |
| Cache invalidation and merge rules | |
| Anything that has broken once | |

---

## Architecture

Three layers, one direction of dependency. See `local-docs/ios-action-plan.md` §1.

```
app target (echno-ios/)   SwiftUI screens, design system
        ↓
EchnoKit                 domain types, mapping, services, stores, auth
        ↓
EchnoAPI                  generated from the backend OpenAPI document
```

- **`EchnoAPI` is never hand-edited.** To change it, add a tag to
  `openapi-generator-config.yaml` and/or re-run `Scripts/sync-openapi.sh`, then
  commit `Sources/EchnoAPI/`. `Scripts/sync-openapi.sh --check` fails if the
  committed client is stale — run it in CI.
- **Generation happens in the script, not as a build-tool plugin.** Xcode gates
  build plugins behind a per-machine trust prompt, and until it is granted the
  whole scheme fails to build — which takes SwiftUI previews down with it, not
  just `xcodebuild`. Generating ahead of time keeps previews and CI working
  anywhere, and makes a contract change arrive as a reviewable diff.
- **Generated types never reach the app target.** `EchnoKit` maps them into
  domain types first. Generated DTOs are all-`var` and largely all-optional
  because 185 schemas omit `required`; unwrapping those invariants once, at the
  mapping boundary, with an error that names the field, is the entire reason
  the middle layer exists.
- **Views own feedback; stores own data.** No alerts, toasts or haptics inside a
  store.
- **Mutation responses have three shapes** and the safe cache action differs per
  shape — full `Dto` replaces, `SimpleDto` merges via `NestedMergeable`, an
  acknowledgement triggers a refetch. Name the DTO in a comment above the
  handler. This has caused user-visible data loss on web twice.

---

## Naming

| Kind | Convention | Example |
|---|---|---|
| Types | `UpperCamelCase`, no prefixes | `AuthenticationMiddleware` |
| Protocols | capability (`-ing`, `-able`) or role noun | `TokenStoring`, `APICredentialProvider` |
| Methods | verb phrase; no `get` prefix | `accessToken()`, not `getAccessToken()` |
| Booleans | read as an assertion | `isExpired`, `hasPendingUpload` |
| Domain types | the business noun, unqualified | `Attendance`, not `AttendanceDto` |
| Generated DTOs | keep the generator's name | `Components.Schemas.AttendanceResponseDto` |
| Files | named for the primary type | `AuthenticationMiddleware.swift` |
| Tests | `@Suite` names the unit; `@Test` states the requirement as a sentence | `"A failed refresh surfaces as an auth error"` |

Domain models are `struct`, `let`-only, `Sendable`, `Hashable`, and
`Identifiable` where they have an id. Mutation produces a new value.
Services are `actor`. Stores are `@Observable final class`.

---

## Copy and capitalization

Apple's HIG asks for title-style capitalization on view titles, labels and
buttons, and sentence case for everything that is prose. Both appear on the same
screen, so the split is by role, not by taste:

| Title Case | Sentence case |
|---|---|
| View and navigation titles — "Create Account" | Body and subtitles — "Fill in your details to get started." |
| Section headers — "Security" | Helper and caption text — "At least 8 characters, with a number." |
| Field labels — "Date of Birth", "Confirm Password" | Placeholders — "Re-enter password" |
| Buttons and links — "Sign In", "Create an Account" | Validation messages — "Username is required" |
| Menu and picker options — "Select a Role" | Accessibility labels and hints |
| Status labels — "Getting There" | Legal and marketing prose |

Title case lowercases articles (`a`, `an`, `the`), coordinating conjunctions and
prepositions of four letters or fewer, unless first or last: "Create an Account",
"Date of Birth", "New to Echno?".

Validation messages are sentences and stay that way — they are read as
statements, not labels, and they are shared with echno-web, whose wording they
must match exactly.

---

## Security

- **Never log a token, refresh token, JWT payload, password or request body.**
  Use `Log.redacted(_:)` when a log line needs to identify *which* credential.
- **Tokens live in the Keychain**, never in `UserDefaults`, a plist, or a file.
  `kSecAttrAccessibleAfterFirstUnlock` — the app refreshes in the background,
  so `WhenUnlocked` would break silent refresh.
- **No secrets in source or in the repository.** Client IDs and base URLs come
  from build configuration. The iOS Keycloak client is public and uses PKCE, so
  it holds no secret by design — keep it that way.
- **Refresh is single-flight.** Keycloak rotates refresh tokens; a second
  concurrent refresh presents a spent token and ends the session.
- **Authorization is the server's job.** Client-side role checks shape the UI;
  they are never the control. Assume every request is authorised server-side.
- **Endpoint exemptions are keyed by `operationId`, not path**, so a backend
  path change cannot silently start sending a token to an anonymous endpoint.
- **`X-Organization-Id` is a tenant boundary.** Never infer it from user input.
- Treat anything from the network as untrusted: decode into typed models and
  fail loudly rather than defaulting a missing invariant.

---

## Documentation

Every `public` declaration carries a doc comment. Beyond that:

- **Say why, not what.** The signature already says what. A comment earns its
  place by recording the constraint, the trade-off, or the bug that shaped it.
- **Record non-obvious backend behaviour at the call site**, with the endpoint
  and DTO named — for example that the check-in multipart part is `photo` on
  `/web` but `photoUrl` on mobile, optional on both, so the wrong name returns
  201 having silently dropped the photo.
- Use `///` with `- Parameter`, `- Returns`, `- Throws` where they add something.
- Cross-reference with ``DoubleBacktick`` symbol links.
- A `TODO` names the phase or ticket that resolves it.
- Keep `local-docs/ios-action-plan.md` truthful. A plan that claims work is done
  when it is not is worse than no plan.

---

## Build configuration

Endpoints live in `Config/Info.plist`, whose values resolve from build settings
(`ECHNO_KEYCLOAK_ISSUER`, `ECHNO_KEYCLOAK_CLIENT_ID`, `ECHNO_OAUTH_REDIRECT_URI`,
`ECHNO_API_BASE_URL`). Empty values fall back to the production defaults in
`EchnoConfiguration`. None is a secret — the iOS Keycloak client is public and
uses PKCE.

Two traps, both hit once already:

- **`INFOPLIST_KEY_*` build settings inject Apple's known keys only.** Custom
  keys are dropped without a warning, which is why a real (partial) plist exists
  alongside `GENERATE_INFOPLIST_FILE = YES`.
- **`Config/` sits outside `echno-ios/`** because that folder is a file-system
  synchronized group: anything inside it joins Copy Bundle Resources
  automatically, and a target's own Info.plist being copied as a resource is a
  "Multiple commands produce" failure.

---

## Commits

- One logical change per commit; do not bundle refactors with features.
- Subject in the imperative, under ~70 characters.
- Body explains **why**, and names anything deliberately not done.
- Never claim a test passed without running it.

---

## Reference

- `local-docs/ios-action-plan.md` — architecture and phases
- `local-docs/backend-mobile-api-gaps.md` — backend contract gaps and open asks
- `local-docs/keycloak-setup.md` — registering the `echno-ios-client` Keycloak client
- `Scripts/sync-openapi.sh` — refresh the vendored OpenAPI document
