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

</br> Download or clone the repo, then run script 1-3 EntraSetup.ps1. Perform the steps requested by the script, you will be prompted to sign in and approve applications and perform steps during the process. PDF files are for reference.<br>
</br> Run the script 4-CreateURBACRolesAndAssignments.ps1 with:<br>
```
.\4-CreateURBACRolesAndAssignments.ps1 -RunMode Setup -AllowCreateMissing
```
</br>Export the roles from the XDR permission page (security.microsoft.com > Settings > Permission > XDR) and run the script .\4-ValidateURBACRolesAndAssignments.ps1 to validate all workloads are enabled.
</br>Perform the steps in the remaining SOPs