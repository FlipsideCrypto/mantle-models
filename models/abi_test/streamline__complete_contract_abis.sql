-- depends on: {{ ref('bronze__streamline_contract_abis') }}
{{ config (
    materialized = "incremental",
    unique_key = "complete_contract_abis_id",
    cluster_by = "partition_key",
    post_hook = "ALTER TABLE {{ this }} ADD SEARCH OPTIMIZATION on equality(complete_contract_abis_id)",
    incremental_predicates = ["dynamic_range", "partition_key"],
    tags = ['streamline_abis_complete']
) }}

SELECT
    partition_key,
    -- decide if need to remove this
    COALESCE(
        VALUE :"CONTRACT_ADDRESS" :: STRING,
        VALUE :"contract_address" :: STRING
    ) AS contract_address,
    {{ dbt_utils.generate_surrogate_key(
        ['contract_address']
    ) }} AS complete_contract_abis_id,
    _inserted_timestamp

{% if is_incremental() %}
{{ ref('bronze__streamline_contract_abis') }}
WHERE
    _inserted_timestamp >= (
        SELECT
            MAX(_inserted_timestamp) _inserted_timestamp
        FROM
            {{ this }}
    )
{% else %}
    {{ ref('bronze__streamline_fr_contract_abis') }}
    -- union in bronze_api__contract_abis
{% endif %}

qualify(ROW_NUMBER() over (PARTITION BY complete_contract_abis_id
ORDER BY
    _inserted_timestamp DESC)) = 1
