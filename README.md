# AutoNSX
Deploy NSX-v from parameter sheet

## Usage
### Install PowerCLI
```
Install-Module VMware.PowerCLI
```
### Install PowerNSX
https://github.com/vmware/powernsx
### Install Python and openpyxl
pass
### Convert Excel parameter sheet to JSON file
```
python AutoNSX\parameter_sheet_to_json.py
```
### Import Module
```
Import-Module AutoNSX\AutoNSX.psd1
```
### Connect to vCenter and NSX Manager
```
Connect-VIServer <vCenter FQDN or IP Address> -User <administrator@vsphere.local> -Password <password>
Connect-NsxServer <NSX Manager FQDN or IP Address> -Username admin -Password <password>
```
### Validate
```
Validate-NSX
```

Red messages are error to be fixed  
Blue messages are warning these are better to be fixed  
### Deploy
```
Deploy-NSX
```

or

```
Deploy-LS
Deploy-ESG
Deploy-DLR
```
## Not Implemented
* DLR CVM Password (It should be modified after deployment)
* DLR CVM Syslog Settings
* DLR CVM SSH Settings
* DLR CVM Logging Settings
* DLR OSPF
* ESG Logging Settings
* ESG FW, LB, VPN...
