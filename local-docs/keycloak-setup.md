# Keycloak setup — `echno-ios-client`

Everything needed to register the iOS client in the Keycloak admin console, and
how to prove it works before handing it to the app.

Written against the modern admin console (Keycloak 22+). The values below are not
suggestions — they are read directly from
`Sources/EchnoKit/Auth/KeycloakAuth.swift` and `echno-ios/App/EchnoConfiguration.swift`,
and the app will not authenticate if they differ.

---

## What you are creating

A **public** OAuth client using **authorization code + PKCE**.

Public means it ships no client secret. A secret embedded in an app binary is
extractable by anyone who downloads it, so it is not a secret. PKCE replaces it:
the app generates a random verifier per sign-in, sends only its SHA-256 hash with
the authorization request, and presents the verifier itself when redeeming the
code. An attacker who intercepts the code on the redirect cannot use it.

**Do not enable Client authentication.** If the console asks for a secret, the
client is confidential and the app cannot use it.

---

## Values

| Setting | Value |
|---|---|
| Realm | `echno-realm` |
| Client ID | `echno-ios-client` |
| Client type | OpenID Connect |
| Client authentication | **Off** (public) |
| Standard flow | **On** |
| Direct access grants | **Off** |
| Implicit flow | **Off** |
| Service accounts | **Off** |
| PKCE method | **S256** (required, not optional) |
| Valid redirect URI | `com.tornotron.echno-ios://oauth/callback` |
| Valid post logout redirect URI | `com.tornotron.echno-ios://oauth/callback` |
| Web origins | *(leave empty — native client, no CORS)* |
| Scopes requested | `openid profile email offline_access` |

The redirect URI must match **exactly**, including the scheme. It is not a web
URL: `com.tornotron.echno-ios` is the app's **bundle identifier** used as a
custom scheme, which is how `ASWebAuthenticationSession` catches the callback.

> Note the two are unrelated despite looking alike. The client ID is
> `echno-ios-client`; the redirect scheme is `com.tornotron.echno-ios`, fixed by
> the bundle identifier. Renaming the client does not change the redirect URI,
> and changing the bundle identifier would.

---

## Steps

### 1. Create the client

1. Admin console → select realm **`echno-realm`** (top-left switcher).
2. **Clients** → **Create client**.
3. *General settings*
   - Client type: **OpenID Connect**
   - Client ID: **`echno-ios-client`**
   - Name: `Echno iOS`
   - Next.
4. *Capability config*
   - Client authentication: **Off**
   - Authorization: **Off**
   - Authentication flow: tick **Standard flow** only. Untick Direct access
     grants, Implicit flow and Service accounts roles.
   - Next.
5. *Login settings*
   - Valid redirect URIs: `com.tornotron.echno-ios://oauth/callback`
   - Valid post logout redirect URIs: `com.tornotron.echno-ios://oauth/callback`
   - Web origins: leave empty.
   - Root URL / Home URL: leave empty.
   - Save.

> **Why Direct access grants is off.** That is the Resource Owner Password flow —
> username and password posted straight to the token endpoint. The app never
> collects a password (see `SignInView`), and leaving the grant enabled widens
> the attack surface for a flow nothing uses.

### 2. Require PKCE

Client → **Advanced** tab → *Advanced settings*:

- **Proof Key for Code Exchange Code Challenge Method**: `S256`
- Save.

Leaving this unset makes PKCE optional. The app always sends a challenge, so
sign-in would still work — which is exactly the problem: the protection would be
silently unenforced, and a client that omitted it would be accepted.

### 3. Token lifetimes

Client → **Advanced** tab → *Advanced settings*:

| Setting | Suggested | Why |
|---|---|---|
| Access Token Lifespan | 5–15 minutes | Short is fine; the app refreshes transparently |
| Client Session Idle | 7–30 days | Mobile sessions should outlive web's. A site worker opening the app weekly should not be signed out |
| Client Session Max | 30–90 days | The hard ceiling before a fresh sign-in |

If left blank these inherit the realm defaults, which are tuned for web and are
usually far too short for a phone.

### 4. Mappers — the part that is easy to miss

A correctly created client still produces a token the backend cannot use. Two
claims are required.

#### 4a. `groups` — organization membership and org roles

The backend's `JwtAuthConverter.extractGroupAuthorities` reads a **top-level
`groups` claim** and derives every tenant authority from it:

| Group path | Becomes | Used by |
|---|---|---|
| `/org-42` | `ORG_MEMBER_42` | `TenantFilter` — validates `X-Organization-Id` |
| `/org-42/system-admin` | `ORG_42_ROLE_system-admin` | `@PreAuthorize("@orgSecurity...")` on nearly every endpoint |

Without it every tenant-scoped request fails, and a multi-organization user gets
`400 X-Organization-Id header required` because the filter can infer nothing.

Client → **Client scopes** → **`echno-ios-client-dedicated`** → **Add mapper** → **By
configuration** → **Group Membership**:

| Field | Value |
|---|---|
| Name | `groups` |
| Token Claim Name | `groups` |
| Full group path | **On** |
| Add to ID token | On |
| Add to access token | **On** |
| Add to userinfo | On |

**Full group path must be on.** With it off Keycloak emits `org-42` without the
leading slash and, worse, drops the parent for nested groups — so
`/org-42/system-admin` arrives as `system-admin`, the `org-` prefix filter
discards it, and every org role silently vanishes.

Org role group names, from the backend's `OrgRole` enum:
`system-admin`, `org-manager`, `hr-admin`, `project-manager`, `qa-engineer`,
`safety-officer`, `site-engineer`.

#### 4b. Audience — backend client roles

`JwtAuthConverter.extractResourceRoles` reads
`resource_access[<KEYCLOAK_BACKEND_CLIENT>].roles`, where that client id comes
from the backend's `jwt.auth.converter.resource-id` setting. A token issued to
`echno-ios-client` carries `resource_access.echno-ios-client`, so unless the backend
client is
named in the audience those roles are simply absent.

Client → **Client scopes** → **`echno-ios-client-dedicated`** → **Add mapper** → **By
configuration** → **Audience**:

| Field | Value |
|---|---|
| Name | `backend-audience` |
| Included Client Audience | *the value of `KEYCLOAK_BACKEND_CLIENT` on the backend* |
| Add to access token | **On** |

> Check what `KEYCLOAK_BACKEND_CLIENT` is set to in the backend's environment
> before filling this in. Copying whatever `echno-web` uses is the quickest way
> to get it right — compare against the `echno-web` client's own mappers.

### 5. Confirm `offline_access` is available

The app requests `offline_access`; without it Keycloak issues no refresh token
and the session dies at the first access-token expiry.

Client → **Client scopes** tab → confirm `offline_access` is listed. If it is
not, **Add client scope** → `offline_access` → assign as **Optional**.

---

## Verify before handing it over

Two checks. Do both — the first proves the client exists, the second proves the
token is usable, and passing the first tells you nothing about the second.

### Check 1 — the authorization endpoint accepts the client

```bash
curl -sI "https://auth.echno.in/realms/echno-realm/protocol/openid-connect/auth\
?client_id=echno-ios-client\
&redirect_uri=com.tornotron.echno-ios%3A%2F%2Foauth%2Fcallback\
&response_type=code\
&scope=openid\
&state=test\
&code_challenge=E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM\
&code_challenge_method=S256" | head -1
```

`200` means the client and redirect URI are accepted. An error page naming
`invalid_redirect_uri` means the URI does not match exactly — check for a
trailing slash.

### Check 2 — the token carries the claims the backend needs

Sign in on a device or simulator, then decode the access token's payload:

```bash
# Paste the access token, then:
echo "<token>" | cut -d. -f2 | base64 -d 2>/dev/null | python3 -m json.tool
```

Confirm:

- `"groups"` is present and contains `/org-<id>` paths **with leading slashes**
- `"aud"` or `resource_access` names the backend client
- `"preferred_username"` is present — the backend uses it as the principal
- `"typ": "Bearer"`

---

## Troubleshooting

| Symptom | Cause |
|---|---|
| Browser shows "Invalid parameter: redirect_uri" | Redirect URI mismatch. Must be `com.tornotron.echno-ios://oauth/callback` exactly, no trailing slash |
| Sheet opens then closes immediately | Custom scheme mismatch between Keycloak and `ECHNO_OAUTH_REDIRECT_URI` |
| `invalid_client` at the token endpoint | Client authentication is On — it must be a public client |
| `invalid_grant` right after sign-in | PKCE mismatch, or the code was already redeemed. Confirm Code Challenge Method is `S256` |
| Signed in, but every API call returns 403 | Missing `groups` mapper, or Full group path is off |
| `400 X-Organization-Id header required` | The `groups` claim is absent, so the backend cannot infer the tenant |
| Signed out after a few minutes | No refresh token — `offline_access` not assigned |
| Signed out on returning after a day | Client Session Idle too short |

---

## After it exists

Nothing in the app needs changing — `echno-ios-client`, the redirect URI and the issuer
are already its defaults. To point a build at a different realm, pass build
settings rather than editing source:

```bash
xcodebuild -project echno-ios.xcodeproj -scheme echno-ios \
  ECHNO_KEYCLOAK_ISSUER="http://localhost:8080/realms/echno-realm-local" \
  ECHNO_KEYCLOAK_CLIENT_ID="echno-ios-client-local" \
  ECHNO_API_BASE_URL="http://localhost:8081/api/v1" \
  build
```

These resolve through `Config/Info.plist` into `EchnoConfiguration`. Empty values
fall back to the production defaults.

---

## Related

- `local-docs/backend-mobile-api-gaps.md` §7 — the original ask, plus the open
  backend items
- `local-docs/ios-action-plan.md` § Phase 1 — what the app does with the session
- `Sources/EchnoKit/Auth/` — the implementation these values feed
