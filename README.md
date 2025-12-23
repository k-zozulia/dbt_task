#Project Overview

This project is a hands-on dbt and Snowflake training project focused on building and optimizing data transformations using best practices. It covers environment setup, GitHub-based development workflows, and multiple transformation tasks. The goal of the project is to understand how dbt models behave in practice and how design choices impact performance, maintainability, and scalability.
---
# Branching Strategy

Each task in this project was developed in its own dedicated Git branch.
This approach allowed changes to be implemented, tested, and reviewed independently for each task.

The main branch contains the final consolidated version of the project, where:

- All completed tasks are merged

- Redundant or overlapping models created during earlier tasks were removed

- Several optimizations were applied to simplify the overall structure and improve performance

Additionally, the main branch includes the complete README documentation, covering all tasks and their outcomes in a single, unified place.

---

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
---

# Task 8: Source Freshness Checks

## Overview
Configured data freshness monitoring for source tables to ensure timely data delivery and catch ETL pipeline failures early.

---

## Challenge: TPC-H Dataset Limitations

The TPC-H sample dataset has two constraints:
1. **Date fields are `DATE` type** (dbt freshness requires `TIMESTAMP`)
2. **No audit columns** like `_loaded_at` exist (static historical data)

### Solution: Created Views with Timestamp Fields

```sql
-- Created in Snowflake (DBT_DB.Transform schema)
CREATE OR REPLACE VIEW orders_with_loaded_at AS
SELECT *, CAST(o_orderdate AS TIMESTAMP) AS _loaded_at
FROM snowflake_sample_data.tpch_sf1.orders;

CREATE OR REPLACE VIEW lineitem_with_loaded_at AS
SELECT *, CAST(l_shipdate AS TIMESTAMP) AS _loaded_at
FROM snowflake_sample_data.tpch_sf1.lineitem;

CREATE OR REPLACE VIEW customer_with_loaded_at AS
SELECT *, CURRENT_TIMESTAMP() AS _loaded_at
FROM snowflake_sample_data.tpch_sf1.customer;
```
---
## Freshness Configuration

| Source | Loaded At Field | Warn After | Error After | Rationale |
|--------|----------------|------------|-------------|-----------|
| orders_with_loaded_at | _loaded_at (o_orderdate) | 12 hours | 1 day | Orders should arrive daily |
| lineitem_with_loaded_at | _loaded_at (l_shipdate) | 12 hours | 1 day | Line items updated with orders |
| customer_with_loaded_at | _loaded_at (current_ts) | 1 day | 3 days | Customer data changes less frequently |

---

## Expected Results

⚠️ Since TPC-H is static historical data, freshness checks will show **ERROR** status (data is years old). This is expected behavior for this demo.

In production with real ETL pipelines:
- **PASS** = Data loaded within expected timeframe
- **WARN** = Data delayed but acceptable
- **ERROR** = Data pipeline issue, investigate immediately

---

## Monitoring Workflow

1. **Pre-deployment check:**
```bash
   dbt source freshness && dbt run && dbt test
```

2. **Scheduled monitoring:**
   - Run freshness checks every 6 hours
   - Alert on ERROR to Slack/PagerDuty
   - Log WARN to monitoring dashboard

3. **Integration:**
   - Add to CI/CD pipeline
   - Block deployments on ERROR status
   - Dashboard: Track freshness trends over time

---
# Task 9: Partitioning and Clustering

## Overview
Optimization of a 6M+ row fact table using Snowflake's clustering feature to improve query performance on frequently filtered columns.

## Dataset
- **Source:** SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.LINEITEM
- **Rows:** 6,001,215
- **Size:** ~157 MB

## Clustering Strategy

### Selected Clustering Keys
```sql
cluster_by=['ship_date', 'return_flag', 'ship_mode']
```

### Rationale
| Column | Reason | Cardinality |
|--------|--------|-------------|
| `ship_date` | High-frequency filter in date range queries | ~2,500 unique dates |
| `return_flag` | Categorical filter with low cardinality | 3 values (R, A, N) |
| `ship_mode` | Common in WHERE clauses for logistics analysis | 7 values |

---

## Performance Results

### Query 1: Date Range Filter
```sql
WHERE ship_date BETWEEN '1995-01-01' AND '1995-12-31'
```

| Metric | Base Table | Clustered Table | Improvement |
|--------|-----------|----------------|-------------|
| Execution Time | 906 ms | 808 ms | **11%**  |
| Bytes Scanned | 49.73 MB | 9.16 MB | **81%** |
| Partitions Scanned | 10 | 3 | **70%**  |

**Analysis**: Clustering dramatically reduced data scanned by 81%, leading to significant cost savings. Execution time improvement is modest due to small dataset size, but would scale better on larger tables.

---

### Query 2: Categorical Filters
```sql
WHERE return_flag = 'R' AND line_status = 'F'
```

| Metric | Base Table | Clustered Table | Improvement |
|--------|-----------|----------------|-------------|
| Execution Time | 534 ms | 411 ms | **23%**  |
| Bytes Scanned | 33.9 MB | 21.08 MB | **38%**  |

**Analysis**: Good improvement on categorical filters, demonstrating that clustering on `return_flag` is effective despite it being the second clustering key.

---

### Query 3: Complex Multi-Column Filter
```sql
WHERE ship_date >= '1994-01-01'
  AND return_flag IN ('R', 'A')
  AND ship_mode = 'AIR'
```

| Metric | Base Table | Clustered Table | Improvement |
|--------|-----------|----------------|-------------|
| Execution Time | 850 ms | 758 ms | **11%** |
| Bytes Scanned | 46.12 MB | 14.91 MB | **68%**  |

**Analysis**: Excellent bytes reduction (68%) when filtering on all three clustering keys simultaneously. This validates our multi-column clustering strategy.

---

### Query 4: Full Table Scan (Control)

| Metric | Base Table | Clustered Table | Impact |
|--------|-----------|----------------|--------|
| Execution Time | 889 ms | 916 ms | **-3%** (negligible) |

**Analysis**: Full table scans show minimal performance impact from clustering metadata overhead. This confirms clustering doesn't hurt non-filtered queries.

---

## EXPLAIN Analysis

### Base Table - Full Partition Scan
```
GlobalStats:
    partitionsTotal=10
    partitionsAssigned=10        ← Scans ALL partitions
    bytesAssigned=147,429,376    ← ~141 MB

TableScan: No partition pruning possible
```

### Clustered Table - Efficient Pruning
```
GlobalStats:
    partitionsTotal=9
    partitionsAssigned=3         ← Scans only 33% of partitions! 
    bytesAssigned=41,428,480     ← ~39.5 MB (72% reduction)

TableScan: Partition pruning active on ship_date filter
```

**Key Insight**: Snowflake successfully eliminated 6 out of 9 partitions (67% pruning rate), scanning only the relevant micro-partitions containing 1995 data.

---

## Clustering Health Metrics
```json
{
  "average_depth": 2.0,        
  "average_overlaps": 1.7778,  
  "total_partition_count": 9,
  "partition_depth_histogram": {
    "00002": 9           
  }
}
```
### Health Assessment

| Metric | Value | Status | Explanation |
|--------|-------|--------|-------------|
| **Clustering Depth** | 2.0 |  Excellent | Well below target of 4 |
| **Average Overlaps** | 1.78 |  Good | Minimal partition overlap |
| **Depth Distribution** | All at level 2 |  Uniform | Consistent clustering quality |

**Snowflake Warning**: High cardinality on `ship_date` noted, but metrics confirm clustering is highly effective.

---

## Key Findings

### ✅ When Clustering Helps Most

1. **Date range filters**: **70% fewer partitions scanned**
   - Ideal for time-series analytics
   - Massive cost savings on large datasets

2. **Categorical filters**: **38% bytes reduction**
   - Effective even on secondary clustering keys
   - Compounds benefits with primary key

3. **Multi-column filters**: **68% bytes reduction**
   - Best performance when filtering on all clustering keys
   - Validates our clustering strategy

### 💰 Cost Optimization

**Average bytes reduction: 62%** across filtered queries
- On Snowflake's compute pricing, this translates to ~62% cost savings for these query patterns
- At scale (100M+ rows), these savings compound significantly

### ⚠️ Clustering Overhead

| Aspect | Impact | Assessment |
|--------|--------|------------|
| Build time | +10-15% | Acceptable |
| Full scan queries | -3% | Negligible |
| Storage | Metadata only | Minimal |
| Reclustering | Automatic | Monitor credits |
---

# Task 10: Project Analysis and Optimization

# DAG Structure Analysis
(Before Optimization)

## Project Overview
- Total Models: 9
- Total Sources: 3
- Total Tests: 21 (18 schema + 3 singular)
- Layers: 3 (staging → intermediate → marts)

## Layer Breakdown

### Sources (3)
1. `tpch.orders` → 1.5M rows
2. `tpch.customer` → 150K rows  
3. `tpch.lineitem` → 6M rows

### Staging Layer (3 models - all VIEWS)
1. `stg_tpch__orders` ← tpch.orders
2. `stg_tpch__customer` ← tpch.customer
3. `stg_tpch__lineitem` ← tpch.lineitem

### Intermediate Layer (2 models - all EPHEMERAL)
1. `int_tpch__orders_with_status` ← stg_tpch__orders
2. `int_tpch__orders_enriched` ← int_tpch__orders_with_status

### Marts Layer (3 models - all TABLES)
1. `fct_tpch__orders` ← int_tpch__orders_enriched
2. `fct_tpch__lineitem_base` ← tpch.lineitem (⚠️ DUPLICATE) (🔴 DELETED)
3. `fct_tpch__lineitem_clustered` ← tpch.lineitem

### Orphaned Models (Demo artifacts)
- `materialization_demo_table` (🔴 DELETED)
- `materialization_demo_view` (🔴 DELETED)
- `orders.sql` (in 02_task_incremental folder) (🔴 DELETED)

## Issues Identified

### 🔴 Critical Issue 1: Duplicate Lineitem Models
**Problem:** Both `fct_tpch__lineitem_base` and `fct_tpch__lineitem_clustered` exist
**Impact:** 
- Double build time (~36s wasted per run)
- Double storage (~314 MB)
- Confusion about which to use

**Action:** DELETED `fct_tpch__lineitem_base.sql`

### ⚠️ Issue 2: Demo Models in Production
**Problem:** 3 demo models not part of main DAG
**Impact:** Cluttered project, longer build times
**Action:** Deleted

## Fixed DAG:

<img width="1364" height="380" alt="image" src="https://github.com/user-attachments/assets/af3fe06d-ff1f-4286-ab60-7da3438b7389" />


## Analyze Model Run Times


## Build Times (Full dbt run)

| # | Model                        | Type      | Time      | Rows | % of Total | Status  |
| - | ---------------------------- | --------- | --------- | ---- | ---------- | ------- |
| 1 | stg_tpch__customer           | view      | **0.42s** | 150K | **4.0%**   | ✅ Fast  |
| 2 | stg_tpch__orders             | view      | **0.73s** | 1.5M | **7.0%**   | ✅ Fast  |
| 3 | stg_tpch__lineitem           | view      | **0.73s** | 6M   | **7.0%**   | ✅ Fast  |
| 4 | int_tpch__orders_with_status | ephemeral | **0.00s** | –    | **0.0%**   | ✅ Fast  |
| 5 | int_tpch__orders_enriched    | ephemeral | **0.00s** | –    | **0.0%**   | ✅ Fast  |
| 6 | fct_tpch__orders             | table     | **1.87s** | 1.5M | **17.9%**  | ✅ OK    |
| 7 | fct_tpch__lineitem           | table     | **6.69s** | 6M   | **64.1%**  | 🔴 SLOW |

**TOTAL BUILD TIME: ~13.1 seconds**

## Key Findings

### 🔴 Critical Bottleneck: Lineitem Models
- **Combined time:** 36.75s (47% of total build!)
- **Issue:** Processing same 6M rows twice
- **Solution:** Delete one, convert other to incremental

### Performance by Layer
| Layer | Total Time | % of Build | Assessment |
|-------|-----------|------------|------------|
| Staging | 1.31s | 1.7% | ✅ Excellent |
| Intermediate | 0.00s | 0.0% | ✅ Excellent (ephemeral) |
| Marts | 40.18s | 51.7% | ⚠️ Needs optimization |

### Key Findings (corrected)
🔴 Critical Bottleneck: Lineitem Model

Time: 6.69s

**Share of total build:** 64.1%
**Issue:** One very large fact table (6M rows) dominates runtime
**Observation:** Even without clustering comparison, fct_tpch__lineitem is the primary performance bottleneck
**Optimization direction:** incremental strategy, clustering, or pruning by date

| Layer            | Total Time | % of Build | Assessment              |
| ---------------- | ---------- | ---------- | ----------------------- |
| **Staging**      | **1.88s**  | **18.0%**  | ✅ Excellent             |
| **Intermediate** | **0.00s**  | **0.0%**   | ✅ Excellent (ephemeral) |
| **Marts**        | **8.56s**  | **82.0%**  | ⚠️ Needs optimization   |

## Test Coverage by Model
### ✅ Well-Tested Models

#### stg_tpch__orders (7 tests)
- [x] unique (order_key)
- [x] not_null (order_key)
- [x] not_null (total_price) - severity: warn
- [x] accepted_values (order_status) - ['O', 'F', 'P']
- [x] accepted_values (order_priority) - 5 values, warn
- [x] relationships (customer_key → stg_tpch__customer)
- [x] string_length_bounds (clerk, order_status)

#### stg_tpch__customer (4 tests)
- [x] unique (customer_key)
- [x] not_null (customer_key)
- [x] values_in_range (customer_key: min 1)
- [x] values_in_range (nation_key: 0-24)
- [x] string_length_bounds (phone: 15 chars)

#### stg_tpch__lineitem (3 tests)
- [x] relationships (order_key → stg_tpch__orders)
- [x] values_in_range (discount: 0-0.10)
- [x] values_in_range (extended_price: min 0.01)

### 🔴 CRITICAL: Models Without Tests

#### fct_tpch__orders (0 tests) ❌
**Status:** Production table with ZERO data quality checks
**Risk Level:** HIGH
**Impact:** Bad data could flow to dashboards undetected

**Missing Tests:**
- [ ] unique (order_key)
- [ ] not_null (order_key, processed_at)
- [ ] accepted_values (fulfillment_status)
- [ ] Data logic: processed_at >= order_date

#### fct_tpch__lineitem (0 tests) ❌
**Status:** Production table with ZERO data quality checks
**Risk Level:** HIGH
**Impact:** 6M rows with no validation

**Missing Tests:**
- [ ] not_null (order_key, line_number)
- [ ] relationships (order_key → stg_tpch__orders)
- [ ] Data logic: discounted_price = extended_price * (1 - discount)
- [ ] Data logic: final_price = discounted_price * (1 + tax)

### ⚪ Ephemeral Models (No tests needed)
- int_tpch__orders_with_status (ephemeral - tested via downstream)
- int_tpch__orders_enriched (ephemeral - tested via downstream)

## Documentation Coverage

### ✅ Fully Documented Models
| Model | Description | Columns Documented | Doc Blocks |
|-------|-------------|-------------------|------------|
| stg_tpch__orders | ✅ Yes | 8/8 (100%) | ✅ Yes |
| stg_tpch__customer | ✅ Yes | 7/8 (88%) | ✅ Yes |
| int_tpch__orders_with_status | ✅ Yes | 2/2 (100%) | ❌ No |
| int_tpch__orders_enriched | ✅ Yes | 2/2 (100%) | ❌ No |
| fct_tpch__orders | ✅ Yes | 10/10 (100%) | ✅ Yes |

### 🔴 Poorly Documented Models
| Model | Description | Columns Documented | Doc Blocks |
|-------|-------------|-------------------|------------|
| stg_tpch__lineitem | ✅ Yes | 10/16 (63%) | ⚠️ Partial |
| fct_tpch__lineitem | ❌ **NO** | 0/20 (0%) | ❌ **NO** |

## Critical Gaps

### 🚨 Priority 0: Test Production Tables
**Action Required:** Add tests to `fct_tpch__orders` and `fct_tpch__lineitem`
**Risk if not fixed:** Production data quality issues undetected

### ⚠️ Priority 1: Document Lineitem Models  
**Action Required:** Add column descriptions
**Risk if not fixed:** Team confusion, harder maintenance

---
# Prioritized Improvement Roadmap

## Priority Framework

| Priority | Definition | Examples |
|----------|-----------|----------|
| **P0** 🔴 | Blocks production / Critical risk | No tests on prod tables |
| **P1** 🟡 | High value / Quick wins | Performance optimizations |
| **P2** 🔵 | Important but not urgent |  Advanced features |
| **P3** ⚪ | Nice to have | Polish & extras |

---

## 🔴 P0: Critical 

### P0.1 - Add Tests to Production Mart Models
**Issue:** Zero data quality validation on production tables
**Models:** `fct_tpch__orders`, `fct_tpch__lineitem`

**Action Items:**
1. Create `models/marts/_fct_tpch_tests.yml` (if not exists)
2. Add tests for fct_tpch__orders
3. Add tests for fct_tpch__lineite
4. Run `dbt test` and verify

**Test Checklist for fct_tpch__orders:**
```yaml
- [ ] unique (order_key)
- [ ] not_null (order_key)
- [ ] not_null (processed_at)
- [ ] accepted_values (fulfillment_status)
- [ ] relationships (customer_key → staging)
```

**Impact:** 🔥 Critical - Prevents bad data in production
**Risk if skipped:** Silent data quality failures

---

## 🟡 P1: High Value

### P1.1 - Convert Lineitem to Incremental
**Issue:** 6M row table rebuilt from scratch every run (18.5s)

**Action:** Modify `fct_tpch__lineitem.sql`

**Implementation:**
```sql
{{ config(
    materialized='incremental',
    unique_key=['order_key', 'line_number'],
    cluster_by=['ship_date', 'return_flag', 'ship_mode'],
    incremental_strategy='merge'
) }}

with source as (
    select * from {{ source('tpch', 'lineitem') }}
    
    {% if is_incremental() %}
    where l_shipdate >= (
        select dateadd(day, -3, max(ship_date))
        from {{ this }}
    )
    {% endif %}
),
-- rest of model...
```

**Impact:** ⚡⚡ 87% faster incremental runs (2-3s vs 18s)
**Savings:** 60-70 seconds per run after initial load

---

### P1.2 - Complete Lineitem Documentation
**Issue:** Production model has 0% column documentation

**Action:** Add to `models/marts/_fct_tpch.yml`

**Template:**
```yaml
models:
  - name: fct_tpch__lineitem_clustered
    description: |
      Production fact table for order line items.
      Clustered on ship_date, return_flag, and ship_mode.
      Includes pre-calculated discounts and taxes.
    
    columns:
      - name: order_key
        description: "Foreign key to fct_tpch__orders"
      
      - name: line_number
        description: "Line item sequence (1-7 typically)"
      
      - name: discounted_price
        description: "Price after discount: extended_price × (1 - discount)"
      
      # ... add all 20 columns
```

**Impact:** 📚 Better team understanding, easier debugging
**Risk:** None

---

## 🔵 P2: Important 

### P2.1 - Add Business Logic Tests
**Current:** 3 singular tests exist
**Target:** Add 2-3 more validation tests

**New Tests to Add:**
```sql
# tests/assert_discounted_price_accuracy.sql
# Validate: discounted_price = extended_price * (1 - discount)

# tests/assert_final_price_accuracy.sql
# Validate: final_price = discounted_price * (1 + tax)
```
**Impact:** Higher confidence in calculations

---

### P2.3 - Set Up Source Freshness Monitoring
**Action:** Already configured, but add to CI/CD
```bash
dbt source freshness
```

**Impact:** Catch data pipeline issues early

---

## 🔵 P3: Nice to Have - Backlog

- Add model contracts (dbt 1.5+)
- Implement snapshots for SCD Type 2
- Add exposures for BI dashboards
- Set up Slack alerting for test failures
- Create data quality dashboard

---

# Project Optimization Report
## Executive Summary

This comprehensive audit analyzed the dbt_task project's DAG structure, performance, test coverage, and documentation quality. The project demonstrates strong foundational knowledge but requires optimization before production deployment.

**Key Findings:**
- 🔴 Critical: Zero tests on production mart tables
- 🟡 Opportunity: 87% faster builds with incremental materialization
- ✅ Strength: Excellent staging layer test coverage

---

## 1. Project Overview
###
Total Models: 7
Staging: 3 (views) 
Intermediate: 2 (ephemeral) 
Marts: 2 (tables) 

Total Tests: 21
Schema: 18 
Singular: 3 
Test Coverage: 33% of models 

## 2. Critical Issues Found

### 🔴 Issue #1: No Tests on Production Tables
**Severity:** CRITICAL - Blocks Production Readiness

**Affected Models:**
- `fct_tpch__orders` (1.5M rows, 0 tests)
- `fct_tpch__lineitem` (6M rows, 0 tests)

**Risk:**
- Bad data could flow to dashboards undetected
- No validation of calculated fields (discounts, taxes)
- Referential integrity not verified

**Action Required:** Add comprehensive test suite (see P0.1)

---

### 🟡 Issue #2: Inefficient Materialization
**Severity:** HIGH - Optimization Opportunity

**Model:** `fct_tpch__lineitem` (6M rows)

**Current:** Full table refresh every run (18.5s)
**Optimal:** Incremental with 3-day lookback (2-3s)

**Expected Savings:**
- Incremental runs: 87% faster (16s saved)
- Daily builds: 4 × 16s = 64 seconds saved
- Monthly: ~32 minutes saved

**Action Required:** Convert to incremental

---

## 3. Performance Analysis

### Current Build Performance

| # | Model                        | Type      | Time      | Rows | % of Total | Status  |
| - | ---------------------------- | --------- | --------- | ---- | ---------- | ------- |
| 1 | stg_tpch__customer           | view      | **0.42s** | 150K | **4.0%**   | ✅ Fast  |
| 2 | stg_tpch__orders             | view      | **0.73s** | 1.5M | **7.0%**   | ✅ Fast  |
| 3 | stg_tpch__lineitem           | view      | **0.73s** | 6M   | **7.0%**   | ✅ Fast  |
| 4 | int_tpch__orders_with_status | ephemeral | **0.00s** | –    | **0.0%**   | ✅ Fast  |
| 5 | int_tpch__orders_enriched    | ephemeral | **0.00s** | –    | **0.0%**   | ✅ Fast  |
| 6 | fct_tpch__orders             | table     | **1.87s** | 1.5M | **17.9%**  | ✅ OK    |
| 7 | fct_tpch__lineitem           | table     | **6.69s** | 6M   | **64.1%**  | 🔴 SLOW |

---
## 4. Test Coverage Gap Analysis

### Current Coverage

| Layer | Models | With Tests | Without Tests | Coverage |
|-------|--------|------------|---------------|----------|
| Staging | 3 | 3 | 0 | 100% ✅ |
| Intermediate | 2 | 0 | 2 | N/A (ephemeral) |
| Marts | 2 | 0 | 2 | 0% 🔴 |

### Missing Critical Tests

#### fct_tpch__orders needs:
- [ ] unique (order_key)
- [ ] not_null (order_key, processed_at)
- [ ] accepted_values (fulfillment_status)
- [ ] relationships (customer_key → staging)

#### fct_tpch__lineitem needs:
- [ ] not_null (order_key, line_number)
- [ ] relationships (order_key → orders)
- [ ] custom: discounted_price calculation accuracy
- [ ] custom: final_price calculation accuracy

---

## 5. Documentation Assessment

### Coverage by Model

| Model | Description | Columns | Score |
|-------|-------------|---------|-------|
| stg_tpch__orders | ✅ | 8/8 (100%) | ⭐⭐⭐⭐⭐ |
| stg_tpch__customer | ✅ | 7/8 (88%) | ⭐⭐⭐⭐ |
| fct_tpch__orders | ✅ | 10/10 (100%) | ⭐⭐⭐⭐⭐ |
| stg_tpch__lineitem | ✅ | 10/16 (63%) | ⭐⭐⭐ |
| fct_tpch__lineitem | ❌ | 0/20 (0%) | 🔴 |

### Missing Documentation
- 20 columns in fct_tpch__lineitem (0% documented)
- 6 columns in stg_tpch__lineitem
- Custom macro documentation missing

---
