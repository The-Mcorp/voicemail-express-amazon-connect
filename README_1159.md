# Voicemail Express Deployment Guide

## Overview
This guide provides step-by-step instructions for deploying the Voicemail Express solution for Amazon Connect through AWS CloudFormation. The solution includes customized department-specific email routing for voicemail delivery.

## Prerequisites
- AWS CLI installed and configured
- Access to an AWS account with appropriate permissions
- Amazon Connect instance already set up

## Deployment Steps

### 1. Set Up Project Structure
Ensure you have the necessary files:

**CloudFormation Templates:**
- CloudFormation/vmx3.yaml (main template)
- CloudFormation/vmx3-core.yaml
- CloudFormation/vmx3-contactflows.yaml (customized with department emails)
- CloudFormation/vmx3-lambda-functions.yaml
- CloudFormation/vmx3-policy-builder.yaml
- CloudFormation/vmx3-ses-setup.yaml
- CloudFormation/vmx3-triggers.yaml

**Lambda Function Source Code:**
- Code/Core/vmx3_ses_template_tool.py
- Code/Core/vmx3_guided_flow_presigner.py
- Code/Core/vmx3_kvs_to_s3.py
- Code/Core/vmx3_packager.py
- Code/Core/vmx3_presigner.py
- Code/Core/vmx3_transcriber.py
- Code/Core/vmx3_transcription_error_handler.py
- Code/Core/sub_connect_task.py
- Code/Core/sub_connect_guided_task.py
- Code/Core/sub_ses_email.py

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

### 4. Upload Templates and Lambda Function Packages
First, upload all CloudFormation templates to the correct location in S3:

```powershell
aws s3 cp .\CloudFormation\vmx3-core.yaml s3://dev-vmx3-vmx-source-us-east-1/vmx3/2024.09.01/cloudformation/ --profile ops
aws s3 cp .\CloudFormation\vmx3-contactflows.yaml s3://dev-vmx3-vmx-source-us-east-1/vmx3/2024.09.01/cloudformation/ --profile ops
aws s3 cp .\CloudFormation\vmx3-lambda-functions.yaml s3://dev-vmx3-vmx-source-us-east-1/vmx3/2024.09.01/cloudformation/ --profile ops
aws s3 cp .\CloudFormation\vmx3-policy-builder.yaml s3://dev-vmx3-vmx-source-us-east-1/vmx3/2024.09.01/cloudformation/ --profile ops
aws s3 cp .\CloudFormation\vmx3-ses-setup.yaml s3://dev-vmx3-vmx-source-us-east-1/vmx3/2024.09.01/cloudformation/ --profile ops
aws s3 cp .\CloudFormation\vmx3-triggers.yaml s3://dev-vmx3-vmx-source-us-east-1/vmx3/2024.09.01/cloudformation/ --profile ops
```

Next, package and upload the Lambda function code:

```powershell
# Create a directory to package the Lambda functions
mkdir -p LambdaPackages

# Create zip files for each Lambda function with CORRECT FILENAMES
# Important: Note the file naming differences between source and destination

# For the SES tools - CRITICAL NAMING CORRECTION
Compress-Archive -Path ".\Code\Core\vmx3_ses_template_tool.py" -DestinationPath ".\LambdaPackages\vmx3_ses_template_tool.py.zip" -Force

# For Python Layer - CRITICAL - REQUIRED FOR LAMBDA STACK
# Create a proper Python layer package with dependencies
mkdir -p python_layer/python

# Create a requirements.txt file
@"
boto3>=1.26.0
requests>=2.28.1
aws-lambda-powertools>=2.15.0
cffi>=1.15.1
"@ | Out-File -FilePath requirements.txt -Encoding utf8

# Install dependencies into python directory
pip install -r requirements.txt -t python_layer/python/

# Create the zip with the CORRECT NAME
cd python_layer
Compress-Archive -Path "python" -DestinationPath "../LambdaPackages/vmx3_common_python.zip" -Force
cd ..

# For other required Lambda functions
Compress-Archive -Path ".\Code\Core\vmx3_guided_flow_presigner.py" -DestinationPath ".\LambdaPackages\vmx3_guided_flow_presigner.py.zip" -Force
Compress-Archive -Path ".\Code\Core\vmx3_kvs_to_s3.py" -DestinationPath ".\LambdaPackages\vmx3_kvs_to_s3.py.zip" -Force
Compress-Archive -Path ".\Code\Core\vmx3_packager.py" -DestinationPath ".\LambdaPackages\vmx3_packager.py.zip" -Force
Compress-Archive -Path ".\Code\Core\vmx3_presigner.py" -DestinationPath ".\LambdaPackages\vmx3_presigner.py.zip" -Force
Compress-Archive -Path ".\Code\Core\vmx3_transcriber.py" -DestinationPath ".\LambdaPackages\vmx3_transcriber.py.zip" -Force
Compress-Archive -Path ".\Code\Core\vmx3_transcription_error_handler.py" -DestinationPath ".\LambdaPackages\vmx3_transcription_error_handler.py.zip" -Force
Compress-Archive -Path ".\Code\Core\sub_connect_task.py" -DestinationPath ".\LambdaPackages\vmx3_connect_task.py.zip" -Force
Compress-Archive -Path ".\Code\Core\sub_connect_guided_task.py" -DestinationPath ".\LambdaPackages\vmx3_connect_guided_task.py.zip" -Force
Compress-Archive -Path ".\Code\Core\sub_ses_email.py" -DestinationPath ".\LambdaPackages\vmx3_ses_email.py.zip" -Force

# Create the zip directory in S3 if it doesn't exist
aws s3 mb s3://dev-vmx3-vmx-source-us-east-1/vmx3/2024.09.01/zip/ --profile ops

# Upload all Lambda zip files
aws s3 cp .\LambdaPackages\ s3://dev-vmx3-vmx-source-us-east-1/vmx3/2024.09.01/zip/ --recursive --profile ops

# Verify the uploads
aws s3 ls s3://dev-vmx3-vmx-source-us-east-1/vmx3/2024.09.01/zip/ --profile ops
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

## Deployment Success (Updated March 20, 2025)

The Voicemail Express stack `dev-1159-voicemail-VMX3` has been successfully deployed. All nested stacks have completed successfully:

1. ✅ **VMXCoreStack** - Deployed core infrastructure
2. ✅ **VMXContactFlowStack** - Created Connect contact flows
3. ✅ **VMXSESSetupStack** - Configured email delivery
4. ✅ **VMXLambdaStack** - Deployed Lambda functions
5. ✅ **VMXPolicyStack** - Created necessary IAM policies
6. ✅ **VMXTriggersStack** - Set up event triggers between components

### Key Learnings During Deployment

1. **Python Layer Naming** - The Lambda stack expects the Python Layer to be named `vmx3_common_python.zip`, not `python.zip`. Ensuring this filename matches what's expected in the CloudFormation template is critical.

2. **Layer Structure** - AWS Lambda Layers require a specific directory structure with Python packages inside a `python/` directory. The correct structure was created and uploaded.

3. **Dependencies** - For this solution, the Python Layer includes these key dependencies:
   - boto3
   - requests
   - aws-lambda-powertools
   - cffi

### Smoke Testing Checklist

- [ ] Make test call and leave voicemail
- [ ] Verify recording is stored in S3
- [ ] Confirm transcription is created
- [ ] Check email delivery to correct department
- [ ] Validate presigned URLs for recordings work properly
- [ ] Test different department routing scenarios

## Known Issues and Solutions

### File Naming Conventions (CRITICAL)
The CloudFormation templates expect specific file names that might differ from the source files:

- `vmx3_ses_template_tool.py` should be packaged as `vmx3_ses_template_tool.py.zip` (not `vmx3_ses_tools.py.zip`)
- The Python Layer package must be named `vmx3_common_python.zip` as per the `vmx3-lambda-functions.yaml` template

### Duplicate Resources Section
Ensure that each CloudFormation template has only one `Resources:` section. Multiple sections will cause deployment failures.

### Resource Name Conflicts
If you receive an error like "Resource already exists with that name":

1. Check the Amazon Connect console for existing contact flows with the same name
2. Delete any conflicting resources before redeploying
3. Alternatively, manually add a unique suffix to resource names in the templates

### Contact Flow Issues
If VMXContactFlowStack fails:

1. Make sure the VMXCustomFlow resource has a unique name
2. Verify that all referenced resources (modules, queues) exist
3. Check for proper JSON escaping in the contact flow Content property

### Lambda Function Issues
If you encounter "S3 Error Code: NoSuchKey. The specified key does not exist" errors:

1. Verify that all Lambda function zip files are correctly uploaded to the S3 path: `s3://dev-vmx3-vmx-source-us-east-1/vmx3/2024.09.01/zip/`
2. Check that the filename matches what's expected in the CloudFormation template
3. Ensure all Python dependencies are included in the zip files if required
4. For the Python Layer, ensure it follows AWS Lambda Layer requirements (Python packages inside a python/ directory)

## Troubleshooting
- If deployment fails, check CloudFormation events for specific error messages
- For JSON validation issues, use tools like jsonlint.com to verify template syntax
- Ensure all templates are uploaded to the correct S3 location
- Verify that the Amazon Connect instance has the necessary permissions
- Check that all parameters in the dev-parameters.json file are correct
- Examine Lambda function code and naming to ensure it matches CloudFormation expectations
- Use the AWS CloudFormation console to view detailed error messages in nested stacks
- Check S3 bucket contents to verify all required files are present with correct paths

## Command Reference

### Reset/Delete Stack
If you need to completely reset your deployment:

```powershell
aws cloudformation delete-stack --stack-name dev-1159-voicemail-VMX3 --profile ops
```

### Validate Template
To check templates for syntax errors before deployment:

```powershell
aws cloudformation validate-template --template-body file://CloudFormation/vmx3-contactflows.yaml --profile ops
```

### Check S3 Contents
To verify files in your S3 bucket:

```powershell
# List templates
aws s3 ls s3://dev-vmx3-vmx-source-us-east-1/vmx3/2024.09.01/cloudformation/ --profile ops

# List Lambda packages
aws s3 ls s3://dev-vmx3-vmx-source-us-east-1/vmx3/2024.09.01/zip/ --profile ops
```

### Examine Specific Lambda Function
If you need to check the content of a Lambda function code in S3:

```powershell
aws s3 cp s3://dev-vmx3-vmx-source-us-east-1/vmx3/2024.09.01/zip/vmx3_ses_template_tool.py.zip . --profile ops
```

### Check Lambda Function Reference in Template
To find where and how Lambda function files are referenced in templates:

```powershell
grep -r "python.zip" CloudFormation/
```

## Monitoring and Maintenance

For ongoing operations:

1. **Monitor CloudWatch Logs** - Check the Lambda function logs for any errors or issues
2. **Set Up CloudWatch Alarms** - Create alarms to notify you of failures in the voicemail processing chain 
3. **Consider Implementing CI/CD** - For regular updates to the solution, setting up a CI/CD pipeline would streamline the process
4. **Document Department Routing** - Create documentation for your team on how the department-specific routing works