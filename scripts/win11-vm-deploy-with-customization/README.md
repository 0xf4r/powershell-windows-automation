# Windows 11 vSphere VM Deployment with BitLocker Handling

**Author:** 0xf4r  
**Version:** 3.0  
**Date:** 2025-08-13

This PowerShell script automates the deployment of a Windows 11 VM from a vSphere template **with BitLocker enabled**, ensuring BitLocker protection is suspended before Sysprep/customization to prevent boot issues.

---

## 📋 Features

- Connects to vCenter using VMware PowerCLI.
- Clones a Windows 11 template to a new VM.
- Applies OS customization using:
  - vCenter customization spec **OR**
  - hardcoded settings in the script.
- Suspends BitLocker inside the VM using VMware Tools before customization.
- Powers on the VM to complete OS customization.
- Handles TPM replacement during VM clone.

---

## 🛠 Requirements

- **Operating System:** Windows with PowerShell 5.1 or later.
- **VMware PowerCLI:** Version 13.0 or later.
- **vCenter Server:** Version 7.x or later.
- **VMware Tools:** Installed and running in the Windows 11 template.
- **Template Configuration:**
  - BitLocker enabled on system drive with TPM.
  - Local administrator account available.

---

## ⚙ Configuration

At the top of the script, edit the **CONFIGURATION** section:

```powershell
# vCenter connection
$vcServer            = "vcenter.domain.local"

# Template / VM details
$templateName        = "W11-Template"
$vmName              = "DEV-W11-01"
$datacenterName      = "dc"
$folderPath          = "parentFolder/w11"
$clusterName         = "Cluster01"
$datastoreName       = "desktopssd"

# Customization
$useHardcodedSpec    = $false
$customSpecName      = "profileq"

# Local Admin credentials on the template VM
$localAdminUser      = "Administrator"
$localAdminPassword  = "YourLocalAdminPass123!"