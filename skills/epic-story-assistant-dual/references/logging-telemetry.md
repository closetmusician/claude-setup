# Logging / Telemetry — mandatory section format

Every new feature in both archetypes includes this section. Format follows BCLOUD-12164 §9. It is distinct from **product Analytics** (Amplitude usage events): logging/telemetry is about traceability and system-of-record auditability, not product-usage questions.

## Two logs, split explicitly

**Activity logging (customer-facing).** Customer-visible traceability/reporting. Surfaced in the product's Activity Logs / reporting experience (often as "Security changes"). Applies to changes that affect a customer user's effective access/configuration, from all originating surfaces (e.g. Self-Service and CSP).

**Audit logging (system / backend trace).** System-of-record auditability per the company Logging & Monitoring Standard, even where the customer-facing view has different retention/formatting/access. Applies to provisioning-at-creation, edits, approvals (if that's when a value is first persisted), and lifecycle/removal actions.

Give each its own purpose/applies-to/fields block, side by side.

## Company Logging & Monitoring Standard (reference in the section)
- Minimum fields: user identity with org/tenant ID, date/time, event type, success/failure, origin, affected-resource identity, event details.
- **Actor and target are logged by ID, never display name.** Names, phone numbers, session identifiers, and access tokens must never appear in logs.
- Minimum retention: 13 months on a centralized authorized logging device; most recent 3 months immediately queryable.

## §.1 Field-level data dictionary
One row per field, marking which log(s) it appears in and whether it's a fixed enum or dynamic.

| Field | Appears in | Value type | Fixed values | Format / notes |
|-------|------------|------------|--------------|----------------|
| `event_name` | Audit | fixed enum | see canonical events | |
| `feature_name` | Activity, Audit | fixed enum | e.g. `user_features_export` | registry allows future values |
| `action` | Activity | fixed enum | `enabled` / `disabled` | derived from before/after |
| `source_system` | Activity, Audit | fixed enum | `Self-Service` / `CSP` | which surface initiated |
| `actor_type` | Audit | fixed enum | `system` / role | `system` only for automated events |
| `outcome` | Audit | fixed enum | `success` / `failure` | |
| `reason` | Audit | fixed enum, conditional | `validation_error` / `permission_denied` / `backend_error` | blank if success |
| `actor_id` | Activity, Audit | dynamic | — | ID only, never display name |
| `target_user_id` | Activity, Audit | dynamic | — | ID only |
| `organization_id` | Activity, Audit | dynamic | — | tenant/org — required by standard |
| `before_value` / `after_value` | Activity, Audit | dynamic | | the payload |
| `timestamp` | Activity, Audit | dynamic | — | ISO 8601, UTC |
| `correlation_id` | Activity, Audit | dynamic | — | joins the Activity and Audit entries for the same change |

Flag any field the company standard requires that's currently missing (e.g. `organization_id` absent from Activity), and any field whose existence needs engineering confirmation (e.g. a separate `event_origin`), as open gaps.

## §.2 Canonical event names
| Event name | Fires when | Log(s) |
|------------|------------|--------|
| [Entity Created] | [condition] | Activity + Audit |
| [Entity Updated] | [edit saved] | Activity + Audit |
| [Entity Permissions/Value Revoked (lifecycle)] | [force-revoke on removal] | Activity + Audit |

Each canonical event should map back to the FR(s) that fire it (traceability check).
