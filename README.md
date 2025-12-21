# Task 1: View vs Table Materialization

## Overview
This demo compares **view** and **table** materializations in dbt using Snowflake's sample dataset (150k customer records).

### Model: `models/materialization_demo.sql`

```sql
{{ config(materialized='table') }}  -- {{ config(materialized='view') }} for view

with src as (
    select * from SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.CUSTOMER  -- 150k rows
),
agg as (
    select
        c_nationkey,
        count(*) as customer_count,
        avg(c_acctbal)::decimal(12,2) as avg_balance
    from src
    group by c_nationkey
)

select * from agg  -- 25 rows result
```

---

## Experiment Results (Dec 12, 2025)

| Materialization | Warehouse | Build Time | Bytes Written | Rows Written | Object Created |
|-----------------|-----------|------------|---------------|--------------|----------------|
| **view** | — | 181 ms | 0 B | 0 | `materialization_demo_view` |
| **table** | X-Small | 1.2 s | ~28 KB | 25 | `materialization_demo_table` |

---

## Recommendations for use

| Use Case | Choose | Reason |
|----------|--------|--------|
| Frequently queried + expensive logic | **table** | Fast & predictable reads |
| Small/intermediate model | **view** | Zero storage, always fresh |
| Needs real-time data | **view** | Always sees latest source data |
| Used in dashboards / BI tools | **table** | Consistent performance for end users |
| Large joins + repeated downstream use | **table** | Much faster subsequent queries |

---

## Key Findings

### Table Materialization ✅
- **Build cost:** 1.2s once (during `dbt run`)
- **Query cost:** ~50ms every time (reads stored data)
- **Storage:** ~28 KB (negligible for this size)
- **Best for:** Production models queried frequently

### View Materialization ⚠️
- **Build cost:** 181ms (just creates SQL definition)
- **Query cost:** ~150ms every time (recomputes aggregation)
- **Storage:** 0 B
- **Best for:** Lightweight transformations, always-fresh data

### Performance Math
If queried 100 times:
- **Table:** 1.2s build + (100 × 0.05s) = 6.2s total
- **View:** 0.18s build + (100 × 0.15s) = 15.18s total

**Table is 2.4× faster** for frequently accessed models.
---

## Conclusion
**Default to `table` materialization** for:
- Mart/analytics models
- Models used in BI tools
- Any model queried more than a few times per day

**Use `view` for:**
- Staging models (simple renaming/casting)
- Models that must reflect real-time source changes
- Intermediate steps in complex pipelines
---

# Task 2: Incremental Orders Model

## Overview
Incremental model that processes only new/updated records from TPCH ORDERS dataset.

## Configuration

```sql
{{ config(
    materialized='incremental',
    unique_key='order_key',
    incremental_strategy='merge'
) }}
```

- **Source:** `SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS`
- **Strategy:** Merge (updates existing, inserts new)
- **Records:** 1.5M rows

## Incremental Logic

```sql
{% if is_incremental() %}
    where o_orderdate > (select max(order_date) from {{ this }})
{% endif %}
```

- **First run:** Loads all data (full load)
- **Subsequent runs:** Only new records after max date
- **`{{ this }}`:** References current model table

## Handling Late-Arriving Data

### Problem
Orders updated after initial load are missed because `order_date` doesn't change:
```
Day 1: Order created (status: 'pending')
Day 2: ETL loads order
Day 3: Order updated (status: 'shipped') ← Missed!
```

### Solution: Lookback Period

```sql
{% if is_incremental() %}
    where o_orderdate >= (
        select dateadd(day, -3, max(order_date)) 
        from {{ this }}
    )
{% endif %}
```

**How it works:**
- Reprocess last 3 days of data on each run
- Merge strategy updates changed records via `unique_key`

**Trade-off:** Reprocesses some unchanged data for guaranteed freshness

### Alternative Approaches

| Method | Accuracy | Performance | Complexity |
|--------|----------|-------------|------------|
| Lookback Period | Good | Fast | Simple |
| `updated_at` field | Excellent | Fastest | Medium |
| Full Refresh Weekly | Perfect | Slow | Simple |


# Task 3: Ephemeral Models and Ref Chains

## Overview
This pipeline demonstrates ephemeral materialization in dbt, where intermediate transformations are compiled as CTEs rather than physical database objects.

## Pipeline Architecture

```
orders (source)
    ↓
stg_orders (view)
    ↓
int_orders_with_status (ephemeral) 👻
    ↓
int_orders_enriched (ephemeral) 👻
    ↓
fct_orders (table)
```

**Key Point:** The two intermediate models don't exist in the database - they're inlined as CTEs in the final model's SQL.

---

## Benefits of Ephemeral Models

| Benefit | Explanation |
|---------|-------------|
| **Clean Database** | No clutter from intermediate transformations |
| **Modular Code** | Each model has single responsibility, easy to maintain |
| **No Permission Issues** | Ephemeral models don't exist, so no access control needed |
| **Single Query Execution** | All logic runs in one optimized query |
| **Version Control Friendly** | Changes are self-contained in model files |

---

## Limitations of Ephemeral Models

| Limitation | Impact | Mitigation |
|------------|--------|------------|
| **Can't query directly** | `SELECT * FROM int_orders_enriched` fails | Change to `view` for debugging |
| **Code duplication** | If referenced by >1 model, CTE is duplicated | Use `view` for shared models |
| **Harder debugging** | Can't inspect intermediate results | Temporarily materialize as view |
| **Large CTE performance** | Complex ephemeral models may not optimize well | Use `table` for expensive transformations |

---

## Lineage Diagram

Visual representation of model dependencies:

<img width="1101" height="270" alt="image" src="https://github.com/user-attachments/assets/d7d7d51e-0972-4ba9-ba4f-d28474f98f41" />

# Task 4: Built-in Schema Tests

## Overview
Comprehensive data quality framework using dbt's four built-in test types with severity levels based on business criticality.
---
## Test Configuration

### 1. Unique Tests

**Purpose:** Ensure no duplicate records exist for unique identifiers.

```yaml
# stg_tpch__orders.order_key (PK)
- unique:
    severity: error
```

**Why ERROR:** Duplicate primary keys indicate data corruption or ETL failures. This must block deployment.
---
### 2. Not Null Tests

**Purpose:** Validate that required fields are populated.

```yaml
# stg_tpch__orders.order_key (PK)
- not_null:
    severity: error
    
# stg_tpch__orders.total_price (business field)
- not_null:
    severity: warn
```

**Why ERROR for PKs:** Missing primary keys break the entire data model.  
**Why WARN for total_price:** Can be backfilled, doesn't break downstream models.
---

### 3. Accepted Values Tests

**Purpose:** Ensure categorical fields contain only valid values.

```yaml
# stg_tpch__orders.order_status
- accepted_values:
    values: ['O', 'F', 'P']
    severity: error
    
# stg_tpch__orders.order_priority
- accepted_values:
    values: ['1-URGENT', '2-HIGH', '3-MEDIUM', '4-NOT SPECIFIED', '5-LOW']
    severity: warn
```

**Why ERROR for status:** Invalid status codes break order workflow logic.  
**Why WARN for priority:** New priority levels may be added over time.

---

### 4. Relationships Tests (2)

**Purpose:** Validate foreign key relationships and referential integrity.

```yaml
# stg_tpch__orders.customer_key → stg_tpch__customer.customer_key
- relationships:
    to: ref('stg_tpch__customer')
    field: customer_key
    severity: error

# stg_tpch__lineitem.order_key → stg_tpch__orders.order_key
- relationships:
    to: ref('stg_tpch__orders')
    field: order_key
    severity: error
```

**Why ERROR:** Orphan records (orders without customers, lineitems without orders) indicate broken data integrity.
---
## Severity Strategy

### 🛑 ERROR Severity (Blocks Deployment)

**Criteria:** Data corruption, broken business logic, or referential integrity violations.

| Test | Model | Column | Reason |
|------|-------|--------|--------|
| unique | stg_tpch__orders | order_key | Duplicate PKs = data corruption |
| not_null | stg_tpch__orders | order_key | Missing PKs = broken system |
| unique | stg_tpch__customer | customer_key | Duplicate PKs = data corruption |
| not_null | stg_tpch__customer | customer_key | Missing PKs = broken system |
| accepted_values | stg_tpch__orders | order_status | Invalid status breaks workflows |
| relationships | stg_tpch__orders | customer_key | Orphan orders = integrity failure |
| relationships | stg_tpch__lineitem | order_key | Orphan lineitems = integrity failure |

**Action on Failure:**
```
 - BLOCK deployment
 - Alert data team immediately
 - Investigate root cause
 - Fix data issues before retry
```

---

### ⚠️ WARN Severity (Generates Alerts)

**Criteria:** Data quality issues that need investigation but don't break core functionality.

| Test | Model | Column | Reason |
|------|-------|--------|--------|
| not_null | stg_tpch__orders | total_price | Can be backfilled, not critical for queries |
| accepted_values | stg_tpch__orders | order_priority | New priority levels may be added |

**Action on Failure:**
```
 - ALLOW deployment to proceed
 - Log failure to monitoring dashboard
 - Create ticket for investigation
 - Notify data team (non-urgent)
```

---

# Task 5: Custom Singular Tests

## Overview
Custom SQL-based tests that validate complex business logic which cannot be expressed using dbt's generic tests.

---

## Test 1: Order-LineItem Status Consistency

**File:** `tests/assert_fulfilled_orders_have_no_open_lines.sql`

**Business Rule:** Fulfilled orders (status 'F') should not contain open line items (status 'O').

**Logic:**
- Identifies orders marked as 'F' (Fulfilled)
- Checks if any line items still have 'O' (Open) status
- Returns violations where fulfillment status is inconsistent

**Result:** ✅ **PASS** - All fulfilled orders have properly closed line items.

---

## Test 2: Order Total Reconciliation

**File:** `tests/assert_order_totals_match.sql`

**Business Rule:** Order `total_price` must match the sum of line item calculations: `SUM(extended_price × (1 - discount) × (1 + tax))`.

**Tolerance:** 1% difference allowed for rounding

**Logic:**
- Calculates expected total from line items
- Compares with stored `total_price` in orders table
- Flags discrepancies > 1% or missing line items

**Result:** ✅ **PASS** - All order totals reconcile within tolerance.

---

## Test 3: Date Logic Validation ⚠️

**File:** `tests/assert_lineitem_dates_logical.sql`

**Business Rule:** Dates must follow chronological order: `commit_date ≤ ship_date ≤ receipt_date`.

**Logic:**
- Validates date sequences for all line items
- Identifies violations:
  - Receipt before commit
  - Ship before commit  
  - Receipt before ship

**Result:** ⚠️ **WARN** - Found **2,926,558 violations**
### Violation Breakdown

The test identified line items where dates don't follow logical order. Common scenarios include:

- **Ship before commit:** Items shipped before committed delivery date (possible rush orders)
- **Receipt before ship:** Receipt date earlier than ship date (data entry errors or timezone issues)
- **Receipt before commit:** Items received before original commitment (expedited shipping)

### Severity Configuration
```sql
{{ config(severity='warn') }}
```

**Why WARN?** 
- Date inconsistencies indicate data quality issues but don't break downstream analytics
- May reflect legitimate business scenarios (rush orders, date corrections)
- Requires investigation but shouldn't block deployments

---

## Why Singular Tests?

These business rules **cannot** be expressed using generic tests because they:
- Compare aggregations across tables (order totals)
- Validate multi-column relationships (date sequences)
- Check cross-table status consistency (orders vs line items)

Singular tests provide the flexibility to encode complex domain logic directly in SQL.
---

# Task 6: Custom Generic Tests (Macros)

## Overview
Reusable generic test macros that validate data quality rules across multiple models and columns.

---

## Macro 1: `test_values_in_range`

**Purpose:** Validates that numeric column values fall within specified minimum and maximum bounds.

### Parameters

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `model` | ref | Yes | - | Model being tested |
| `column_name` | string | Yes | - | Numeric column to validate |
| `min_value` | numeric | No | none | Minimum acceptable value (inclusive) |
| `max_value` | numeric | No | none | Maximum acceptable value (inclusive) |

### Usage Examples
```yaml
# Ensure primary keys are positive
- name: order_key
  tests:
    - values_in_range:
        min_value: 1
        severity: error

# Validate discount percentage (0-10%)
- name: discount
  tests:
    - values_in_range:
        min_value: 0
        max_value: 0.10
        severity: error

# Check nation_key range (TPCH has 25 nations: 0-24)
- name: nation_key
  tests:
    - values_in_range:
        min_value: 0
        max_value: 24
        severity: error
```

## Macro 2: `test_string_length_bounds`

**Purpose:** Validates that string lengths fall within acceptable character count bounds.

### Parameters

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `model` | ref | Yes | - | Model being tested |
| `column_name` | string | Yes | - | String column to validate |
| `min_length` | integer | No | none | Minimum string length |
| `max_length` | integer | No | none | Maximum string length |

### Usage Examples
```yaml
# Validate exact length (standardized IDs)
- name: clerk
  tests:
    - string_length_bounds:
        min_length: 15
        max_length: 15
        severity: error

# Ensure single-character codes
- name: order_status
  tests:
    - string_length_bounds:
        min_length: 1
        max_length: 1
        severity: error

# Validate phone number format
- name: phone
  tests:
    - string_length_bounds:
        min_length: 15
        max_length: 15
        severity: error
```
---
## Use Cases

| Test | Best For |
|------|----------|
| `values_in_range` | Primary keys, percentages, monetary amounts, quantities, age ranges |
| `string_length_bounds` | Standardized IDs, status codes, phone numbers, postal codes, SKUs |

Both tests return detailed information about violations, making debugging straightforward.
---
# Task 7: Model and Column Documentation

## Documentation Strategy

### Reusable Doc Blocks
Created standardized descriptions in `models/docs.md` for:
- Common keys (order_key, customer_key)
- Order status codes
- Data source context (TPC-H)

### Coverage
- **Staging models:** 3 models, 20+ columns documented
- **Intermediate models:** 2 models with business logic explained
- **Mart models:** 1 production table with full context

### Key Features
- All tests visible in column documentation
- Business context provided for derived fields
- Lineage Graph
<img width="1370" height="447" alt="image" src="https://github.com/user-attachments/assets/66cd0229-1467-469f-a0db-eba3444b561c" />

