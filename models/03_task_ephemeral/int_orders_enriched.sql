{{ config(materialized='ephemeral') }}

select *,
    case 
        when total_price < 50000 then 'Small'
        when total_price < 150000 then 'Medium'
        when total_price < 300000 then 'Large'
        else 'Very Large'
    end as order_size,

    case 
        when order_priority in ('1-URGENT', '2-HIGH') then 'High Priority'
        when order_priority in ('3-MEDIUM') then 'Medium Priority'
        else 'Low Priority'
    end as priority_level
from {{ ref('int_orders_with_status')}}