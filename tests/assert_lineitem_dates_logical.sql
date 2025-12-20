-- Test: Verify that line item dates follow logical chronological order
-- Business Rule: commit_date <= ship_date <= receipt_date
-- Invalid date sequences indicate data quality issues in the shipping process

{{ config(
    severity='warn'
) }}

with date_validation as (
    select
        order_key,
        line_number,
        commit_date,
        ship_date,
        receipt_date,
        case
            when receipt_date < commit_date then 'Receipt before commit'
            when ship_date < commit_date then 'Ship before commit'
            when receipt_date < ship_date then 'Receipt before ship'
            else null
        end as violation_type
    from {{ ref('stg_tpch__lineitem') }}
    where 
        commit_date is not null
        and ship_date is not null
        and receipt_date is not null
)

select *
from date_validation
where violation_type is not null