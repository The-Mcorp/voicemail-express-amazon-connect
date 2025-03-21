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
Create a file at `CloudFormation/parameters/dev-parameters.json` with the necessary parameters, including the department email addresses and the S3 bucket prefix.

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

Next, prepare and upload the Lambda function code:

```powershell
# Create directories for packaging
mkdir -p LambdaPackages
mkdir -p python_layer/python

# Create the Python layer with ALL required dependencies
# CRITICAL: This is the most important step to get right!

# Install external dependencies
pip install boto3>=1.26.0 requests>=2.28.1 aws-lambda-powertools>=2.15.0 cffi>=1.15.1 phonenumbers>=8.12.0 -t python_layer/python/

# Copy the Kinesis Video Streams library
mkdir -p python_layer/python/amazon_kinesis_video_consumer_library
Copy-Item -Path ".\Code\Core\amazon_kinesis_video_consumer_library\*" -Destination "python_layer/python/amazon_kinesis_video_consumer_library" -Recurse

# Copy ALL Python modules to the layer
# This ensures all necessary imports will work in Lambda functions
Copy-Item -Path ".\Code\Core\*.py" -Destination "python_layer\python\"

# Create the layer zip with the correct structure
cd python_layer
Compress-Archive -Path "python" -DestinationPath "../LambdaPackages/vmx3_common_python.zip" -Force
cd ..

# Create individual Lambda function zip files
Compress-Archive -Path ".\Code\Core\vmx3_ses_template_tool.py" -DestinationPath ".\LambdaPackages\vmx3_ses_template_tool.py.zip" -Force
Compress-Archive -Path ".\Code\Core\vmx3_guided_flow_presigner.py" -DestinationPath ".\LambdaPackages\vmx3_guided_flow_presigner.py.zip" -Force
Compress-Archive -Path ".\Code\Core\vmx3_kvs_to_s3.py" -DestinationPath ".\LambdaPackages\vmx3_kvs_to_s3.py.zip" -Force
Compress-Archive -Path ".\Code\Core\vmx3_packager.py" -DestinationPath ".\LambdaPackages\vmx3_packager.py.zip" -Force
Compress-Archive -Path ".\Code\Core\vmx3_presigner.py" -DestinationPath ".\LambdaPackages\vmx3_presigner.py.zip" -Force
Compress-Archive -Path ".\Code\Core\vmx3_transcriber.py" -DestinationPath ".\LambdaPackages\vmx3_transcriber.py.zip" -Force
Compress-Archive -Path ".\Code\Core\vmx3_transcription_error_handler.py" -DestinationPath ".\LambdaPackages\vmx3_transcription_error_handler.py.zip" -Force

# Upload all packages to S3
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

## Lessons Learned and Key Implementation Details

### Python Layer Structure (CRITICAL)
The most important aspect of this deployment is correctly setting up the Python layer. There are two critical requirements:

1. **Layer Directory Structure**: AWS Lambda layers must have a specific structure:
   ```
   vmx3_common_python.zip
   └── python/
       ├── boto3/
       ├── requests/
       └── ... (all modules and libraries)
   ```

2. **Complete Module Inclusion**: You must include **ALL** Python modules from the Code/Core directory in the layer. Missing even one module will cause Lambda function imports to fail with errors like:
   ```
   Unable to import module 'vmx3_packager': No module named 'sub_connect_task'
   ```

### Updating an Existing Deployment
If you need to fix issues with the Lambda functions after initial deployment:

1. **Update the Python Layer**:
   ```powershell
   # Create a new version of the layer with all required modules
   mkdir -p python_layer/python
   pip install boto3>=1.26.0 requests>=2.28.1 aws-lambda-powertools>=2.15.0 cffi>=1.15.1 phonenumbers>=8.12.0 -t python_layer/python/
   Copy-Item -Path ".\Code\Core\*.py" -Destination "python_layer\python\"
   Copy-Item -Path ".\Code\Core\amazon_kinesis_video_consumer_library\*" -Destination "python_layer/python/amazon_kinesis_video_consumer_library" -Recurse
   cd python_layer
   Compress-Archive -Path "python" -DestinationPath "../LambdaPackages/vmx3_common_python.zip" -Force
   cd ..
   aws s3 cp .\LambdaPackages\vmx3_common_python.zip s3://dev-vmx3-vmx-source-us-east-1/vmx3/2024.09.01/zip/ --profile ops
   ```

2. **Update Lambda Functions to Use the Layer**:
   ```powershell
   # Update through AWS Console or using AWS CLI
   aws lambda update-function-configuration --function-name VMX3-Packager-dev-elevenfiftynine --layers arn:aws:lambda:us-east-1:091070931078:layer:common_python_layer_dev-elevenfiftynine:1 --profile ops
   # Repeat for other functions
   ```

### Smoke Testing Checklist
After deployment, validate your implementation:

- [x] Make test call and leave voicemail
- [x] Verify recording is stored in S3
- [x] Confirm transcription is created
- [x] Check email delivery to correct department
- [x] Validate presigned URLs for recordings work properly

## Common Issues and Solutions

### "No module named" Errors
If you see "No module named" errors in CloudWatch logs:

1. Ensure all Python modules from Code/Core are included in the Python layer
2. Verify the layer is correctly structured with the `python/` directory at the root
3. Confirm the Lambda functions are configured to use the layer

### File Naming Conventions
The CloudFormation templates expect specific file names:

- Python layer zip must be named `vmx3_common_python.zip`
- Lambda function zips must match the conventions in the templates (e.g., `vmx3_ses_template_tool.py.zip`)

### Troubleshooting
- Check CloudWatch logs for specific error messages
- Verify S3 paths match what's expected in CloudFormation templates
- Examine Lambda function configuration to ensure layers are correctly attached

## Command Reference

### Reset/Delete Stack
If you need to completely reset your deployment:

```powershell
aws cloudformation delete-stack --stack-name dev-1159-voicemail-VMX3 --profile ops
```

### Check S3 Contents
To verify files in your S3 bucket:

```powershell
# List templates
aws s3 ls s3://dev-vmx3-vmx-source-us-east-1/vmx3/2024.09.01/cloudformation/ --profile ops

# List Lambda packages
aws s3 ls s3://dev-vmx3-vmx-source-us-east-1/vmx3/2024.09.01/zip/ --profile ops
```

## Success! (Updated March 21, 2025)

The Voicemail Express solution is now fully operational with all components working correctly:
- Voice recording is successfully captured from KVS and stored in S3
- Transcription is properly generated
- Email delivery with presigned URLs is working as expected
