# Degea / Truesec onboarding scripts
# Prerequisites
Prerequisites have been detailed in this document:
</br> [0-DEG SOP - Prerequisites.pdf](https://github.com/Degea-AB/degea-ts-onboard/blob/main/0-DEG%20SOP%20-%20Prerequisites.pdf)
</br> 

# How-to
Scripts are only tested in **Powershell v7** and later on Windows 10/11. <br><br>
[Powershell 7 overview and download page Microsoft Learn](https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell?view=powershell-7.3)

Requires Microsoft.Graph module.
```
Install-Module -Name Microsoft.Graph -Scope CurrentUser
```

</br> Download or clone the repo, then run script 1-3 EntraSetup.ps1. PDF files are for reference.<br>
</br>Perform the steps in "4-TSD SOP - 04 Onboard Microsoft 365 Defender Unified RBAC.pdf", then export the roles and run the script validate RBAC settings
</br>Perform the steps in the remaining SOPs

(Degea Access) should only be run if Degea does not have regular admin access (GDAP).
