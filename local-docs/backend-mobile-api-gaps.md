# Echno backend — mobile API gap report

**For:** backend team
**From:** iOS client work (`echno-ios`)
**Date:** 2026-09-06
**Method:** static analysis of every `*Controller*.java` under `echno-backend/src/main/java/org/tornotron/echno_backend` — **100 controllers, 738 endpoints** parsed and diffed pairwise. Figures below are counted, not estimated.

---

## TL;DR — four blockers

| # | Issue | Blast radius |
|---|---|---|
| **1** | **20 mobile controllers still authorize with `hasAuthority('<resource>:<scope>')`**, which reads the `authorization.permissions` claim. That claim only exists in a Keycloak **RPT** (UMA token), not in a normal OIDC access token. A standard PKCE-issued mobile token will **403 on every one of those 168 endpoints.** | 🔴 Hard blocker |
| **2** | Those same `hasAuthority` checks are **not tenant-scoped** — no `isMemberOfCurrentTenant()`. Where web asks "are you a member of *this org*", mobile asks only "do you hold this scope anywhere". | 🔴 Security |
| **3** | **31 domains have no mobile controller at all** (179 endpoints), including `attachment`, all of `finance/*`, `inspections`, `ncrs`, `labour`, `search`, `invitation`. | 🟠 Scope |
| **4** | **73 endpoints exist on web but not mobile**, and **42 mobile endpoints use a different path shape** for the same operation. Mobile is a stale fork, not a parallel surface. | 🟠 Drift |

The good news: 15 mobile controllers — `attendance`, `attendance-regularizations`, `attendance-settings`, `shift-timings`, `movement-records`, `leave-requests`, `leave-balances`, `leave-policies`, `purchase-orders`, `purchase-order-items`, `wbs`, `user`, `keycloak`, `auth`, `generate-report` — **have already been migrated** to `@orgSecurity.*`. In `LeaveApprovalController.java` the old line is sitting right there commented out:

```java
@PostMapping("/requests/{requestId}/approve")
//    @PreAuthorize("hasAuthority('leave:approve') or hasAuthority('leave:admin')")
@PreAuthorize("@orgSecurity.hasAnyOrgRoleForCurrentTenant('system-admin','hr-admin')")
```

So the pattern is settled and half-applied. **What we need is the other half.**

---

## 1. Authorization model split (blocker #1 and #2)

`JwtAuthConverter.extractPermissions()` builds `<rsname>:<scope>` authorities from the JWT's `authorization.permissions` claim, and logs `"No 'authorization' claim found in JWT - RPT token may not have been obtained"` when it is absent. It is absent from every ordinary authorization-code token — obtaining it needs a second UMA grant exchange against Keycloak Authorization Services.

echno-web never hits this because its controllers use `@orgSecurity.*`, which reads `ORG_MEMBER_<id>` / org-role group authorities that **are** in a normal token.

**Consequence for iOS:** unless we implement the UMA RPT exchange (which we would rather not — it doubles the token lifecycle and Authorization Services is not configured for a mobile client), the mobile controllers are unusable as-is.

**Ask:** finish the `hasAuthority(...)` → `@orgSecurity.*` migration on the 20 controllers below, matching the `/web` twin's expression exactly.

### Mobile controllers still on `hasAuthority` — 168 endpoints

| Mobile controller | Endpoints | `hasAuthority` checks | Web twin's model |
|---|---|---|---|
| `/api/v1/vendors` | 23 | 23 | `hasAnyOrgRoleForCurrentTenant('system-admin')` |
| `/api/v1/inventory-transactions` | 13 | 13 | `hasAnyOrgRoleForCurrentTenant('system-admin')` |
| `/api/v1/materials` | 12 | 12 | `hasAnyOrgRoleForCurrentTenant('system-admin','project-manager')` |
| `/api/v1/indent-items` | 10 | 10 | `hasAnyOrgRoleForCurrentTenant('system-admin')` |
| `/api/v1/site-transfers` | 10 | 10 | `hasAnyOrgRoleForCurrentTenant('system-admin')` |
| `/api/v1/project` | 10 | 9 | `isMemberOfCurrentTenant()` / `hasAnyOrgRoleForCurrentTenant(...)` |
| `/api/v1/indents` | 9 | 9 | `hasAnyOrgRoleForCurrentTenant('system-admin')` |
| `/api/v1/material-consumptions` | 8 | 8 | `hasAnyOrgRoleForCurrentTenant('system-admin')` |
| `/api/v1/employee` | 8 | 7 | `hasAnyOrgRoleForCurrentTenant('system-admin','hr-admin',…)` / `isSelfOrHasAnyOrgRole` |
| `/api/v1/grns` | 7 | 7 | `hasAnyOrgRoleForCurrentTenant('system-admin')` |
| `/api/v1/payables` | 7 | 7 | `hasAnyOrgRoleForCurrentTenant('system-admin')` |
| `/api/v1/organization` | 7 | 2 | `isMemberOrAdmin(#id)` / `hasOrgRole(#id,'system-admin')` |
| `/api/v1/storage-locations` | 6 | 6 | `hasAnyOrgRoleForCurrentTenant('system-admin','project-manager')` |
| `/api/v1/leave-calendar` | 6 | 6 | `hasAnyOrgRoleForCurrentTenant('system-admin','hr-admin')` |
| `/api/v1/leave-approvals` | 6 | 5 | `hasAnyOrgRoleForCurrentTenant('system-admin','hr-admin')` |
| `/api/v1/tasks` | 6 | 5 | `isMemberOfCurrentTenant()` / `hasAnyOrgRoleForCurrentTenant(...)` |
| `/api/v1/notifications` | 5 | 5 | `hasAnyOrgRoleForCurrentTenant('system-admin','hr-admin')` |
| `/api/v1/issues` | 5 | 4 | `isMemberOfCurrentTenant()` / `hasAnyOrgRoleForCurrentTenant(...)` |
| `/api/v1/workCategories` | 4 | 4 | `hasAnyOrgRoleForCurrentTenant('system-admin','project-manager')` |
| `/api/v1/issues/comments` | 3 | 3 | `isMemberOfCurrentTenant()` / `hasAnyOrgRoleForCurrentTenant(...)` |

> `leave-approvals` and `organization` are **partially** migrated — mixed `hasAuthority` and `@orgSecurity` in the same file. Worth a careful pass rather than a find-and-replace.

### Related: `organization:admin` is a global tenant bypass

`TenantFilter` treats the `organization:admin` authority as a full tenant-isolation bypass:

```java
if (hasAuthority(authentication, ORG_ADMIN_AUTHORITY)) {   // "organization:admin"
    log.warn("[TenantFilter] Tenant isolation bypassed for global admin ...");
    TenantContext.setBypass(true);
```

That authority comes from the same RPT permissions claim. Two questions for the team:
1. Is `organization:admin` intended to be a **platform-operator** authority, or does any org admin end up holding it?
2. Since the RPT claim is absent from normal tokens today, is this bypass currently reachable at all — and if not, is anything depending on it?

---

## 2. Tenant-context gaps on the mobile paths

`TenantFilter` resolves the active org from the `X-Organization-Id` header, requires `ORG_MEMBER_<id>` to match, and **400s** when a multi-org user omits the header. Two mobile-specific problems:

**a) The bootstrap call has no unscoped mobile equivalent.** `preTenantReason()` exempts exactly two paths:

```java
if (path.equals(apiRoot + "/auth/register")) { ... }
if (path.equals(apiRoot + "/user/web"))      { return "The current-user lookup answers across every organization the caller belongs to"; }
```

`/api/v1/user` — the mobile twin — is **not** exempt. So the first call the app makes after sign-in, to find out which orgs the user belongs to, gets tenant-scoped and 400s for any multi-org user. Chicken-and-egg.

**Ask:** add `/api/v1/user` to `preTenantReason()`, or tell us the intended mobile bootstrap sequence.

**b) `GET /api/v1/user/employees` does not exist on mobile.** Web has `getEmployeesForCurrentUser` returning `List<EmployeeDto>`; that is how the client learns the caller's employee record per org. Needed on mobile for the same reason.

**c) CORS `allowedHeaders` already lists `X-Organization-Id`** — fine for us (native clients skip preflight), noted only so nobody "cleans it up".

---

## 3. Domains with no mobile controller at all

31 controllers are web-only. Priority is ours, not a demand — but **`attachment` is a hard dependency**: without it the app cannot upload or read any photo or document outside the attendance selfie path.

| Priority | Domains | Why |
|---|---|---|
| **P0 — blocks v1** | `attachment/web` (6 ep) | Every photo/document flow in the app. Nothing else unblocks it. |
| **P1 — field workflows** | `labour/web` (5), `stock-adjustments/web` (8), `expenses/web` (6) | Site-level data capture; natural phone work. |
| **P2 — org onboarding** | `invitation/web` (4), `keycloakGroup/web` (3), `search/web` (1) | Join-org flow and global search. |
| **P3 — inspection suite** | `inspections/web` (12), `ncrs/web` (11), `checklist-templates/web` (6), `inspections/web/compliance` (4) | Strong mobile use case (on-site QA/QC with camera), but a large surface. |
| **P4 — asset tracking** | `assets/web` (11) | Useful on phone; not v1. |
| **P5 — back-office** | all `finance/*` (64 ep across 14 controllers), `receipts/web` (6), `sub-contracts/web` (6), `billing/*` (30) | We plan to consume these read-only on iPad via `/web`; no mobile twin needed unless you prefer one. |

**Ask:** P0 now; P1–P2 before the site-operations wave; P3+ on your normal roadmap. For P5 we are happy to call `/web` directly — confirm that is acceptable rather than us waiting on new controllers.

### Full web-only endpoint inventory


**`/api/v1/assets/web`** — 11 endpoints
  - `GET    /` → `List<AssetDto`
  - `POST   /` → `AssetDto`
  - `GET    /documents/expiring` → `List<AttachmentDto`
  - `GET    /paginated` → `Page<AssetDto`
  - `DELETE /{id}` → `ApiResponse`
  - `GET    /{id}` → `AssetDto`
  - `PUT    /{id}` → `AssetDto`
  - `GET    /{id}/documents` → `List<AttachmentDto`
  - `GET    /{id}/movements` → `Page<AssetMovementDto`
  - `POST   /{id}/movements` → `AssetMovementDto`
  - `GET    /{id}/placement-history` → `List<AssetPlacementSpanDto`

**`/api/v1/attachment/web`** — 6 endpoints
  - `DELETE /attachmentId/{attachmentId}` → `ApiResponse`
  - `PATCH  /attachmentId/{attachmentId}/document` → `AttachmentDto`
  - `GET    /entityId/{entityId}/entityType/{entityType}` → `List<AttachmentDto`
  - `POST   /entityId/{entityId}/entityType/{entityType}` → `List<AttachmentDto`
  - `POST   /presign/entityId/{entityId}/entityType/{entityType}` → `List<PresignedUpload`
  - `POST   /register/entityId/{entityId}/entityType/{entityType}` → `List<AttachmentDto`

**`/api/v1/billing/features/web`** — 8 endpoints
  - `GET    /` → `List<FeatureDto`
  - `POST   /` → `FeatureDto`
  - `GET    /all` → `List<FeatureDto`
  - `GET    /code/{code}` → `FeatureDto`
  - `DELETE /{id}` → `ApiResponse`
  - `GET    /{id}` → `FeatureDto`
  - `PUT    /{id}` → `FeatureDto`
  - `POST   /{id}/activate` → `ApiResponse`

**`/api/v1/billing/plans/web`** — 10 endpoints
  - `GET    /` → `List<PlanDto`
  - `POST   /` → `PlanDto`
  - `GET    /code/{code}` → `PlanDto`
  - `GET    /public` → `List<PlanDto`
  - `DELETE /{id}` → `ApiResponse`
  - `GET    /{id}` → `PlanDto`
  - `PUT    /{id}` → `PlanDto`
  - `POST   /{id}/activate` → `ApiResponse`
  - `POST   /{planId}/features` → `PlanDto`
  - `DELETE /{planId}/features/{featureCode}` → `PlanDto`

**`/api/v1/billing/subscriptions/web`** — 12 endpoints
  - `POST   /` → `SubscriptionDto`
  - `POST   /cancel` → `ApiResponse`
  - `PUT    /change-plan` → `SubscriptionDto`
  - `GET    /current` → `SubscriptionDto`
  - `GET    /features/{featureCode}/access` → `FeatureAccessResultDto`
  - `GET    /history` → `List<SubscriptionDto`
  - `POST   /usage` → `ApiResponse`
  - `GET    /user/{userId}` → `SubscriptionDto`
  - `POST   /user/{userId}` → `SubscriptionDto`
  - `POST   /user/{userId}/cancel` → `ApiResponse`
  - `PUT    /user/{userId}/change-plan` → `SubscriptionDto`
  - `GET    /user/{userId}/history` → `List<SubscriptionDto`

**`/api/v1/checklist-templates/web`** — 6 endpoints
  - `GET    /` → `Page<ChecklistTemplateDto`
  - `POST   /` → `ChecklistTemplateDto`
  - `GET    /starters` → `List<StarterChecklistTemplateDto`
  - `POST   /starters/{trade}/adopt` → `ChecklistTemplateDto`
  - `GET    /{id}` → `ChecklistTemplateDto`
  - `PUT    /{id}` → `ChecklistTemplateDto`

**`/api/v1/expenses/web`** — 6 endpoints
  - `GET    /` → `List<ExpenseDto`
  - `POST   /` → `ExpenseDto`
  - `GET    /paginated` → `Page<ExpenseDto`
  - `DELETE /{id}` → `ApiResponse`
  - `GET    /{id}` → `ExpenseDto`
  - `PUT    /{id}` → `ExpenseDto`

**`/api/v1/finance/accounts/web`** — 10 endpoints
  - `GET    /` → `List<AccountDto`
  - `POST   /` → `AccountDto`
  - `GET    /by-code/{code}` → `AccountDto`
  - `GET    /export` → `byte[]`
  - `POST   /import` → `CoaImportSummary`
  - `POST   /seed-defaults` → `Map<String, Integer`
  - `GET    /tree` → `List<AccountTreeDto`
  - `GET    /{id}` → `AccountDto`
  - `PUT    /{id}` → `AccountDto`
  - `POST   /{id}/deactivate` → `AccountDto`

**`/api/v1/finance/company-bank-accounts/web`** — 4 endpoints
  - `GET    /` → `List<CompanyBankAccountDto`
  - `POST   /` → `CompanyBankAccountDto`
  - `GET    /{id}` → `CompanyBankAccountDto`
  - `POST   /{id}/deactivate` → `CompanyBankAccountDto`

**`/api/v1/finance/construction-invoices/web`** — 9 endpoints
  - `GET    /` → `Page<ConstructionInvoiceDto`
  - `POST   /` → `ConstructionInvoiceDto`
  - `GET    /{id}` → `ConstructionInvoiceDto`
  - `PUT    /{id}` → `ConstructionInvoiceDto`
  - `POST   /{id}/approve` → `ConstructionInvoiceDto`
  - `POST   /{id}/cancel` → `ConstructionInvoiceDto`
  - `GET    /{id}/pdf` → `byte[]`
  - `POST   /{id}/record-payment` → `ConstructionInvoiceDto`
  - `POST   /{id}/submit` → `ConstructionInvoiceDto`

**`/api/v1/finance/construction-payments/web`** — 6 endpoints
  - `GET    /` → `Page<ConstructionPaymentDto`
  - `POST   /` → `ConstructionPaymentDto`
  - `GET    /{id}` → `ConstructionPaymentDto`
  - `PUT    /{id}` → `ConstructionPaymentDto`
  - `POST   /{id}/cancel` → `ConstructionPaymentDto`
  - `POST   /{id}/verify` → `ConstructionPaymentDto`

**`/api/v1/finance/cost-categories/web`** — 6 endpoints
  - `GET    /` → `List<CostCategoryDto`
  - `POST   /` → `CostCategoryDto`
  - `POST   /seed-defaults` → `Map<String, Integer`
  - `GET    /{id}` → `CostCategoryDto`
  - `PUT    /{id}` → `CostCategoryDto`
  - `POST   /{id}/deactivate` → `CostCategoryDto`

**`/api/v1/finance/customers/web`** — 5 endpoints
  - `GET    /` → `CustomerDto`
  - `POST   /` → `CustomerDto`
  - `GET    /all` → `List<CustomerDto`
  - `PUT    /{id}` → `CustomerDto`
  - `POST   /{id}/deactivate` → `Void`

**`/api/v1/finance/invoices/web`** — 5 endpoints
  - `GET    /` → `Page<InvoiceDto`
  - `POST   /` → `InvoiceDto`
  - `GET    /{id}` → `InvoiceDto`
  - `POST   /{id}/cancel` → `InvoiceDto`
  - `POST   /{id}/issue` → `InvoiceDto`

**`/api/v1/finance/journal/web`** — 1 endpoints
  - `GET    /export` → `byte[]`

**`/api/v1/finance/journal-entries/web`** — 4 endpoints
  - `GET    /` → `JournalEntryDto`
  - `POST   /` → `JournalEntryDto`
  - `GET    /all` → `List<JournalEntryDto`
  - `POST   /reverse` → `JournalEntryDto`

**`/api/v1/finance/payments/web`** — 2 endpoints
  - `POST   /` → `PaymentDto`
  - `GET    /{id}` → `PaymentDto`

**`/api/v1/finance/posting-accounts/web`** — 3 endpoints
  - `GET    /` → `List<PostingAccountMappingDto`
  - `DELETE /{role}` → `PostingAccountMappingDto`
  - `PUT    /{role}` → `PostingAccountMappingDto`

**`/api/v1/finance/projects/{projectId}/budget/web`** — 3 endpoints
  - `GET    /` → `List<BudgetAllocationDto`
  - `DELETE /{costCategoryId}` → `Void`
  - `PUT    /{costCategoryId}` → `BudgetAllocationDto`

**`/api/v1/finance/projects/{projectId}/cost-control/web`** — 1 endpoints
  - `GET    /` → `ProjectCostControlDto`

**`/api/v1/finance/reports/web`** — 3 endpoints
  - `GET    /balance-sheet` → `BalanceSheetReport`
  - `GET    /profit-and-loss` → `ProfitAndLossReport`
  - `GET    /trial-balance` → `TrialBalanceReport`

**`/api/v1/finance/settings/web`** — 2 endpoints
  - `GET    /` → `FinanceSettingsDto`
  - `PUT    /` → `FinanceSettingsDto`

**`/api/v1/inspections/web`** — 12 endpoints
  - `GET    /` → `Page<InspectionDto`
  - `POST   /` → `InspectionDto`
  - `GET    /{id}` → `InspectionDto`
  - `PUT    /{id}` → `InspectionDto`
  - `GET    /{id}/annotations` → `Page<DefectPhotoAnnotationDto`
  - `PUT    /{id}/annotations` → `List<DefectPhotoAnnotationDto`
  - `GET    /{id}/evidence` → `List<AttachmentDto`
  - `POST   /{id}/evidence` → `List<AttachmentDto`
  - `POST   /{id}/evidence/presign` → `List<PresignedUpload`
  - `POST   /{id}/evidence/register` → `List<AttachmentDto`
  - `DELETE /{id}/evidence/{attachmentId}` → `Void`
  - `GET    /{id}/pdf` → `byte[]`

**`/api/v1/invitation/web`** — 4 endpoints
  - `POST   /generateCode/organizationId/{organizationId}` → `ProjectInviteCodeDto`
  - `GET    /organizationId/{organizationId}` → `List<ProjectInviteCodeDto`
  - `POST   /validate/userId/{userId}` → `OrganizationDto`
  - `PATCH  /{inviteCodeId}` → `ProjectInviteCodeDto`

**`/api/v1/keycloakGroup/web`** — 3 endpoints
  - `POST   /assign` → `ApiResponse`
  - `POST   /assignRole` → `ApiResponse`
  - `POST   /unassignRole` → `ApiResponse`

**`/api/v1/labour/web`** — 5 endpoints
  - `GET    /` → `List<LabourDto`
  - `POST   /` → `LabourSimpleDto`
  - `DELETE /{id}` → `ApiResponse`
  - `GET    /{id}` → `LabourDto`
  - `PATCH  /{id}` → `ApiResponse`

**`/api/v1/ncrs/web`** — 11 endpoints
  - `GET    /` → `Page<NcrDto`
  - `POST   /` → `NcrDto`
  - `GET    /punch-list/pdf` → `byte[]`
  - `GET    /{id}` → `NcrDto`
  - `POST   /{id}/assign` → `NcrDto`
  - `POST   /{id}/close` → `NcrDto`
  - `POST   /{id}/corrective-action-complete` → `NcrDto`
  - `GET    /{id}/pdf` → `byte[]`
  - `POST   /{id}/reject` → `NcrDto`
  - `POST   /{id}/reopen` → `NcrDto`
  - `POST   /{id}/verify` → `NcrDto`

**`/api/v1/receipts/web`** — 6 endpoints
  - `GET    /` → `List<ReceiptDto`
  - `POST   /` → `ReceiptDto`
  - `GET    /paginated` → `Page<ReceiptDto`
  - `DELETE /{id}` → `ApiResponse`
  - `GET    /{id}` → `ReceiptDto`
  - `PUT    /{id}` → `ReceiptDto`

**`/api/v1/search/web`** — 1 endpoints
  - `GET    /` → `List<SearchHit`

**`/api/v1/stock-adjustments/web`** — 8 endpoints
  - `GET    /` → `List<StockAdjustmentDto`
  - `POST   /` → `StockAdjustmentDto`
  - `GET    /paginated` → `Page<StockAdjustmentDto`
  - `DELETE /{id}` → `ApiResponse`
  - `GET    /{id}` → `StockAdjustmentDto`
  - `PUT    /{id}` → `StockAdjustmentDto`
  - `POST   /{id}/approve` → `StockAdjustmentDto`
  - `POST   /{id}/reject` → `StockAdjustmentDto`

**`/api/v1/sub-contracts/web`** — 6 endpoints
  - `GET    /` → `List<SubContractDto`
  - `POST   /` → `SubContractDto`
  - `GET    /paginated` → `Page<SubContractDto`
  - `DELETE /{id}` → `ApiResponse`
  - `GET    /{id}` → `SubContractDto`
  - `PUT    /{id}` → `SubContractDto`

---

## 4. Endpoint drift on the 32 paired controllers

281 web endpoints vs 250 mobile. **73 operations available on web are missing from mobile**; **42 mobile endpoints implement the same operation under a different path shape** (mostly path-param vs query-param, in both directions).

### 4.1 Summary table

| Module | web ep | mobile ep | missing on mobile | mobile-only | authz diffs | signature diffs |
|---|---|---|---|---|---|---|
| `attendance` | 9 | 9 | — | — | — | 1 |
| `attendance-regularizations` | 5 | 4 | 1 | — | — | — |
| `attendance-settings` | 6 | 6 | — | — | — | — |
| `category` | 4 | 4 | — | — | 4 | — |
| `employee` | 15 | 8 | 11 | 4 | 4 | — |
| `grns` | 7 | 7 | — | — | 7 | — |
| `indent-items` | 10 | 10 | — | — | 10 | — |
| `indents` | 11 | 9 | 2 | — | 9 | — |
| `inventory-transactions` | 14 | 13 | 1 | — | 13 | — |
| `issues` | 9 | 4 | 5 | — | 4 | — |
| `issues/comments` | 5 | 3 | 2 | — | 3 | — |
| `leave-approvals` | 6 | 6 | 6 | 6 | — | — |
| `leave-balances` | 7 | 7 | 6 | 6 | — | — |
| `leave-calendar` | 6 | 6 | 5 | 5 | 1 | — |
| `leave-policies` | 8 | 9 | 6 | 7 | — | — |
| `leave-requests` | 14 | 13 | 9 | 8 | — | — |
| `material-consumptions` | 8 | 8 | — | — | 8 | — |
| `materials` | 13 | 12 | 1 | — | 12 | — |
| `movement-records` | 4 | 4 | — | — | — | — |
| `notifications` | 5 | 5 | 1 | 1 | 4 | — |
| `organization` | 6 | 5 | 3 | 2 | 2 | — |
| `payables` | 7 | 7 | — | — | 7 | — |
| `project` | 12 | 9 | 5 | 2 | 7 | 1 |
| `project/{projectId}/wbs` | 10 | 10 | — | — | — | — |
| `purchase-order-items` | 8 | 8 | 1 | 1 | — | — |
| `purchase-orders` | 10 | 9 | 1 | — | — | — |
| `shift-timings` | 5 | 5 | — | — | — | — |
| `site-transfers` | 11 | 10 | 1 | — | 10 | — |
| `storage-locations` | 8 | 6 | 2 | — | 6 | — |
| `tasks` | 8 | 5 | 3 | — | 5 | 1 |
| `user` | 7 | 6 | 1 | — | — | 2 |
| `vendors` | 23 | 23 | — | — | 23 | — |
| **total (32 pairs)** | **281** | **250** | **73** | **42** | **139** | **5** |

> **Reading the columns.** *missing on mobile* = web can do it, mobile cannot. *mobile-only* = same operation, different URL — see the per-module detail. *authz diffs* = shared endpoint where web uses `@orgSecurity.*` and mobile uses `hasAuthority(...)` (issue #1). *signature diffs* = different parameters or return type on the same verb+path.

### 4.2 The five signature divergences — these bite silently

These are the ones that compile, deploy, and then misbehave at runtime.

**a) `POST /attendance/check-in` — the multipart part is named differently.** 🔴

| | multipart field |
|---|---|
| `/api/v1/attendance/web/check-in` | `@RequestParam(value = "photo") MultipartFile photo` |
| `/api/v1/attendance/check-in` | `@RequestParam(value = "photoUrl") MultipartFile photoUrl` |

`photoUrl` also collides with the *string* field of the same name on the response DTO. Since the part is `required = false`, a client sending `photo` to the mobile endpoint gets **201 Created with the selfie silently discarded** — no error anywhere. Attendance photos are the compliance artifact for site check-in, so this is a data-loss bug waiting for whoever ports first.

**Ask:** rename mobile's part to `photo` to match web (accept both for one release if any caller exists). Note `POST /clock-event` is already consistent — it is only `check-in`.

**b) `PATCH /user/{id}` — completely different request encoding.**

| | request |
|---|---|
| web | `multipart` — `@RequestPart("data") String data` + `MultipartFile profilePicture` + `MultipartFile cv` |
| mobile | `@RequestBody Map<String, Object> updates` — JSON, no file support |

Mobile cannot set a profile picture or CV at all. **Ask:** align mobile onto the web multipart shape.

**c) `GET /user/` — mobile takes `JwtAuthenticationToken`, web takes nothing.** Cosmetic (both resolve the caller from the security context), but it means the two methods have drifted independently. Worth confirming they return the same DTO.

**d) `GET /project/` and `GET /tasks/` — mobile accepts `@Valid @ParameterObject PageQuery pageQuery`, web accepts no parameters.** Mobile paginates the collection endpoint; web has a separate `/paginated`. Two different pagination conventions for the same resource. **Ask:** pick one — we would prefer mobile's (`PageQuery` on the collection endpoint).

### 4.3 Path-shape divergence — the `leave-*` family

The whole leave suite implements the same operations under different URLs on each side. Mobile uses REST-style path params; web moved to query params. Neither is wrong, but a client cannot share one code path:

| Operation | mobile | web |
|---|---|---|
| Approve request | `POST /leave-approvals/requests/{requestId}/approve` | `POST /leave-approvals/approve` |
| Approval chain | `GET /leave-approvals/requests/{requestId}/chain` | `GET /leave-approvals/chain` |
| Employee balances | `GET /leave-balances/employee/{employeeId}` | `GET /leave-balances/` |
| Balance summary | `GET /leave-balances/employee/{employeeId}/summary` | `GET /leave-balances/summary` |
| Org calendar | `GET /leave-calendar/organization/{organizationId}` | `GET /leave-calendar/organization` |
| Employee requests | `GET /leave-requests/employeeId/{employeeId}` | `GET /leave-requests/employee` |
| Update request | `PATCH /leave-requests/requestId/{requestId}` | `PATCH /leave-requests/update` |
| Cancel request | `POST /leave-requests/requestId/{requestId}/cancel` | `POST /leave-requests/cancel` |
| Get policy | `GET /leave-policies/{policyId}` | `GET /leave-policies/policy` |
| Update policy | `PATCH /leave-policies/{policyId}` | `PATCH /leave-policies/update` |
| Mark notification read | `PATCH /notifications/{notificationId}/read` | `PATCH /notifications/read` |

Same story in `employee` (`POST /joinOrganization/{userId}/{orgId}` vs `POST /joinOrganization/userId/{userId}/organizationId/{orgId}`) and `purchase-order-items` (mobile `PUT /` vs web `PATCH /` for the same update).

**Ask:** no urgency, but a decision. Either converge on one shape, or tell us mobile's shape is the intended one and web is the outlier — we will follow whatever you pick, we just need it not to move afterwards.

### 4.4 Per-module detail

### `attendance`  ·  web `/attendance/web` (9 ep) vs mobile `/attendance` (9 ep)

**Signature divergence:**

- `POST /check-in`
    - params — web `@Parameter(schema = @Schema(implementation = AttendanceCheckInDto.class)) @RequestParam("data") String data; @RequestParam(value = "photo", required = false)MultipartFile photo`
    - params — mobile `@Parameter(schema = @Schema(implementation = AttendanceCheckInDto.class)) @RequestParam("data") String data; @RequestParam(value = "photoUrl", required = false) MultipartFile photoUrl`

### `attendance-regularizations`  ·  web `/attendance-regularizations/web` (5 ep) vs mobile `/attendance-regularizations` (4 ep)

**Missing on mobile (1):**

- `GET /` → `Page<AttendanceRegularizationDto` (`list`)

### `attendance-settings` — ✅ identical (6 endpoints)

### `category`  ·  web `/category/web` (4 ep) vs mobile `/workCategories` (4 ep)

**Authorization model differs on 4 shared endpoints** — web uses tenant-scoped org roles, mobile uses RPT scope authorities. Example `DELETE /{id}`:

  - web: `@orgSecurity.hasAnyOrgRoleForCurrentTenant('system-admin','project-manager')`
  - mobile: `hasAuthority('category:delete') or hasAuthority('category:admin')`

### `employee`  ·  web `/employee/web` (15 ep) vs mobile `/employee` (8 ep)

**Missing on mobile (11):**

- `DELETE /employeeId/{employeeId}/manager` → `EmployeeDto` (`removeManager`)
- `DELETE /{employeeId}/roles/{role}` → `EmployeeDto` (`removeOrgRole`)
- `GET /lookup` → `List<EmployeeLookupDto` (`lookupEmployees`)
- `GET /managerId/{managerId}/subordinates` → `List<EmployeeDto` (`getDirectSubordinates`)
- `GET /managers` → `List<EmployeeDto` (`getAllTheManagers`)
- `GET /managers/organizationId/{organizationId}` → `List<EmployeeDto` (`getAllManagersForAnOrganization`)
- `GET /paginated` → `Page<EmployeeDto` (`readAllEmployeesPaginated`)
- `GET /{employeeId}/roles` → `Set<OrgRole` (`getOrgRoles`)
- `POST /joinOrganization/userId/{userId}/organizationId/{orgId}` → `EmployeeDto` (`joinOrganization`)
- `POST /{employeeId}/roles` → `EmployeeDto` (`assignOrgRole`)
- `PUT /employeeId/{employeeId}/managerId/{managerId}` → `EmployeeDto` (`assignManager`)

**Present only on mobile (4) — usually the *older* path shape:**

- `GET /organization/{id}` (`readEmployeesByOrganizationId`)
- `PATCH /batch` (`batchUpdateEmployees`)
- `POST /` (`createEmployee`)
- `POST /joinOrganization/{userId}/{orgId}` (`joinOrganization`)

**Authorization model differs on 4 shared endpoints** — web uses tenant-scoped org roles, mobile uses RPT scope authorities. Example `DELETE /{id}`:

  - web: `@orgSecurity.hasAnyOrgRoleForCurrentTenant('system-admin','hr-admin')`
  - mobile: `hasAuthority('employee:delete') or hasAuthority('employee:admin')`

### `grns`  ·  web `/grns/web` (7 ep) vs mobile `/grns` (7 ep)

**Authorization model differs on 7 shared endpoints** — web uses tenant-scoped org roles, mobile uses RPT scope authorities. Example `GET /`:

  - web: `@orgSecurity.hasAnyOrgRoleForCurrentTenant('system-admin')`
  - mobile: `hasAuthority('grn:read') or hasAuthority('grn:admin')`

### `indent-items`  ·  web `/indent-items/web` (10 ep) vs mobile `/indent-items` (10 ep)

**Authorization model differs on 10 shared endpoints** — web uses tenant-scoped org roles, mobile uses RPT scope authorities. Example `DELETE /{id}`:

  - web: `@orgSecurity.hasAnyOrgRoleForCurrentTenant('system-admin')`
  - mobile: `hasAuthority('indent-item:delete') or hasAuthority('indent-item:admin')`

### `indents`  ·  web `/indents/web` (11 ep) vs mobile `/indents` (9 ep)

**Missing on mobile (2):**

- `GET /summary` → `Page<IndentSummaryDto` (`getAllIndentSummaries`)
- `PATCH /{id}` → `IndentDto` (`UpdateAnIndent`)

**Authorization model differs on 9 shared endpoints** — web uses tenant-scoped org roles, mobile uses RPT scope authorities. Example `DELETE /{id}`:

  - web: `@orgSecurity.hasAnyOrgRoleForCurrentTenant('system-admin')`
  - mobile: `hasAuthority('indent:delete') or hasAuthority('indent:admin')`

### `inventory-transactions`  ·  web `/inventory-transactions/web` (14 ep) vs mobile `/inventory-transactions` (13 ep)

**Missing on mobile (1):**

- `GET /storage-location/{storageLocationId}/material/{materialId}/project/{projectId}` → `List<InventoryTransactionDto` (`getTransactionsByStorageLocationMaterialAndProject`)

**Authorization model differs on 13 shared endpoints** — web uses tenant-scoped org roles, mobile uses RPT scope authorities. Example `GET /`:

  - web: `@orgSecurity.hasAnyOrgRoleForCurrentTenant('system-admin')`
  - mobile: `hasAuthority('inventory-transaction:read') or hasAuthority('inventory-transaction:admin')`

### `issues`  ·  web `/issues/web` (9 ep) vs mobile `/issues` (4 ep)

**Missing on mobile (5):**

- `GET /` → `List<IssueDto` (`readAllIssues`)
- `GET /paginated` → `Page<IssueDto` (`readAllIssuesPaginated`)
- `GET /project/{projectId}` → `List<IssueDto` (`readAllIssuesOfProject`)
- `GET /stats` → `IssueStatsDto` (`readIssueStats`)
- `GET /taskId/{taskId}` → `List<IssueDto` (`readAllIssuesForTask`)

**Authorization model differs on 4 shared endpoints** — web uses tenant-scoped org roles, mobile uses RPT scope authorities. Example `DELETE /{id}`:

  - web: `@orgSecurity.hasAnyOrgRoleForCurrentTenant('system-admin','project-manager')`
  - mobile: `hasAuthority('issue:delete') or hasAuthority('issue:admin')`

### `issues/comments`  ·  web `/issues/comments/web` (5 ep) vs mobile `/issues/comments` (3 ep)

**Missing on mobile (2):**

- `GET /issueId/{issueId}` → `List<IssueCommentDto` (`getAllIssueCommentsByIssueId`)
- `GET /{id}` → `IssueCommentDto` (`getAnIssueComment`)

**Authorization model differs on 3 shared endpoints** — web uses tenant-scoped org roles, mobile uses RPT scope authorities. Example `DELETE /{id}`:

  - web: `@orgSecurity.hasAnyOrgRoleForCurrentTenant('system-admin','project-manager')`
  - mobile: `hasAuthority('issue-comment:delete') or hasAuthority('issue-comment:admin')`

### `leave-approvals`  ·  web `/leave-approvals/web` (6 ep) vs mobile `/leave-approvals` (6 ep)

**Missing on mobile (6):**

- `GET /can-approve` → `Map<String, Boolean` (`canApprove`)
- `GET /chain` → `List<LeaveApprovalDto` (`getApprovalChain`)
- `GET /history` → `List<LeaveApprovalDto` (`getApprovalHistory`)
- `POST /approve` → `LeaveRequestDto` (`approve`)
- `POST /delegate` → `LeaveRequestDto` (`delegate`)
- `POST /reject` → `LeaveRequestDto` (`reject`)

**Present only on mobile (6) — usually the *older* path shape:**

- `GET /requests/{requestId}/can-approve` (`canApprove`)
- `GET /requests/{requestId}/chain` (`getApprovalChain`)
- `GET /requests/{requestId}/history` (`getApprovalHistory`)
- `POST /requests/{requestId}/approve` (`approve`)
- `POST /requests/{requestId}/delegate` (`delegate`)
- `POST /requests/{requestId}/reject` (`reject`)

### `leave-balances`  ·  web `/leave-balances/web` (7 ep) vs mobile `/leave-balances` (7 ep)

**Missing on mobile (6):**

- `GET /` → `List<LeaveBalanceDto` (`getEmployeeBalances`)
- `GET /specific` → `LeaveBalanceDto` (`getSpecificBalance`)
- `GET /summary` → `LeaveBalanceSummaryDto` (`getBalanceSummary`)
- `GET /transactions` → `List<LeaveTransactionDto` (`getTransactionHistory`)
- `GET /transactions-by-balance` → `List<LeaveTransactionDto` (`getTransactionsByBalance`)
- `POST /recalculate` → `List<LeaveBalanceDto` (`recalculateBalances`)

**Present only on mobile (6) — usually the *older* path shape:**

- `GET /employee/{employeeId}` (`getEmployeeBalances`)
- `GET /employee/{employeeId}/policy/{policyId}` (`getSpecificBalance`)
- `GET /employee/{employeeId}/summary` (`getBalanceSummary`)
- `GET /employee/{employeeId}/transactions` (`getTransactionHistory`)
- `GET /{balanceId}/transactions` (`getTransactionsByBalance`)
- `POST /employee/{employeeId}/recalculate` (`recalculateBalances`)

### `leave-calendar`  ·  web `/leave-calendar/web` (6 ep) vs mobile `/leave-calendar` (6 ep)

**Missing on mobile (5):**

- `GET /count` → `Map<String, Long` (`getEmployeesOnLeaveCount`)
- `GET /department` → `List<LeaveCalendarDto` (`getDepartmentCalendar`)
- `GET /employee` → `List<LeaveCalendarDto` (`getEmployeeCalendar`)
- `GET /grouped` → `Map<LocalDate, List<LeaveCalendarDto` (`getCalendarGroupedByDate`)
- `GET /organization` → `List<LeaveCalendarDto` (`getOrganizationCalendar`)

**Present only on mobile (5) — usually the *older* path shape:**

- `GET /employee/{employeeId}` (`getEmployeeCalendar`)
- `GET /organization/{organizationId}` (`getOrganizationCalendar`)
- `GET /organization/{organizationId}/count` (`getEmployeesOnLeaveCount`)
- `GET /organization/{organizationId}/department` (`getDepartmentCalendar`)
- `GET /organization/{organizationId}/grouped` (`getCalendarGroupedByDate`)

**Authorization model differs on 1 shared endpoints** — web uses tenant-scoped org roles, mobile uses RPT scope authorities. Example `GET /team`:

  - web: `@orgSecurity.hasAnyOrgRoleForCurrentTenant('system-admin','hr-admin')`
  - mobile: `hasAuthority('leave:read') or hasAuthority('leave:admin')`

### `leave-policies`  ·  web `/leave-policies/web` (8 ep) vs mobile `/leave-policies` (9 ep)

**Missing on mobile (6):**

- `DELETE /deactivate` → `ApiResponse` (`deactivatePolicy`)
- `GET /employee` → `List<LeavePolicyDto` (`getApplicablePoliciesForEmployee`)
- `GET /policy` → `LeavePolicyDto` (`getPolicy`)
- `PATCH /update` → `LeavePolicyDto` (`updatePolicy`)
- `POST /activate` → `ApiResponse` (`activatePolicy`)
- `POST /duplicate` → `LeavePolicyDto` (`duplicatePolicy`)

**Present only on mobile (7) — usually the *older* path shape:**

- `DELETE /{policyId}` (`deactivatePolicy`)
- `GET /employee/{employeeId}` (`getApplicablePoliciesForEmployee`)
- `GET /organization/{organizationId}` (`getPoliciesByOrganization`)
- `GET /{policyId}` (`getPolicy`)
- `PATCH /{policyId}` (`updatePolicy`)
- `POST /{policyId}/activate` (`activatePolicy`)
- `POST /{policyId}/duplicate` (`duplicatePolicy`)

### `leave-requests`  ·  web `/leave-requests/web` (14 ep) vs mobile `/leave-requests` (13 ep)

**Missing on mobile (9):**

- `GET /approver` → `List<LeaveRequestDto` (`getRequestsByApprover`)
- `GET /employee` → `List<LeaveRequestDto` (`getEmployeeRequests`)
- `GET /employee-by-status` → `List<LeaveRequestDto` (`getEmployeeRequestsByStatus`)
- `GET /organization` → `List<LeaveRequestDto` (`getOrganizationRequests`)
- `GET /request` → `LeaveRequestDto` (`getRequest`)
- `PATCH /update` → `LeaveRequestDto` (`updateRequest`)
- `POST /cancel` → `LeaveRequestDto` (`cancelRequest`)
- `POST /employeeId/{employeeId}/submit` → `LeaveRequestDto` (`submitRequest`)
- `POST /employeeId/{employeeId}/withdraw` → `LeaveRequestDto` (`withdrawRequest`)

**Present only on mobile (8) — usually the *older* path shape:**

- `GET /employeeId/{employeeId}` (`getEmployeeRequests`)
- `GET /employeeId/{employeeId}/status/{status}` (`getEmployeeRequestsByStatus`)
- `GET /organizationId/{organizationId}` (`getOrganizationRequests`)
- `GET /requestId/{requestId}` (`getRequest`)
- `PATCH /requestId/{requestId}` (`updateRequest`)
- `POST /requestId/{requestId}/cancel` (`cancelRequest`)
- `POST /requestId/{requestId}/submit` (`submitRequest`)
- `POST /requestId/{requestId}/withdraw` (`withdrawRequest`)

### `material-consumptions`  ·  web `/material-consumptions/web` (8 ep) vs mobile `/material-consumptions` (8 ep)

**Authorization model differs on 8 shared endpoints** — web uses tenant-scoped org roles, mobile uses RPT scope authorities. Example `GET /`:

  - web: `@orgSecurity.hasAnyOrgRoleForCurrentTenant('system-admin')`
  - mobile: `hasAuthority('material-consumption:read') or hasAuthority('material-consumption:admin')`

### `materials`  ·  web `/materials/web` (13 ep) vs mobile `/materials` (12 ep)

**Missing on mobile (1):**

- `GET /summary` → `MaterialStockSummaryDto` (`getStockSummary`)

**Authorization model differs on 12 shared endpoints** — web uses tenant-scoped org roles, mobile uses RPT scope authorities. Example `DELETE /{id}`:

  - web: `@orgSecurity.hasAnyOrgRoleForCurrentTenant('system-admin')`
  - mobile: `hasAuthority('material:delete') or hasAuthority('material:admin')`

### `movement-records` — ✅ identical (4 endpoints)

### `notifications`  ·  web `/notifications/web` (5 ep) vs mobile `/notifications` (5 ep)

**Missing on mobile (1):**

- `PATCH /read` → `ApiResponse` (`markAsRead`)

**Present only on mobile (1) — usually the *older* path shape:**

- `PATCH /{notificationId}/read` (`markAsRead`)

**Authorization model differs on 4 shared endpoints** — web uses tenant-scoped org roles, mobile uses RPT scope authorities. Example `GET /`:

  - web: `@orgSecurity.hasAnyOrgRoleForCurrentTenant('system-admin','hr-admin')`
  - mobile: `hasAuthority('leave:read') or hasAuthority('leave:admin')`

### `organization`  ·  web `/organization/web` (6 ep) vs mobile `/organization` (5 ep)

**Missing on mobile (3):**

- `GET /` → `List<OrganizationDto` (`readAllOrganizations`)
- `GET /summary` → `List<OrganizationSimpleDto` (`readAllOrganizationSummaries`)
- `PATCH /{id}` → `OrganizationSimpleDto` (`partialUpdateAnOrganization`)

**Present only on mobile (2) — usually the *older* path shape:**

- `GET /creator/{creatorId}` (`readAllOrganizationsByCreatorId`)
- `PATCH /batch` (`batchUpdateOrganizations`)

**Authorization model differs on 2 shared endpoints** — web uses tenant-scoped org roles, mobile uses RPT scope authorities. Example `DELETE /{id}`:

  - web: `@orgSecurity.hasOrgRole(#id, 'system-admin')`
  - mobile: `@orgSecurity.hasOrgRole(#id, 'system-admin') or (hasAuthority('organization:delete') and @orgSecurity.isMember(#id)) or hasAuthority('organization:admin')`

### `payables`  ·  web `/payables/web` (7 ep) vs mobile `/payables` (7 ep)

**Authorization model differs on 7 shared endpoints** — web uses tenant-scoped org roles, mobile uses RPT scope authorities. Example `GET /`:

  - web: `@orgSecurity.hasAnyOrgRoleForCurrentTenant('system-admin')`
  - mobile: `hasAuthority('payable:read') or hasAuthority('payable:admin')`

### `project`  ·  web `/project/web` (12 ep) vs mobile `/project` (9 ep)

**Missing on mobile (5):**

- `GET /employees/{employeeId}` → `List<ProjectDto` (`getProjectsByEmployeeId`)
- `GET /paginated` → `Page<ProjectDto` (`readAllProjectsPaginated`)
- `GET /summary` → `Page<ProjectSummaryDto` (`readAllProjectSummaries`)
- `GET /{id}/status-history` → `Page<StatusTransitionDto` (`readStatusHistory`)
- `PATCH /{id}` → `ProjectSimpleDto` (`partialUpdateAProject`)

**Present only on mobile (2) — usually the *older* path shape:**

- `GET /{id}/organization` (`getOrganizationIdByProjectId`)
- `PATCH /batch` (`batchUpdateProjects`)

**Signature divergence:**

- `GET /`
    - params — web `(none)`
    - params — mobile `@Valid @ParameterObject PageQuery pageQuery`

**Authorization model differs on 7 shared endpoints** — web uses tenant-scoped org roles, mobile uses RPT scope authorities. Example `DELETE /{id}`:

  - web: `@orgSecurity.hasAnyOrgRoleForCurrentTenant('system-admin','project-manager')`
  - mobile: `hasAuthority('project:delete') or hasAuthority('project:admin')`

### `project/{projectId}/wbs` — ✅ identical (10 endpoints)

### `purchase-order-items`  ·  web `/purchase-order-items/web` (8 ep) vs mobile `/purchase-order-items` (8 ep)

**Missing on mobile (1):**

- `PATCH /` → `PurchaseOrderItemResponseDto` (`updatePurchaseOrderItem`)

**Present only on mobile (1) — usually the *older* path shape:**

- `PUT /` (`updatePurchaseOrderItem`)

### `purchase-orders`  ·  web `/purchase-orders/web` (10 ep) vs mobile `/purchase-orders` (9 ep)

**Missing on mobile (1):**

- `GET /{id}/status-history` → `Page<StatusTransitionDto` (`readStatusHistory`)

### `shift-timings` — ✅ identical (5 endpoints)

### `site-transfers`  ·  web `/site-transfers/web` (11 ep) vs mobile `/site-transfers` (10 ep)

**Missing on mobile (1):**

- `GET /{id}/status-history` → `Page<StatusTransitionDto` (`readStatusHistory`)

**Authorization model differs on 10 shared endpoints** — web uses tenant-scoped org roles, mobile uses RPT scope authorities. Example `GET /`:

  - web: `@orgSecurity.hasAnyOrgRoleForCurrentTenant('system-admin')`
  - mobile: `hasAuthority('site-transfer:read') or hasAuthority('site-transfer:admin')`

### `storage-locations`  ·  web `/storage-locations/web` (8 ep) vs mobile `/storage-locations` (6 ep)

**Missing on mobile (2):**

- `DELETE /{id}` → `ApiResponse` (`deleteStorageLocation`)
- `PATCH /{id}` → `StorageLocationDto` (`updateStorageLocation`)

**Authorization model differs on 6 shared endpoints** — web uses tenant-scoped org roles, mobile uses RPT scope authorities. Example `GET /`:

  - web: `@orgSecurity.hasAnyOrgRoleForCurrentTenant('system-admin','project-manager')`
  - mobile: `hasAuthority('storage-location:read') or hasAuthority('storage-location:admin')`

### `tasks`  ·  web `/tasks/web` (8 ep) vs mobile `/tasks` (5 ep)

**Missing on mobile (3):**

- `GET /paginated` → `Page<TaskDto` (`readAllTasksPaginated`)
- `GET /projectId/{projectId}` → `List<TaskDto` (`readAllTasksForProject`)
- `PATCH /{id}` → `TaskSimpleDto` (`partialUpdateATask`)

**Signature divergence:**

- `GET /`
    - params — web `(none)`
    - params — mobile `@Valid @ParameterObject PageQuery pageQuery`

**Authorization model differs on 5 shared endpoints** — web uses tenant-scoped org roles, mobile uses RPT scope authorities. Example `DELETE /{id}`:

  - web: `@orgSecurity.hasAnyOrgRoleForCurrentTenant('system-admin','project-manager')`
  - mobile: `hasAuthority('task:delete') or hasAuthority('task:admin')`

### `user`  ·  web `/user/web` (7 ep) vs mobile `/user` (6 ep)

**Missing on mobile (1):**

- `GET /employees` → `List<EmployeeDto` (`getEmployeesForCurrentUser`)

**Signature divergence:**

- `GET /`
    - params — web `(none)`
    - params — mobile `JwtAuthenticationToken authenticationToken`
- `PATCH /{id}`
    - params — web `@Parameter(schema = @Schema(implementation = UserUpdateFieldsDto.class)) @RequestPart(value = "data", required = false) String data; @PathVariable Long id; @RequestParam(value = "profilePicture", required = false) MultipartFile profilePicture; @RequestParam(value = "cv", required = false) MultipartFile cv`
    - params — mobile `@io.swagger.v3.oas.annotations.parameters.RequestBody( content = @Content(schema = @Schema(implementation = UserUpdateFieldsDto.class))) @RequestBody Map<String, Object> updates; @PathVariable Long id`

### `vendors`  ·  web `/vendors/web` (23 ep) vs mobile `/vendors` (23 ep)

**Authorization model differs on 23 shared endpoints** — web uses tenant-scoped org roles, mobile uses RPT scope authorities. Example `DELETE /{id}`:

  - web: `@orgSecurity.hasAnyOrgRoleForCurrentTenant('system-admin')`
  - mobile: `hasAuthority('vendor:delete') or hasAuthority('vendor:admin')`


---

## 5. Naming and routing inconsistencies

Small things, but they break any tooling that infers the pair from the path (ours does, and so would a generated SDK):

| Path | Class | Problem |
|---|---|---|
| `/api/v1/chat` | `ChatControllerWeb` | Class says web, path says mobile. 12 endpoints. Which is it? |
| `/api/v1/inspections/web/compliance` | `ComplianceControllerWeb` | `/web` is **infixed**, not suffixed — breaks the `<base>` + `/web` convention. Should be `/api/v1/inspections/compliance/web`. |
| `/api/v1/invitation/web` | `ProjectInviteCodeController` | Web path, no `Web` suffix on the class. |
| `/api/v1/search/web` | `SearchController` | Same. |
| `/api/v1/keycloakGroup/web` | `KeycloakGroupController` | Same. |
| `/api/v1/billing/{features,plans,subscriptions}/web` | `FeatureController`, `PlanController`, `SubscriptionController` | Same. |
| `api/v1/workCategories` | `CategoryController` | Mobile twin of `/api/v1/category/web` — **different resource name on each side**, and camelCase where everything else is kebab-case. |
| `api/v1/keycloak`, `api/v1/workCategories` | — | `@RequestMapping` missing the **leading slash** (works, but inconsistent). |

**Ask:** rename `workCategories` → `/api/v1/categories` (or rename the web side to `/api/v1/work-categories/web`) so the pair is derivable. The rest are cosmetic — flagging so they get fixed while the file is open.

---

## 6. Missing: the module-activation endpoint

`MODULE_ARCHITECTURE.md` and the web-side plan describe `GET/POST/DELETE /api/v1/core/modules` plus a `ModuleGuardInterceptor` for per-org module installation. **No controller in the repo maps `core/modules`** — it is not built yet.

We are shipping iOS v1 with a static feature set. **Ask:** tell us when that endpoint lands and what the manifest payload looks like, so the app gates features the same way web will rather than inventing its own scheme.

---

## 7. Keycloak configuration asks

Not controller issues, but needed before iOS can call anything:

1. **New public client `echno-ios`** in realm `echno-realm`: PKCE (S256) required, redirect URI `com.tornotron.echno-ios://oauth/callback`, refresh tokens enabled, standard flow only.
2. **`KEYCLOAK_BACKEND_CLIENT`** — `jwt.auth.converter.resource-id` names a single client, and `extractResourceRoles` only reads `resource_access[<that client>].roles`. Confirm the mobile token will carry roles under that same client (audience mapper), otherwise every resource role silently disappears for iOS.
3. **Group/org authorities** — confirm `ORG_MEMBER_<id>` and org-role group authorities are emitted into the mobile client's tokens too. `TenantFilter` and every `@orgSecurity.*` check depend on them.
4. **Token lifetimes** — mobile sessions should outlive web's. Current access/refresh TTLs and whether a separate client can have its own.

---

## 7b. OpenAPI document — blockers for client code generation

The iOS client generates its wire layer from `echno-backend/docs/openapi.json` with
`swift-openapi-generator`. The document is in good shape overall — OpenAPI 3.1.0, 557 paths,
737 operations, 315 schemas, every operation carrying an `operationId`, `bearerAuth` declared,
and `OpenApiSnapshotTest` holding the committed copy to what the code serves. Two things stop
it being usable as-is.

### 🔴 Duplicate root tags — generation fails outright

```
Error: Failed to satisfy: The names of Tags in the Document are unique at root of document
```

Twenty-six controller pairs suffix the web tag with `(Web)`. Six do not, so the same tag name
is declared twice at the document root:

| Tag | Declared by |
|---|---|
| `Employees` | `EmployeeController` **and** `EmployeeControllerWeb` |
| `Issues` | `IssueController` **and** `IssueControllerWeb` |
| `Issue Comments` | `IssueCommentController` **and** `IssueCommentControllerWeb` |
| `Projects` | `ProjectController` **and** `ProjectControllerWeb` |
| `Tasks` | `TaskController` **and** `TaskControllerWeb` |
| `Users` | `UserController` **and** `UserControllerWeb` |

Six one-line edits. Beyond unblocking generation, a shared tag also makes the two controller
families indistinguishable when filtering the document by tag — which is how the client
generates one module at a time.

### 🟠 Missing `required` — every generated property becomes optional

205 of 315 object schemas, **185 of them DTOs**, have no `required` array. In OpenAPI that means
every property may be absent, so the generator is correct to emit:

```swift
public struct AttendanceResponseDto: Codable, Hashable, Sendable {
    public var id: Swift.Int64?              // never null on any row
    public var employeeName: Swift.String?   // never null on any row
}
```

The client can absorb this in a mapping layer, and will — but it means the contract does not
currently distinguish "may legitimately be null" from "nobody said". That is the same gap
issue #645 closed for nullability: `NullableSchemaCustomizer` plus `OpenApiNullabilityTest` now
guarantee that an annotated field is described as nullable. The complement — that a field which
is *not* nullable is described as `required` — would make the document self-describing for any
generated client, in any language.

Worth noting the asymmetry: guessing wrong in this direction is safe (an unnecessary optional),
guessing wrong in the other is a runtime decode failure. So the client will not infer `required`
from the absence of a null union; it needs the backend to say so.

## 8. Consolidated ask list

| # | Ask | Priority | Effort |
|---|---|---|---|
| 1 | Migrate 20 mobile controllers from `hasAuthority(...)` to `@orgSecurity.*`, matching each `/web` twin (168 endpoints) | 🔴 P0 | Mechanical; `leave-*` shows the pattern |
| 2 | Rename `check-in` multipart part `photoUrl` → `photo` on `/api/v1/attendance` | 🔴 P0 | One line |
| 3 | Exempt `/api/v1/user` in `TenantFilter.preTenantReason()` (or specify the mobile bootstrap sequence) | 🔴 P0 | One line |
| 4 | Add `GET /api/v1/user/employees` (mobile twin of the web endpoint) | 🔴 P0 | Small |
| 5 | Create Keycloak client `echno-ios`; confirm items in §7 | 🔴 P0 | Config |
| 6 | Add mobile controller for `attachment` (6 endpoints) | 🔴 P0 | Medium |
| 7 | Align `PATCH /user/{id}` on mobile to the web multipart shape (profile picture + CV) | 🟠 P1 | Small |
| 8 | Decide one pagination convention for `project` / `tasks` collection endpoints | 🟠 P1 | Decision |
| 9 | Backfill the 73 web-only operations on paired mobile controllers (see §4.4) | 🟠 P1 | Per module |
| 10 | Decide path shape for `leave-*`, `employee`, `purchase-order-items` and converge | 🟡 P2 | Decision |
| 11 | Mobile controllers for `labour`, `stock-adjustments`, `expenses`, `invitation`, `search` | 🟡 P2 | Per module |
| 12 | Rename `workCategories` → `categories`; fix leading slashes and `Web` class-name suffixes | 🟡 P3 | Cosmetic |
| 13 | Confirm `/web` is acceptable for iOS to call for `finance/*`, `inspections`, `billing` | 🟡 P3 | Decision |
| 14 | Clarify `organization:admin` global tenant bypass (§1) | 🟡 P3 | Decision |
| 15 | Timeline + manifest shape for `GET /api/v1/core/modules` | 🟡 P3 | Info |
| 16 | **Rename the web-side `@Tag` on 6 controllers to `… (Web)`** — `EmployeeControllerWeb`, `IssueControllerWeb`, `IssueCommentControllerWeb`, `ProjectControllerWeb`, `TaskControllerWeb`, `UserControllerWeb` all declare the same tag name as their mobile twin | 🔴 P0 | 6 one-line changes |
| 17 | **Mark non-nullable schema fields `required`** — 205 of 315 object schemas (185 DTOs) carry no `required` list | 🟠 P1 | Extends the #645 customizer |
| 18 | Publish `docs/openapi.json` as a CI artifact, or confirm clients may vendor it from the repo | 🟡 P2 | Config |

**Items 1–6 are what unblock the iOS client.** Everything below that is sequencing.

---

## Appendix — how to reproduce

Every count in this report comes from parsing `@RequestMapping` / `@{Get,Post,Put,Patch,Delete}Mapping` / `@PreAuthorize` annotations across all 100 controllers and diffing the 32 `<base>` ↔ `<base>/web` pairs by `(verb, path)`. Nothing was sampled or estimated.

Pairing rule: a controller at `/api/v1/x/web` is paired with one at `/api/v1/x`. Unpaired-mobile results (`auth`, `chat`, `generate-report`, `keycloak`, `inspections/web/compliance`) are all explained in §5 — none is a genuine mobile-only surface.
