## Before You Begin

<details>
<summary><strong>🔑 Lab Credentials (Click to expand when you need to sign in)</strong></summary>

In any point of time during the lab, if you need to sign in to the virtual machine (Windows) or any Azure or Microsoft 365 apps (M365 Copilot, SharePoint, Teams etc.), use the credentials provided below.

### Sign into Virtual Machine (Windows)

If you need to sign in the virtual machine, use the following credentials:

- **User name**: +++@lab.VirtualMachine(Win11-Pro-Base).Username+++  
- **Password**: +++@lab.VirtualMachine(Win11-Pro-Base).Password+++

### Sign into Azure & Microsoft 365

If you need to sign in to any Azure or Microsoft 365 apps, use the following credentials:

- **Username**: +++@lab.CloudPortalCredential(User1).Username+++  
- **Temporary Access Pass**: +++@lab.CloudPortalCredential(User1).AccessToken+++

</details>

## Overview

In this hands-on lab, you'll build a knowledge base using agentic retrieval in Azure AI Search. Unlike traditional search or basic RAG systems that simply return documents, an agentic knowledge base plans how and where to search, chooses the most relevant knowledge sources, and synthesizes grounded, citation-backed responses tailored to the user's intent.

Through 9 progressive exercises, you'll explore multiple retrieval patterns across different data sources (search indexes, SharePoint, web, blob storage), experiment with answer synthesis strategies, and optimize performance by adjusting reasoning effort levels. Parts 3 and 3B both use SharePoint: Part 3 shows the remote (live-permission) pattern, and Part 3B shows the indexed (high-performance, citation-rich) pattern—run Part 3B immediately after Part 3.

## Getting Started

Follow the steps below to set up your environment and begin the lab.

### Sign into Windows

In the virtual machine, sign into Windows using the following credentials:

- **User name**: +++@lab.VirtualMachine(Win11-Pro-Base).Username+++  
- **Password**: +++@lab.VirtualMachine(Win11-Pro-Base).Password+++

### Access the Lab Repository

Once signed in to the Skillable environment, you’ll find the lab repository already cloned on your desktop under the folder: **Desktop > ignite25-lab511-private-dev**.

> This folder contains all the code, notebooks, and resources you’ll need for the lab.

### Open the Project Folder in Visual Studio Code

Open Visual Studio Code and select **File > Open Folder**. Then navigate to Desktop and select the **ignite25-lab511-private-dev** folder and then **Select Folder**.

> [!TIP]
> * When prompted whether to trust the authors of the files, select **Yes, I trust the authors**.

### Verify the Environment Setup

All required Azure services including **Azure AI Search with pre-indexed data** and **Azure OpenAI deployments** have already been provisioned for you.

<details>
<summary><strong>📋 What's Pre-Configured (Click to expand for details)</strong></summary>

- **Azure AI Search** - Standard tier with two pre-created indexes:
  - **hrdocs:** HR policies, employee handbook, role library, company overview
  - **healthdocs:** Health insurance plans, benefits options, coverage details
- **Azure OpenAI** - Deployed models **gpt-4.1** for chat completion and answer synthesis and **text-embedding-3-large** for vector embeddings
- **Pre-computed vectors** - All 384 document chunks are already vectorized and indexed

</details>

#### Verify Environment Variables

1. Open the **.env** file under the main project folder.  
2. Verify that it includes the key environment variables *AZURE_SEARCH_SERVICE_ENDPOINT*, *AZURE_SEARCH_ADMIN_KEY*, *AZURE_OPENAI_ENDPOINT*, and *AZURE_OPENAI_KEY*.

If these variables are present, proceed to verify the indexes in Azure Portal.

#### Verify Indexes in Azure Portal

Let's confirm that the search indexes have been created successfully:

1. Open a web browser and navigate to the +++https://portal.azure.com+++.
2. Sign in using your lab credentials:
    - **Username**: +++@lab.CloudPortalCredential(User1).Username+++  
    - **Temporary Access Pass**: +++@lab.CloudPortalCredential(User1).AccessToken+++
3. In the Azure Portal search bar at the top, search for +++lab511-search+++ and select your AI Search service (it will look like *lab511-search-.....*).
4. In the left navigation menu, select **Search management** > **Indexes**.
5. You should see two indexes:
   - **hrdocs** - Should show document count of 50
   - **healthdocs** - Should show document count of 334

If your indexes are present and populated, your environment is ready to use. You can now proceed to start with the Jupyter Notebooks.

<details>
<summary><strong>⚠️ Troubleshooting ⚠️ Click to expand if environment setup fails!</strong></summary>

If the automated environment setup fails, follow these steps to configure your environment manually:

**Step 1: Configure Environment Variables**

1. In Visual Studio Code, locate the **env.sample** file in the project root folder.
2. Rename **env.sample** to **.env**.
3. Gather the required credentials from Azure Portal:

   **For Azure AI Search:**
   - Navigate to **Azure Portal** > Search for +++lab511-search+++ > Select your AI Search service
   - Go to **Settings** > **Keys**
   - Copy the **URL** (endpoint) and **Primary admin key**

   **For Azure OpenAI:**
   - Navigate to **Azure Portal** > Search for +++lab511-openai+++ > Select your OpenAI service
   - Go to **Keys and Endpoint**
   - Copy the **Endpoint** and **KEY 1**

   **For Azure Storage:**
   - Navigate to **Azure Portal** > Search for +++lab511st+++ > Select your Storage Account
   - Go to **Security + networking** > **Access keys**
   - Copy the **Connection string** from key1

   **For Azure AI Services:**
   - Navigate to **Azure Portal** > Search for +++lab511-ai-services+++ > Select your AI Services
   - Go to **Keys and Endpoint**
   - Copy the **Endpoint** and **KEY 1**

4. Update the **.env** file with your values (replace the placeholder values).

**Step 2: Create Python Virtual Environment**

1. Open the first notebook **notebooks/part1-basic-knowledge-base.ipynb**.
2. Run the first code cell and when prompted to select a kernel, choose **Create New Environment**.
3. Select **Venv** and then select the **requirements.txt** file in the **notebooks/** folder.
4. Wait for the virtual environment to be created.

**Step 3: Run Knowledge Base Setup Script**

1. Open a new terminal in Visual Studio Code (**Terminal** > **New Terminal**).
2. Activate the virtual environment by running:

   +++.\.venv\Scripts\Activate.ps1+++

3. Run the knowledge base creation script:

   +++python infra/create-knowledge.py+++

4. Wait for the script to complete. It will create and populate the required indexes. Check **Azure AI Search > Search management > Indexes** to verify that the indexes **hrdocs** and **healthdocs** are created and populated with documents.

**Step 4: Verify GPT-4.1 Model Deployment**

If you encounter errors related to the GPT model when running notebook cells:

1. Navigate to +++https://portal.azure.com+++ > Select your OpenAI service.
2. Select **Go to Azure AI Foundry**.
3. Select **Deployments**.
4. Verify that **gpt-4.1** is deployed.
5. If missing, click **Create new deployment**:
   - Select **gpt-4.1** model
   - Set **Standard** deployment type
   - Make sure your existing OpenAI resource is selected
   - Click **Deploy**

</details>

### Start with Jupyter Notebooks

This lab includes 9 progressive notebooks covering different knowledge base patterns (follow the order below so Part 3B runs right after Part 3):

1. **Basic Knowledge Base** - Connect indexed data, configure Azure OpenAI, generate cited answers
2. **Multiple Knowledge Sources** - Query across indexes with custom instructions
3. **SharePoint Integration (Remote)** - Real-time document retrieval from SharePoint with live permissions
4. **Indexed SharePoint (Part 3B, formerly Part 9)** - High-performance SharePoint indexing for faster search, richer citations, and scheduling
5. **Web Sources** - Combine internal and external content
6. **Blob Storage** - Upload and index with minimal vs. semantic strategies
7. **Combined Sources** - Unified querying across multiple source types
8. **Minimal Reasoning** - Speed-optimized retrieval
9. **Medium Reasoning** - Balanced query decomposition

Start with **part1-basic-knowledge-base.ipynb** in the **notebooks/** folder and progress through each notebook sequentially following the order above (1, 2, 3, 3B, 4, 5, 6, 7, 8).

### Complete the Lab

Work through each notebook in order, starting with **part1-basic-knowledge-base.ipynb**. Each notebook explores a different knowledge base pattern and builds on concepts from previous parts.

Once you've completed all 9 notebooks, select **Next** to review key takeaways and next steps.
