param(
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroupName
)

$ErrorActionPreference = "Stop"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "LAB511 Environment Setup" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Get repository root (2 levels up from this script)
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

# Check if resource group exists
Write-Host "Checking resource group: $ResourceGroupName" -ForegroundColor Yellow
$rgExists = az group exists --name $ResourceGroupName
if ($rgExists -ne "true") {
    Write-Host "✗ Resource group '$ResourceGroupName' does not exist" -ForegroundColor Red
    Write-Host "  Run the deploy script first: .\deploy.ps1 -ResourceGroupName '$ResourceGroupName' -Location 'westcentralus'" -ForegroundColor Yellow
    exit 1
}
Write-Host "✓ Resource group found" -ForegroundColor Green

# Get all resources in the resource group
Write-Host ""
Write-Host "Retrieving Azure resources..." -ForegroundColor Yellow

try {
    # Get Azure AI Search service
    $searchServices = az search service list --resource-group $ResourceGroupName --output json | ConvertFrom-Json
    if ($searchServices.Count -eq 0) {
        throw "No Azure AI Search service found in resource group"
    }
    $searchService = $searchServices[0]
    $searchEndpoint = "https://$($searchService.name).search.windows.net"
    $searchAdminKey = az search admin-key show --resource-group $ResourceGroupName --service-name $searchService.name --query primaryKey -o tsv
    
    Write-Host "✓ Azure AI Search: $($searchService.name)" -ForegroundColor Green
    
    # Get Azure OpenAI service
    $openAiServices = az cognitiveservices account list --resource-group $ResourceGroupName --output json | ConvertFrom-Json | Where-Object { $_.kind -eq "OpenAI" }
    if ($openAiServices.Count -eq 0) {
        throw "No Azure OpenAI service found in resource group"
    }
    $openAiService = $openAiServices[0]
    $openAiEndpoint = $openAiService.properties.endpoint
    $openAiKey = az cognitiveservices account keys list --resource-group $ResourceGroupName --name $openAiService.name --query key1 -o tsv
    
    Write-Host "✓ Azure OpenAI: $($openAiService.name)" -ForegroundColor Green
    
    # Get AI Services (CognitiveServices kind)
    $aiServices = az cognitiveservices account list --resource-group $ResourceGroupName --output json | ConvertFrom-Json | Where-Object { $_.kind -eq "CognitiveServices" }
    if ($aiServices.Count -eq 0) {
        throw "No AI Services found in resource group"
    }
    $aiService = $aiServices[0]
    $aiServicesEndpoint = $aiService.properties.endpoint
    $aiServicesKey = az cognitiveservices account keys list --resource-group $ResourceGroupName --name $aiService.name --query key1 -o tsv
    
    Write-Host "✓ AI Services: $($aiService.name)" -ForegroundColor Green
    
    # Get Storage Account
    $storageAccounts = az storage account list --resource-group $ResourceGroupName --output json | ConvertFrom-Json
    if ($storageAccounts.Count -eq 0) {
        throw "No Storage Account found in resource group"
    }
    $storageAccount = $storageAccounts[0]
    $blobConnectionString = az storage account show-connection-string --resource-group $ResourceGroupName --name $storageAccount.name --query connectionString -o tsv
    
    Write-Host "✓ Storage Account: $($storageAccount.name)" -ForegroundColor Green
    
} catch {
    Write-Host "✗ Failed to retrieve Azure resources" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}

# Create .env file
Write-Host ""
Write-Host "Creating .env file..." -ForegroundColor Yellow

$envContent = @"
# Azure AI Search Configuration
AZURE_SEARCH_SERVICE_ENDPOINT=$searchEndpoint
AZURE_SEARCH_ADMIN_KEY=$searchAdminKey

# Azure Blob Storage Configuration
BLOB_CONNECTION_STRING=$blobConnectionString
BLOB_CONTAINER_NAME=documents
SEARCH_BLOB_DATASOURCE_CONNECTION_STRING=$blobConnectionString

# Azure OpenAI Configuration
AZURE_OPENAI_ENDPOINT=$openAiEndpoint
AZURE_OPENAI_KEY=$openAiKey
AZURE_OPENAI_EMBEDDING_DEPLOYMENT=text-embedding-3-large
AZURE_OPENAI_EMBEDDING_MODEL_NAME=text-embedding-3-large
AZURE_OPENAI_CHATGPT_DEPLOYMENT=gpt-4.1
AZURE_OPENAI_CHATGPT_MODEL_NAME=gpt-4.1

# Azure AI Services Configuration
AI_SERVICES_ENDPOINT=$aiServicesEndpoint
AI_SERVICES_KEY=$aiServicesKey

# Knowledge Base Configuration
AZURE_SEARCH_KNOWLEDGE_AGENT=knowledge-base
USE_VERBALIZATION=false
"@

$envPath = Join-Path $repoRoot ".env"
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText($envPath, $envContent, $utf8NoBom)

Write-Host "✓ Created .env file at: $envPath" -ForegroundColor Green
Write-Host "  ⚠️  SECURITY: Never commit this file to source control!" -ForegroundColor Yellow

# Set up Python environment
Write-Host ""
Write-Host "Setting up Python environment..." -ForegroundColor Yellow

$pythonCmd = Get-Command python -ErrorAction SilentlyContinue
if (-not $pythonCmd) {
    $pythonCmd = Get-Command py -ErrorAction SilentlyContinue
}
if (-not $pythonCmd) {
    Write-Host "✗ Python 3.10+ is required but not found" -ForegroundColor Red
    Write-Host "  Install from: https://www.python.org/downloads/" -ForegroundColor Yellow
    exit 1
}

$pythonVersion = & python --version
Write-Host "✓ Found: $pythonVersion" -ForegroundColor Green

# Create virtual environment in repo root
$venvPath = Join-Path $repoRoot ".venv"
if (-not (Test-Path $venvPath)) {
    Write-Host "  Creating virtual environment..." -ForegroundColor Yellow
    Push-Location $repoRoot
    & python -m venv .venv
    Pop-Location
    Write-Host "✓ Virtual environment created" -ForegroundColor Green
} else {
    Write-Host "✓ Virtual environment already exists" -ForegroundColor Green
}

# Install dependencies
Write-Host ""
Write-Host "Installing Python dependencies..." -ForegroundColor Yellow
$venvPython = Join-Path $repoRoot ".venv\Scripts\python.exe"
$requirementsPath = Join-Path $repoRoot "notebooks\requirements.txt"

if (-not (Test-Path $venvPython)) {
    Write-Host "✗ Virtual environment Python not found at: $venvPython" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $requirementsPath)) {
    Write-Host "✗ requirements.txt not found at: $requirementsPath" -ForegroundColor Red
    exit 1
}

Push-Location $repoRoot
& $venvPython -m pip install --upgrade pip --quiet
& $venvPython -m pip install -r $requirementsPath --quiet
Pop-Location

Write-Host "✓ Dependencies installed" -ForegroundColor Green

# Create search indexes and upload data
Write-Host ""
Write-Host "Creating search indexes and uploading data..." -ForegroundColor Yellow
Write-Host "  This may take 2-3 minutes..." -ForegroundColor Gray

$createIndexesPath = Join-Path $PSScriptRoot "create-indexes.py"

if (-not (Test-Path $createIndexesPath)) {
    Write-Host "✗ create-indexes.py not found at: $createIndexesPath" -ForegroundColor Red
    exit 1
}

Push-Location $repoRoot
try {
    & $venvPython $createIndexesPath
    Write-Host "✓ Indexes created and data uploaded" -ForegroundColor Green
} catch {
    Write-Host "✗ Failed to create indexes or upload data" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host "  Check the log file for details: $repoRoot\infra\index-creation.log" -ForegroundColor Yellow
}
Pop-Location

# Summary
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Setup Complete!" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Your environment is ready! Next steps:" -ForegroundColor Yellow
Write-Host ""
Write-Host "  1. Navigate to the notebooks folder:" -ForegroundColor White
Write-Host "     cd $repoRoot\notebooks" -ForegroundColor Gray
Write-Host ""
Write-Host "  2. Open in VS Code:" -ForegroundColor White
Write-Host "     code ." -ForegroundColor Gray
Write-Host ""
Write-Host "  3. Select the Python interpreter:" -ForegroundColor White
Write-Host "     .venv\Scripts\python.exe" -ForegroundColor Gray
Write-Host ""
Write-Host "  4. Open and run the notebooks in order:" -ForegroundColor White
Write-Host "     - part1-basic-knowledge-base.ipynb" -ForegroundColor Gray
Write-Host "     - part2-multiple-knowledge-sources.ipynb" -ForegroundColor Gray
Write-Host "     - etc..." -ForegroundColor Gray
Write-Host ""
Write-Host "Environment file: $envPath" -ForegroundColor Cyan
Write-Host ""
