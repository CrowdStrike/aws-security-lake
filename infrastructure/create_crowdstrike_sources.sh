#!/bin/bash
# CrowdStrike Amazon Security Lake Custom Sources - v0.1

SUPPORTED_OCSF_CLASSES=(
    "PROCESS_ACTIVITY"
    "MODULE_ACTIVITY"
    "FILE_ACTIVITY"
    "DNS_ACTIVITY"
    "NETWORK_ACTIVITY"
    # Not supported by Amazon Security Lake
    # "KERNEL_EXTENSION_ACTIVITY"
)

SECURITY_LAKE_REGION=
GLI_ARN=
ACCOUNT_ID=
ROLE_EXTERNALID="CrowdStrikeCustomSource"

# jq is required
if ! command -v jq &> /dev/null
then
    echo "[X] jq is not installed. Please install it before running this script"
    exit 1
fi

if [[ -z "${EXTERNALID}" ]]; then
    echo "Using default external ID: ${ROLE_EXTERNALID} (set EXTERNALID env var to override)"
else
    ROLE_EXTERNALID="${EXTERNALID}"
fi

# Check if we have a "AWS region" set in an environment variable before prompting...
if [[ -z "${AWS_REGION}" ]]; then
    read -p "[?] AWS Region: " SECURITY_LAKE_REGION
else
    SECURITY_LAKE_REGION="${AWS_REGION}"
fi

# Check if we have a "AWS account ID" set in an environment variable before prompting...
if [[ -z "${AWS_ACCOUNT_ID}" ]]; then
    read -p "[?] AWS Account ID: " ACCOUNT_ID
else
    ACCOUNT_ID="${AWS_ACCOUNT_ID}"
fi

read -p "[?] ARN of IAM Role that has permissions to Invoke Glue: " GLI_ARN

echo "[!] Checking to see if at least one source is enabled..."
SOURCES=$(aws securitylake get-data-lake-sources)

NUM_SOURCES=$(echo $SOURCES | jq -r '.dataLakeSources | length')
if [ "$NUM_SOURCES" == "0" ] || [ "$NUM_SOURCES" == "" ] ; then
    echo "[X] You haven't setup at least one Amazon Security Lake source yet, please do that first"
    exit 1
fi
echo "[!] $NUM_SOURCES sources exist, continuing..."


for klass in ${SUPPORTED_OCSF_CLASSES[@]}; do
    source_name="CrowdStrike_${klass}"
    # The sourceType field from the `get-region-status` output...
    aws_source_type="CrowdStrike_${klass} (${klass})"

    # Has this custom data source already been created?
    #
    # This is calculated by looking at all the sources for a given AWS account and
    # match the sourceType to ours and then ensure they're in our target account (defined by the user)
    SOURCE_ACCOUNT_ID=$(echo $SOURCES | jq --arg AWS_SOURCE_TYPE "${aws_source_type}" -e -r '.dataLakeSources[] | select(.sourceType==$AWS_SOURCE_TYPE).account')

    if [ "$SOURCE_ACCOUNT_ID" == "$ACCOUNT_ID" ]; then
        echo "[!] ${source_name} already exists, skipping..."
        continue
    fi

    echo "[+] Creating ${source_name}..."
    aws securitylake create-custom-log-source \
        --configuration "{\"crawlerConfiguration\":{\"roleArn\":\"$GLI_ARN\"},\"providerIdentity\":{\"externalId\":\"$ROLE_EXTERNALID\",\"principal\":\"$ACCOUNT_ID\"}}" \
        --event-classes "[\"$klass\"]" \
        --source-name ${source_name} \
        --region ${SECURITY_LAKE_REGION}
done