-- Test model to validate get_var() macro functionality
{{
  config(
    materialized = 'view'
  )
}}

WITH test_results AS (
  {% set variable_query %}
    SELECT key, data_type, parent_key 
    FROM {{ ref('silver__ez_variables') }}
    WHERE is_enabled
    AND (parent_key IS NULL OR parent_key = '')
  {% endset %}
  
  {% for key_record in run_query(variable_query) %}
    {% set key = key_record[0] %}
    {% set expected_type = key_record[1] | lower %}
    {% set parent_key = key_record[2] %}
    {% set var_value = fsc_evm.get_var(key, none) %}
    
    SELECT 
      '{{ key }}' AS variable_key,
      '{{ expected_type }}' AS expected_type,

      -- Check type of variable value
      {% if var_value is not none %}
        {% if expected_type in ['boolean'] %}
          CASE 
            WHEN {{ var_value }} IN (TRUE, FALSE) THEN '{{ expected_type }}'
            ELSE 'not_' || '{{ expected_type }}'
          END
        {% elif expected_type in ['number', 'integer', 'fixed', 'float', 'decimal'] %}
          CASE 
            WHEN IS_NUMERIC({{ var_value }}) THEN '{{ expected_type }}'
            ELSE 'not_' || '{{ expected_type }}'
          END
        {% elif expected_type in ['string', 'text', 'varchar'] %}
          CASE 
            WHEN TRY_CAST('{{ var_value }}' AS STRING) IS NOT NULL THEN '{{ expected_type }}'
            ELSE 'not_' || '{{ expected_type }}'
          END
        {% elif expected_type in ['array'] %}
          CASE 
            WHEN IS_ARRAY(PARSE_JSON('{{ tojson(var_value) }}')) THEN '{{ expected_type }}'
            ELSE 'not_' || '{{ expected_type }}'
          END
        {% elif expected_type in ['json', 'variant', 'object'] %}
          CASE 
            WHEN IS_OBJECT(PARSE_JSON('{{ tojson(var_value) }}')) THEN '{{ expected_type }}'
            ELSE 'not_' || '{{ expected_type }}'
          END
        {% else %}
          'unknown_type'
        {% endif %}
      {% else %}
        'null'
      {% endif %} AS actual_type,
      
      -- Type-specific output value columns
      {% if expected_type == 'boolean' and var_value is not none %}
        {{ var_value }} AS boolean_value,
      {% else %}
        NULL AS boolean_value,
      {% endif %}
      
      {% if expected_type in ['number', 'integer', 'fixed', 'float', 'decimal'] and var_value is not none %}
        {{ var_value }} AS number_value,
      {% else %}
        NULL AS number_value,
      {% endif %}
      
      {% if expected_type in ['string', 'text', 'varchar'] and var_value is not none %}
        '{{ var_value }}' AS string_value,
      {% else %}
        NULL AS string_value,
      {% endif %}
      
      {% if expected_type in ['array', 'json', 'variant', 'object'] and var_value is not none %}
        PARSE_JSON('{{ tojson(var_value) }}') AS json_value,
      {% else %}
        NULL AS json_value,
      {% endif %}
      
      -- String representation for debugging
      '{{ var_value }}' AS raw_value_string,
      
      NULL AS parent_key
    
    {% if not loop.last %}
      UNION ALL
    {% endif %}
  {% endfor %}
),

-- Test parent-child relationships (mappings)
parent_child_tests AS (
  {% set parent_query %}
    SELECT DISTINCT parent_key 
    FROM {{ ref('silver__ez_variables') }}
    WHERE parent_key IS NOT NULL AND parent_key != ''
    AND is_enabled
  {% endset %}
  
  {% for parent_record in run_query(parent_query) %}
    {% set parent_key = parent_record[0] %}
    {% set mapping = fsc_evm.get_var(parent_key, none) %}
    
    SELECT 
      '{{ parent_key }}' AS variable_key,
      'mapping' AS expected_type,
      {% if mapping is not none %}
        CASE 
          WHEN IS_OBJECT(PARSE_JSON('{{ tojson(mapping) }}')) THEN 'mapping'
          ELSE 'not_mapping'
        END
      {% else %}
        'null'
      {% endif %} AS actual_type,
      
      -- Type-specific value columns
      NULL AS boolean_value,
      NULL AS number_value,
      NULL AS string_value,
      {% if mapping is not none %}
        PARSE_JSON('{{ tojson(mapping) }}') AS json_value,
      {% else %}
        NULL AS json_value,
      {% endif %}
      
      -- String representation for debugging
      '{{ tojson(mapping) }}' AS raw_value_string,
      
      NULL AS parent_key
    
    {% if not loop.last %}
      UNION ALL
    {% endif %}
  {% endfor %}
),

-- Test child keys within parent mappings
child_key_tests AS (
  {% set child_query %}
    SELECT key, data_type, parent_key 
    FROM {{ ref('silver__ez_variables') }}
    WHERE parent_key IS NOT NULL AND parent_key != ''
    AND is_enabled
  {% endset %}
  
  {% for child_record in run_query(child_query) %}
    {% set child_key = child_record[0] %}
    {% set expected_type = child_record[1] | lower %}
    {% set parent_key = child_record[2] %}
    {% set parent_obj = fsc_evm.get_var(parent_key, none) %}
    
    {% if parent_obj is not none and parent_obj is mapping and child_key in parent_obj %}
      {% set child_value = parent_obj[child_key] %}
      
      SELECT 
        '{{ child_key }}' AS variable_key,
        '{{ expected_type }}' AS expected_type,
        {% if child_value is not none %}
          {% if expected_type in ['boolean'] %}
            CASE 
              WHEN {{ child_value }} IN (TRUE, FALSE) THEN '{{ expected_type }}'
              ELSE 'not_' || '{{ expected_type }}'
            END
          {% elif expected_type in ['number', 'integer', 'fixed', 'float', 'decimal'] %}
            CASE 
              WHEN IS_NUMERIC({{ child_value }}) THEN '{{ expected_type }}'
              ELSE 'not_' || '{{ expected_type }}'
            END
          {% elif expected_type in ['string', 'text', 'varchar'] %}
            CASE 
              WHEN TRY_CAST('{{ child_value }}' AS STRING) IS NOT NULL THEN '{{ expected_type }}'
              ELSE 'not_' || '{{ expected_type }}'
            END
          {% else %}
            'unknown_type'
          {% endif %}
        {% else %}
          'null'
        {% endif %} AS actual_type,
        
        -- Type-specific value columns
        {% if expected_type == 'boolean' and child_value is not none %}
          {{ child_value }} AS boolean_value,
        {% else %}
          NULL AS boolean_value,
        {% endif %}
        
        {% if expected_type in ['number', 'integer', 'fixed', 'float', 'decimal'] and child_value is not none %}
          {{ child_value }} AS number_value,
        {% else %}
          NULL AS number_value,
        {% endif %}
        
        {% if expected_type in ['string', 'text', 'varchar'] and child_value is not none %}
          '{{ child_value }}' AS string_value,
        {% else %}
          NULL AS string_value,
        {% endif %}
        
        {% if expected_type in ['array', 'json', 'variant', 'object'] and child_value is not none %}
          PARSE_JSON('{{ tojson(child_value) }}') AS json_value,
        {% else %}
          NULL AS json_value,
        {% endif %}
        
        -- String representation for debugging
        '{{ child_value }}' AS raw_value_string,
        
        '{{ parent_key }}' AS parent_key
      
      {% if not loop.last %}
        UNION ALL
      {% endif %}
    {% endif %}
  {% endfor %}
)

-- Combine all test results
SELECT 
  variable_key,
  expected_type,
  actual_type,
  boolean_value,
  number_value,
  string_value,
  json_value,
  raw_value_string,
  parent_key,
  CASE 
    WHEN actual_type = expected_type THEN 'PASS'
    WHEN actual_type = 'null' THEN 'NULL_VALUE'
    WHEN expected_type IN ('number', 'integer', 'fixed', 'float', 'decimal') AND actual_type = expected_type THEN 'PASS'
    WHEN expected_type IN ('string', 'text', 'varchar') AND actual_type = 'string' THEN 'PASS'
    WHEN expected_type IN ('json', 'variant', 'object') AND actual_type = 'object' THEN 'PASS'
    ELSE 'FAIL'
  END AS test_result
FROM test_results

UNION ALL

SELECT 
  variable_key,
  expected_type,
  actual_type,
  boolean_value,
  number_value,
  string_value,
  json_value,
  raw_value_string,
  parent_key,
  CASE 
    WHEN actual_type = expected_type THEN 'PASS'
    WHEN actual_type = 'null' THEN 'NULL_VALUE'
    ELSE 'FAIL'
  END AS test_result
FROM parent_child_tests

UNION ALL

SELECT 
  variable_key,
  expected_type,
  actual_type,
  boolean_value,
  number_value,
  string_value,
  json_value,
  raw_value_string,
  parent_key,
  CASE 
    WHEN actual_type = expected_type THEN 'PASS'
    WHEN actual_type = 'null' THEN 'NULL_VALUE'
    WHEN expected_type IN ('number', 'integer', 'fixed', 'float', 'decimal') AND actual_type = expected_type THEN 'PASS'
    WHEN expected_type IN ('string', 'text', 'varchar') AND actual_type = 'string' THEN 'PASS'
    ELSE 'FAIL'
  END AS test_result
FROM child_key_tests