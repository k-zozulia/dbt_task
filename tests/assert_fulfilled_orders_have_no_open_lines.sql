-- Test: Verify that fulfilled orders don't have open line items
-- Business Rule: Orders with status 'F' (Fulfilled) should only have 
-- line items with status 'F' (not 'O' = Open)
-- This ensures order fulfillment status accurately reflects all line items

with fulfilled_orders as (
    select order_key
    from {{ ref('stg_tpch__orders') }}
    where order_status = 'F'
),

open_line_items as (
    select
        order_key,
        line_number,
        line_status,
        return_flag
    from {{ ref('stg_tpch__lineitem') }}
    where line_status = 'O'
),

violations as (
    select
        fo.order_key,
        oli.line_number,
        oli.line_status,
        oli.return_flag,
        count(*) over (partition by fo.order_key) as open_lines_count
    from fulfilled_orders fo
    inner join open_line_items oli on fo.order_key = oli.order_key
)

select
    order_key,
    open_lines_count,
    'Fulfilled order has ' || open_lines_count || ' open line items' as issue_description
from violations
group by order_key, open_lines_count