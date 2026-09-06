# echno-ios — Action Plan (v2)

**Repo:** `/Users/ezio/dev/echno/echno-ios` (branch `development`, no remote yet)
**Target:** universal iPhone + iPad, bundle `com.tornotron.echno-ios`, team `8F8K7KCY39`
**Settled:** iOS 18.0 · Swift 6 strict concurrency · `TARGETED_DEVICE_FAMILY = "1,2"`
**Revised:** 2026-09-06 — supersedes v1

> **What changed from v1.** v1 made `echno-core` (TypeScript) the source of truth and
> hand-translated each module into Swift. That is dropped. The contract now comes from the
> backend's **OpenAPI document**, and Swift for the wire layer is **generated**. echno-core is
> out of this project's context entirely. `echno-web` stays in scope for **one** purpose:
> the UI/UX language this app should feel consistent with.

---

## 0. Why the change

Hand-porting 43k lines of TypeScript was the schedule risk in v1, and it bought nothing at
runtime — the output was always going to be plain Swift. Generating it from the contract
removes the transcription step and the drift it creates.

Validated before committing to it, not assumed:

| Check | Result |
|---|---|
| Does a usable spec exist? | **Yes.** `echno-backend/docs/openapi.json` — committed, 3.0 MB, OpenAPI **3.1.0** |
| Is it trustworthy? | **Yes.** `OpenApiSnapshotTest` fails the backend build if it drifts from what the code serves. `OpenApiNullabilityTest`, `OpenApiValidationConstraintsTest` and `OpenApiPageSizeDefaultTest` hold its quality |
| Coverage | 557 paths, **737 operations**, 315 schemas — matches the 738 endpoints counted from the controllers |
| Quality | every operation has an `operationId`; `bearerAuth` declared; `int64`/`int32`/`date-time`/`date`/`uuid`/`email` formats; descriptions and examples throughout |
| Does `swift-openapi-generator` handle it? | **Yes — after one fix.** Generated + compiled the Attendance module: 9,161 lines of Swift in ~10 s |

The generated types come out as `Codable, Hashable, Sendable` with the backend's own field
docs attached — the same shape the v1 hand-port guide prescribed, without the typing.

---

## 1. Architecture

Three layers. Only the middle one is written by hand.

```
┌──────────────────────────────────────────────────────────┐
│  App target — SwiftUI, iPhone + iPad                     │
│  screens, navigation, design system                      │
└───────────────────────────┬──────────────────────────────┘
                            │ domain types
┌───────────────────────────┴──────────────────────────────┐
│  EchnoCore — HAND-WRITTEN                                │
│  · domain structs: `let`, non-optional where invariant   │
│  · mapping from generated DTOs (unwrap once, here)       │
│  · service actors, @Observable stores                    │
│  · auth, endpoint routing, logging                       │
└───────────────────────────┬──────────────────────────────┘
                            │ generated client + DTOs
┌───────────────────────────┴──────────────────────────────┐
│  EchnoAPI — GENERATED, never hand-edited                 │
│  swift-openapi-generator ← docs/openapi.json             │
└──────────────────────────────────────────────────────────┘
```

### Why there is still a hand-written layer

Generating straight into the UI would be a mistake. From the actual generated output:

```swift
public struct AttendanceResponseDto: Codable, Hashable, Sendable {
    public var id: Swift.Int64?                  // never null in practice
    public var employeeName: Swift.String?       // never null in practice
    public var attendanceDate: Swift.String?     // format: date → String, not Date
    public var approvalStatus: Components.Schemas.AttendanceResponseDto.approvalStatusPayload?
}
```

Four problems, all fixed once per module in the mapping layer rather than at every call site:

1. **Everything is optional.** 205 of 315 object schemas — **185 DTOs** — carry no `required`
   list, so OpenAPI says every property may be absent. Writing UI against `attendance.id?` is
   miserable and hides real errors.
2. **`format: date` generates `String`.** Only `date-time` maps to `Foundation.Date`.
3. **Names are verbose.** `Components.Schemas.AttendanceResponseDto.approvalStatusPayload` is
   not what a view should reference.
4. **`var`, not `let`.** Domain models should be immutable.

The mapping layer is ~1 small file per module and it is where the value is: it unwraps the
invariants **once**, with a real error when the backend breaks one, instead of scattering `?`
and `!` through the app. It is also the seam that absorbs contract churn without touching UI.

### What this kills

- No transcription of 43k lines of TypeScript.
- No echno-core version tracking, no port log, no "which commit was this ported from".
- Contract drift becomes a **compile error**: regenerate, and any mapping that no longer
  matches fails to build. That is the CI contract check from v1 §9, for free.

---

## 2. Getting the spec into this repo

`docs/openapi.json` is committed in echno-backend and is **not** reachable over the network —
`springdoc.swagger-ui.public-access` defaults to `false` and the edge vhost 404s the docs paths
(deliberate; the document is the whole endpoint surface). So we vendor the file rather than
fetch it.

`Scripts/sync-openapi.sh` will:

1. Copy `echno-backend/docs/openapi.json` → `Sources/EchnoAPI/openapi.json`.
2. **Normalise it** — see the blocker below.
3. Record the source git sha in `Sources/EchnoAPI/openapi.source` so a regeneration is traceable.

### 🔴 Blocker: duplicate tags make the document ungeneratable

`swift-openapi-generator` refuses the document outright:

```
Error: Failed to satisfy: The names of Tags in the Document are unique at root of document
```

Six controller pairs declare the **same** `@Tag(name = …)` on both the mobile and the web
controller, where the other 26 pairs correctly suffix the web one with `(Web)`:

| Tag | Controllers |
|---|---|
| `Employees` | `EmployeeController` + `EmployeeControllerWeb` |
| `Issues` | `IssueController` + `IssueControllerWeb` |
| `Issue Comments` | `IssueCommentController` + `IssueCommentControllerWeb` |
| `Projects` | `ProjectController` + `ProjectControllerWeb` |
| `Tasks` | `TaskController` + `TaskControllerWeb` |
| `Users` | `UserController` + `UserControllerWeb` |

Six one-line changes on the backend. Until they land, `sync-openapi.sh` dedupes the root `tags`
array locally — but that only unblocks generation, it does **not** fix filtering: with a shared
tag, `filter: tags: [Employees]` pulls both the mobile and the web operations into one module.

> Two encoding notes for whoever writes the sync script: the generator parses JSON through a
> YAML parser, so re-serialising with `\uXXXX` escapes breaks it — preserve literal UTF-8. And
> normalise only the root `tags` array; leave per-operation tags alone.

---

## 3. Revised phases

> **Status note, 2026-09-06.** Phase 0 was built, reverted at the user's request, then rebuilt.
> Phase 0.5 followed. Both are done; the auth UI was built out of order in between.

### Phase 0 — Foundation ✅ done (`e500fa7`, reverted, rebuilt)

- `Package.swift` with the `EchnoCore` and `EchnoAPI` targets; app links them as a local package
- `APIError`, `APIResponse`, `CacheMerge`, `Endpoints`, `JSONCoding`, `Log`, `TokenStore`,
  `KeycloakAuth`, `Credentials`, `Multipart`
- Project settings: **iOS 18.0**, **Swift 6 + `SWIFT_STRICT_CONCURRENCY = complete`**,
  `TARGETED_DEVICE_FAMILY = "1,2"`, iOS-only `SUPPORTED_PLATFORMS`, shared scheme, `.gitignore`
- Builds clean on iPhone and iPad simulators at iOS 18.5

`APIClient`'s verb methods were **not** rebuilt — the generated client replaces them, as the
architecture note said. What survived is split into `Credentials.swift`
(`APICredentialProvider`) and `Multipart.swift` (`MultipartPart`), both still needed.

### Phase 0.9 — Auth UI ✅ done (`88a8c3a`)

Built before the foundation, out of plan order. The UI half of Phase 1 plus the first slice of
the Phase 3 design system.

- `DesignSystem/{Theme,BrandPanel,FormControls}.swift` — echno-web's tokens and brand artwork (§4)
- `Features/Auth/{SignInView,RegisterView,RegistrationForm}.swift`

Both screens compile clean under Swift 6 strict concurrency. `signIn()` needs Phase 1;
`register()` can now be wired to the generated `registerUser` operation.

### Phase 0.5 — Generation pipeline ✅ done

- [x] `Scripts/sync-openapi.sh` — vendors `echno-backend/docs/openapi.json`, normalises it,
      stamps the source commit into `Sources/EchnoAPI/openapi.source`
- [x] `EchnoAPI` target: generator plugin + runtime + URLSession transport
- [x] `openapi-generator-config.yaml` with a `filter`, currently just the `Auth` tag —
      1,437 lines generated instead of the ~100k the whole document would produce
- [x] `AuthenticationMiddleware` — bearer token and `X-Organization-Id`, with an
      `unauthenticatedOperations` exemption keyed by `operationId` so registration is not
      sent a token it cannot have
- [x] `EchnoClient` factory and `APIError.from(_:)` mapping transport errors onto `APIError`
- [x] Proven: 23 tests, including one that drives the generated `registerUser` through a
      recording transport and asserts it reaches `POST …/auth/register` carrying no
      `Authorization` header
- [ ] **Blocked on backend ask #16** — 6 duplicate root `@Tag` names. `sync-openapi.sh` dedupes
      them locally so generation works, but operations still share a tag, so filtering on
      `Employees`, `Issues`, `Issue Comments`, `Projects`, `Tasks` or `Users` pulls in both the
      mobile and the web controller. Delete the workaround in the script once it lands.

**Deviation from the plan.** The plan asked for a round trip against the real backend. The only
endpoint reachable without a session is registration, and calling it would create a real user,
so the proof is a recording transport instead. A live round trip becomes free after Phase 1.

**Two things to know when building:**

- Xcode gates build-tool plugins behind a trust prompt. In the IDE, approve `OpenAPIGenerator`
  once. From the command line, pass `-skipPackagePluginValidation`.
- The generator emits `public import` warnings by the hundred. They are suppressed for the
  `EchnoAPI` target only, so warnings from our own code stay visible.

### Phase 1 — Auth (2–3 days) — unchanged from v1

Keycloak public client + PKCE via `ASWebAuthenticationSession`, Keychain token store,
single-flight refresh. `AuthenticationService` and `TokenStoring` already exist as protocols.

### Phase 2 — Domain + mapping conventions (2 days)

Establish the pattern **once**, on one module, before it is repeated 26 times:

- [ ] Domain struct conventions: `let`, `Identifiable`, `Sendable`, non-optional where invariant.
- [ ] `DTOMapping` protocol + a `MappingError` that names the field and DTO when an invariant breaks.
- [ ] Where `String`-typed `format: date` becomes `Date`.
- [ ] How generated enums are re-exported as domain enums.
- [ ] Service actor shape wrapping the generated client.
- [ ] `@Observable` store shape, including the three mutation-response rules (full Dto / SimpleDto / ack) — that discipline is backend behaviour and survives the change of source.

### Phase 3 — App shell, navigation, design system (3–4 days)

See §4 — this is where `echno-web` is the reference.

### Phase 4 — Modules

Same waves as v1, but each module is now: add its tag to the generator filter → write domain
types + mapping → service actor → store → screens. No transcription step.

| Wave | Modules |
|---|---|
| 1 — Identity | user, organization, employee |
| 2 — Field core | attendance (+ settings, shift timing, movement, regularization), leave |
| 3 — Execution | project, task, issue, wbs, work category |
| 4 — Site operations | materials, indents, indent items, grn, inventory transactions, site transfers, storage locations, material consumption, purchase orders, purchase order items, vendor |
| 5 — Web-only surfaces | attachment, invitation, labour, inspection |
| 6 — iPad-first | finance, reports |

### Phases 5–7 — native capabilities, iPad, CI/release

Unchanged from v1: camera + CoreLocation + offline queue; iPad multi-column and multi-window;
tests, CI, TestFlight, privacy manifest.

---

## 4. Following echno-web's UI/UX

echno-web is a Next.js app using **shadcn/ui** (`new-york` style, `zinc` base), Tailwind v4
with OKLCH tokens, **lucide** icons and the Geist type family. We do not port its components —
SwiftUI has its own idioms — we match its **design language** so the two products read as one.

### Colour tokens, converted to sRGB

Define these once as an asset catalog colour set with light + dark variants.

| Token | Light | Dark | Use on iOS |
|---|---|---|---|
| `brand` | `#E68300` | `#FE9A00` | accent / highlights |
| `primary` | `#686FFF` | `#8693FF` | tint colour, primary actions |
| `destructive` | `#E7000B` | `#FF6467` | delete, error states |
| `background` | `#FFFFFF` | `#09090B` | `systemBackground` equivalent |
| `foreground` | `#09090B` | `#FAFAFA` | primary label |
| `muted-foreground` | `#71717B` | `#9F9FA9` | secondary label |
| `card` | `#FFFFFF` | `#18181B` | grouped list / card background |
| `border` | `#E4E4E7` | white @ 10% | separators |

`--radius: 0.625rem` = **10 pt** corner radius; the scale is `sm 6 / md 8 / lg 10 / xl 14`.

### Patterns to carry over

| echno-web | iOS equivalent |
|---|---|
| `components/common/page-header.tsx` — title + description + actions | `.navigationTitle` + subtitle, toolbar actions |
| `components/common/data-table.tsx` | `List` on iPhone, `Table` on iPad |
| `components/common/search-and-filter.tsx` + `active-filter-chip.tsx` | `.searchable` + a filter chip row |
| `components/ui/badge.tsx` for status | a shared `StatusPill` view |
| `components/ui/empty.tsx` | `ContentUnavailableView` |
| `components/common/attachments-section.tsx` / `-uploader.tsx` | attachment grid + `PhotosPicker` / camera |
| `components/common/pagination.tsx` | infinite scroll on iPhone; pagination controls on iPad |
| sidebar + 6 nav sections | `NavigationSplitView` sidebar on iPad; `TabView` on compact iPhone |
| `theme-toggle.tsx` | follow system, with an override in Settings |

### Where to deliberately diverge

Matching a web app too closely is its own failure. Use the native thing:

- **Navigation** — no hamburger; `NavigationSplitView` / `TabView`, native back gestures.
- **Type** — Dynamic Type with semantic text styles, not fixed Geist sizes. Geist is not a
  system font; use SF and match weight/hierarchy rather than shipping a webfont.
- **Icons** — SF Symbols, not lucide. Match meaning, not glyph.
- **Tables** — a dense web data table does not belong on a phone. Cards/rows on iPhone,
  `Table` on iPad.
- **Modals** — sheets and `.confirmationDialog`, not web dialog conventions.
- **Feedback** — inline state and haptics; not toast stacks.

---

## 5. Open items and risks

| # | Item | Impact | Action |
|---|---|---|---|
| 1 | 6 duplicate root tags block generation | 🔴 Cannot generate | Backend fix; local dedupe meanwhile |
| 2 | 185 DTOs have no `required` → all-optional Swift | 🟠 Design | Mapping layer absorbs it; ask backend to extend the #645 machinery to `required` |
| 3 | 168 mobile endpoints authorize off an RPT-only claim | 🔴 403s | Call `/web`; `Endpoints.swift` already encodes this |
| 4 | 31 domains have no mobile controller (179 endpoints) | 🟠 Scope | `attachment` first |
| 5 | `photoUrl` vs `photo` on mobile check-in | 🔴 Silent data loss | Backend one-liner |
| 6 | `/api/v1/user` not tenant-exempt | 🔴 Bootstrap 400s | Backend one-liner |
| 7 | Spec changes under us | 🟠 Drift | Vendored + sha-stamped; regeneration surfaces breaks as compile errors |
| 8 | Generated code volume (~9k lines/module) | 🟡 Build time | Generate per module via `filter`, never the whole spec |
| 9 | `GET /api/v1/core/modules` not implemented | 🟡 Feature gating | Static feature set for v1 |

Items 3–6 are detailed in [`backend-mobile-api-gaps.md`](./backend-mobile-api-gaps.md).

### New backend asks from this analysis

- **A.** Rename the web-side `@Tag` on the 6 controllers in §2 to `… (Web)`. *Blocking.*
- **B.** Mark non-nullable fields `required` in the schema — the complement of the
  `NullableSchemaCustomizer` work in #645, with an ArchUnit test to hold it. Without it every
  generated property is optional.
- **C.** Publish `docs/openapi.json` as a CI artifact (or confirm we vendor from the repo).

---

## 6. Immediate next steps

1. Send asks **A**, **B**, **C** to the backend team alongside the existing gap report.
2. Write `Scripts/sync-openapi.sh` and stand up the `EchnoAPI` target (Phase 0.5).
3. Phase 1 auth — unblocked, nothing in it depends on the above.
4. Phase 2 on `user`, establishing the mapping conventions.
5. Then modules, wave by wave.
