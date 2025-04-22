# Degea / Truesec onboarding scripts
Scripts are only tested in **Powershell v7** and later on Windows 10/11. <br><br>
[Powershell 7 overview and download page Microsoft Learn](https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell?view=powershell-7.3)

Requires Microsoft.Graph module.
```
Install-Module -Name Microsoft.Graph -Scope CurrentUser
```
SOC License requirements: <br>
-At least Azure Active Premium Plan 2 level to enable PIM functionality. (One AAD Premium Plan 2 license) <br>
-(EDR) Enough Defender for Endpoint Plan 2 licenses to change licensing in security portal to DfE P2. (DfE Plan 2 license or license containing DfE Plan 2) <br>
[Endpoint subscription state](https://security.microsoft.com/securitysettings/endpoints/licenses) > Subscription state should be DfE P2, can be changed under "Manage subscription settings" <br>
-Onboarded at least one device to Defender for Endpoint, ensure that EDR logs appear on device (timeline + advanced hunting)<br>
-XDR license requirements, included in e.g. Security E5 addon:<br>
Entra ID Protection (P2)<br>
Defender for Office (P2)<br>
Defender for Identity<br>
Defender for Cloud Apps<br>

Download or clone the repo, then run script 1-3 EntraSetup.ps1. PDF files are for reference.<br>
Perform the steps in "4-TSD SOP - 04 Onboard Microsoft 365 Defender Unified RBAC.pdf", then export the roles and validate
Perform the steps in the remaining SOPs

(Degea Access) should only be run if Degea does not have regular admin access (GDAP).
