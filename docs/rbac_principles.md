# Snowflake EDW Setup — Best Practices

Documented from `001_build_all.sql` and `002_teardown_all.sql`.

---

## 1. Parameterised Naming Convention

All object names are derived from a small set of parameters in a single `SECTION 0` block.
No hard-coded names appear anywhere else in the scripts.

```sql
SET beNm  = 'SNOW';   -- Business entity
SET evNm  = 'D';      -- Environment: D | T | P
SET dpNm  = '';       -- Data product (blank = shared core EDW)

SET prefixNm = $beNm || IFF($evNm='','','_'||$evNm) || IFF($dpNm='','','_'||$dpNm);
-- Result: SNOW_D
```

**Why it matters:** A single edit deploys consistently named objects across dev, test, and production. It also prevents copy-paste errors when cloning environments.

**Naming patterns used:**

| Object type | Pattern | Example |
|---|---|---|
| Functional role | `{PREFIX}_{TIER}` | `SNOW_D_ADMIN` |
| Warehouse | `{PREFIX}_{WORKLOAD}` | `SNOW_D_ADHOC` |
| WH access role | `_WH_{O\|U}_{WAREHOUSE}` | `_WH_O_SNOW_D_ADHOC` |
| Database | `{PREFIX}_{ZONE}` | `SNOW_D_RAW` |
| DB role | `DB_{R\|W\|C}` | `DB_C` |
| Schema access role | `SC_{R\|W\|C}_{SCHEMA}` | `SC_R_TPCH` |

> The underscore prefix on warehouse access roles (`_WH_O_`, `_WH_U_`) is a deliberate convention to visually distinguish access roles (technical, never assigned directly to users) from functional roles.

---

## 2. Two-Layer Role Architecture

Roles are split into two distinct categories that are never mixed.

### Functional Roles — "what job can you do?"
Assigned to humans and service accounts, typically via IdP/SCIM group mapping.

```
SYSADMIN
  └── SNOW_D_ADMIN    (Delegated Admin — full control of this environment)
        └── SNOW_D_DEPLOY  (Deploy Admin — create and modify objects)
              └── SNOW_D_WRITE   (Data Engineering — write data, operate pipelines)
                    └── SNOW_D_READ    (Read-only access)
```

### Access Roles — "what object can you touch?"
Technical privilege containers wired to specific objects. Never assigned directly to users.

- Warehouse access roles: `_WH_O_*`, `_WH_U_*`
- Database roles: `DB_C`, `DB_W`, `DB_R`
- Schema access roles: `SC_C_*`, `SC_W_*`, `SC_R_*`

**Why it matters:** Functional roles remain stable as the access layer evolves. Adding a new schema or warehouse only requires wiring new access roles — functional role assignments to users do not change.

---

## 3. Principle of Least Privilege

Every role is granted only the minimum privileges required for its tier.

### Warehouse — Usage vs. Operate split

| Role | Privileges | Granted to |
|---|---|---|
| `_WH_U_*` | `MONITOR`, `USAGE` | `SNOW_D_READ` |
| `_WH_O_*` | `OPERATE`, `MODIFY` + inherits `_WH_U_*` | `SNOW_D_WRITE`, `SNOW_D_DEPLOY` |

Read-only users can run queries but cannot resize, suspend, or resume the warehouse.

### Schema — Read / Write / Create split

| Role | Privileges | Granted to |
|---|---|---|
| `SC_R_*` | `SELECT` on tables, views, dynamic tables, materialised views; `USAGE` on functions | `DB_R` → `SNOW_D_READ` |
| `SC_W_*` | `INSERT`, `UPDATE`, `DELETE`, `TRUNCATE`; `OPERATE` on tasks, dynamic tables, alerts; `READ/WRITE` on stages | `DB_W` → `SNOW_D_WRITE` |
| `SC_C_*` | `CREATE TABLE/VIEW/STREAM/FUNCTION/PROCEDURE/TASK/STAGE/PIPE/...` | `DB_C` → `SNOW_D_DEPLOY` |

DDL (schema changes) are deliberately separated from DML (data changes): a `WRITE` user cannot create or drop objects.

### Account-level grants scoped to the minimum required tier

```sql
GRANT EXECUTE TASK        ON ACCOUNT           TO ROLE IDENTIFIER($afrWrite);
GRANT IMPORTED PRIVILEGES ON DATABASE SNOWFLAKE TO ROLE IDENTIFIER($afrWrite);
```

These are granted to `WRITE`, not `DEPLOY` or `ADMIN`, because pipeline engineers need them but not schema deployers.

---

## 4. Ownership Separation

Ownership is split to reflect operational responsibility:

| Owner | Objects owned | Reason |
|---|---|---|
| `SECURITYADMIN` | Functional roles (ADMIN, DEPLOY, WRITE, READ) | IdP/SCIM manages group-to-role mapping; security team controls access grants |
| `SNOW_D_ADMIN` | Warehouse, WH access roles, databases, DB roles, schema access roles | Delegated admin manages all environment infrastructure |

Ownership is always transferred explicitly with `COPY CURRENT GRANTS` to preserve existing grants during the handover:

```sql
GRANT OWNERSHIP ON ROLE IDENTIFIER($afrAdmin) TO ROLE IDENTIFIER($scimRl) COPY CURRENT GRANTS;
```

---

## 5. Future Grants

Every privilege grant is paired with a `FUTURE` counterpart to cover objects created after the schema is set up.

```sql
GRANT SELECT ON ALL TABLES    IN SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarR);
GRANT SELECT ON FUTURE TABLES IN SCHEMA IDENTIFIER($scNm) TO DATABASE ROLE IDENTIFIER($sarR);
```

**Why it matters:** Without `FUTURE` grants, every new table, view, or task requires a manual privilege grant. With them, new objects are automatically accessible to the correct roles the moment they are created.

---

## 6. Managed Access Schemas

All schemas are created with `WITH MANAGED ACCESS`:

```sql
CREATE SCHEMA IF NOT EXISTS IDENTIFIER($scNm) WITH MANAGED ACCESS COMMENT = $scComment;
```

**Why it matters:** In a standard schema, the schema owner can grant privileges to any role. Managed access centralises privilege management — only the schema owner or `SECURITYADMIN` can grant object privileges, preventing privilege creep by individual developers.

---

## 7. Three-Zone Data Architecture

Databases are partitioned into three zones reflecting the data lifecycle:

| Zone | Database | Purpose |
|---|---|---|
| **RAW** | `SNOW_D_RAW` | Source data landed as-is; no transformations |
| **INT** | `SNOW_D_INT` | Transformed, conformed, and integrated data |
| **PRES** | `SNOW_D_PRES` | Analytics-ready, consumer-facing data |

Each zone is an independent database with its own role set, allowing different retention policies, access controls, and cost attribution per zone.

---

## 8. Warehouse Configuration Defaults

```sql
CREATE WAREHOUSE IF NOT EXISTS IDENTIFIER($whNm) WITH
    WAREHOUSE_SIZE               = XSMALL
    INITIALLY_SUSPENDED          = TRUE
    AUTO_RESUME                  = TRUE
    AUTO_SUSPEND                 = 60
    STATEMENT_TIMEOUT_IN_SECONDS = 1800
```

| Setting | Value | Reason |
|---|---|---|
| `INITIALLY_SUSPENDED` | `TRUE` | No credits consumed until first query |
| `AUTO_RESUME` | `TRUE` | Transparent to end users |
| `AUTO_SUSPEND` | `60s` | Minimises idle credit burn |
| `STATEMENT_TIMEOUT_IN_SECONDS` | `1800` (30 min) | Prevents runaway queries from consuming credits indefinitely |
| `WAREHOUSE_SIZE` | `XSMALL` | Start small; resize up deliberately rather than defaulting large |

---

## 9. Removal of the Default PUBLIC Schema

```sql
DROP SCHEMA IF EXISTS PUBLIC;
```

Snowflake creates a `PUBLIC` schema in every new database. It is dropped immediately to prevent objects from being accidentally created in an uncontrolled, ungoverned schema.

---

## 10. Time Travel

All databases are created with 7 days of time travel:

```sql
DATA_RETENTION_TIME_IN_DAYS = $timetravelDays   -- 7
```

This allows point-in-time queries and object restoration for a full week, balancing recovery capability against storage cost.

---

## 11. Repeatable, Templated Structure

The schema block is identical for every schema across all three databases — only the `SET` lines at the top change. This makes the pattern:

- Easy to review (same structure every time)
- Safe to extend (copy a block, change the `SET` lines)
- Consistent (no one-off privilege variations per schema)

The same principle applies to the teardown script, which mirrors the setup script in exact reverse creation order.

---

## 12. Preview Before Execute

Each destructive or significant operation is preceded by a `SELECT` that previews the derived names before any object is created or dropped:

```sql
SELECT
    $prefixNm  AS "Prefix"
  , $afrAdmin  AS "ADMIN Role"
  , $afrDeploy AS "DEPLOY Role"
  , $whNm      AS "Warehouse"
  ...
```

**Why it matters:** Running the `SELECT` first in an interactive session lets the operator verify the computed names are correct before committing to object creation or deletion.

---

## 13. Paired Setup and Teardown Scripts

`001_build_all.sql` and `002_teardown_all.sql` share identical `SECTION 0` parameters. The teardown drops objects in the exact reverse of the creation order:

```
Teardown order:  PRES → INT → RAW → Warehouse → WH access roles → Functional roles
Setup order:     Functional roles → Warehouse → WH access roles → RAW → INT → PRES
```

This prevents foreign-key and dependency errors and ensures the environment can be fully recreated from a clean state.
