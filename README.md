# Degea / Truesec onboarding scripts
Scripts are only tested in **Powershell v7** and later on Windows 10/11. <br><br>
[Overview and download page Microsoft Learn](https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell?view=powershell-7.3)

Requires Microsoft.Graph module.
```
Install-Module -Name Microsoft.Graph -Scope CurrentUser
```
SOC License requirements: <br>
-At least Azure Active Premium Plan 2 level. (One AAD Premium Plan 2 license) <br>
-At least one license containing Microsoft Defender for Endpoint plan 2. (One DfE Plan 2 license or license containing DfE Plan 2) <br>
-Onboarded at least one device to Defender for Endpoint, ensure that EDR logs appear on device (timeline + advanced hunting)<br>

Download or clone the repo, then run scripts in order 1-4. PDF files are for reference.

Due to a lack of programmatic support the steps in part 4 still need to be executed manually.

Part 5 (Degea Access) should only be run if Degea does not have regular admin access (GDAP).
