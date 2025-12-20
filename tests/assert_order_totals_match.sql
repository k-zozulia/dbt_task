-- Test: Verify that order totals match the sum of line items
-- Business Rule: The total_price in orders should equal the sum of 
-- (extended_price * (1 - discount) * (1 + tax)) from line items
-- We allow 1% tolerance for rounding differences

with order_totals as (
    select 
        order_key,
        total_price
    from {{ ref("fct_tpch__orders")}}
),

lineitem_total as (
    select 
        order_key,
        sum(extended_price * (1 - discount) * (1 + tax)) as calculated_total

    from {{ ref("stg_tpch__lineitem")}}
    group by order_key
),

comparison as (
    select
        o.order_key,
        o.total_price as order_total,
        l.calculated_total as lineitem_total,
        abs(o.total_price - l.calculated_total) as difference,
        abs(o.total_price - l.calculated_total) / nullif(o.total_price, 0) as pct_difference
    from order_totals o
    left join lineitem_total l on l.order_key = o.order_key
) 

select *
from comparison
where pct_difference > 0.01
   or lineitem_total is null 
