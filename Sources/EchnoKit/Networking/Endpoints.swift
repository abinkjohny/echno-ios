import Foundation

/// The one place that decides whether a module calls the backend's **mobile**
/// controller (`/api/v1/<x>`) or its **web** controller (`/api/v1/<x>/web`).
///
/// ## Why this is centralised
///
/// The backend exposes both for 32 domains. They are not interchangeable today:
///
/// - 20 mobile controllers (168 endpoints) authorize with
///   `hasAuthority('<resource>:<scope>')`, which reads a claim present only in
///   a Keycloak **RPT**, not in the token a PKCE flow issues. Those endpoints
///   return **403** to this app.
/// - 73 operations exist on web but not on mobile, and 42 mobile endpoints put
///   the same operation at a different path.
///
/// So the app calls `/web` by default and moves each module to its mobile twin
/// as the backend migrates that twin to `@orgSecurity.*`. Flipping one module
/// is a one-line change here.
///
/// The full analysis is in `local-docs/backend-mobile-api-gaps.md`.
public enum Endpoints {

    /// Which controller family a module's requests go to.
    public enum Family: Sendable {
        /// `/api/v1/<base>/web` — tenant-scoped, works with a normal token.
        case web
        /// `/api/v1/<base>` — the mobile controller, once it has been migrated.
        case mobile
    }

    /// Modules cleared to use their mobile controller.
    ///
    /// A module belongs here only once its mobile controller authorizes with
    /// `@orgSecurity.*` **and** its endpoint set matches what the app calls.
    /// Verified against the backend at the commit noted in the port log —
    /// re-check when the backend team confirms a migration.
    private static let mobileReady: Set<String> = [
        // Migrated to @orgSecurity and endpoint-compatible.
        "attendance",
        "attendance-regularizations",
        "attendance-settings",
        "shift-timings",
        "movement-records",
        "project/{projectId}/wbs",

        // Migrated, but check the per-module notes in the gap report first:
        // "leave-requests", "leave-balances", "leave-policies" differ in path
        //   shape from their web twins (§4.3) — port against one and stay there.
        // "user" is migrated but /api/v1/user is not tenant-exempt the way
        //   /api/v1/user/web is (§2), which breaks multi-org bootstrap.
        // "purchase-orders", "purchase-order-items" are migrated but each is
        //   missing an endpoint the app will want.
    ]

    /// The family to use for `base`, e.g. `"materials"` or `"leave-requests"`.
    public static func family(for base: String) -> Family {
        mobileReady.contains(base) ? .mobile : .web
    }

    /// Builds a path for `base`, choosing the family automatically.
    ///
    /// ```swift
    /// Endpoints.path("materials", "/low-stock")  // "materials/web/low-stock"
    /// Endpoints.path("attendance", "/check-in")  // "attendance/check-in"
    /// ```
    public static func path(_ base: String, _ suffix: String = "") -> String {
        let root = family(for: base) == .mobile ? base : "\(base)/web"
        guard !suffix.isEmpty else { return root }
        return suffix.hasPrefix("/") ? "\(root)\(suffix)" : "\(root)/\(suffix)"
    }
}
