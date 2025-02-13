{{ config (
    materialized = "view",
    post_hook = fsc_utils.if_data_call_function_v2(
        func = 'streamline.udf_bulk_rest_api_v2',
        target = "{{this.schema}}.{{this.identifier}}",
        params ={ "external_table" :"abi_new",
        "sql_limit" :"100",
        "producer_batch_size" :"1",
        "worker_batch_size" :"1",
        "sql_source" :"{{this.identifier}}" }
    ),
    tags = ['streamline_abis_realtime']
) }}

WITH recent_relevant_contracts AS (
    -- because we wanna get old and new contracts that have recently gotten relevant

    SELECT
        contract_address,
        total_interaction_count,
        GREATEST(
            max_inserted_timestamp_logs,
            max_inserted_timestamp_traces
        ) max_inserted_timestamp
    FROM
        {{ ref('silver__relevant_contracts') }} C

{% if is_incremental() %}
LEFT JOIN {{ ref("streamline__complete_contract_abis") }}
s USING (contract_address)
{% else %}
    LEFT JOIN {{ ref("bronze_api__contract_abis") }}
    b USING (contract_address)
{% endif %}
WHERE
    1 = 1

{% if is_incremental() %}
AND s.contract_address IS NULL
{% else %}
    AND b.contract_address IS NULL
{% endif %}
AND total_interaction_count > {{ var('BLOCK_EXPLORER_ABI_INTERACTION_LIMIT') }}
AND max_inserted_timestamp >= DATEADD(DAY, -3, SYSDATE())
ORDER BY
    total_interaction_count DESC
LIMIT
    {{ var('BLOCK_EXPLORER_ABI_LIMIT') }}
), all_contracts AS (
    SELECT
        contract_address
    FROM
        recent_relevant_contracts

{% if is_incremental() %}
UNION
SELECT
    contract_address
FROM
    {{ ref('_retry_abis') }}
{% endif %}
)
SELECT
    contract_address,
    DATE_PART('EPOCH_SECONDS', systimestamp()) :: INT AS partition_key,
    live.udf_api(
        'GET',
        CONCAT(
            '{{ var(' block_explorer_abi_url ') }}',
            contract_address,
            '&apikey={key}'
        ),{ 'User-Agent': 'FlipsideStreamline' },{},
        '{{ var(' block_explorer_abi_api_key_path ') }}'
    ) AS request
FROM
    all_contracts
