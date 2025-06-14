# Set TLS to accept TLS, TLS 1.1 and TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12

#HelloID variables
$script:PortalBaseUrl = "https://CUSTOMER.helloid.com"
$apiKey = "API_KEY"
$apiSecret = "API_SECRET"
$delegatedFormName = "<DELEGATED FORM NAME>"
$useManualDelegatedFormCategories = $false #$true means use manual categories listed below. $false means receive current categories from DelegatedForm
$manualDelegatedFormCategories = @() #Only unique names are supported. Categories will be created if not exists
$defaultDelegatedFormAccessGroupNames = @() #Only unique names are supported. Groups must exist within HelloID!
$rootExportFolder = "C:\HelloID\Delegated Forms" #example: C:\HelloID\Delegated Forms


# Delegated Form export folders
$subfolder = $delegatedFormName -replace [regex]::escape('('), '['
$subfolder = $subfolder -replace [regex]::escape(')'), ']'
$subfolder = $subfolder -replace [regex]'[^[\]a-zA-Z0-9_ -]', ''
$subfolder = $subfolder.Trim("\")
$rootExportFolder = $rootExportFolder.Trim("\")
$allInOneFolder = "$rootExportFolder\$subfolder\All-in-one setup"
$manualResourceFolder = "$rootExportFolder\$subfolder\Manual resources"
$null = New-Item -ItemType Directory -Force -Path $allInOneFolder
$null = New-Item -ItemType Directory -Force -Path $manualResourceFolder


# Create authorization headers with HelloID API key
$pair = "$apiKey" + ":" + "$apiSecret"
$bytes = [System.Text.Encoding]::ASCII.GetBytes($pair)
$base64 = [System.Convert]::ToBase64String($bytes)
$key = "Basic $base64"
$script:headers = @{"authorization" = $Key }
# Define specific endpoint URI
$script:PortalBaseUrl = $script:PortalBaseUrl.trim("/") + "/"


function Update-DynamicFormSchema([System.Object[]]$formSchema, [string]$propertyName) {
    for ($i = 0; $i -lt $formSchema.Length; $i++) {
        $tmp = $($formSchema[$i]).psobject.Members | where-object membertype -like 'noteproperty'
    
        foreach ($item in $tmp) {
            if (($item.Name -eq $propertyName) -and ([string]::IsNullOrEmpty($item.Value) -eq $false)) {
                $oldValue = $item.Value
                $item.Value = "$" + $propertyName + "_" + $script:dataSourcesGuids.Count
                $script:dataSourcesGuids.add($item.Value, $oldValue)               
            }
            elseif (($item.Value -is [array]) -or ($item.Value -is [System.Management.Automation.PSCustomObject])) {
                Update-DynamicFormSchema $($item.Value) $propertyName
            }
        }
    }
}

function Get-HelloIDData([string]$endpointUri) {
    $take = 1000;   
    $skip = 0;
     
    $results = [System.Collections.Generic.List[object]]@();
    $paged = $true;
    while ($paged) {
        $uri = "$($script:PortalBaseUrl)$($endpointUri)?take=$($take)&skip=$($skip)";
        $response = (Invoke-RestMethod -Method GET -Uri $uri -Headers $script:headers -ContentType 'application/json' -TimeoutSec 60)
        if ([bool]($response.PSobject.Properties.name -eq "data")) { $response = $response.data }
        if (($response.count -lt $take) -or ($response.count -gt $take)) {
            $paged = $false;
        }
        else {
            $skip += $take;
        }
           
        if ($response -is [array]) {
            $results.AddRange($response);
        }
        else {
            $results.Add($response);
        }
    }
    return $results;
}


#Delegated Form
$delegatedForm = (Get-HelloIDData -endpointUri "/api/v1/delegatedforms/$delegatedFormName")
if ([string]::IsNullOrEmpty($delegatedForm.delegatedFormGUID)) {
    Write-Error "Failed to load Delegated Form called: $delegatedFormName";
    exit;
}

#Delegated Form categories
if (-not $useManualDelegatedFormCategories -eq $true) {
    $tmpCategories = @();
    $currentCategories = $delegatedForm.categoryGuids
    
    foreach ($item in $currentCategories) {
        $tmpCategory = (Get-HelloIDData -endpointUri "/api/v1/delegatedformcategories/$($item)")
        $tmpCategories += $tmpCategory.name.en
    }

    if ($tmpCategories.Count -gt 0) {
        $delegatedFormCategories = $tmpCategories
    }
    else {
        # use default delegated form categories
        $delegatedFormCategories = $manualDelegatedFormCategories 
    }
}
else {
    # use default delegated form categories
    $delegatedFormCategories = $manualDelegatedFormCategories
}

$psScripts = [System.Collections.Generic.List[object]]@(); #define array of used PowerShell scripts to determine use of HelloID global variables
$delegatedFormAutomationTaskGUID = $null # default value for (legacy) Delegated Form Automation task reference GUID

#DelegatedForm (Automation) Task
$taskList = (Get-HelloIDData -endpointUri "/api/v1/automationtasks")
$delegatedFormAutomationTaskGUID = ($taskList | Where-Object { $_.objectGUID -eq $delegatedForm.delegatedFormGUID }).automationTaskGuid
if (-not [string]::IsNullOrEmpty($delegatedFormAutomationTaskGUID)) {
    # using old automation task
    $delegatedFormAutomationTask = (Get-HelloIDData -endpointUri "/api/v1/automationtasks/$($delegatedFormAutomationTaskGUID)")

    # Add Delegated Form automation Task to array of Powershell scripts (to find use of global variables)
    $tmpScript = $($delegatedFormAutomationTask.variables | Where-Object { $_.name -eq "powershellscript" }).Value;
    $psScripts.Add($tmpScript)

    # Export Delegated Form automation task to Manual Resource Folder
    $tmpFileName = "$manualResourceFolder\[task]_$($delegatedFormAutomationTask.Name).ps1"
    set-content -LiteralPath $tmpFileName -Value $tmpScript -Force

    # Export Delegated Form automation task mapping to Manual Resource Folder
    $tmpMapping = $($delegatedFormAutomationTask.variables) | Select-Object Name, Value
    $tmpMapping = $tmpMapping | Where-Object { $_.name -ne "powershellscript" -and $_.name -ne "useTemplate" -and $_.name -ne "powerShellScriptGuid" }
    $tmpFileName = "$manualResourceFolder\[task]_$($delegatedFormAutomationTask.Name).mapping.json"
    set-content -LiteralPath $tmpFileName -Value (ConvertTo-Json -InputObject $tmpMapping -Depth 100) -Force
}
else {
    # integrated Delegated Form Task
    $delegatedFormAutomationTaskId = $delegatedForm.task.id
    $tmpScript = $($delegatedForm.task.script)
    $tmpScriptName = $($delegatedForm.task.name)
    $psScripts.Add($tmpScript)

    # Export Delegated Form task to Manual Resource Folder
    $tmpFileName = "$manualResourceFolder\[task]_$tmpScriptName.ps1"
    set-content -LiteralPath $tmpFileName -Value $tmpScript -Force

    # Export Delegated Form task config to Manual Resource Folder
    $taskConfig = [PSCustomObject]@{ 
        name       = $delegatedForm.task.name; 
        runInCloud = $delegatedForm.task.runInCloud;
    }

    $tmpFileName = "$manualResourceFolder\[task]_$tmpScriptName.config.json"
    set-content -LiteralPath $tmpFileName -Value (ConvertTo-Json -InputObject $taskConfig -Depth 100) -Force
}

#DynamicForm
$dynamicForm = (Get-HelloIDData -endpointUri "/api/v1/forms/$($delegatedForm.dynamicFormGUID)")

#Get all global variables
$allGlobalVariables = (Get-HelloIDData -endpointUri "/api/v1/automation/variables")

#Get all data source GUIDs used in Dynamic Form
$script:dataSourcesGuids = @{}
Update-DynamicFormSchema $($dynamicForm.formSchema) "dataSourceGuid"
set-content -LiteralPath "$manualResourceFolder\dynamicform.json" -Value (ConvertTo-Json -InputObject $dynamicForm.formSchema -Depth 100) -Force

#Data Sources
$dataSources = [System.Collections.Generic.List[object]]@();
foreach ($item in $script:dataSourcesGuids.GetEnumerator()) {
    try {
        $dataSource = (Get-HelloIDData -endpointUri "/api/v1/datasource/$($item.Value)")
        $dsTask = $null
        
        if ($dataSource.Type -eq 3 -and $dataSource.automationTaskGUID.Length -gt 0) {
            $dsTask = (Get-HelloIDData -endpointUri "/api/v1/automationtasks/$($dataSource.automationTaskGUID)")
        }

        $dataSources.Add([PSCustomObject]@{ 
                guid       = $item.Value; 
                guidRef    = $item.Key; 
                datasource = $dataSource; 
                task       = $dsTask; 
            })

        switch ($dataSource.type) {
            # Static data source
            2 {
                # Export Data source to Manual resource folder
                $tmpFileName = "$manualResourceFolder\[static-datasource]_$($dataSource.name)"
                set-content -LiteralPath "$tmpFileName.json" -Value (ConvertTo-Json -InputObject $datasource.value -Depth 100) -Force
                set-content -LiteralPath "$tmpFileName.model.json" -Value (ConvertTo-Json -InputObject $datasource.model -Depth 100) -Force
                break;
            }

            # Task data source
            3 {
                # Add Powershell script to array (to look for use of global variables)
                $tmpScript = $($dsTask.variables | Where-Object { $_.name -eq "powershellscript" }).Value
                $psScripts.Add($tmpScript)
                
                # Export Data source to Manual resource folder
                $tmpFileName = "$manualResourceFolder\[task-datasource]_$($dataSource.name)"
                set-content -LiteralPath "$tmpFileName.ps1" -Value $tmpScript -Force
                set-content -LiteralPath "$tmpFileName.model.json" -Value (ConvertTo-Json -InputObject $datasource.model -Depth 100) -Force
                set-content -LiteralPath "$tmpFileName.inputs.json" -Value (ConvertTo-Json -InputObject $datasource.input -Depth 100) -Force
                break; 
            }
            
            # Powershell data source
            4 {
                # Add Powershell script to array (to look for use of global variables)
                $tmpScript = $dataSource.script
                $psScripts.Add($tmpScript);

                # Export Data source to Manual resource folder
                $tmpFileName = "$manualResourceFolder\[powershell-datasource]_$($dataSource.name)"
                set-content -LiteralPath "$tmpFileName.ps1" -Value $tmpScript -Force
                set-content -LiteralPath "$tmpFileName.model.json" -Value (ConvertTo-Json -InputObject $datasource.model -Depth 100) -Force
                set-content -LiteralPath "$tmpFileName.inputs.json" -Value (ConvertTo-Json -InputObject $datasource.input -Depth 100) -Force
                $powershellDatasourceConfig = [PSCustomObject]@{ 
                    name       = $datasource.name; 
                    runInCloud = $datasource.runInCloud;
                }
                set-content -LiteralPath "$tmpFileName.config.json" -Value (ConvertTo-Json -InputObject $powershellDatasourceConfig -Depth 100) -Force
                break;
            }
        }
    }
    catch {
        Write-Error "Failed to get Datasource";
    }
}


# get all Global variables used in PS scripts (task data sources, powershell data source and delegated form task)
$globalVariables = [System.Collections.Generic.List[object]]@();
foreach ($tmpScript in $psScripts) {
    if (-not [string]::IsNullOrEmpty($tmpScript)) {
        $lowerCase = $tmpScript.ToLower()
        foreach ($var in $allGlobalVariables) {
            $result = $lowerCase.IndexOf($var.Name.ToLower())
            
            if (($result -ne -1) -and (($globalVariables.name -contains $var.name) -eq $false)) {
                $tmpValue = if ($var.secret -eq $true) { ""; } else { $var.value; }
                $globalVariables.Add([PSCustomObject]@{name = $var.Name; value = $tmpValue; secret = $var.secret })
            }
        }
    }
}


# default all-in-one script output
$PowershellScript = @'
# Set TLS to accept TLS, TLS 1.1 and TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12

#HelloID variables
#Note: when running this script inside HelloID; portalUrl and API credentials are provided automatically (generate and save API credentials first in your admin panel!)
$portalUrl = "https://CUSTOMER.helloid.com"
$apiKey = "API_KEY"
$apiSecret = "API_SECRET"
'@
$PowershellScript += "`n`$delegatedFormAccessGroupNames = @(" + ('"{0}"' -f ($defaultDelegatedFormAccessGroupNames -join '","')) + ") #Only unique names are supported. Groups must exist!";
$PowershellScript += "`n`$delegatedFormCategories = @(" + ('"{0}"' -f ($delegatedFormCategories -join '","')) + ") #Only unique names are supported. Categories will be created if not exists";
$PowershellScript += "`n`$script:debugLogging = `$false #Default value: `$false. If `$true, the HelloID resource GUIDs will be shown in the logging"
$PowershellScript += "`n`$script:duplicateForm = `$false #Default value: `$false. If `$true, the HelloID resource names will be changed to import a duplicate Form"
$PowershellScript += "`n`$script:duplicateFormSuffix = ""_tmp"" #the suffix will be added to all HelloID resource names to generate a duplicate form with different resource names"
$PowershellScript += "`n`n";

$PowershellScript += "#The following HelloID Global variables are used by this form. No existing HelloID global variables will be overriden only new ones are created.`n"
$PowershellScript += "#NOTE: You can also update the HelloID Global variable values afterwards in the HelloID Admin Portal: https://<CUSTOMER>.helloid.com/admin/variablelibrary`n"
$PowershellScript += "`$globalHelloIDVariables = [System.Collections.Generic.List[object]]@();`n`n"

$tmpCounter = 1
foreach ($item in $globalVariables) {
    $PowershellScript += "#Global variable #$tmpCounter >> $($item.Name)`n";
    $PowershellScript += "`$tmpName = @'`n" + $($item.Name) + "`n'@ `n";
    if ([string]::IsNullOrEmpty($item.value)) {
        $PowershellScript += "`$tmpValue = """" `n";
    }
    else {
        $PowershellScript += "`$tmpValue = @'`n" + ($item.value) + "`n'@ `n";
    }    
    $PowershellScript += "`$globalHelloIDVariables.Add([PSCustomObject]@{name = `$tmpName; value = `$tmpValue; secret = ""$($item.secret)""});`n`n"

    $tmpCounter++
}
$PowershellScript += "`n";
$PowershellScript += @'
#make sure write-information logging is visual
$InformationPreference = "continue"

# Check for prefilled API Authorization header
if (-not [string]::IsNullOrEmpty($portalApiBasic)) {
    $script:headers = @{"authorization" = $portalApiBasic}
    Write-Information "Using prefilled API credentials"
} else {
    # Create authorization headers with HelloID API key
    $pair = "$apiKey" + ":" + "$apiSecret"
    $bytes = [System.Text.Encoding]::ASCII.GetBytes($pair)
    $base64 = [System.Convert]::ToBase64String($bytes)
    $key = "Basic $base64"
    $script:headers = @{"authorization" = $Key}
    Write-Information "Using manual API credentials"
}

# Check for prefilled PortalBaseURL
if (-not [string]::IsNullOrEmpty($portalBaseUrl)) {
    $script:PortalBaseUrl = $portalBaseUrl
    Write-Information "Using prefilled PortalURL: $script:PortalBaseUrl"
} else {
    $script:PortalBaseUrl = $portalUrl
    Write-Information "Using manual PortalURL: $script:PortalBaseUrl"
}

# Define specific endpoint URI
$script:PortalBaseUrl = $script:PortalBaseUrl.trim("/") + "/"  

# Make sure to reveive an empty array using PowerShell Core
function ConvertFrom-Json-WithEmptyArray([string]$jsonString) {
    # Running in PowerShell Core?
    if($IsCoreCLR -eq $true){
        $r = [Object[]]($jsonString | ConvertFrom-Json -NoEnumerate)
        return ,$r  # Force return value to be an array using a comma
    } else {
        $r = [Object[]]($jsonString | ConvertFrom-Json)
        return ,$r  # Force return value to be an array using a comma
    }
}

function Invoke-HelloIDGlobalVariable {
    param(
        [parameter(Mandatory)][String]$Name,
        [parameter(Mandatory)][String][AllowEmptyString()]$Value,
        [parameter(Mandatory)][String]$Secret
    )

    $Name = $Name + $(if ($script:duplicateForm -eq $true) { $script:duplicateFormSuffix })

    try {
        $uri = ($script:PortalBaseUrl + "api/v1/automation/variables/named/$Name")
        $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false
    
        if ([string]::IsNullOrEmpty($response.automationVariableGuid)) {
            #Create Variable
            $body = @{
                name     = $Name;
                value    = $Value;
                secret   = $Secret;
                ItemType = 0;
            }    
            $body = ConvertTo-Json -InputObject $body -Depth 100
    
            $uri = ($script:PortalBaseUrl + "api/v1/automation/variable")
            $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false -Body $body
            $variableGuid = $response.automationVariableGuid

            Write-Information "Variable '$Name' created$(if ($script:debugLogging -eq $true) { ": " + $variableGuid })"
        } else {
            $variableGuid = $response.automationVariableGuid
            Write-Warning "Variable '$Name' already exists$(if ($script:debugLogging -eq $true) { ": " + $variableGuid })"
        }
    } catch {
        Write-Error "Variable '$Name', message: $_"
    }
}

function Invoke-HelloIDAutomationTask {
    param(
        [parameter(Mandatory)][String]$TaskName,
        [parameter(Mandatory)][String]$UseTemplate,
        [parameter(Mandatory)][String]$AutomationContainer,
        [parameter(Mandatory)][String][AllowEmptyString()]$Variables,
        [parameter(Mandatory)][String]$PowershellScript,
        [parameter()][String][AllowEmptyString()]$ObjectGuid,
        [parameter()][String][AllowEmptyString()]$ForceCreateTask,
        [parameter(Mandatory)][Ref]$returnObject
    )
    
    $TaskName = $TaskName + $(if ($script:duplicateForm -eq $true) { $script:duplicateFormSuffix })

    try {
        $uri = ($script:PortalBaseUrl +"api/v1/automationtasks?search=$TaskName&container=$AutomationContainer")
        $responseRaw = (Invoke-RestMethod -Method Get -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false) 
        $response = $responseRaw | Where-Object -filter {$_.name -eq $TaskName}
    
        if([string]::IsNullOrEmpty($response.automationTaskGuid) -or $ForceCreateTask -eq $true) {
            #Create Task

            $body = @{
                name                = $TaskName;
                useTemplate         = $UseTemplate;
                powerShellScript    = $PowershellScript;
                automationContainer = $AutomationContainer;
                objectGuid          = $ObjectGuid;
                variables           = (ConvertFrom-Json-WithEmptyArray($Variables));
            }
            $body = ConvertTo-Json -InputObject $body -Depth 100
    
            $uri = ($script:PortalBaseUrl +"api/v1/automationtasks/powershell")
            $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false -Body $body
            $taskGuid = $response.automationTaskGuid

            Write-Information "Powershell task '$TaskName' created$(if ($script:debugLogging -eq $true) { ": " + $taskGuid })"
        } else {
            #Get TaskGUID
            $taskGuid = $response.automationTaskGuid
            Write-Warning "Powershell task '$TaskName' already exists$(if ($script:debugLogging -eq $true) { ": " + $taskGuid })"
        }
    } catch {
        Write-Error "Powershell task '$TaskName', message: $_"
    }

    $returnObject.Value = $taskGuid
}

function Invoke-HelloIDDatasource {
    param(
        [parameter(Mandatory)][String]$DatasourceName,
        [parameter(Mandatory)][String]$DatasourceType,
        [parameter(Mandatory)][String][AllowEmptyString()]$DatasourceModel,
        [parameter()][String][AllowEmptyString()]$DatasourceStaticValue,
        [parameter()][String][AllowEmptyString()]$DatasourcePsScript,        
        [parameter()][String][AllowEmptyString()]$DatasourceInput,
        [parameter()][String][AllowEmptyString()]$AutomationTaskGuid,
        [parameter()][String][AllowEmptyString()]$DatasourceRunInCloud,
        [parameter(Mandatory)][Ref]$returnObject
    )

    $DatasourceName = $DatasourceName + $(if ($script:duplicateForm -eq $true) { $script:duplicateFormSuffix })

    $datasourceTypeName = switch($DatasourceType) { 
        "1" { "Native data source"; break} 
        "2" { "Static data source"; break} 
        "3" { "Task data source"; break} 
        "4" { "Powershell data source"; break}
    }
    
    try {
        $uri = ($script:PortalBaseUrl +"api/v1/datasource/named/$DatasourceName")
        $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false
      
        if([string]::IsNullOrEmpty($response.dataSourceGUID)) {
            #Create DataSource
            $body = @{
                name               = $DatasourceName;
                type               = $DatasourceType;
                model              = (ConvertFrom-Json-WithEmptyArray($DatasourceModel));
                automationTaskGUID = $AutomationTaskGuid;
                value              = (ConvertFrom-Json-WithEmptyArray($DatasourceStaticValue));
                script             = $DatasourcePsScript;
                input              = (ConvertFrom-Json-WithEmptyArray($DatasourceInput));
                runInCloud         = $DatasourceRunInCloud;
            }
            $body = ConvertTo-Json -InputObject $body -Depth 100
      
            $uri = ($script:PortalBaseUrl +"api/v1/datasource")
            $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false -Body $body
              
            $datasourceGuid = $response.dataSourceGUID
            Write-Information "$datasourceTypeName '$DatasourceName' created$(if ($script:debugLogging -eq $true) { ": " + $datasourceGuid })"
        } else {
            #Get DatasourceGUID
            $datasourceGuid = $response.dataSourceGUID
            Write-Warning "$datasourceTypeName '$DatasourceName' already exists$(if ($script:debugLogging -eq $true) { ": " + $datasourceGuid })"
        }
    } catch {
      Write-Error "$datasourceTypeName '$DatasourceName', message: $_"
    }

    $returnObject.Value = $datasourceGuid
}

function Invoke-HelloIDDynamicForm {
    param(
        [parameter(Mandatory)][String]$FormName,
        [parameter(Mandatory)][String]$FormSchema,
        [parameter(Mandatory)][Ref]$returnObject
    )
    
    $FormName = $FormName + $(if ($script:duplicateForm -eq $true) { $script:duplicateFormSuffix })

    try {
        try {
            $uri = ($script:PortalBaseUrl +"api/v1/forms/$FormName")
            $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false
        } catch {
            $response = $null
        }
    
        if(([string]::IsNullOrEmpty($response.dynamicFormGUID)) -or ($response.isUpdated -eq $true)) {
            #Create Dynamic form
            $body = @{
                Name       = $FormName;
                FormSchema = (ConvertFrom-Json-WithEmptyArray($FormSchema));
            }
            $body = ConvertTo-Json -InputObject $body -Depth 100
    
            $uri = ($script:PortalBaseUrl +"api/v1/forms")
            $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false -Body $body
    
            $formGuid = $response.dynamicFormGUID
            Write-Information "Dynamic form '$formName' created$(if ($script:debugLogging -eq $true) { ": " + $formGuid })"
        } else {
            $formGuid = $response.dynamicFormGUID
            Write-Warning "Dynamic form '$FormName' already exists$(if ($script:debugLogging -eq $true) { ": " + $formGuid })"
        }
    } catch {
        Write-Error "Dynamic form '$FormName', message: $_"
    }

    $returnObject.Value = $formGuid
}


function Invoke-HelloIDDelegatedForm {
    param(
        [parameter(Mandatory)][String]$DelegatedFormName,
        [parameter(Mandatory)][String]$DynamicFormGuid,
        [parameter()][Array][AllowEmptyString()]$AccessGroups,
        [parameter()][String][AllowEmptyString()]$Categories,
        [parameter(Mandatory)][String]$UseFaIcon,
        [parameter()][String][AllowEmptyString()]$FaIcon,
        [parameter()][String][AllowEmptyString()]$task,
        [parameter(Mandatory)][Ref]$returnObject
    )
    $delegatedFormCreated = $false
    $DelegatedFormName = $DelegatedFormName + $(if ($script:duplicateForm -eq $true) { $script:duplicateFormSuffix })

    try {
        try {
            $uri = ($script:PortalBaseUrl +"api/v1/delegatedforms/$DelegatedFormName")
            $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false
        } catch {
            $response = $null
        }
    
        if([string]::IsNullOrEmpty($response.delegatedFormGUID)) {
            #Create DelegatedForm
            $body = @{
                name            = $DelegatedFormName;
                dynamicFormGUID = $DynamicFormGuid;
                isEnabled       = "True";
                useFaIcon       = $UseFaIcon;
                faIcon          = $FaIcon;
                task            = ConvertFrom-Json -inputObject $task;
            }
            if(-not[String]::IsNullOrEmpty($AccessGroups)) { 
                $body += @{
                    accessGroups    = (ConvertFrom-Json-WithEmptyArray($AccessGroups));
                }
            }
            $body = ConvertTo-Json -InputObject $body -Depth 100
    
            $uri = ($script:PortalBaseUrl +"api/v1/delegatedforms")
            $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false -Body $body
    
            $delegatedFormGuid = $response.delegatedFormGUID
            Write-Information "Delegated form '$DelegatedFormName' created$(if ($script:debugLogging -eq $true) { ": " + $delegatedFormGuid })"
            $delegatedFormCreated = $true

            $bodyCategories = $Categories
            $uri = ($script:PortalBaseUrl +"api/v1/delegatedforms/$delegatedFormGuid/categories")
            $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false -Body $bodyCategories
            Write-Information "Delegated form '$DelegatedFormName' updated with categories"
        } else {
            #Get delegatedFormGUID
            $delegatedFormGuid = $response.delegatedFormGUID
            Write-Warning "Delegated form '$DelegatedFormName' already exists$(if ($script:debugLogging -eq $true) { ": " + $delegatedFormGuid })"
        }
    } catch {
        Write-Error "Delegated form '$DelegatedFormName', message: $_"
    }

    $returnObject.value.guid = $delegatedFormGuid
    $returnObject.value.created = $delegatedFormCreated
}

'@

#Build All-in-one PS script
$PowershellScript += "`n`n<# Begin: HelloID Global Variables #>`n"
$PowershellScript += "foreach (`$item in `$globalHelloIDVariables) {`n"
$PowershellScript += "`tInvoke-HelloIDGlobalVariable -Name `$item.name -Value `$item.value -Secret `$item.secret `n"
$PowershellScript += "}`n"
$PowershellScript += "<# End: HelloID Global Variables #>`n"
$PowershellScript += "`n`n" 
$PowershellScript += "<# Begin: HelloID Data sources #>"
foreach ($item in $dataSources) {
    $PowershellScript += "`n<# Begin: DataSource ""$($item.Datasource.Name)"" #>`n"

    switch ($item.datasource.type) {
        # Native / buildin data source (only need to get GUID value)
        1 {
            # Output method call Data source with parameters
            $PowershellScript += ($item.guidRef) + " = [PSCustomObject]@{} `n"
            $PowershellScript += ($item.guidRef) + "_Name = @'`n" + $($item.datasource.Name) + "`n'@ `n";
            $PowershellScript += "Invoke-HelloIDDatasource -DatasourceName " + ($item.guidRef) + "_Name -DatasourceType ""$($item.datasource.type)"" -DatasourceModel `$null -returnObject ([Ref]" + ($item.guidRef) + ") `n"

            break;
        }
        
        # Static data source
        2 {
            # Output data source JSON data schema and model definition
            $PowershellScript += "`$tmpStaticValue = @'`n" + (ConvertTo-Json -InputObject $item.datasource.value -Depth 100 -Compress) + "`n'@ `n";
            $PowershellScript += "`$tmpModel = @'`n" + (ConvertTo-Json -InputObject $item.datasource.model -Depth 100 -Compress) + "`n'@ `n";

            # Output method call Data source with parameters
            $PowershellScript += ($item.guidRef) + " = [PSCustomObject]@{} `n"																																	  
            $PowershellScript += ($item.guidRef) + "_Name = @'`n" + $($item.datasource.Name) + "`n'@ `n";
            $PowershellScript += "Invoke-HelloIDDatasource -DatasourceName " + ($item.guidRef) + "_Name -DatasourceType ""$($item.datasource.type)"" -DatasourceStaticValue `$tmpStaticValue -DatasourceModel `$tmpModel -returnObject ([Ref]" + ($item.guidRef) + ") `n"

            break;
        }
        
        # Task data source
        3 {
            # Output PS script in local variable
            $PowershellScript += "`$tmpScript = @'`n" + (($item.task.variables | Where-Object { $_.name -eq "powerShellScript" }).Value) + "`n'@; `n";
            $PowershellScript += "`n"            
            
            # Generate task variable mapping (required properties only and fixed typeConstraint value)
            $tmpVariables = $item.task.variables | Where-Object { $_.name -ne "powerShellScript" -and $_.name -ne "powerShellScriptGuid" -and $_.name -ne "useTemplate" }
            $tmpVariables = $tmpVariables | Select-Object Name, Value, Secret, @{name = "typeConstraint"; e = { "string" } }
            
            # Output task variable mapping in local variable as JSON string
            $PowershellScript += "`$tmpVariables = @'`n" + (ConvertTo-Json -InputObject $tmpVariables -Depth 100 -Compress) + "`n'@ `n";
            $PowershellScript += "`n"

            # Output method call Automation task with parameters
            $PowershellScript += "`$taskGuid = [PSCustomObject]@{} `n"
            $PowershellScript += ($item.guidRef) + "_Name = @'`n" + $($item.Task.Name) + "`n'@ `n";
            $PowershellScript += "Invoke-HelloIDAutomationTask -TaskName " + ($item.guidRef) + "_Name -UseTemplate """ + ($item.task.variables | Where-Object { $_.name -eq "useTemplate" }).Value + """ -AutomationContainer ""$($item.Task.automationContainer)"" -Variables `$tmpVariables -PowershellScript `$tmpScript -returnObject ([Ref]`$taskGuid) `n"
            $PowershellScript += "`n"

            # Output data source input variables and model definition
            $PowershellScript += "`$tmpInput = @'`n" + (ConvertTo-Json -InputObject $item.datasource.input -Depth 100 -Compress) + "`n'@ `n";
            $PowershellScript += "`$tmpModel = @'`n" + (ConvertTo-Json -InputObject $item.datasource.model -Depth 100 -Compress) + "`n'@ `n";

            # Output method call Data source with parameters
            $PowershellScript += ($item.guidRef) + " = [PSCustomObject]@{} `n"																																  
            $PowershellScript += ($item.guidRef) + "_Name = @'`n" + $($item.datasource.Name) + "`n'@ `n";
            $PowershellScript += "Invoke-HelloIDDatasource -DatasourceName " + ($item.guidRef) + "_Name -DatasourceType ""$($item.datasource.type)"" -DatasourceInput `$tmpInput -DatasourceModel `$tmpModel -AutomationTaskGuid `$taskGuid -returnObject ([Ref]" + ($item.guidRef) + ") `n"

            break;
        }

        # Powershell data source
        4 {
            # Output data source JSON data schema, model definition and input variables
            $PowershellScript += "`$tmpPsScript = @'`n" + $item.datasource.script + "`n'@ `n";
            $PowershellScript += "`$tmpModel = @'`n" + (ConvertTo-Json -InputObject $item.datasource.model -Depth 100 -Compress) + "`n'@ `n";
            $PowershellScript += "`$tmpInput = @'`n" + (ConvertTo-Json -InputObject $item.datasource.input -Depth 100 -Compress) + "`n'@ `n";

            # Output method call Data source with parameters
            $PowershellScript += ($item.guidRef) + " = [PSCustomObject]@{} `n"
            $PowershellScript += ($item.guidRef) + "_Name = @'`n" + $($item.datasource.Name) + "`n'@ `n";
            $PowershellScript += "Invoke-HelloIDDatasource -DatasourceName " + ($item.guidRef) + "_Name -DatasourceType ""$($item.datasource.type)"" -DatasourceInput `$tmpInput -DatasourcePsScript `$tmpPsScript -DatasourceModel `$tmpModel -DataSourceRunInCloud ""$($item.datasource.runInCloud)"" -returnObject ([Ref]" + ($item.guidRef) + ") `n"

            break;
        }
    }
    $PowershellScript += "<# End: DataSource ""$($item.Datasource.Name)"" #>`n"
}
$PowershellScript += "<# End: HelloID Data sources #>`n`n"
$PowershellScript += "<# Begin: Dynamic Form ""$($dynamicForm.name)"" #>`n"
$PowershellScript += "`$tmpSchema = @""`n" + (ConvertTo-Json -InputObject $dynamicForm.formSchema -Depth 100 -Compress) + "`n""@ `n";
$PowershellScript += "`n"
$PowershellScript += "`$dynamicFormGuid = [PSCustomObject]@{} `n"
$PowershellScript += "`$dynamicFormName = @'`n" + $($dynamicForm.name) + "`n'@ `n";
$PowershellScript += "Invoke-HelloIDDynamicForm -FormName `$dynamicFormName -FormSchema `$tmpSchema  -returnObject ([Ref]`$dynamicFormGuid) `n"
$PowershellScript += "<# END: Dynamic Form #>`n`n"

$PowershellScript += "<# Begin: Delegated Form Access Groups and Categories #>`n"
$PowershellScript += @'
$delegatedFormAccessGroupGuids = @()
if(-not[String]::IsNullOrEmpty($delegatedFormAccessGroupNames)){
    foreach($group in $delegatedFormAccessGroupNames) {
        try {
            $uri = ($script:PortalBaseUrl +"api/v1/groups/$group")
            $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false
            $delegatedFormAccessGroupGuid = $response.groupGuid
            $delegatedFormAccessGroupGuids += $delegatedFormAccessGroupGuid
            
            Write-Information "HelloID (access)group '$group' successfully found$(if ($script:debugLogging -eq $true) { ": " + $delegatedFormAccessGroupGuid })"
        } catch {
            Write-Error "HelloID (access)group '$group', message: $_"
        }
    }
    if($null -ne $delegatedFormAccessGroupGuids){
        $delegatedFormAccessGroupGuids = ($delegatedFormAccessGroupGuids | Select-Object -Unique | ConvertTo-Json -Depth 100 -Compress)
    }
}

$delegatedFormCategoryGuids = @()
foreach($category in $delegatedFormCategories) {
    try {
        $uri = ($script:PortalBaseUrl +"api/v1/delegatedformcategories/$category")
        $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false
        $response = $response | Where-Object {$_.name.en -eq $category}
        
        $tmpGuid = $response.delegatedFormCategoryGuid
        $delegatedFormCategoryGuids += $tmpGuid
        
        Write-Information "HelloID Delegated Form category '$category' successfully found$(if ($script:debugLogging -eq $true) { ": " + $tmpGuid })"
    } catch {
        Write-Warning "HelloID Delegated Form category '$category' not found"
        $body = @{
            name = @{"en" = $category};
        }
        $body = ConvertTo-Json -InputObject $body -Depth 100

        $uri = ($script:PortalBaseUrl +"api/v1/delegatedformcategories")
        $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false -Body $body
        $tmpGuid = $response.delegatedFormCategoryGuid
        $delegatedFormCategoryGuids += $tmpGuid

        Write-Information "HelloID Delegated Form category '$category' successfully created$(if ($script:debugLogging -eq $true) { ": " + $tmpGuid })"
    }
}
$delegatedFormCategoryGuids = (ConvertTo-Json -InputObject $delegatedFormCategoryGuids -Depth 100 -Compress)
'@
$PowershellScript += "`n<# End: Delegated Form Access Groups and Categories #>`n"

$PowershellScript += "`n<# Begin: Delegated Form #>`n"
$PowershellScript += "`$delegatedFormRef = [PSCustomObject]@{guid = `$null; created = `$null} `n"
$PowershellScript += "`$delegatedFormName = @'`n" + ($delegatedForm.name) + "`n'@`n"

if (-not [string]::IsNullOrEmpty($delegatedFormAutomationTaskId)) {
    $tmpTaskObject = [PSCustomObject]@{
        name       = $delegatedForm.task.name;
        script     = $delegatedForm.task.script;
        runInCloud = $delegatedForm.task.runInCloud;
    }

    # Output PS script in local variable
    $PowershellScript += "`$tmpTask = @'`n" + (ConvertTo-Json -InputObject $tmpTaskObject -Depth 100 -Compress) + "`n'@ `n";
}
else {
    $PowershellScript += "`$tmpTask = `$null `n";
}
$PowershellScript += "`n"  

$PowershellScript += "Invoke-HelloIDDelegatedForm -DelegatedFormName `$delegatedFormName -DynamicFormGuid `$dynamicFormGuid -AccessGroups `$delegatedFormAccessGroupGuids -Categories `$delegatedFormCategoryGuids -UseFaIcon ""$($delegatedForm.useFaIcon)"" -FaIcon ""$($delegatedForm.faIcon)"" -task `$tmpTask -returnObject ([Ref]`$delegatedFormRef) `n"
$PowershellScript += "<# End: Delegated Form #>`n"


if (-not [string]::IsNullOrEmpty($delegatedFormAutomationTaskGUID)) {
    $PowershellScript += "`n<# Begin: Delegated Form Automation Task #>`n"
    $PowershellScript += "if(`$delegatedFormRef.created -eq `$true) { `n"     

    # Output PS script in local variable
    $PowershellScript += "`t`$tmpScript = @'`n" + ($($delegatedFormAutomationTask.variables | Where-Object { $_.name -eq "powershellscript" }).Value) + "`n'@; `n";
    $PowershellScript += "`n"            

    # Generate DelegatedForm automation task variable mapping (required properties only and fixed typeConstraint value)
    $tmpVariables = $delegatedFormAutomationTask.variables | Where-Object { $_.name -ne "powerShellScript" -and $_.name -ne "powerShellScriptGuid" -and $_.name -ne "useTemplate" }
    $tmpVariables = $tmpVariables | Select-Object Name, Value, Secret, @{name = "typeConstraint"; e = { "string" } }

    # Output task variable mapping in local variable as JSON string
    $PowershellScript += "`t`$tmpVariables = @'`n" + (ConvertTo-Json -InputObject $tmpVariables -Depth 100 -Compress) + "`n'@ `n";
    $PowershellScript += "`n"

    # Output method call DelegatedForm Automation task with parameters
    $PowershellScript += "`t`$delegatedFormAutomationTaskGUID = [PSCustomObject]@{} `n"
    $PowershellScript += "`t`$delegatedFormAutomationTaskName = @'`n" + ($delegatedFormAutomationTask.Name) + "`n'@`n"
    $PowershellScript += "`tInvoke-HelloIDAutomationTask -TaskName `$delegatedFormAutomationTaskName -UseTemplate """ + ($delegatedFormAutomationTask.variables | Where-Object { $_.name -eq "useTemplate" }).Value + """ -AutomationContainer ""$($delegatedFormAutomationTask.automationContainer)"" -Variables `$tmpVariables -PowershellScript `$tmpScript -ObjectGuid `$delegatedFormRef.guid -ForceCreateTask `$true -returnObject ([Ref]`$delegatedFormAutomationTaskGUID) `n"
    $PowershellScript += "} else {`n"
    $PowershellScript += "`tWrite-Warning ""Delegated form '`$delegatedFormName' already exists. Nothing to do with the Delegated Form automation task..."" `n"
    $PowershellScript += "}`n"
    $PowershellScript += "<# End: Delegated Form Automation Task #>"
}

set-content -LiteralPath "$allInOneFolder\createform.ps1" -Value $PowershellScript -Force
