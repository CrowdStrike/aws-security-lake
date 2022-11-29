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
STACK_NAME=
GLI_ARN=
LP_ARN=
ACCOUNT_ID=

# check if we're in a python venv
if [[ -z "${VIRTUAL_ENV}" ]]; then
    echo "[X] You do not appear to be in a python venv. Please ensure you have the aws-cli installed that supports Amazon Security Lake."
    exit 1
else
    venv=$(echo "${VIRTUAL_ENV}" | tr '[:upper:]' '[:lower:]')
    if ! [[ "${venv}" =~ "amazon-security-lake" ]]; then
        echo "[X] You do not appear to be in a Amazon Security Lake python venv, if you are sure.. Please confirm"
        read -p "[?] Are you in a python venv that supports Amazon Security Lake? (Y/N): " betaCLI
        if [[ $betaCLI == [nN] || $betaCLI == [nN][oO] ]]; then
            exit 1
        fi
    fi
fi

# jq is required
if ! command -v jq &> /dev/null
then
    echo "[X] jq is not installed. Please install it before running this script"
    exit 1
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

# Check if we have a "CS_SECURITY_LAKE_STACK_NAME" set in an environment variable before prompting...
if [[ -z "${CS_SECURITY_LAKE_STACK_NAME}" ]]; then
    read -p "[?] Stack Name: " STACK_NAME
else
    STACK_NAME="${CS_SECURITY_LAKE_STACK_NAME}"
fi

PROD_ENDPOINT=${PROD_ENDPOINT:-https://account-management."$SECURITY_LAKE_REGION".prod.security-lake.aws.dev}

echo "[!] Checking to see if at least one source is enabled..."
SOURCES=$(aws security-lake get-region-status --region ${SECURITY_LAKE_REGION} --endpoint-url ${PROD_ENDPOINT})
NUM_SOURCES=$(echo $SOURCES | jq -r '.accountSourcesList | length')
if [ "$NUM_SOURCES" == "0" ] || [ "$NUM_SOURCES" == "" ] ; then
    echo "[X] You haven't setup at least one Amazon Security Lake source yet, please do that first"
    exit 1
fi
echo "[!] $NUM_SOURCES sources exist, continuing..."

echo "[!] Checking to see if the external source CloudFormation stack exists with name ${STACK_NAME}..."
STACK_EXISTS=$(aws cloudformation describe-stacks --stack-name=$STACK_NAME)
if ! [ $? -eq 0 ]; then
    echo "[X] There doesn't seem to be a CloudFormation stack with the name $STACK_NAME. Would you like us to create it for you?"
    read -p "[?] Please confirm (Y/N): " giveMeTheStack

    if [[ $giveMeTheStack == [yY] || $giveMeTheStack == [yY][eE][sS] ]]; then
        echo "[!] Creating CloudFormation stack ${STACK_NAME}"
        aws cloudformation create-stack --stack-name $STACK_NAME \
            --template-body file://cloudFormationExternalData.json \
            --capabilities CAPABILITY_NAMED_IAM \
            --parameters \
            ParameterKey=accountId,ParameterValue=$ACCOUNT_ID \
            ParameterKey=customSource,ParameterValue=CrowdStrike

        # wait for it to finish...
        echo "[!] Waiting for ${STACK_NAME}..."
        aws cloudformation wait stack-create-complete --stack-name $STACK_NAME
        sleep 10
    else
        exit 1
    fi
fi

GLI_ARN=$(aws cloudformation describe-stacks \
   --stack-name $STACK_NAME \
   --query "Stacks[0].Outputs[?OutputKey=='SecurityLakeGlueInvocationRole'].OutputValue" --output text)

LP_ARN=$(aws cloudformation describe-stacks \
   --stack-name $STACK_NAME \
   --query "Stacks[0].Outputs[?OutputKey=='LogProviderRole'].OutputValue" --output text)


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
    aws security-lake register-custom-data \
        --custom-source-name ${source_name} \
        --event-class ${klass} \
        --glue-invocation-role-arn  ${GLI_ARN} \
        --log-provider-access-role-arn ${LP_ARN} \
        --log-provider-account-id ${ACCOUNT_ID} \
        --region ${SECURITY_LAKE_REGION} \
        --endpoint-url ${PROD_ENDPOINT}
done
