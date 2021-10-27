# HelloID-Conn-SA-Source-HelloID-DelegatedForms
<!-- Description -->
## Description
This HelloID Service Automation Powershell script generates a complete set of files including an _"All-in-one Powershell script"_ for the provided delegated form.

## Versioning
| Version | Description | Date |
| - | - | - |
| 1.0.1   | Added version number | 2021/10/27  |
| 1.0.0   | Initial release | 2021/01/08  |
 
<!-- TABLE OF CONTENTS -->
## Table of Contents
* [Script outcome](#script-outcome)
* [PowerShell setup script](#powershell-setup-script)
  * [Update connection and configuration details](#update-connection-and-configuration-details)
* [What is included?](#what-is-included?)
* [Known limitations](#known-limitations)


## Script outcome
After configuring and running the "generate-all-in-one.ps1" script the following outcome will be automaticly generated.
<table>
  <tr><td><strong>File</strong></td><td><strong>Description</strong></td></tr>
  <tr><td>All-in-one setup\createform.ps1</td><td>An All-in-one PS script to generate (import) the complete Delegated form and required resources into you HelloID portal using API calls</td></tr>
  <tr><td>Manual resources\[task]_&lt;task-name&gt;.ps1</td><td>Powershell task connected to Delegated From</td></tr>
  <tr><td>Manual resources\[task]_&lt;task-name&gt;.mapping.json</td><td>Variable mapping of Powershell task connected to Delegated From</td></tr>
  <tr><td>Manual resources\dynamicform.jsom</td><td>JSON form structure of the Dynamic form</td></tr>
  <tr><td>Manual resources\[datasource]_&lt;datasource-name&gt;.json</td><td>JSON data structure used for Static data sources (only)</td></tr>
  <tr><td>Manual resources\[datasource]_&lt;datasource-name&gt;.ps1</td><td>Powershell script from Task Data source or Powershell data source</td></tr>
  <tr><td>Manual resources\[datasource]_&lt;datasource-name&gt;.model.json</td><td>Data source model definition</td></tr>
  <tr><td>Manual resources\[datasource]_&lt;datasource-name&gt;.inputs.json</td><td>Data source input configuration</td></tr>
</table>


## PowerShell setup script
The PowerShell script "generate-all-in-one.ps1" contains a complete PowerShell script using the HelloID API to create an all-in-one script and exporting manual resource files (see table above). Please follow the steps below in order to setup and run the "generate-all-in-one.ps1" PowerShell script in your own environment.
1. Download the "generate-all-in-one.ps1" file
2. Open it in your favorite PowerShell console/editor
3. Create a HelloID [API key and secret](https://docs.helloid.com/hc/en-us/articles/360002008873-API-Keys-Overview)
4. Update the [connection and configuration details](#update-connection-and-configuration-details) in the script's header
5. Run the script on a machine with PowerShell support and an internet connection

### Update connection and configuration details
<table>
  <tr><td><strong>Variable name</strong></td><td><strong>Example value</strong></td><td><strong>Description</strong></td></tr>
  <tr><td>$script:PortalBaseUrl</td><td>https://customer01.helloid.com</td><td>Your HelloID portal's URL</td></tr>
  <tr><td>$apiKey</td><td>*****</td><td>API Key value of your own environment</td></tr>
  <tr><td>$apiSecret</td><td>*****</td><td>API secret value of your own environment</td></tr>
  <tr><td>$delegatedFormName</td><td>AD Account - Create</td><td>Name of the Delegated Form you want to export</td></tr>
  <tr><td>$useManualDelegatedFormCategories</td><td>$true</td><td>$true means use manual categories listed below. $false means receive current categories from DelegatedForm</td></tr>
  <tr><td>$manualDelegatedFormCategories</td><td>@("Active Directory", "User Management")</td><td>Array of Delegated Form categories to be connected to the newly generated Delegated Form. Only unique names are supported. Categories will be created if they don't exists</td></tr>
  <tr><td>$defaultDelegatedFormAccessGroupNames</td><td>@("Users", "HID_administrators")</td><td>Array of HelloID Group names to be connected as AccessGroups. Only unique names are supported. Group names have to exist.</td></tr>
  <tr><td>$debug</td><td>$false</td><td>Boolean value indicating debug mode. In Debug mode the HelloID resource names will get an suffix in order to "duplicate" the Delegated Form in the same environment (for testing)</td></tr>
  <tr><td>$debugSuffix</td><td>_tmp</td><td>Value of the name suffix that will be used for all HelloID resources in debug modus.</td></tr>
  <tr><td>$rootExportFolder</td><td>C:\HelloID\Delegated Forms</td><td>Local folder path for exporting files</td></tr>

</table>

 
## What is included?
The generated all-in-one PowerShell script includes the following resources
1. All used Global variables
   * Based on variable name in used PowerShell scripts (Delegated Form task, Task data source and Powershell data source)
   * The current value is used when the global variable is not configured as secret
2. All used data sources with the Dynamic Form
   * Internal buildin HelloID data sources (for example HelloID Groups)
   * Static data sources (including JSON data structure and model definition)
   * Task data sources (including Powershell Task, model definition and data source inputs)
   * Powershell data sources (including Powershell script, model definition and data source inputs)
3. All used Powershell scripts
   * Delegated Form task (including variable mapping)
   * Task data source Powershell Task
   * Powershell data source script
4. Dynamic form JSON data structure
   * The data source references in the JSON data structure are dynamicly updated to your own environment
5. Configured Access Groups are assigned to the Delegated form
6. Configured Categories are assigned to the Delegated form
   * Manual configurated categories can be used or current categories connected to the referred Delegated Form
   * Categories are created if they don't exist in the target HelloID environment


## Known limitations
 * Only global variables of type "string" are supported
 * Only script variable mappings of type "string" are supported
 * Powershel script template (use template instead of inline Powershell script) is not supported
 * Delegate Form Access Groups are not exported but are hardcoded in the generated script (you need to update them manually)

## Getting help
_If you need help, feel free to ask questions on our [forum](https://forum.helloid.com/forum/helloid-connectors/service-automation/463-helloid-sa-export-helloid-delegated-form)_

# HelloID Docs
The official HelloID documentation can be found at: https://docs.helloid.com/
