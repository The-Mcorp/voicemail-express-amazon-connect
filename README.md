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

## New Environment Deployment

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

### 2. Configure AWS Systems Manager Parameter Store
Create the necessary parameters in Parameter Store following this hierarchical structure:

```
/1159-voicemail/{env}/AWSRegion
/1159-voicemail/{env}/ConnectCTRStreamARN
/1159-voicemail/{env}/EXPDevBucketPrefix
...and other required parameters
```

You can use the AWS CLI to create these parameters:

```powershell
# Example: Setting up a parameter
aws ssm put-parameter \
    --name "/1159-voicemail/dev/AWSRegion" \
    --value "us-east-1" \
    --type "String" \
    --profile ops
```

### 3. Create Parameters File
Create a file at `CloudFormation/parameters/{env}-parameters.json` that references the environment and SSM parameter paths:

```json
[
  {
    "ParameterKey": "Environment",
    "ParameterValue": "{env}"
  },
  {
    "ParameterKey": "AWSRegion",
    "ParameterValue": "/1159-voicemail/{env}/AWSRegion"
  },
  {
    "ParameterKey": "ConnectCTRStreamARN",
    "ParameterValue": "/1159-voicemail/{env}/ConnectCTRStreamARN"
  },
  {
    "ParameterKey": "EXPDevBucketPrefix",
    "ParameterValue": "/1159-voicemail/{env}/EXPDevBucketPrefix"
  }
  // Add all other required parameters
]
```

### 4. Create Source S3 Bucket (for CloudFormation Templates and Custom Prompts)
Create an S3 bucket that matches the format specified in parameters (e.g., value of EXPDevBucketPrefix combined with -vmx-source-region):

```powershell
aws s3 mb s3://{env}-vmx3-vmx-source-{region} --region {region} --profile ops
```

### 5. Create Bucket Policy for Source S3 Bucket

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
                    "aws:SourceArn": "arn:aws:connect:{region}:{accountId}:instance/{replace_with_connect_instance_id}",
                    "aws:SourceAccount": "{accountId}"
                }
            }
        }
    ]
}
```

### 6. Upload Custom Department Prompts to Source S3 Bucket

e.g., s3://{env}-vmx3-vmx-source-{region}/prompts/ClientServices.wav

### 7. Upload Templates and Lambda Function Packages
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

### 8. Deploy the CloudFormation Stack
Deploy the main template using the AWS CLI:

```powershell
aws cloudformation deploy `
  --template-file CloudFormation/vmx3.yaml `
  --stack-name {env}-1159-voicemail-VMX3 `
  --parameter-overrides file://CloudFormation/parameters/{env}-parameters.json `
  --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND `
  --profile ops
```

### 9. Monitor Deployment
Monitor the deployment progress in the AWS CloudFormation console or using the AWS CLI:

```powershell
aws cloudformation describe-stack-events --stack-name {env}-1159-voicemail-VMX3 --profile ops
```

### 10. Configure Connect Instance
After deploying the voicemail system, configure your Amazon Connect instance to use it:
- New Connect instances: Following these steps will immediately enable voicemail functionality for your phone number.
- Existing instances: Plan cutover carefully by:
    - Testing in a development environment first
    - Scheduling changes during low-traffic periods
    - Understanding rollback strategy if needed

Configuration Steps:

1. Make sure all email addresses used for agents and/or FROM email addresses are (1) verified in SES and (2) set as the 'email' field in Amazon Connect instance users

2. Update Connect Instance Data Streaming. After clicking on the Connect instance in the console, go to `Data streaming` and update `Kinesis Stream` to be the value stored in the SSM parameter `/1159-voicemail/{env}/ConnectCTRStreamARN`.

3. Within the Connect instance, go to `Phone numbers` --> click on the target phone number --> update `Contact flow / IVR` to be the one with 'VMX3' and 'Custom Flow' in it. Save Changes.

### 11. Smoke Test
After deployment, validate your implementation:
- [ ] Make test call and leave voicemail
- [ ] Verify recording is stored in S3
- [ ] Confirm transcription is created
- [ ] Check email delivery to correct department
- [ ] Validate presigned URLs for recordings work properly

## Add or Update Stack Tags
Tags are currently updated via command line, pending more mature CI/CD process. Run a command similar to the one below to update tags:

```powershell
aws cloudformation deploy --template-file CloudFormation/vmx3.yaml --stack-name {env}-1159-voicemail-VMX3 --parameter-overrides file://CloudFormation/parameters/{env}-parameters.json --tags environment={env} createdBy=example.example@example.com project=Voicemail createdOn=03202025 --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND --profile ops
```

## Update Stack

This walk-through is for manual updates. More mature CI/CD processes are in the backlog.

### 1. Make Changes to Template Files
First, modify the necessary CloudFormation template files. Common updates may include:
- Adding or modifying call flow resources in `vmx3-contactflows.yaml`
- Updating Lambda functions in `vmx3-lambda-functions.yaml`
- Changing IAM policy definitions in `vmx3-policy-builder.yaml`

### 2. Update Parameter Store Values (if needed)
If your changes require parameter updates, update the values in AWS Systems Manager Parameter Store:

```powershell
aws ssm put-parameter \
    --name "/1159-voicemail/{env}/{ParameterName}" \
    --value "{new-value}" \
    --type "String" \
    --overwrite \
    --profile ops
```

Note: Since the application reads these configuration values at deployment, you must redeploy the CloudFormation stack after updating parameters for the changes to take effect. Simply updating the parameter values in SSM without redeploying will not update the running application configuration.

### 3. Upload Updated Templates to S3
After making your changes, upload the modified templates to the source S3 bucket:

```powershell
# Upload modified templates to S3
aws s3 cp .\CloudFormation\vmx3-contactflows.yaml s3://{env}-vmx3-vmx-source-{region}/vmx3/2024.09.01/cloudformation/ --profile ops

# For Lambda function updates, rebuild and upload packages if needed
Compress-Archive -Path ".\Code\Core\vmx3_some_function.py" -DestinationPath ".\LambdaPackages\vmx3_some_function.py.zip" -Force
aws s3 cp .\LambdaPackages\vmx3_some_function.py.zip s3://{env}-vmx3-vmx-source-{region}/vmx3/2024.09.01/zip/ --profile ops
```

### 4. Deploy the Stack Update
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

### 5. Monitor Update Progress
Track the update progress using the AWS CLI or the CloudFormation console:

```powershell
aws cloudformation describe-stack-events --stack-name {env}-1159-voicemail-VMX3 --profile ops
```

### Important Notes About Updates

- **Partial Updates**: The parent stack (vmx3.yaml) will only update the nested stacks containing modified templates.
- **S3 Dependency**: Always upload to S3 before deploying, as the parent stack references templates from S3, not local files.
- **Testing**: After updating, perform smoke testing to verify that all components still work correctly.
- **Rollback**: CloudFormation will automatically roll back changes if an update fails.
- **Parameter Store**: Changes to Parameter Store values will take effect during the next stack update.

### Troubleshooting Updates

If the update fails, check the CloudFormation events for the specific error:

```powershell
aws cloudformation describe-stack-events --stack-name {env}-1159-voicemail-VMX3 --profile ops | Select-String -Pattern "FAILED"
```

You can also check CloudWatch logs for any Lambda function errors that might have occurred during or after the update.
