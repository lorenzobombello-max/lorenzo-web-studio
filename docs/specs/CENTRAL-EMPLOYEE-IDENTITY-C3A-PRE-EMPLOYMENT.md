# Central Employee Identity C3A - Pre-employment reservation

Status: implemented and proven locally; not applied to production.

## Two identity layers

`employee_identity_reservations` owns permanent human-facing identity before formal employment. A row in this table does not establish employment, attendance readiness, payroll readiness, an auth account, or an Operator capability.

`workforce_employees` remains the formal employment authority. Its existing `start_date not null` rule is unchanged. Calendar and Workforce continue to use `workforce_employees.id` as canonical employee UUID.

## Reserved identities

| Employee number | Display name | Identity status | Workforce employee |
| --- | --- | --- | --- |
| `LWS-00001` | Lorenzo Bombello | `PRE_EMPLOYMENT` | `NULL` |
| `LWS-00002` | Herlinde Verlodt | `PRE_EMPLOYMENT` | `NULL` |
| `LWS-00003` | Daisy Defraine | `PRE_EMPLOYMENT` | `NULL` |

The general allocator starts at `LWS-00004`.

## Number allocation

`employee_identity_number_seq` is the concurrency-safe numeric authority. Allocation does not inspect row order and does not use `MAX + 1`. Sequence gaps are valid; allocated numbers are never recycled.

`reserve_employee_identity_v1` atomically creates:

1. one `PRE_EMPLOYMENT` reservation with a server-generated identity UUID;
2. one final `employee_number_allocation_ledger` row for the same UUID and number.

The allocation ledger is append-only. Its employee identity and employee number are protected by a composite foreign key to prevent mismatched evidence.

## Workforce activation

`activate_workforce_employee_identity_v1` requires a real start date and a valid existing Workforce employment status. In one database transaction it:

1. locks an unactivated reservation;
2. creates one `workforce_employees` row with a server-generated UUID;
3. binds that UUID to the reservation and changes its status to `ACTIVATED`;
4. writes one append-only activation event containing the permanent employee number and exact Workforce UUID.

Any failure rolls back the complete statement. An activated reservation cannot be rebound through normal database mutation.

The three owner identities are not activated by C3A. The only valid start date used by tests belongs to a clearly marked test identity and is rolled back.

## Runtime authority

C3A grants neither reservation nor activation execution to `anon`, `authenticated`, or `service_role`. The functions are database foundations for a later owner-approved authority route. Existing auth policies are unchanged.

No `commercial_operator_id`, auth account, or Operator profile is assigned. Future `OP-01` through `OP-15` capability preparation remains independent from employee number, employment status, and login identity.

## Compatibility

Pre-employment reservations have no `workforce_employees` row and therefore cannot appear in Calendar, Workforce Personnel, attendance, or payroll projections. After valid activation, existing Calendar and Workforce RPCs discover the created employee through the unchanged `workforce_employees.id` UUID contract. No DTO or runtime file changes in C3A.