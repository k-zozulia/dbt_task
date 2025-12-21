{% test string_length_bounds(model, column_name, min_length=none, max_length=none) %}

{#
    Test that validates string column length is within acceptable bounds.
    
    Parameters:
        - model: The model being tested
        - column_name: String column to validate
        - min_length: Minimum string length (optional)
        - max_length: Maximum string length (optional)
    
    Returns: Rows where string length is out of bounds
#}

with validation as (
    select
        {{ column_name }} as value,
        length({{ column_name }}) as actual_length,
        {% if min_length is not none %}
            length({{ column_name }}) < {{ min_length }} as too_short,
        {% else %}
            false as too_short,
        {% endif %}
        {% if max_length is not none %}
            length({{ column_name }}) > {{ max_length }} as too_long
        {% else %}
            false as too_long
        {% endif %}
    from {{ model }}
    where {{ column_name }} is not null
)

select 
    value,
    actual_length,
    {% if min_length is not none%} {{min_length}} {% else %} null {% endif %} as min_allowed,
    {% if max_length is not none%} {{max_length}} {% else %} null {% endif %} as msx_allowed,
    case
        when too_short then 'String too short'
        when too_long then 'String too long'
    end as violation_type
from validation
where too_short or too_long

{% endtest %}