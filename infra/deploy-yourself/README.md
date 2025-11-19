# Deploy to Your Own Azure Subscription

This folder contains resources for deploying the LAB511 Knowledge Base infrastructure to your own Azure subscription.

## 📋 Prerequisites

- **Azure Subscription** with sufficient permissions to create resources
- **Azure CLI** installed and configured ([Install guide](https://learn.microsoft.com/cli/azure/install-azure-cli))
- **Python 3.10+** installed
- **Git** (to clone this repository)
- **VS Code** with Jupyter extension (recommended)

### Required Azure Permissions

You'll need permissions to:
- Create resource groups
- Deploy Bicep templates
- Create and manage:
  - Azure Storage Accounts
  - Azure AI Search services
  - Azure OpenAI services
  - Azure AI Services (Cognitive Services)
- Assign Azure RBAC roles

## 🚀 Quick Start

### 1. Clone the Repository

```bash
git clone https://github.com/microsoft/ignite25-LAB511-build-agentic-knowledge-bases-next-level-rag-with-azure-ai-search.git
cd ignite25-LAB511-build-agentic-knowledge-bases-next-level-rag-with-azure-ai-search
```

### 2. Login to Azure

```bash
az login
```

### 3. Deploy Infrastructure

⏱️ **Estimated time: 10-15 minutes**

#### Option A: Using the Deployment Script

**Windows (PowerShell):**
```powershell
cd infra/deploy-yourself
.\deploy.ps1 -ResourceGroupName "rg-lab511" -Location "westcentralus"
```

**Linux/macOS (Bash):**
```bash
cd infra/deploy-yourself
chmod +x deploy.sh
./deploy.sh -g "rg-lab511" -l "westcentralus"
```

#### Option B: Manual Deployment

```bash
# Create resource group
az group create --name rg-lab511 --location westcentralus

# Get your user object ID
USER_OBJECT_ID=$(az ad signed-in-user show --query id -o tsv)

# Deploy Bicep template
az deployment group create \
  --resource-group rg-lab511 \
  --template-file ../LAB511.bicep \
  --parameters labUserObjectId=$USER_OBJECT_ID \
  --parameters resourcePrefix=lab511
```

### 4. Set Up the Environment

⏱️ **Estimated time: 5-10 minutes**

After the infrastructure is deployed, run the setup script:

**Windows (PowerShell):**
```powershell
.\setup-environment.ps1 -ResourceGroupName "rg-lab511"
```

**Linux/macOS (Bash):**
```bash
chmod +x setup-environment.sh
./setup-environment.sh -g "rg-lab511"
```

This script will retrieve connection strings and endpoints from Azure, create a `.env` file in the repository root, set up the Python virtual environment, install required dependencies, and create the search indexes and upload sample data.

### 5. Start the Lab

⏱️ **Estimated time: 60-90 minutes for all notebooks**

Open the [notebooks](../../notebooks) folder in VS Code and **start with `part1-basic-knowledge-base.ipynb`**.

## 🧹 Cleanup

To delete all resources and avoid ongoing charges:

```bash
az group delete --name rg-lab511 --yes --no-wait
```

## 📚 Additional Resources

- [Azure AI Search Documentation](https://learn.microsoft.com/azure/search/)
- [Azure OpenAI Service Documentation](https://learn.microsoft.com/azure/ai-services/openai/)
- [Azure Bicep Documentation](https://learn.microsoft.com/azure/azure-resource-manager/bicep/)
- [Azure AI Foundry Community Discord](https://aka.ms/AIFoundryDiscord-Ignite25)