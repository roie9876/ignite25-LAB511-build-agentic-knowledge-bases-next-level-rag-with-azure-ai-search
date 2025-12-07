# SharePoint Site URL Guide

## 🔍 How to Find Your SharePoint Site URL

When configuring the IndexedSharePointKnowledgeSource, you need the **site URL**, not a document library or page URL.

### Step-by-Step Instructions

1. **Open your SharePoint site** in a web browser
2. **Look at the URL** in the address bar
3. **Copy the URL up to and including** `/sites/[site-name]`
4. **Remove** any path after the site name

### URL Format

#### ✓ Correct Format
```
https://[tenant].sharepoint.com/sites/[site-name]
```

#### ✗ Incorrect Format (includes document library path)
```
https://[tenant].sharepoint.com/sites/[site-name]/Shared%20Documents/Forms/AllItems.aspx
```

### Real-World Example

If your browser address bar shows:
```
https://mngenvmcap338326.sharepoint.com/sites/lab511-demo/Shared%20Documents/Forms/AllItems.aspx
```

**You should use:**
```
https://mngenvmcap338326.sharepoint.com/sites/lab511-demo
```

### Common SharePoint URL Patterns

| Site Type | Example URL |
|-----------|-------------|
| **Team Site** | `https://contoso.sharepoint.com/sites/engineering` |
| **Project Site** | `https://mycompany.sharepoint.com/sites/ProjectAlpha` |
| **Personal OneDrive** | `https://mycompany-my.sharepoint.com/personal/user_mycompany_com` |
| **Root Site** | `https://contoso.sharepoint.com` |

### What Gets Indexed?

When you provide the site URL, the Azure AI Search indexer will:
- ✅ Index **all accessible documents** in the site
- ✅ Index **all document libraries** (Shared Documents, etc.)
- ✅ Index **all folders** within those libraries
- ✅ Respect **SharePoint permissions** (if configured)

### Filtering to Specific Folders

If you want to index only specific folders, you can use the `folder_filter_path` parameter:

```python
knowledge_source_params = IndexedSharePointKnowledgeSourceParameters(
    connection_string=sharepoint_connection_string,
    folder_filter_path="/sites/lab511-demo/Shared Documents/HR"  # Optional: specific folder
)
```

### Troubleshooting

**Q: What if I use the wrong URL format?**
- A: The indexer will fail to connect or may not index the expected content.

**Q: Can I index multiple sites?**
- A: No, each `IndexedSharePointKnowledgeSource` indexes one site. Create multiple knowledge sources for multiple sites.

**Q: What about OneDrive for Business?**
- A: OneDrive uses a different URL pattern: `https://[tenant]-my.sharepoint.com/personal/[user]_[domain]_com`

**Q: Do I need trailing slashes?**
- A: No, avoid trailing slashes: `https://contoso.sharepoint.com/sites/lab511` (not `/lab511/`)

### Quick Validation

Your URL is correct if:
- ✅ It starts with `https://`
- ✅ It contains `.sharepoint.com`
- ✅ It ends with `/sites/[name]` (for team sites)
- ✅ It does NOT contain `/Shared%20Documents/` or `/Forms/`
- ✅ You can access the site when pasting the URL in a browser

### Using with the Setup Script

```bash
cd infra/deploy-yourself
./setup-sharepoint.sh -g LAB511-ResourceGroup -s https://mngenvmcap338326.sharepoint.com/sites/lab511-demo
```

### Using in the Notebook

The notebook will prompt you for the URL and validate the format. If you ran the setup script, the URL will be automatically loaded from the `.env` file.
