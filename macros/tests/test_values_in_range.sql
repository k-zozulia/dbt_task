{% test values_in_range(model, column_name, min_value=none, max_value=none) %}

{#
    Test that validates numeric column values fall within specified range.
    
    Parameters:
        - model: The model being tested
        - column_name: Column to validate
        - min_value: Minimum acceptable value (optional, inclusive)
        - max_value: Maximum acceptable value (optional, inclusive)
    
    Returns: Rows that violate the range constraint
#}

with validation as (
    select 
        {{column_name}} as value,
        {% if min_value is not none %}
            {{column_name}} < {{ min_value }} as below_min,
        {% else %}
            false as below_min,
        {% endif %}
        {% if max_value is not none %}
            {{column_name}} > {{max_value}} as above_max
        {% else %}
            false as above_max
        {% endif %}
    from {{model}}
    where {{column_name}} is not null
)

select *
from validation
where below_min or above_max

{% endtest%}