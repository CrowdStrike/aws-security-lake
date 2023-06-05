![CrowdStrike Falcon](https://raw.githubusercontent.com/CrowdStrike/falconpy/main/docs/asset/cs-logo.png)

<br>

![Twitter URL](https://img.shields.io/twitter/url?label=Follow%20%40CrowdStrike&style=social&url=https%3A%2F%2Ftwitter.com%2FCrowdStrike)

# CrowdStrike Falcon Data Replicator and Amazon Security Lake Integration Guide

## Table of Contents

- [CrowdStrike Falcon Data Replicator and Amazon Security Lake Integration Guide](#crowdstrike-falcon-data-replicator-and-amazon-security-lake-integration-guide)
  - [Table of Contents](#table-of-contents)
  - [Overview](#overview)
    - [What is Falcon Data Replicator](#what-is-falcon-data-replicator)
    - [What is Amazon Security Lake](#what-is-amazon-security-lake)
    - [Integration overview](#integration-overview)
    - [Prerequisites](#prerequisites)
  - [Integration guide](#integration-guide)
    - [1. Setup Falcon Data Replicator (FDR)](#1-setup-falcon-data-replicator-fdr)
    - [2. Setting up CrowdStrike as a Amazon Security Lake Provider](#2-setting-up-crowdstrike-as-a-amazon-security-lake-provider)
      - [2.1 Create Glu IAM Roles](#21-create-glu-iam-roles)
      - [2.2 Register CrowdStrike as custom source provider](#22-register-crowdstrike-as-custom-source-provider)
      - [2.3 Create Custom Resource Write Role](#23-create-custom-resource-write-role)
    - [3. Configuring and running the Falcon Data Replicator application](#3-configuring-and-running-the-falcon-data-replicator-application)
    - [4. Validation](#4-validation)
  - [Support](#support)
  - [References](#references)

## Overview

### What is Falcon Data Replicator

CrowdStrike Falcon Data Replicator (FDR) delivers and enriches endpoint, cloud workload and identity data with the CrowdStrike Security Cloud and world-class artificial intelligence (AI), enabling your team to derive actionable insights to improve security operations center (SOC) performance. FDR contains near real-time data collected by the CrowdStrike Falcon® platform via its single, lightweight Falcon agent across all of your cloud workloads, identities and managed endpoints, including laptops, servers, workstations and mobile devices. The data is ingested, transformed and analyzed to address your organization’s unique needs, using cloud delivery and storage mechanisms such as AWS S3 buckets and Google Cloud buckets.

### What is Amazon Security Lake

Amazon Security Lake is a fully-managed security data lake service that allows you to centrally aggregate, manage, and use security-related log and event data at scale. Amazon Security Lake makes it easy and cost-effective for organizations to centrally consolidate their security logs and events from AWS, on-premises, and other cloud providers. Amazon Security Lake automates the collection of security-related log and **event** data from integrated AWS services and third party sources, manages the lifecycle of that data with customizable retention settings and roll up to preferred AWS Regions, and transforms that data into a standard open-source format called Open Cybersecurity Schema Framework (OCSF). You can use the security data that's stored and accessed in Amazon Security Lake for incident response and security data analytics.

### Integration overview

This integration guide provides instructions for transforming and loading data from FDR to Amazon Security Lake. This integration will:

1. Pull the customer’s FDR data from CrowdStrike's S3 bucket
1. Extract and transform a subset of data into Open Cybersecurity Schema Framework (OCSF)
1. Convert it to Parquet files
1. Upload it to the customer-owned Amazon S3 bucket for Amazon Security Lake to ingest

While FDR data encompasses a large amount of events, only certain events are applicable for Amazon Security Lake. Only events classified to the following OSCF classes are mapped and loaded into Amazon Security Lake:

- DNS (DNS_ACTIVITY)
- File (FILE_ACTIVITY)
- Kernel Extension (MODULE_ACTIVITY)
- Network Activity (NETWORK_ACTIVITY)
- Process Activity (PROCESS_ACTIVITY)

### Prerequisites

- AWS CLI version greater than `2.11.24`
- You must be a customer of CrowdStrike Insights XDR and Falcon Data Replicator
- Contact your CrowdStrike account manager to obtain the FDR OCSF mapping files
- Contact your CrowdStrike account manager to start using FDR
- An AWS account with at least one AWS source pre-configured with Amazon Security Lake (e.g. CloudTrail, VPC Flow, Route53)

## Integration guide

### 1. Setup Falcon Data Replicator (FDR)

In this step, you'll set up FDR in your CrowdStrike Customer ID (CID). This will provide you access to the CrowdStrike-owned S3 bucket, SQS queue, and credentials to fetch the FDR files.

1. Contact your CrowdStrike account representative to set up your FDR feed
1. In the Falcon console, go to `Support and resources > Resources and tools > API clients and keys` and click `Create new credentials` under **FDR AWS S3 Credentials and SQS Queue**
   1. *This process provides you with several items you'll need later when setting up an SQS consumer to check for new data:*
      1. `Client ID` to use later as `AWS_KEY`
      1. `Secret` to use later as `AWS_SECRET`
      1. `SQS URL` to use later as `QUEUE_URL`

### 2. Setting up CrowdStrike as a Amazon Security Lake Provider

In this step, you'll set up the required resources for CrowdStrike to be registered as a custom provider in Amazon Security Lake and register the supporting source types.

**Execute the instructions below in your master Amazon Security Lake account.**

#### 2.1 Create Glu IAM Roles

Please follow AWS's guidance on creating an IAM role that allows Security Lake to interact with custom sources: [Prerequisite: Create IAM role before adding custom sources](https://docs.aws.amazon.com/security-lake/latest/userguide/custom-sources.html). If you've already created the IAM role, record the ARN as you'll need it for the next step.

#### 2.2 Register CrowdStrike as custom source provider

In this step, you'll run a script that will register CrowdStrike sources for each supported OCSF Event Class with Amazon Security Lake.

This script will also create an IAM role that will be used to write data to your Amazon Security Lake bucket.

1. From the root of this project's directory, run the following script: `sh ./infrastructure/create_crowdstrike_sources.sh`
   1. When prompted for the `ARN of IAM Role that has permissions to Invoke Glue`, use the ARN from 2.1


#### 2.3 Create Custom Resource Write Role

  The Falcon Data Replicator (FDR) application will write data to your Amazon Security Lake bucket. To do this, you'll need to create an IAM role with the least amount of permissions and has the correct ExternalId. This repo contains a CloudFormation template that will create the role for you.

  Use the `./infrastructure/iam_role.yaml` CloudFormation template to create the role.

  | Parameter | Description | Required | Default |
  | --------- | ----------- | -------- | ------- |
  | BucketName | The name of the S3 bucket to write data to. Use the bucket in the same region you created the custom sources. You can find the buckets used by security lake by going to `Security Lake > Regions` | Yes | N/A |
  | AccountId | The AWS account ID where the FDR github tool will be deployed. | Yes | N/A |
  | RoleName | The name of the role to create. | No | `CrowdStrike-AmazonSecurityLake-CustomSourceRole` |
  | ExternalId | The External ID to use for the role. This is used to prevent privilege escalation. Use the same External ID you used in step 2.2 | No | `CrowdStrikeCustomSource` |
### 3. Configuring and running the Falcon Data Replicator application

In this step, you'll configure and run a script that reads files written to your FDR bucket, transforms it to OSFC schema, and loads it into Amazon Security Lake.

1. Clone the [FDR application](https://github.com/CrowdStrike/FDR) project from GitHub to your machine
1. Place the mapping files you obtained from your account manager into the `./ocsf/mappings` directory of your project
1. Open `falcon_data_replicator.ini` in a text editor and provide CrowdStrike FDR and Amazon Security Lake S3 details:
   1. Under `[Source]`:
      1. `AWS_KEY`={{ Replace with value from step 1 }}
      1. `AWS_SECRET`={{ Replace with value from step 1 }}
      1. `QUEUE_URL`={{ Replace with value from step 1 }}
      1. `REGION_NAME`={{ Replace with proper value below }}
         1. If your CID is in `us-1`, then replace with `us-west-1`
         1. If your CID is in `us-2`, then replace with `us-west-2`
         1. If your CID is in `eu-1`, then replace with `eu-central-1`
   1. Under `[Destination]`:
      1. `TARGET_ACCOUNT_ID`={{ Replace with AWS Security Lake account ID }}
      1. `TARGET_BUCKET`={{ Replace with value you received from Amazon Security Lake }}
      1. `TARGET_REGION`={{ Replace with value you received from Amazon Security Lake }}
      1. `DO_OCSF_CONVERSION`=yes
      1. `OCSF_ROLE_NAME`={{ Replace with name of the role created from the CFT in step 2.3. Default is `CrowdStrike-AmazonSecurityLake-CustomSourceRole` }}
      1. `OCSF_ROLE_EXTERNAL_ID`={{ Replace with value from step 2.3. Default is `CrowdStrikeCustomSource` }}
1. Run the application in the same account where your Amazon Security Lake master is configured by issuing the following command: `python falcon_data_replicator.py`

### 4. Validation

To validate that the integration is working successfully, log-in to your AWS account where Amazon Security Lake is configured and click on “Custom Sources”. You should see several CrowdStrike sources based on each of the supported OCSF event classes.

## Support

The integration guide is an open source project and not a CrowdStrike product. As such, it carries no formal support, expressed, or implied. If you encounter any issues while deploying the integration guide, you can create an issue on our Github repository for bugs, enhancements, or other requests.

Amazon Security Lake is an AWS product. As such, any questions or problems you experience with this service should be handled through a support ticket with AWS Support.

## References

- [CrowdStrike Falcon Data Replicator (FDR) Data Sheet](https://www.crowdstrike.com/wp-content/uploads/2022/06/crowdstrike-falcon-data-replicator-data-sheet.pdf)
