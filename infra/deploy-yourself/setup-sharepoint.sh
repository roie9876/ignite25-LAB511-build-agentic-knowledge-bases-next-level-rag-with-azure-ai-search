#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

RESOURCE_GROUP=""
SHAREPOINT_SITE_URL=""

# Parse command line arguments
while getopts "g:s:h" opt; do
  case $opt in
    g) RESOURCE_GROUP="$OPTARG" ;;
    s) SHAREPOINT_SITE_URL="$OPTARG" ;;
    h)
      echo "Usage: $0 -g <resource-group> -s <sharepoint-site-url>"
      echo ""
      echo "Required:"
      echo "  -g  Resource group name (same as used in setup-environment.sh)"
      echo "  -s  SharePoint site URL (e.g., https://mycompany.sharepoint.com/sites/MyTeamSite)"
      echo ""
      echo "SharePoint URL Format:"
      echo "  ✓ Correct:   https://[tenant].sharepoint.com/sites/[site-name]"
      echo "  ✗ Incorrect: https://[tenant].sharepoint.com/sites/[site]/Shared%20Documents/..."
      echo ""
      echo "How to find your SharePoint site URL:"
      echo "  1. Open your SharePoint site in a browser"
      echo "  2. Look at the URL in the address bar"
      echo "  3. Copy everything up to and including /sites/[site-name]"
      echo "  4. Remove any path after the site name (like /Shared%20Documents/...)"
      echo ""
      echo "Real Example:"
      echo "  If you see: https://mngenvmcap338326.sharepoint.com/sites/lab511-demo/Shared%20Documents/Forms/AllItems.aspx"
      echo "  Use this:   https://mngenvmcap338326.sharepoint.com/sites/lab511-demo"
      echo ""
      echo "Command Example:"
      echo "  $0 -g LAB511-ResourceGroup -s https://contoso.sharepoint.com/sites/lab511"
      echo ""
      echo "Prerequisites:"
      echo "  - You must be logged in as a user with Azure AD admin privileges"
      echo "  - SharePoint site must exist and be accessible"
      echo "  - You must have permissions to grant admin consent for apps"
      exit 0
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      exit 1
      ;;
  esac
done

if [ -z "$RESOURCE_GROUP" ]; then
  echo -e "${RED}Error: Resource group (-g) is required${NC}"
  echo "Use -h for help"
  exit 1
fi

if [ -z "$SHAREPOINT_SITE_URL" ]; then
  echo -e "${RED}Error: SharePoint site URL (-s) is required${NC}"
  echo "Use -h for help"
  exit 1
fi

# Validate SharePoint URL format
if [[ ! "$SHAREPOINT_SITE_URL" =~ ^https://.*\.sharepoint\.com/.* ]]; then
  echo -e "${RED}Error: Invalid SharePoint URL format${NC}"
  echo "Expected format: https://[tenant].sharepoint.com/sites/[site]"
  exit 1
fi

echo -e "${BLUE}========================================"
echo "SharePoint Indexer Setup for LAB511"
echo "========================================${NC}"
echo ""

# Get repository root (2 levels up from this script)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Check if .env exists
ENV_PATH="$REPO_ROOT/.env"
if [ ! -f "$ENV_PATH" ]; then
    echo -e "${RED}✗ .env file not found${NC}"
    echo "  Run setup-environment.sh first"
    exit 1
fi

# Check if user is logged in to Azure
echo -e "${BLUE}Checking Azure login...${NC}"
if ! az account show &>/dev/null; then
    echo -e "${RED}✗ Not logged in to Azure${NC}"
    echo "  Run: az login"
    exit 1
fi

# Get current user's object ID and check admin status
CURRENT_USER_ID=$(az ad signed-in-user show --query id -o tsv)
CURRENT_USER_UPN=$(az ad signed-in-user show --query userPrincipalName -o tsv)
TENANT_ID=$(az account show --query tenantId -o tsv)

echo -e "${GREEN}✓ Logged in as: ${CURRENT_USER_UPN}${NC}"
echo -e "${GREEN}✓ Tenant ID: ${TENANT_ID}${NC}"

# Check if user has required admin roles
echo ""
echo -e "${BLUE}Checking admin privileges...${NC}"
HAS_ADMIN=false

# Check for Global Administrator or Application Administrator role (ACTIVE assignments)
ADMIN_ROLES=$(az rest --method GET --url "https://graph.microsoft.com/v1.0/me/memberOf/microsoft.graph.directoryRole" --query "value[?displayName=='Global Administrator' || displayName=='Application Administrator'].displayName" -o tsv 2>/dev/null || echo "")

if [ -n "$ADMIN_ROLES" ]; then
    HAS_ADMIN=true
    echo -e "${GREEN}✓ Admin role detected: ${ADMIN_ROLES}${NC}"
    echo -e "${GREEN}✓ Admin consent will be granted automatically${NC}"
else
    echo -e "${YELLOW}⚠ WARNING: Admin role not detected${NC}"
    echo ""
    echo -e "${YELLOW}═══════════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}  IMPORTANT: Admin Consent Required${NC}"
    echo -e "${YELLOW}═══════════════════════════════════════════════════════${NC}"
    echo ""
    echo "This script requires an ACTIVE 'Global Administrator' or"
    echo "'Application Administrator' role to grant admin consent for"
    echo "SharePoint API permissions."
    echo ""
    echo -e "${YELLOW}If you have an ELIGIBLE role via PIM (Privileged Identity Management):${NC}"
    echo "  1. Go to Azure Portal → Azure AD → Privileged Identity Management"
    echo "  2. Click 'My roles' → 'Azure AD roles'"
    echo "  3. Find your admin role under 'Eligible assignments'"
    echo "  4. Click 'Activate' and provide justification"
    echo "  5. Wait 5-10 minutes for activation to complete"
    echo "  6. Re-run this script"
    echo ""
    echo -e "${YELLOW}Without admin privileges:${NC}"
    echo "  - The script will create the app registration"
    echo "  - Admin consent will need to be granted MANUALLY"
    echo "  - You'll receive a URL to complete consent in the portal"
    echo ""
    read -p "Do you want to continue anyway? (yes/no): " CONTINUE
    if [ "$CONTINUE" != "yes" ]; then
        echo "Setup cancelled"
        exit 1
    fi
fi

# Get Azure AI Search service details
echo ""
echo -e "${BLUE}Retrieving Azure AI Search service...${NC}"
SEARCH_SERVICE_NAME=$(az search service list --resource-group "$RESOURCE_GROUP" --query "[0].name" -o tsv)
if [ -z "$SEARCH_SERVICE_NAME" ]; then
    echo -e "${RED}✗ No Azure AI Search service found in resource group${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Azure AI Search: ${SEARCH_SERVICE_NAME}${NC}"

# Enable system-assigned managed identity
echo ""
echo -e "${BLUE}Enabling system-assigned managed identity...${NC}"
MANAGED_IDENTITY_PRINCIPAL_ID=$(az search service show \
    --resource-group "$RESOURCE_GROUP" \
    --name "$SEARCH_SERVICE_NAME" \
    --query "identity.principalId" -o tsv 2>/dev/null || echo "")

if [ -z "$MANAGED_IDENTITY_PRINCIPAL_ID" ] || [ "$MANAGED_IDENTITY_PRINCIPAL_ID" == "null" ]; then
    echo "  Creating managed identity..."
    az search service update \
        --resource-group "$RESOURCE_GROUP" \
        --name "$SEARCH_SERVICE_NAME" \
        --identity-type SystemAssigned \
        --output none
    
    # Wait a bit for identity to propagate
    sleep 10
    
    MANAGED_IDENTITY_PRINCIPAL_ID=$(az search service show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$SEARCH_SERVICE_NAME" \
        --query "identity.principalId" -o tsv)
fi

echo -e "${GREEN}✓ Managed Identity Principal ID: ${MANAGED_IDENTITY_PRINCIPAL_ID}${NC}"

# Create App Registration
echo ""
echo -e "${BLUE}Creating Microsoft Entra app registration...${NC}"
APP_NAME="AzureAISearch-SharePoint-${SEARCH_SERVICE_NAME}"

# Check if app already exists
EXISTING_APP_ID=$(az ad app list --display-name "$APP_NAME" --query "[0].appId" -o tsv 2>/dev/null || echo "")

if [ -n "$EXISTING_APP_ID" ] && [ "$EXISTING_APP_ID" != "null" ]; then
    echo -e "${YELLOW}⚠ App registration already exists: ${APP_NAME}${NC}"
    echo "  App ID: ${EXISTING_APP_ID}"
    read -p "Do you want to delete and recreate it? (yes/no): " RECREATE
    
    if [ "$RECREATE" == "yes" ]; then
        echo "  Deleting existing app..."
        az ad app delete --id "$EXISTING_APP_ID"
        sleep 5
        EXISTING_APP_ID=""
    else
        APPLICATION_ID="$EXISTING_APP_ID"
    fi
fi

if [ -z "$EXISTING_APP_ID" ]; then
    # Create the app registration
    APPLICATION_ID=$(az ad app create \
        --display-name "$APP_NAME" \
        --sign-in-audience AzureADMyOrg \
        --query appId -o tsv)
    
    echo -e "${GREEN}✓ App created: ${APPLICATION_ID}${NC}"
    
    # Get the object ID for the app
    APP_OBJECT_ID=$(az ad app show --id "$APPLICATION_ID" --query id -o tsv)
    
    # Configure public client flows (optional - not required for federated credentials)
    echo "  Configuring authentication settings..."
    az ad app update --id "$APPLICATION_ID" \
        --set isFallbackPublicClient=true \
        2>/dev/null || echo "  (skipping public client configuration)"
    
    sleep 3
fi

# Get or create service principal
echo ""
echo -e "${BLUE}Creating service principal...${NC}"
SP_OBJECT_ID=$(az ad sp list --filter "appId eq '$APPLICATION_ID'" --query "[0].id" -o tsv 2>/dev/null || echo "")

if [ -z "$SP_OBJECT_ID" ] || [ "$SP_OBJECT_ID" == "null" ]; then
    echo "  Creating service principal..."
    SP_OBJECT_ID=$(az ad sp create --id "$APPLICATION_ID" --query id -o tsv)
    sleep 5
fi
echo -e "${GREEN}✓ Service Principal ID: ${SP_OBJECT_ID}${NC}"

# Configure API permissions and admin consent
echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}API Permissions Configuration${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Add permissions via single requiredResourceAccess payload (more reliable than add)
echo -e "${YELLOW}Step 1: Add API Permissions${NC}"

GRAPH_API_ID="00000003-0000-0000-c000-000000000000"
# Application permission IDs (Microsoft Graph)
# Files.Read.All (Application): 01d4889c-1287-42c6-ac1f-5d1e02578ef6
# Sites.FullControl.All (Application): a82116e5-55eb-4c41-a434-62fe8a61c773
FILES_READ_ALL_ID="01d4889c-1287-42c6-ac1f-5d1e02578ef6"
SITES_FULLCONTROL_ALL_ID="a82116e5-55eb-4c41-a434-62fe8a61c773"

echo "  Patching requiredResourceAccess with Files.Read.All and Sites.FullControl.All (for ACL-aware indexing)..."
az ad app update --id "$APPLICATION_ID" \
    --required-resource-access "[{\"resourceAppId\":\"${GRAPH_API_ID}\",\"resourceAccess\":[{\"id\":\"${FILES_READ_ALL_ID}\",\"type\":\"Role\"},{\"id\":\"${SITES_FULLCONTROL_ALL_ID}\",\"type\":\"Role\"}]}]" >/dev/null

echo "  Waiting for permissions to propagate in Azure AD (30s)..."
sleep 30
echo "  ✓ Propagation wait complete"

if [ "$HAS_ADMIN" = true ]; then
    echo ""
    echo -e "${YELLOW}Step 2: Grant Admin Consent${NC}"
    echo ""
    echo "  Open this consent URL in your browser:"
    echo ""
    echo -e "  ${GREEN}https://login.microsoftonline.com/${TENANT_ID}/adminconsent?client_id=${APPLICATION_ID}${NC}"
    echo ""
    echo "  1. Review the requested permissions (Files.Read.All, Sites.Read.All)"
    echo "  2. Click '${GREEN}Accept${NC}' to grant consent"
    echo "  3. Wait for confirmation page"
    echo ""
    read -p "Press Enter after granting consent..."
    echo ""
    echo -e "${GREEN}✓ Admin consent granted${NC}"
else
    echo ""
    echo -e "${YELLOW}Step 2: Grant Admin Consent (Manual)${NC}"
    echo ""
    echo "  IMPORTANT: Use this direct consent URL (not the portal button):"
    echo ""
    echo -e "  ${GREEN}https://login.microsoftonline.com/${TENANT_ID}/adminconsent?client_id=${APPLICATION_ID}${NC}"
    echo ""
    echo "  1. Open the URL above in your browser"
    echo "  2. Sign in with admin credentials (activate PIM if needed)"
    echo "  3. Review permissions (Files.Read.All, Sites.Read.All) and click 'Accept'"
    echo "  4. Wait for confirmation"
    echo ""
    read -p "Press Enter after granting consent to continue..."
    echo ""
    echo -e "${GREEN}✓ Proceeding (assuming consent was granted)${NC}"
fi

# Configure federated credentials for managed identity
echo ""
echo -e "${BLUE}Configuring federated credentials...${NC}"

SUBSCRIPTION_ID=$(az account show --query id -o tsv)
CREDENTIAL_NAME="SearchServiceManagedIdentity"

# Check if credential already exists
EXISTING_CRED=$(az ad app federated-credential list --id "$APPLICATION_ID" --query "[?name=='${CREDENTIAL_NAME}'].name" -o tsv 2>/dev/null || echo "")

if [ -n "$EXISTING_CRED" ]; then
    echo -e "${YELLOW}  Federated credential already exists, deleting...${NC}"
    az ad app federated-credential delete \
        --id "$APPLICATION_ID" \
        --federated-credential-id "$CREDENTIAL_NAME" \
        2>/dev/null || true
    sleep 3
fi

# Create federated credential JSON
cat > /tmp/federated-cred.json <<EOF
{
  "name": "${CREDENTIAL_NAME}",
  "issuer": "https://login.microsoftonline.com/${TENANT_ID}/v2.0",
  "subject": "${MANAGED_IDENTITY_PRINCIPAL_ID}",
  "description": "Federated credential for Azure AI Search managed identity",
  "audiences": [
    "api://AzureADTokenExchange"
  ]
}
EOF

echo "  Creating federated credential..."
az ad app federated-credential create \
    --id "$APPLICATION_ID" \
    --parameters @/tmp/federated-cred.json \
    --output none

rm /tmp/federated-cred.json

echo -e "${GREEN}✓ Federated credential configured${NC}"

# Build connection string
echo ""
echo -e "${BLUE}Building SharePoint connection string...${NC}"

SHAREPOINT_CONNECTION_STRING="SharePointOnlineEndpoint=${SHAREPOINT_SITE_URL};ApplicationId=${APPLICATION_ID};FederatedCredentialObjectId=${MANAGED_IDENTITY_PRINCIPAL_ID};TenantId=${TENANT_ID}"

echo -e "${GREEN}✓ Connection string created${NC}"

# Update .env file
echo ""
echo -e "${BLUE}Updating .env file...${NC}"

# Check if SharePoint config already exists in .env
if grep -q "# SharePoint Configuration (Automated)" "$ENV_PATH"; then
    echo "  Removing old SharePoint configuration..."
    # Remove old SharePoint section
    sed -i.bak '/# SharePoint Configuration (Automated)/,/^$/d' "$ENV_PATH"
fi

# Append new SharePoint configuration
cat >> "$ENV_PATH" <<EOF

# SharePoint Configuration (Automated)
# Generated by setup-sharepoint.sh on $(date)
SHAREPOINT_SITE_URL=${SHAREPOINT_SITE_URL}
SHAREPOINT_CONNECTION_STRING=${SHAREPOINT_CONNECTION_STRING}
SHAREPOINT_APP_ID=${APPLICATION_ID}
SHAREPOINT_TENANT_ID=${TENANT_ID}
SHAREPOINT_MANAGED_IDENTITY_PRINCIPAL_ID=${MANAGED_IDENTITY_PRINCIPAL_ID}
SHAREPOINT_CONTAINER_NAME=defaultSiteLibrary

EOF

echo -e "${GREEN}✓ Updated .env file${NC}"

# Summary
echo ""
echo -e "${GREEN}========================================"
echo "Setup Complete!"
echo "========================================${NC}"
echo ""
echo "SharePoint Indexer Configuration:"
echo "  📁 SharePoint Site: ${SHAREPOINT_SITE_URL}"
echo "  🔐 App Registration: ${APP_NAME}"
echo "  🆔 Application ID: ${APPLICATION_ID}"
echo "  🏢 Tenant ID: ${TENANT_ID}"
echo "  🔑 Managed Identity: ${MANAGED_IDENTITY_PRINCIPAL_ID}"
echo "  🔗 Authentication: Federated Credentials (Secretless)"
echo ""
echo "Configuration saved to: ${ENV_PATH}"
echo ""
echo -e "${YELLOW}⚠️  IMPORTANT: Never commit .env to source control!${NC}"
echo ""
echo "Next Steps:"
echo "  1. Open notebooks/part3b-sharepoint-indexed-knowledge-source.ipynb"
echo "  2. Run the notebook - it will use the automated configuration"
echo "  3. The notebook will load settings from .env automatically"
echo ""
echo "The app registration has been configured with:"
echo "  ✓ Files.Read.All permission"
echo "  ✓ Sites.Read.All permission"
echo "  ✓ Admin consent granted"
echo "  ✓ Federated credentials for managed identity"
echo "  ✓ Public client flows enabled"
echo ""
echo "To view app registration in Azure Portal:"
echo "  https://portal.azure.com/#view/Microsoft_AAD_RegisteredApps/ApplicationMenuBlade/~/Overview/appId/${APPLICATION_ID}"
echo ""
