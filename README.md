# 11:59 Voicemail System 

Forked from [amazon-connect/voicemail-express-amazon-connect](https://github.com/The-Mcorp/voicemail-express-amazon-connect). Updated to incorporate custom Connect Flows/Modules for department-based routing.

![Voicemail Express Architecture](Docs/Img/VMX3.png)

## Overview
This guide provides step-by-step instructions for deploying, updating, and troubleshooting 11:59's Amazon Connect Voicemail solution through AWS CloudFormation.

## Prerequisites & Assumptions
- AWS CLI installed and configured. The profile name is assumed to be  `ops` (e.g., --profile ops).
- Proper access is granted to 11:59's ops account
- An Amazon Connect instance already set up
- `{env}` is a placeholder for environment name, such as 'dev' or 'prod.'
- `{region}` is a placeholder for the region of the Amazon Connect instance

## New Environment Deployment Steps

This section walks through setting up a new voicemail environment after prerequisites are met.

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
Create a file at `CloudFormation/parameters/{env}-parameters.json` with the necessary parameters, including department email(s) addresses and the S3 bucket prefix.

### 3. Create Source S3 Bucket (for CloudFormation Templates and Custom Prompts)
Create an S3 bucket that matches the format specified in parameters (e.g., value of EXPDevBucketPrefix combined with -vmx-source-region):

```powershell
aws s3 mb s3://{env}-vmx3-vmx-source-{region} --region {region} --profile ops
```

### 4. Create Bucket Policy for Source S3 Bucket

```json
{
    "Version": "2012-10-17",
    "Id": "Policy1634763725216",
    "Statement": [
        {
            "Sid": "Stmt1634763712285",
            "Effect": "Allow",
            "Principal": {
                "Service": "connect.amazonaws.com"
            },
            "Action": [
                "s3:GetObject",
                "s3:ListBucket"
            ],
            "Resource": [
                "arn:aws:s3:::{replace_with_your_bucket_name}",
                "arn:aws:s3:::{replace_with_your_bucket_name}/*"
            ],
            "Condition": {
                "StringEquals": {
                    "aws:SourceArn": "arn:aws:connect:{region}:{accountId}:instance/aaf2f3d0-0fe6-4fb1-8a6b-4c080505e41d",
                    "aws:SourceAccount": "{accountId}"
                }
            }
        }
    ]
}
```

### 5. Upload Custom Department Prompts to Source S3 Bucket

e.g., s3://{env}-vmx3-vmx-source-{region}/prompts/ClientServices.wav

### 6. Upload Templates and Lambda Function Packages
First, upload all CloudFormation templates to the correct location in S3:

```powershell
aws s3 cp .\CloudFormation\vmx3-core.yaml s3://{env}-vmx3-vmx-source-{region}/vmx3/2024.09.01/cloudformation/ --profile ops
aws s3 cp .\CloudFormation\vmx3-contactflows.yaml s3://{env}-vmx3-vmx-source-{region}/vmx3/2024.09.01/cloudformation/ --profile ops
aws s3 cp .\CloudFormation\vmx3-lambda-functions.yaml s3://{env}-vmx3-vmx-source-{region}/vmx3/2024.09.01/cloudformation/ --profile ops
aws s3 cp .\CloudFormation\vmx3-policy-builder.yaml s3://{env}-vmx3-vmx-source-{region}/vmx3/2024.09.01/cloudformation/ --profile ops
aws s3 cp .\CloudFormation\vmx3-ses-setup.yaml s3://{env}-vmx3-vmx-source-{region}/vmx3/2024.09.01/cloudformation/ --profile ops
aws s3 cp .\CloudFormation\vmx3-triggers.yaml s3://{env}-vmx3-vmx-source-{region}/vmx3/2024.09.01/cloudformation/ --profile ops
```

Next, prepare and upload the Lambda function code:

```powershell
# Create directories for packaging
mkdir -p LambdaPackages
mkdir -p python_layer/python

# Create the Python layer with ALL required dependencies

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
aws s3 cp .\LambdaPackages\ s3://{env}-vmx3-vmx-source-{region}/vmx3/2024.09.01/zip/ --recursive --profile ops

# Verify the uploads
aws s3 ls s3://{env}-vmx3-vmx-source-{region}/vmx3/2024.09.01/zip/ --profile ops
```

### 7. Deploy the CloudFormation Stack
Deploy the main template using the AWS CLI:

```powershell
aws cloudformation deploy `
  --template-file CloudFormation/vmx3.yaml `
  --stack-name {env}-1159-voicemail-VMX3 `
  --parameter-overrides file://CloudFormation/parameters/{env}-parameters.json `
  --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND `
  --profile ops
```

### 8. Monitor Deployment
Monitor the deployment progress in the AWS CloudFormation console or using the AWS CLI:

```powershell
aws cloudformation describe-stack-events --stack-name {env}-1159-voicemail-VMX3 --profile ops
```

### 8. Configure Connect Instance
After deploying the voicemail system, configure your Amazon Connect instance to use it:
- New Connect instances: Following these steps will immediately enable voicemail functionality for your phone number.
- Existing instances: Plan cutover carefully by:
    - Testing in a development environment first
    - Scheduling changes during low-traffic periods
    - Understanding rollback strategy if needed

Configuration Steps:

1. Make sure all email addresses used for agents and/or FROM email addresses are (1) verified in SES and (2) set as the 'email' field in Amazon Connect instance users

2. Update Connect Instance Data Streaming. After clicking on the Connect instance in the console, go to `Data streaming` and update `Kinesis Stream` to be the value of the `ConnectCTRStreamARN` parameter in CloudFormation\parameters\{env}-parameters.json.

3. Within the Connect instance, go to `Phone numbers` --> click on the target phone number --> update `Contact flow / IVR` to be the one with 'VMX3' and 'Custom Flow' in it. Save Changes.

## Update Steps

This walk-through is for manual updates. More mature CI/CD processes are in the backlog, along with deploying a prod environment.

### 1. Make Changes to Template Files
First, modify the necessary CloudFormation template files. Common updates include:
- Adding or modifying call flow resources in `vmx3-contactflows.yaml`
- Updating Lambda functions in `vmx3-lambda-functions.yaml`
- Changing IAM policy definitions in `vmx3-policy-builder.yaml`

### 2. Upload Updated Templates to S3
After making your changes, upload the modified templates to the source S3 bucket:

```powershell
# Upload modified templates to S3
aws s3 cp .\CloudFormation\vmx3-contactflows.yaml s3://{env}-vmx3-vmx-source-{region}/vmx3/2024.09.01/cloudformation/ --profile ops

# For Lambda function updates, rebuild and upload packages if needed
Compress-Archive -Path ".\Code\Core\vmx3_some_function.py" -DestinationPath ".\LambdaPackages\vmx3_some_function.py.zip" -Force
aws s3 cp .\LambdaPackages\vmx3_some_function.py.zip s3://{env}-vmx3-vmx-source-{region}/vmx3/2024.09.01/zip/ --profile ops
```

### 3. Deploy the Stack Update
Once all modified files are uploaded to S3, run the CloudFormation deploy command to update the stack:

```powershell
aws cloudformation deploy `
  --template-file CloudFormation/vmx3.yaml `
  --stack-name {env}-1159-voicemail-VMX3 `
  --parameter-overrides file://CloudFormation/parameters/{env}-parameters.json `
  --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND `
  --profile ops `
  --no-fail-on-empty-changeset
```

The `--no-fail-on-empty-changeset` flag ensures the command won't error out if no changes are detected.

### 4. Monitor Update Progress
Track the update progress using the AWS CLI or the CloudFormation console:

```powershell
aws cloudformation describe-stack-events --stack-name {env}-1159-voicemail-VMX3 --profile ops
```

### Important Notes About Updates

- **Partial Updates**: The parent stack (vmx3.yaml) will only update the nested stacks containing modified templates.
- **S3 Dependency**: Always upload to S3 before deploying, as the parent stack references templates from S3, not local files.
- **Testing**: After updating, perform smoke testing to verify that all components still work correctly.
- **Rollback**: CloudFormation will automatically roll back changes if an update fails.

### Troubleshooting Updates

If the update fails, check the CloudFormation events for the specific error:

```powershell
aws cloudformation describe-stack-events --stack-name {env}-1159-voicemail-VMX3 --profile ops | Select-String -Pattern "FAILED"
```

You can also check CloudWatch logs for any Lambda function errors that might have occurred during or after the update.

## Lessons Learned and Key Implementation Details

### Python Layer Structure

1. **Layer Directory Structure**: AWS Lambda layers must have a specific structure:
   ```
   vmx3_common_python.zip
   └── python/
       ├── boto3/
       ├── requests/
       └── ... (all modules and libraries)
   ```

2. **Update the Python Layer**:
   ```powershell
   # Create a new version of the layer with all required modules
   mkdir -p python_layer/python
   pip install boto3>=1.26.0 requests>=2.28.1 aws-lambda-powertools>=2.15.0 cffi>=1.15.1 phonenumbers>=8.12.0 -t python_layer/python/
   Copy-Item -Path ".\Code\Core\*.py" -Destination "python_layer\python\"
   Copy-Item -Path ".\Code\Core\amazon_kinesis_video_consumer_library\*" -Destination "python_layer/python/amazon_kinesis_video_consumer_library" -Recurse
   cd python_layer
   Compress-Archive -Path "python" -DestinationPath "../LambdaPackages/vmx3_common_python.zip" -Force
   cd ..
   aws s3 cp .\LambdaPackages\vmx3_common_python.zip s3://{env}-vmx3-vmx-source-{region}/vmx3/2024.09.01/zip/ --profile ops
   ```

3. **Ensure Complete Module Inclusion**: You must include **ALL** Python modules from the Code/Core directory in the layer. Missing even one module will cause Lambda function imports to fail with errors like:
   ```
   Unable to import module 'vmx3_packager': No module named 'sub_connect_task'
   ```

4. **Update Lambda Functions to Use the Layer**

### Smoke Testing Checklist
After deployment, validate your implementation:

- [x] Make test call and leave voicemail
- [x] Verify recording is stored in S3
- [x] Confirm transcription is created
- [x] Check email delivery to correct department
- [x] Validate presigned URLs for recordings work properly

## Common Issues and Solutions

### Department Prompt is in S3, but the Fallback Prompt is Played:

1. Verify 'error' in CloudWatch flow logs (if enabled)
2. Make sure a `Set {Department} Agent` block is set up in the custom flow with `department_audio_url` set to the right s3 URL (e.g., `s3://{env}-vmx3-vmx-source-{region}/prompts/{Department}.wav`)
3. Make sure the s3 bucket has a bucket policy enabled for Connect access
4. Make sure that the S3 audio file adheres to AWS requirements. [Note U-Law encoding](https://docs.aws.amazon.com/connect/latest/adminguide/setup-prompts-s3.html)


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
