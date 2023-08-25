# Degea / Truesec onboarding scripts
Scripts are only tested in Powershell v7 and later. 

Requires Microsoft.Graph module.
```
Install-Module -Name Microsoft.Graph -Scope CurrentUser
```
SOC License requirements:
At least Azure Active Premium Plan 2 level. (One AAD Premium Plan 2 license)
At least one license containing Microsoft Defender for Endpoint plan 2. (One DfE Plan 2 license or license containing DfE Plan 2)

Download or clone the repo, then run scripts in order 1-4. PDF files are for reference.

Due to a lack of programmatic support the steps in part 4 still need to be executed manually.

Part 5 (Degea Access) should only be run if Degea does not have regular admin access (GDAP).
