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
CFT_ROLE_NAME="CrowdStrike-AmazonSecurityLake-CustomSourceRole"
CFT_BUCKET_NAME=
CFT_EXTERNALID="CrowdStrikeCustomSource"
CFT_STACKNAME="CrowdStrike-AmazonSecurityLake-CustomSourceRole"

# jq is required
if ! command -v jq &> /dev/null
then
    echo "[X] jq is not installed. Please install it before running this script"
    exit 1
fi

# Check if we have a "ROLE_NAME" set in an environment variable
if [[ -z "${ROLE_NAME}" ]]; then
    echo "Using default role name: ${CFT_ROLE_NAME} (set ROLE_NAME env var to override)"
else
    CFT_ROLE_NAME="${ROLE_NAME}"
fi

# Check if we have a "EXTERNALID" set in an environment variable
if [[ -z "${EXTERNALID}" ]]; then
    echo "Using default external ID: ${CFT_EXTERNALID} (set EXTERNALID env var to override)"
else
    CFT_EXTERNALID="${EXTERNALID}"
fi

# Check if we have a "CFT_STACKNAME" set in an environment variable
if [[ -z "${STACKNAME}" ]]; then
    echo "Using default CloudFormation stack name: ${CFT_STACKNAME} (set STACKNAME env var to override)"
else
    CFT_STACKNAME="${CFT_STACKNAME}"
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


# Check if we have a "BUCKET_NAME" set in an environment variable before prompting...
if [[ -z "${BUCKET_NAME}" ]]; then
    read -p "[?] S3 Bucket name to write source to: " BUCKET_NAME
else
    BUCKET_NAME="${BUCKET_NAME}"
fi

read -p "[?] ARN of IAM Role that has permissions to Invoke Glue: " GLI_ARN

echo "[!] Checking to see if at least one source is enabled..."
SOURCES=$(aws securitylake get-datalake-status)
NUM_SOURCES=$(echo $SOURCES | jq -r '.accountSourcesList | length')
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
    SOURCE_ACCOUNT_ID=$(echo $SOURCES | jq --arg AWS_SOURCE_TYPE "${aws_source_type}" -e -r '.accountSourcesList[] | select(.sourceType==$AWS_SOURCE_TYPE).account')

    if [ "$SOURCE_ACCOUNT_ID" == "$ACCOUNT_ID" ]; then
        echo "[!] ${source_name} already exists, skipping..."
        continue
    fi

    echo "[+] Creating ${source_name}..."
    aws securitylake create-custom-log-source  \
        --custom-source-name ${source_name} \
        --event-class ${klass} \
        --glue-invocation-role-arn  ${GLI_ARN} \
        --log-provider-account-id ${ACCOUNT_ID} \
        --region ${SECURITY_LAKE_REGION}
done

aws cloudformation create-stack \
    --stack-name ${ROLE_NAME} \
    --template-body file://infrastructure/iam_role.yaml \
    --capabilities CAPABILITY_NAMED_IAM \
    --parameters ParameterKey=ExternalId,ParameterValue=${EXTERNALID} \
                 ParameterKey=BucketName,ParameterValue=${BUCKET_NAME} \
                 ParameterKey=RoleName,ParameterValue=${ROLE_NAME} \
    --region ${SECURITY_LAKE_REGION}