# Voicemail Express Deployment Guide

## Overview
This guide provides step-by-step instructions for deploying the Voicemail Express solution for Amazon Connect through AWS CloudFormation. The solution includes customized department-specific email routing for voicemail delivery.

## Prerequisites
- AWS CLI installed and configured
- Access to an AWS account with appropriate permissions
- Amazon Connect instance already set up

## Deployment Steps

### 1. Set Up Project Structure
Ensure you have the necessary CloudFormation templates:
- CloudFormation/vmx3.yaml (main template)
- CloudFormation/vmx3-core.yaml
- CloudFormation/vmx3-contactflows.yaml (customized with department emails)
- CloudFormation/vmx3-lambda-functions.yaml
- CloudFormation/vmx3-policy-builder.yaml
- CloudFormation/vmx3-ses-setup.yaml
- CloudFormation/vmx3-triggers.yaml

### 2. Create Parameters File
Create a file at `CloudFormation/parameters/dev-parameters.json` with the necessary parameters, including the department email addresses and the S3 bucket prefix:

```json
[
  {
    "ParameterKey": "EXPDevBucketPrefix",
    "ParameterValue": "dev-vmx3-"
  },
  {
    "ParameterKey": "ConnectInstanceAlias",
    "ParameterValue": "your-connect-instance-alias"
  },
  {
    "ParameterKey": "ConnectInstanceARN",
    "ParameterValue": "your-connect-instance-arn"
  },
  {
    "ParameterKey": "ClientServicesAgentEmail",
    "ParameterValue": "client-services@example.com"
  },
  {
    "ParameterKey": "SalesAgentEmail",
    "ParameterValue": "sales@example.com"
  },
  {
    "ParameterKey": "MarketingAgentEmail",
    "ParameterValue": "marketing@example.com"
  },
  {
    "ParameterKey": "HRAgentEmail",
    "ParameterValue": "hr@example.com"
  },
  {
    "ParameterKey": "OtherAgentEmail",
    "ParameterValue": "general@example.com"
  }
  // Include other required parameters...
]
```

### 3. Create S3 Bucket for Templates
Create an S3 bucket that matches the format specified in your parameters:

```powershell
aws s3 mb s3://dev-vmx3-vmx-source-us-east-1 --region us-east-1 --profile ops
```

### 4. Upload Templates to S3
Upload all required templates to the correct location in S3:

```powershell
aws s3 cp .\CloudFormation\vmx3-core.yaml s3://dev-vmx3-vmx-source-us-east-1/vmx3/2024.09.01/cloudformation/ --profile ops
aws s3 cp .\CloudFormation\vmx3-contactflows.yaml s3://dev-vmx3-vmx-source-us-east-1/vmx3/2024.09.01/cloudformation/ --profile ops
aws s3 cp .\CloudFormation\vmx3-lambda-functions.yaml s3://dev-vmx3-vmx-source-us-east-1/vmx3/2024.09.01/cloudformation/ --profile ops
aws s3 cp .\CloudFormation\vmx3-policy-builder.yaml s3://dev-vmx3-vmx-source-us-east-1/vmx3/2024.09.01/cloudformation/ --profile ops
aws s3 cp .\CloudFormation\vmx3-ses-setup.yaml s3://dev-vmx3-vmx-source-us-east-1/vmx3/2024.09.01/cloudformation/ --profile ops
aws s3 cp .\CloudFormation\vmx3-triggers.yaml s3://dev-vmx3-vmx-source-us-east-1/vmx3/2024.09.01/cloudformation/ --profile ops
```

### 5. Deploy the CloudFormation Stack
Deploy the main template using the AWS CLI:

```powershell
aws cloudformation deploy `
  --template-file CloudFormation/vmx3.yaml `
  --stack-name dev-1159-voicemail-VMX3 `
  --parameter-overrides file://CloudFormation/parameters/dev-parameters.json `
  --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND `
  --profile ops
```

### 6. Monitor Deployment
Monitor the deployment progress in the AWS CloudFormation console or using the AWS CLI:

```powershell
aws cloudformation describe-stack-events --stack-name dev-1159-voicemail-VMX3 --profile ops
```

## Technical Details

### Template Structure
- **vmx3.yaml**: Main template that orchestrates the deployment of nested stacks
- **vmx3-core.yaml**: Deploys core infrastructure including S3 buckets and IAM roles
- **vmx3-contactflows.yaml**: Creates Connect contact flows including department-specific routing
- **vmx3-lambda-functions.yaml**: Deploys Lambda functions for voicemail processing
- **vmx3-policy-builder.yaml**: Creates IAM policies for the solution components
- **vmx3-ses-setup.yaml**: Configures SES for email delivery (if enabled)
- **vmx3-triggers.yaml**: Sets up event triggers between components

### EXPDevBucketPrefix Parameter
The `EXPDevBucketPrefix` parameter is critical for deployment as it defines the S3 bucket where templates and resources are stored. When set to "dev-vmx3-", the system will look for templates at:
`s3://dev-vmx3-vmx-source-us-east-1/vmx3/2024.09.01/cloudformation/`

## Post-Deployment
After successful deployment, you can:
1. Test the voicemail functionality by calling the provided test number
2. Configure additional routing rules in Amazon Connect
3. Verify voicemail delivery to the specified department email addresses

## Troubleshooting
- If deployment fails, check CloudFormation events for specific error messages
- Ensure all templates are uploaded to the correct S3 location
- Verify that the Amazon Connect instance has the necessary permissions
- Check that all parameters in the dev-parameters.json file are correct
