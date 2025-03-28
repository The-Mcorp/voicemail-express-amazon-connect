param(
    [Parameter(Mandatory=$true)]
    [string]$Environment,
    
    [Parameter(Mandatory=$false)]
    [string]$ParameterJsonPath = ".\CloudFormation\parameters\$Environment-parameters.json"
)

# prefix for SSM Parameter Store
$prefix = "/1159-voicemail/$Environment"

# Ensure the JSON file exists
if (-not (Test-Path $ParameterJsonPath)) {
    Write-Error "Parameter file not found: $ParameterJsonPath"
    exit 1
}

# Read and parse JSON
$jsonContent = Get-Content -Raw $ParameterJsonPath
$parameters = $jsonContent | ConvertFrom-Json

Write-Host "Importing parameters to AWS SSM Parameter Store with prefix: $prefix"
Write-Host "Total parameters to import: $($parameters.Length)"

# Loop through each param, create it in Parameter Store
$importedCount = 0
foreach ($param in $parameters) {
    $paramName = $param.ParameterKey
    $paramValue = $param.ParameterValue
    $ssmPath = "$prefix/$paramName"

    $type = "String"
    
    Write-Host "Processing parameter: $ssmPath (Type: $type)"
    
    # Use aws cli to check if parameter exists
    $checkParam = aws ssm get-parameter --name $ssmPath --profile ops 2>$null
    $paramExists = $LASTEXITCODE -eq 0
    
    try {
        if ($paramExists) {
            Write-Host "  -> Updating existing parameter"
            # Update existing parameter without tags
            aws ssm put-parameter `
                --name $ssmPath `
                --value $paramValue `
                --type $type `
                --overwrite `
                --profile ops
        } else {
            Write-Host "  -> Creating new parameter with tags"
            # Create new parameter with tags
            aws ssm put-parameter `
                --name $ssmPath `
                --value $paramValue `
                --type $type `
                --tags Key=environment,Value=$Environment Key=project,Value=1159Voicemail `
                --profile ops
        }
        
        $importedCount++
    }
    catch {
        Write-Error "Failed to process parameter $ssmPath : $_"
    }
}

Write-Host "Import complete. Successfully imported $importedCount of $($parameters.Length) parameters."