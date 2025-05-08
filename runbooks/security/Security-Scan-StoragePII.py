#!/usr/bin/env python3
"""
Security-Scan-StoragePII.py - Scans Azure Storage Accounts for potential PII data

This runbook scans blob containers and file shares in Azure Storage Accounts for patterns
that may indicate the presence of Personally Identifiable Information (PII) or other
sensitive data. It can help identify potential compliance issues with data privacy
regulations like GDPR, CCPA, HIPAA, etc.

Parameters:
    resource_group_names (list, optional): List of resource groups to scan.
        If not provided, uses the TargetResourceGroups variable from the Automation Account.
    max_scan_size_mb (int, optional): Maximum file size in MB to scan. Default is 10.
    scan_depth (int, optional): Maximum number of items to scan per container/share. Default is 100.

The script uses regex patterns to identify common PII data patterns like:
- Social Security Numbers
- Credit Card Numbers
- Email Addresses
- Phone Numbers
- Passport Numbers
- Driver's License Numbers (US)
- IP Addresses
- AWS Access Keys
- Azure Connection Strings

Output is sent to Log Analytics and the Automation job output.
"""

import re
import os
import json
import datetime
from azure.common.credentials import get_azure_cli_credentials
from azure.mgmt.resource import ResourceManagementClient
from azure.mgmt.storage import StorageManagementClient
from azure.storage.blob import BlobServiceClient
from azure.storage.file.share import ShareServiceClient

# PII detection regex patterns
PII_PATTERNS = {
    'SSN': r'\b\d{3}[-\s]?\d{2}[-\s]?\d{4}\b',
    'Credit Card': r'\b(?:\d{4}[-\s]?){3}\d{4}\b',
    'Email': r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b',
    'Phone Number': r'\b(\+\d{1,2}\s)?\(?\d{3}\)?[\s.-]?\d{3}[\s.-]?\d{4}\b',
    'Passport Number': r'\b[A-Z]{1,2}[0-9]{6,9}\b',
    'US Driver License': r'\b[A-Z]{1}[0-9]{7}\b',
    'IP Address': r'\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b',
    'AWS Access Key': r'\b[A-Z0-9]{20}\b',
    'Azure Connection String': r'DefaultEndpointsProtocol=https;AccountName=[^;]+;AccountKey=[^;]+;',
}

def get_automation_vars():
    """Get variables from Azure Automation account."""
    from automationassets import get_automation_variable
    
    try:
        resource_groups_json = get_automation_variable("TargetResourceGroups")
        resource_groups = json.loads(resource_groups_json)
        return resource_groups
    except Exception as e:
        print(f"Error getting automation variables: {str(e)}")
        return []

def scan_text_for_pii(text):
    """Scan text content for PII using regex patterns."""
    findings = {}
    
    for pattern_name, pattern in PII_PATTERNS.items():
        matches = re.findall(pattern, text)
        if matches:
            # Redact/mask the actual values in the output for security
            redacted_matches = []
            for match in matches:
                if pattern_name == 'Email':
                    parts = match.split('@')
                    if len(parts) > 1:
                        redacted = f"{parts[0][0]}{'*' * (len(parts[0])-2)}{parts[0][-1]}@{parts[1]}"
                        redacted_matches.append(redacted)
                elif pattern_name in ['SSN', 'Credit Card', 'Phone Number']:
                    redacted = f"{'*' * (len(match) - 4)}{match[-4:]}"
                    redacted_matches.append(redacted)
                else:
                    redacted = f"{match[0:3]}{'*' * (len(match) - 6)}{match[-3:]}" if len(match) > 6 else f"{match[0]}{'*' * (len(match) - 2)}{match[-1]}"
                    redacted_matches.append(redacted)
            
            findings[pattern_name] = {
                "count": len(matches),
                "samples": redacted_matches[:3]  # Just show up to 3 redacted examples
            }
    
    return findings

async def scan_blob(blob_client, max_size_mb):
    """Scan a blob for PII."""
    try:
        properties = await blob_client.get_blob_properties()
        
        # Skip if the blob is too large
        if properties.size > (max_size_mb * 1024 * 1024):
            return {
                "scanned": False,
                "reason": "File too large",
                "size_mb": properties.size / (1024 * 1024)
            }
        
        # Download the blob content
        stream = await blob_client.download_blob()
        content = await stream.readall()
        
        # Try to decode as text
        try:
            text_content = content.decode('utf-8')
            pii_findings = scan_text_for_pii(text_content)
            
            return {
                "scanned": True,
                "size_mb": properties.size / (1024 * 1024),
                "findings": pii_findings,
                "has_pii": len(pii_findings) > 0
            }
        except UnicodeDecodeError:
            # Not a text file
            return {
                "scanned": False,
                "reason": "Not a text file",
                "size_mb": properties.size / (1024 * 1024)
            }
    except Exception as e:
        return {
            "scanned": False,
            "reason": f"Error: {str(e)}"
        }

async def scan_storage_account(account_name, account_key, resource_group, max_size_mb=10, scan_depth=100):
    """Scan all containers in a storage account for PII."""
    results = {
        "storage_account": account_name,
        "resource_group": resource_group,
        "scan_time": datetime.datetime.now().isoformat(),
        "containers_scanned": 0,
        "blobs_scanned": 0,
        "pii_found_count": 0,
        "pii_findings": []
    }
    
    # Connect to blob service
    blob_service = BlobServiceClient(
        account_url=f"https://{account_name}.blob.core.windows.net",
        credential=account_key
    )
    
    try:
        # List all containers
        containers = blob_service.list_containers()
        
        for container in containers:
            container_client = blob_service.get_container_client(container.name)
            container_results = {
                "container_name": container.name,
                "blobs_scanned": 0,
                "blobs_with_pii": 0,
                "findings": []
            }
            
            # List blobs in the container
            blobs = container_client.list_blobs()
            
            # Limit the number of blobs to scan per container
            scan_count = 0
            
            for blob in blobs:
                if scan_count >= scan_depth:
                    break
                    
                blob_client = container_client.get_blob_client(blob.name)
                scan_result = await scan_blob(blob_client, max_size_mb)
                
                if scan_result.get("scanned", False):
                    container_results["blobs_scanned"] += 1
                    results["blobs_scanned"] += 1
                    
                    if scan_result.get("has_pii", False):
                        container_results["blobs_with_pii"] += 1
                        results["pii_found_count"] += 1
                        
                        finding = {
                            "blob_name": blob.name,
                            "size_mb": scan_result.get("size_mb", 0),
                            "pii_types": list(scan_result.get("findings", {}).keys()),
                            "details": scan_result.get("findings", {})
                        }
                        
                        container_results["findings"].append(finding)
                
                scan_count += 1
            
            results["containers_scanned"] += 1
            
            # Only add container results if PII was found
            if container_results["blobs_with_pii"] > 0:
                results["pii_findings"].append(container_results)
    
    except Exception as e:
        print(f"Error scanning storage account {account_name}: {str(e)}")
    
    return results

def main(resource_group_names=None, max_scan_size_mb=10, scan_depth=100):
    """Main function to scan storage accounts for PII."""
    print("Starting PII scan of Azure Storage Accounts")
    
    # If resource_group_names is not provided, get from Automation variable
    if not resource_group_names:
        resource_group_names = get_automation_vars()
        print(f"Using resource groups from Automation variables: {resource_group_names}")
    
    # Use Azure Automation's Managed Identity
    from automationassets import get_automation_runas_credential
    
    try:
        # Get authentication using Run As account
        automation_credential = get_automation_runas_credential()
        subscription_id = os.environ['AZURE_SUBSCRIPTION_ID']
        
        # Create clients
        resource_client = ResourceManagementClient(
            credential=automation_credential,
            subscription_id=subscription_id
        )
        
        storage_client = StorageManagementClient(
            credential=automation_credential,
            subscription_id=subscription_id
        )
        
        # Scan each resource group
        all_results = []
        
        for rg_name in resource_group_names:
            print(f"Scanning storage accounts in resource group: {rg_name}")
            
            # Get all storage accounts in the resource group
            storage_accounts = storage_client.storage_accounts.list_by_resource_group(rg_name)
            
            for storage_account in storage_accounts:
                print(f"  - Scanning storage account: {storage_account.name}")
                
                # Get storage account keys
                keys = storage_client.storage_accounts.list_keys(rg_name, storage_account.name)
                primary_key = keys.keys[0].value
                
                # Scan the storage account
                scan_results = scan_storage_account(
                    account_name=storage_account.name,
                    account_key=primary_key,
                    resource_group=rg_name,
                    max_size_mb=max_scan_size_mb,
                    scan_depth=scan_depth
                )
                
                all_results.append(scan_results)
                
                # Print summary of findings
                print(f"    - Containers scanned: {scan_results['containers_scanned']}")
                print(f"    - Blobs scanned: {scan_results['blobs_scanned']}")
                print(f"    - Blobs with PII detected: {scan_results['pii_found_count']}")
                
                if scan_results['pii_found_count'] > 0:
                    print(f"    - PII types found:")
                    pii_types = set()
                    for container in scan_results.get('pii_findings', []):
                        for finding in container.get('findings', []):
                            for pii_type in finding.get('pii_types', []):
                                pii_types.add(pii_type)
                    
                    for pii_type in pii_types:
                        print(f"      - {pii_type}")
        
        # Generate and print overall summary
        total_accounts_scanned = len(all_results)
        total_containers_scanned = sum(result['containers_scanned'] for result in all_results)
        total_blobs_scanned = sum(result['blobs_scanned'] for result in all_results)
        total_pii_found = sum(result['pii_found_count'] for result in all_results)
        accounts_with_pii = sum(1 for result in all_results if result['pii_found_count'] > 0)
        
        summary = f"""
PII Scan Summary:
-----------------
Storage accounts scanned: {total_accounts_scanned}
Containers scanned: {total_containers_scanned}
Blobs scanned: {total_blobs_scanned}
Blobs with PII detected: {total_pii_found}
Storage accounts with PII: {accounts_with_pii}
        """
        
        print(summary)
        
        # Return the full results JSON
        return {
            "summary": {
                "storage_accounts_scanned": total_accounts_scanned,
                "containers_scanned": total_containers_scanned,
                "blobs_scanned": total_blobs_scanned,
                "blobs_with_pii": total_pii_found,
                "storage_accounts_with_pii": accounts_with_pii
            },
            "detailed_results": all_results
        }
        
    except Exception as e:
        error_msg = f"Error in PII scan: {str(e)}"
        print(error_msg)
        raise Exception(error_msg)

if __name__ == "__main__":
    # This script is meant to be run in Azure Automation, but this allows for local testing
    from azure.identity import DefaultAzureCredential
    credential = DefaultAzureCredential()
    
    # Set subscription ID for local testing
    os.environ['AZURE_SUBSCRIPTION_ID'] = 'YOUR_SUBSCRIPTION_ID'
    
    # Use resource groups for local testing
    resource_groups = ['YourResourceGroup']
    
    main(resource_groups)
