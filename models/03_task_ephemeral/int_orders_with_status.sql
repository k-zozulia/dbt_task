{{ config(materialized='ephemeral')}}

select *,
    case 
        when order_status = 'O' then 'Open'
        when order_status = 'F' then 'Fulfilled'
        when order_status = 'P' then 'Partitial'
        else 'Unknown'
    end as status_category,

    case
        when order_status = 'O' then false
        when order_status = 'F' then true
        when order_status = 'P' then false
        else null
    end as is_completed
from {{ ref('stg_orders') }}