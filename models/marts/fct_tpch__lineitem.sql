{{ config(
    materialized='table',
    cluster_by=['ship_date', 'return_flag', 'ship_mode']
) }}


select
    order_key,
    part_key,
    supplier_key,
    line_number,
    quantity,
    extended_price,
    discount,
    tax,
    return_flag,
    line_status,
    ship_date,
    commit_date,
    receipt_date,
    ship_instructions,
    ship_mode,
    comment,
    
    -- Derived metrics
    extended_price * (1 - discount) as discounted_price,
    extended_price * (1 - discount) * (1 + tax) as final_price,
    
    -- Date parts for analysis
    year(ship_date) as ship_year,
    month(ship_date) as ship_month,
    quarter(ship_date) as ship_quarter,
    
    current_timestamp() as loaded_at

from {{ ref("stg_tpch__lineitem")}}
