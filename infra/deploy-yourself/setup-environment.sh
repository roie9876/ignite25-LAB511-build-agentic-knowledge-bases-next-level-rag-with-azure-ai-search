set -e

RESOURCE_GROUP=""

# Parse command line arguments
while getopts "g:h" opt; do
  case $opt in
    g) RESOURCE_GROUP="$OPTARG" ;;
    h)
      echo "Usage: $0 -g <resource-group>"
      echo ""
      echo "Required:"
      echo "  -g  Resource group name"
      echo ""
      echo "  -h  Show this help message"
      exit 0
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      exit 1
      ;;
  esac
done

if [ -z "$RESOURCE_GROUP" ]; then
  echo "Error: Resource group (-g) is required"
  echo "Use -h for help"
  exit 1
fi

echo "========================================"
echo "LAB511 Environment Setup"
echo "========================================"
echo ""

# Get repository root (2 levels up from this script)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Check if resource group exists
echo "Checking resource group: $RESOURCE_GROUP"
if ! az group exists --name "$RESOURCE_GROUP" | grep -q "true"; then
    echo "✗ Resource group '$RESOURCE_GROUP' does not exist"
    echo "  Run the deploy script first: ./deploy.sh -g '$RESOURCE_GROUP' -l 'westcentralus'"
    exit 1
fi
echo "✓ Resource group found"

# Get all resources in the resource group
echo ""
echo "Retrieving Azure resources..."

# Get Azure AI Search service
SEARCH_SERVICE_NAME=$(az search service list --resource-group "$RESOURCE_GROUP" --query "[0].name" -o tsv)
if [ -z "$SEARCH_SERVICE_NAME" ]; then
    echo "✗ No Azure AI Search service found in resource group"
    exit 1
fi
SEARCH_ENDPOINT="https://${SEARCH_SERVICE_NAME}.search.windows.net"
SEARCH_ADMIN_KEY=$(az search admin-key show --resource-group "$RESOURCE_GROUP" --service-name "$SEARCH_SERVICE_NAME" --query primaryKey -o tsv)
echo "✓ Azure AI Search: $SEARCH_SERVICE_NAME"

# Get Azure OpenAI service
OPENAI_SERVICE_NAME=$(az cognitiveservices account list --resource-group "$RESOURCE_GROUP" --query "[?kind=='OpenAI'].name | [0]" -o tsv)
if [ -z "$OPENAI_SERVICE_NAME" ]; then
    echo "✗ No Azure OpenAI service found in resource group"
    exit 1
fi
OPENAI_ENDPOINT=$(az cognitiveservices account show --resource-group "$RESOURCE_GROUP" --name "$OPENAI_SERVICE_NAME" --query properties.endpoint -o tsv)
OPENAI_KEY=$(az cognitiveservices account keys list --resource-group "$RESOURCE_GROUP" --name "$OPENAI_SERVICE_NAME" --query key1 -o tsv)
echo "✓ Azure OpenAI: $OPENAI_SERVICE_NAME"

# Get AI Services (CognitiveServices kind)
AI_SERVICE_NAME=$(az cognitiveservices account list --resource-group "$RESOURCE_GROUP" --query "[?kind=='CognitiveServices'].name | [0]" -o tsv)
if [ -z "$AI_SERVICE_NAME" ]; then
    echo "✗ No AI Services found in resource group"
    exit 1
fi
AI_SERVICES_ENDPOINT=$(az cognitiveservices account show --resource-group "$RESOURCE_GROUP" --name "$AI_SERVICE_NAME" --query properties.endpoint -o tsv)
AI_SERVICES_KEY=$(az cognitiveservices account keys list --resource-group "$RESOURCE_GROUP" --name "$AI_SERVICE_NAME" --query key1 -o tsv)
echo "✓ AI Services: $AI_SERVICE_NAME"

# Get Storage Account
STORAGE_ACCOUNT_NAME=$(az storage account list --resource-group "$RESOURCE_GROUP" --query "[0].name" -o tsv)
if [ -z "$STORAGE_ACCOUNT_NAME" ]; then
    echo "✗ No Storage Account found in resource group"
    exit 1
fi
BLOB_CONNECTION_STRING=$(az storage account show-connection-string --resource-group "$RESOURCE_GROUP" --name "$STORAGE_ACCOUNT_NAME" --query connectionString -o tsv)
echo "✓ Storage Account: $STORAGE_ACCOUNT_NAME"

# Create .env file
echo ""
echo "Creating .env file..."

ENV_CONTENT="# Azure AI Search Configuration
AZURE_SEARCH_SERVICE_ENDPOINT=$SEARCH_ENDPOINT
AZURE_SEARCH_ADMIN_KEY=$SEARCH_ADMIN_KEY

# Azure Blob Storage Configuration
BLOB_CONNECTION_STRING=$BLOB_CONNECTION_STRING
BLOB_CONTAINER_NAME=documents
SEARCH_BLOB_DATASOURCE_CONNECTION_STRING=$BLOB_CONNECTION_STRING

# Azure OpenAI Configuration
AZURE_OPENAI_ENDPOINT=$OPENAI_ENDPOINT
AZURE_OPENAI_KEY=$OPENAI_KEY
AZURE_OPENAI_EMBEDDING_DEPLOYMENT=text-embedding-3-large
AZURE_OPENAI_EMBEDDING_MODEL_NAME=text-embedding-3-large
AZURE_OPENAI_CHATGPT_DEPLOYMENT=gpt-4.1
AZURE_OPENAI_CHATGPT_MODEL_NAME=gpt-4.1

# Azure AI Services Configuration
AI_SERVICES_ENDPOINT=$AI_SERVICES_ENDPOINT
AI_SERVICES_KEY=$AI_SERVICES_KEY

# Knowledge Base Configuration
AZURE_SEARCH_KNOWLEDGE_AGENT=knowledge-base
USE_VERBALIZATION=false
"

ENV_PATH="$REPO_ROOT/.env"
echo "$ENV_CONTENT" > "$ENV_PATH"

echo "✓ Created .env file at: $ENV_PATH"
echo "  ⚠️  SECURITY: Never commit this file to source control!"

# Set up Python environment
echo ""
echo "Setting up Python environment..."

if ! command -v python3 &> /dev/null; then
    echo "✗ Python 3.10+ is required but not found"
    echo "  Install from: https://www.python.org/downloads/"
    exit 1
fi

PYTHON_VERSION=$(python3 --version)
echo "✓ Found: $PYTHON_VERSION"

# Create virtual environment in repo root
VENV_PATH="$REPO_ROOT/.venv"
if [ ! -d "$VENV_PATH" ]; then
    echo "  Creating virtual environment..."
    cd "$REPO_ROOT"
    python3 -m venv .venv
    echo "✓ Virtual environment created"
else
    echo "✓ Virtual environment already exists"
fi

# Install dependencies
echo ""
echo "Installing Python dependencies..."
VENV_PYTHON="$REPO_ROOT/.venv/bin/python"
REQUIREMENTS_PATH="$REPO_ROOT/notebooks/requirements.txt"

if [ ! -f "$VENV_PYTHON" ]; then
    echo "✗ Virtual environment Python not found at: $VENV_PYTHON"
    exit 1
fi

if [ ! -f "$REQUIREMENTS_PATH" ]; then
    echo "✗ requirements.txt not found at: $REQUIREMENTS_PATH"
    exit 1
fi

cd "$REPO_ROOT"
"$VENV_PYTHON" -m pip install --upgrade pip --quiet
"$VENV_PYTHON" -m pip install -r "$REQUIREMENTS_PATH" --quiet

echo "✓ Dependencies installed"

# Create search indexes and upload data
echo ""
echo "Creating search indexes and uploading data..."
echo "  This may take 2-3 minutes..."

CREATE_INDEXES_PATH="$SCRIPT_DIR/create-indexes.py"

if [ ! -f "$CREATE_INDEXES_PATH" ]; then
    echo "✗ create-indexes.py not found at: $CREATE_INDEXES_PATH"
    exit 1
fi

cd "$REPO_ROOT"
if "$VENV_PYTHON" "$CREATE_INDEXES_PATH"; then
    echo "✓ Indexes created and data uploaded"
else
    echo "✗ Failed to create indexes or upload data"
    echo "  Check the log file for details: $REPO_ROOT/infra/index-creation.log"
fi

# Summary
echo ""
echo "========================================"
echo "Setup Complete!"
echo "========================================"
echo ""
echo "Your environment is ready! Next steps:"
echo ""
echo "  1. Navigate to the notebooks folder:"
echo "     cd $REPO_ROOT/notebooks"
echo ""
echo "  2. Open in VS Code:"
echo "     code ."
echo ""
echo "  3. Select the Python interpreter:"
echo "     .venv/bin/python"
echo ""
echo "  4. Open and run the notebooks in order:"
echo "     - part1-basic-knowledge-base.ipynb"
echo "     - part2-multiple-knowledge-sources.ipynb"
echo "     - etc..."
echo ""
echo "Environment file: $ENV_PATH"
echo ""
