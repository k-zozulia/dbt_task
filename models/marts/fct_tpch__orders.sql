{{ config(materialized='table') }}

select
    order_key,
    customer_key,
    order_date,
    total_price,
    status_category,
    is_completed,
    order_size,
    priority_level,

    case 
        when is_completed and priority_level = 'High Priority' 
        then 'Completed High Priority'
        when is_completed 
        then 'Completed Normal'
        when priority_level = 'High Priority' 
        then 'Pending High Priority'
        else 'Pending Normal'
    end as fulfillment_status,

    current_timestamp() as processed_at
from {{ ref('int_tpch__orders_enriched') }}