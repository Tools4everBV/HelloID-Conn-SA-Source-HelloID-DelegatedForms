#################################################
# HelloID-Conn-SA-Source-HelloID-DelegatedForms
# Exporting delegated form(s) to manual resource files
# This HelloID Service Automation Powershell script generates a complete set of files including an "All-in-one Powershell script" for the provided delegated form
#################################################

# Set TLS to accept TLS, TLS 1.1 and TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12

#HelloID variables
$script:PortalBaseUrl = "https://CUSTOMER.helloid.com"
$apiKey = "API_KEY"
$apiSecret = "API_SECRET"
$selfserviceProductName = "<DELEGATED FORM NAME>" #Only unique names are supported. Note that, in large environments this won't improve the performance 
$useManualSelfserviceProductCategories = $false #$true means use manual categories listed below. $false means receive current categories from SelfserviceProduct
$manualSelfserviceProductCategories = @() #Only unique names are supported. Categories will be created if not exists
$defaultSelfserviceProductManagedByGroupName = "" #Only single value supported. Group must exist within HelloID!
$rootExportFolder = "C:\HelloID\Delegated Forms" #example: C:\HelloID\Selfservice Products

# Selfservice Product export folders
$subfolder = $selfserviceProductName -replace [regex]::escape('('), '['
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
        if ($response.count -lt $take) {
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


function Get-ProductActions([string]$stateAction) {

    #SelfserviceProduct state actions 
    $psScripts = [System.Collections.Generic.List[object]]@();
    $actionList = $SelfserviceProduct.$stateAction
    foreach ($action in $actionList) {
        # Add Selfservice Product Task to array of Powershell scripts (to find use of global variables)
        $tmpScript = $($action.script);
        if ($null -ne $tmpScript) {
            $psScripts.Add($tmpScript)

            # Export Selfservice Product task to Manual Resource Folder
            $tmpFileName = "$manualResourceFolder\" + "$stateAction" + "_[action]_$($action.Name).ps1"
            set-content -LiteralPath $tmpFileName -Value $tmpScript -Force

        }
    }

}

#Selfservice Product
$SelfserviceProductTemp = (Get-HelloIDData -endpointUri "/api/v1/products") | Where-Object { $_.name -eq $selfserviceProductName }
if ([string]::IsNullOrEmpty($SelfserviceProductTemp.productId)) {
    Write-Error "Failed to load Selfservice Product called: $selfserviceProductName";
    exit;
}
elseif ($SelfserviceProductTemp.productId.count -gt 1) {
    Write-Error "Multiple Selfservice Product called: $($selfserviceProductName). Please make sure this is unique";
    exit;  
}
$SelfserviceProduct = (Get-HelloIDData -endpointUri "/api/v1/products/$($SelfserviceProductTemp.productId)")
if ([string]::IsNullOrEmpty($SelfserviceProduct.productId)) {
    Write-Error "Failed to load Selfservice Product called: $selfserviceProductName";
    exit;
}

#Selfservice Product categories
if (-not $useManualSelfserviceProductCategories -eq $true) {
    $currentCategories = $SelfserviceProduct.categories

    if ($currentCategories.Count -gt 0) {
        $SelfserviceProductCategories = $currentCategories
    }
    else {
        # use default Selfservice Product categories
        $SelfserviceProductCategories = $manualSelfserviceProductCategories 
    }
}
else {
    # use default Selfservice Product categories
    $SelfserviceProductCategories = $manualSelfserviceProductCategories
}


#SelfserviceProduct state actions

if ($null -ne $SelfserviceProduct.onRequest) {
    Get-ProductActions -stateAction "onRequest"
}
else {
    Write-Verbose "No onRequest actions"
}

if ($null -ne $SelfserviceProduct.onApprove) {
    Get-ProductActions -stateAction "onApprove"
}
else {
    Write-Verbose "No onApprove actions"
}

if ($null -ne $SelfserviceProduct.onDeny) {
    Get-ProductActions -stateAction "onDeny"
}
else {
    Write-Verbose "No onDeny actions"
}

if ($null -ne $SelfserviceProduct.onReturn) {
    Get-ProductActions -stateAction "onReturn"
}
else {
    Write-Verbose "No onReturn actions"
}

if ($null -ne $SelfserviceProduct.onWithdrawn) {
    Get-ProductActions -stateAction "onWithdrawn"
}
else {
    Write-Verbose "No onWithdrawn actions"
}

#DynamicForm
if ($null -ne $SelfserviceProduct.dynamicForm) {
    $dynamicForm = (Get-HelloIDData -endpointUri "/api/v1/forms/$($SelfserviceProduct.dynamicForm.id)")

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
                    set-content -LiteralPath "$tmpFileName.json" -Value (ConvertTo-Json -InputObject $datasource.value) -Force
                    set-content -LiteralPath "$tmpFileName.model.json" -Value (ConvertTo-Json -InputObject $datasource.model) -Force
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
                    set-content -LiteralPath "$tmpFileName.model.json" -Value (ConvertTo-Json -InputObject $datasource.model) -Force
                    set-content -LiteralPath "$tmpFileName.inputs.json" -Value (ConvertTo-Json -InputObject $datasource.input) -Force
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
                    set-content -LiteralPath "$tmpFileName.model.json" -Value (ConvertTo-Json -InputObject $datasource.model) -Force
                    set-content -LiteralPath "$tmpFileName.inputs.json" -Value (ConvertTo-Json -InputObject $datasource.input) -Force
                    break;
                }
            }
        }
        catch {
            Write-Error "Failed to get Datasource";
        }
    }
}

#Get all global variables
$allGlobalVariables = (Get-HelloIDData -endpointUri "/api/v1/automation/variables")

# get all Global variables used in PS scripts (task data sources, powershell data source and Selfservice Product task)
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
$script:PortalBaseUrl = "https://CUSTOMER.helloid.com"
$apiKey = "API_KEY"
$apiSecret = "API_SECRET"
'@
$PowershellScript += "`n`$SelfserviceProductApprovalWorkflowName = @(" + ('"{0}"' -f ($($SelfserviceProduct.approvalWorkflow))) + ") # Approval workflow must exist!";
$PowershellScript += "`n`$SelfserviceProductCategories = @(" + ('"{0}"' -f ($($SelfserviceProductCategories.name) -join '","')) + ") #Only unique names are supported. Categories will be created if not exists";
$PowershellScript += "`n`$SelfserviceProductManagedByGroupName = @(" + ('"{0}"' -f ($defaultSelfserviceProductManagedByGroupName)) + ") #Only single value supported. Group must exist within HelloID!";
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
    $script:headers = @{"authorization" = $portalApiBasic }
    Write-Information "Using prefilled API credentials"
}
else {
    # Create authorization headers with HelloID API key
    $pair = "$apiKey" + ":" + "$apiSecret"
    $bytes = [System.Text.Encoding]::ASCII.GetBytes($pair)
    $base64 = [System.Convert]::ToBase64String($bytes)
    $key = "Basic $base64"
    $script:headers = @{"authorization" = $Key }
    Write-Information "Using manual API credentials"
}

# Check for prefilled PortalBaseURL
if (-not [string]::IsNullOrEmpty($portalBaseUrl)) {
    $script:PortalBaseUrl = $portalBaseUrl
    Write-Information "Using prefilled PortalURL: $script:PortalBaseUrl"
}
else {
    $script:PortalBaseUrl = $portalUrl
    Write-Information "Using manual PortalURL: $script:PortalBaseUrl"
}

# Define specific endpoint URI
$script:PortalBaseUrl = $script:PortalBaseUrl.trim("/") + "/"  
 

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
            $body = ConvertTo-Json -InputObject $body
    
            $uri = ($script:PortalBaseUrl + "api/v1/automation/variable")
            $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false -Body $body
            $variableGuid = $response.automationVariableGuid

            Write-Information "Variable '$Name' created$(if ($script:debugLogging -eq $true) { ": " + $variableGuid })"
        }
        else {
            $variableGuid = $response.automationVariableGuid
            Write-Warning "Variable '$Name' already exists$(if ($script:debugLogging -eq $true) { ": " + $variableGuid })"
        }
    }
    catch {
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
        $uri = ($script:PortalBaseUrl + "api/v1/automationtasks?search=$TaskName&container=$AutomationContainer")
        $responseRaw = (Invoke-RestMethod -Method Get -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false) 
        $response = $responseRaw | Where-Object -filter { $_.name -eq $TaskName }
    
        if ([string]::IsNullOrEmpty($response.automationTaskGuid) -or $ForceCreateTask -eq $true) {
            #Create Task

            $body = @{
                name                = $TaskName;
                useTemplate         = $UseTemplate;
                powerShellScript    = $PowershellScript;
                automationContainer = $AutomationContainer;
                objectGuid          = $ObjectGuid;
                variables           = [Object[]]($Variables | ConvertFrom-Json);
            }
            $body = ConvertTo-Json -InputObject $body
    
            $uri = ($script:PortalBaseUrl + "api/v1/automationtasks/powershell")
            $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false -Body $body
            $taskGuid = $response.automationTaskGuid

            Write-Information "Powershell task '$TaskName' created$(if ($script:debugLogging -eq $true) { ": " + $taskGuid })"
        }
        else {
            #Get TaskGUID
            $taskGuid = $response.automationTaskGuid
            Write-Warning "Powershell task '$TaskName' already exists$(if ($script:debugLogging -eq $true) { ": " + $taskGuid })"
        }
    }
    catch {
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
        [parameter(Mandatory)][Ref]$returnObject
    )

    $DatasourceName = $DatasourceName + $(if ($script:duplicateForm -eq $true) { $script:duplicateFormSuffix })

    $datasourceTypeName = switch ($DatasourceType) { 
        "1" { "Native data source"; break } 
        "2" { "Static data source"; break } 
        "3" { "Task data source"; break } 
        "4" { "Powershell data source"; break }
    }
    
    try {
        $uri = ($script:PortalBaseUrl + "api/v1/datasource/named/$DatasourceName")
        $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false
      
        if ([string]::IsNullOrEmpty($response.dataSourceGUID)) {
            #Create DataSource
            $body = @{
                name               = $DatasourceName;
                type               = $DatasourceType;
                model              = [Object[]]($DatasourceModel | ConvertFrom-Json);
                automationTaskGUID = $AutomationTaskGuid;
                value              = [Object[]]($DatasourceStaticValue | ConvertFrom-Json);
                script             = $DatasourcePsScript;
                input              = [Object[]]($DatasourceInput | ConvertFrom-Json);
            }
            $body = ConvertTo-Json -InputObject $body
      
            $uri = ($script:PortalBaseUrl + "api/v1/datasource")
            $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false -Body $body
              
            $datasourceGuid = $response.dataSourceGUID
            Write-Information "$datasourceTypeName '$DatasourceName' created$(if ($script:debugLogging -eq $true) { ": " + $datasourceGuid })"
        }
        else {
            #Get DatasourceGUID
            $datasourceGuid = $response.dataSourceGUID
            Write-Warning "$datasourceTypeName '$DatasourceName' already exists$(if ($script:debugLogging -eq $true) { ": " + $datasourceGuid })"
        }
    }
    catch {
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
            $uri = ($script:PortalBaseUrl + "api/v1/forms/$FormName")
            $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false
        }
        catch {
            $response = $null
        }
    
        if (([string]::IsNullOrEmpty($response.dynamicFormGUID)) -or ($response.isUpdated -eq $true)) {
            #Create Dynamic form
            $body = @{
                Name       = $FormName;
                FormSchema = [Object[]]($FormSchema | ConvertFrom-Json)
            }
            $body = ConvertTo-Json -InputObject $body -Depth 100
    
            $uri = ($script:PortalBaseUrl + "api/v1/forms")
            $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false -Body $body
    
            $formGuid = $response.dynamicFormGUID
            $formName = $response.name
            Write-Information "Dynamic form '$formName' created$(if ($script:debugLogging -eq $true) { ": " + $formGuid })"
        }
        else {
            $formGuid = $response.dynamicFormGUID
            $formName = $response.name
            Write-Warning "Dynamic form '$FormName' already exists$(if ($script:debugLogging -eq $true) { ": " + $formGuid })"
        }
    }
    catch {
        Write-Error "Dynamic form '$FormName', message: $_"
    }

    $returnObject.Value = $formGuid
}


function Invoke-HelloIDSelfserviceProduct {
    param(
        [parameter(Mandatory)][String]$selfserviceProductName,
        [parameter()][String]$Description,
        [parameter(Mandatory)][String]$Code,
        [parameter()][String][AllowEmptyString()]$ManagedByGroupGUID,
        [parameter()]$Categories,
        [parameter(Mandatory)][String]$UseFaIcon,
        [parameter()][String][AllowEmptyString()]$FaIcon,
        [parameter()][String][AllowEmptyString()]$Icon,
        [parameter(Mandatory)][String]$Visibility,
        [parameter(Mandatory)][String]$AllowMultipleRequests,
        [parameter(Mandatory)][String]$HasTimeLimit,
        [parameter()][String][AllowEmptyString()]$LimitType,
        [parameter(Mandatory)][String]$ManagerCanOverrideDuration,
        [parameter()][String][AllowEmptyString()]$OwnershipMaxDuration,
        [parameter(Mandatory)][String]$HasRiskFactor,
        [parameter()][String][AllowEmptyString()]$RiskFactor,
        [parameter()][String][AllowEmptyString()]$MaxCount,
        [parameter(Mandatory)]$ShowPrice,
        [parameter()][String][AllowEmptyString()]$Price,
        [parameter()]$DynamicFormName,
        [parameter()][String][AllowEmptyString()]$ApprovalWorkflowName, 
        [parameter()]$onRequest,
        [parameter()]$onApprove,
        [parameter()]$onDeny,
        [parameter()]$onReturn,
        [parameter()]$onWithdrawn,
        [parameter(Mandatory)][Ref]$returnObject
    )
    $SelfserviceProductCreated = $false
    $selfserviceProductName = $selfserviceProductName + $(if ($script:duplicateForm -eq $true) { $script:duplicateFormSuffix })

    try {
        try {
            $uri = ($script:PortalBaseUrl + "api/v1/products")
            $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false
            $response = $response | Where-Object { $_.name -eq $selfserviceProductName }       
        }
        catch {
            $response = $null
        }

        # Add the Actions
        $onApproveActions = [System.Collections.Generic.list[object]]@()
        $onRequestActions = [System.Collections.Generic.list[object]]@()
        $onDenyActions    = [System.Collections.Generic.list[object]]@()
        $onReturnActions = [System.Collections.Generic.list[object]]@()
        $onWithdrawnActions = [System.Collections.Generic.list[object]]@()

        foreach ($action in $onRequest ) {

            [void]$onRequestActions.Add([PSCustomObject]@{
                id          = "" # supplying an id when creating a product action is not supported. You have to leave the 'id' property empty or leave the property out alltogether when creating a new product action
                name        = $action.name
                script      = $action.script
                agentPoolId = $action.agentPoolId
                runInCloud  = $action.runInCloud
            })
              

        }
        foreach ($action in $onApprove ) {

            [void]$onApproveActions.Add([PSCustomObject]@{
                id          = "" # supplying an id when creating a product action is not supported. You have to leave the 'id' property empty or leave the property out alltogether when creating a new product action
                name        = $action.name
                script      = $action.script
                agentPoolId = $action.agentPoolId
                runInCloud  = $action.runInCloud
            })

        }

        foreach ($action in $onDeny ) {

            [void]$onDenyActions.Add([PSCustomObject]@{
                id          = "" # supplying an id when creating a product action is not supported. You have to leave the 'id' property empty or leave the property out alltogether when creating a new product action
                name        = $action.name
                script      = $action.script
                agentPoolId = $action.agentPoolId
                runInCloud  = $action.runInCloud
            })

        }
        foreach ($action in $onReturn ) {

            [void]$onReturnActions.Add([PSCustomObject]@{
                id          = "" # supplying an id when creating a product action is not supported. You have to leave the 'id' property empty or leave the property out alltogether when creating a new product action
                name        = $action.name
                script      = $action.script
                agentPoolId = $action.agentPoolId
                runInCloud  = $action.runInCloud
            })

        }
        foreach ($action in $onWithdrawn ) {

            [void]$onWithdrawnActions.Add([PSCustomObject]@{
                id          = "" # supplying an id when creating a product action is not supported. You have to leave the 'id' property empty or leave the property out alltogether when creating a new product action
                name        = $action.name
                script      = $action.script
                agentPoolId = $action.agentPoolId
                runInCloud  = $action.runInCloud
            })

        }
    
        if ([string]::IsNullOrEmpty($response.productId)) {
            #Create SelfserviceProduct
            $body = @{
                name                          = $selfserviceProductName;
                description                   = $Description;
                code                          = $Code;
                managedByGroupGUID            = $ManagedByGroupGUID;
                categories                    = $Categories;
                icon                          = $Icon;
                useFaIcon                     = $UseFaIcon;
                faIcon                        = $FaIcon;
                visibility                     = $Visibility;
                allowMultipleRequests         = $AllowMultipleRequests
                hasTimeLimit                  = $HasTimeLimit;
                limitType                     = $LimitType;
                managerCanOverrideDuration    = $ManagerCanOverrideDuration;
                hasRiskFactor                 = $HasRiskFactor;
                riskFactor                    = $RiskFactor
                maxCount                      = $MaxCount
                showPrice                     = $ShowPrice
                price                         = $Price
                dynamicForm                   = @{id = $DynamicFormName }
                approvalWorkflowName          = $ApprovalWorkflowName
                onRequest                     = $onRequestActions
                onApprove                     = $onApproveActions
                onDeny                        = $onDenyActions
                onReturn                      = $onReturnActions
                onWithdrawn                   = $onWithdrawnActions

            }

            # Only add OwnershipMaxDurationInMinutes if it doesn't equal '0', as this cannot be 0 for the API calls.
            if ($OwnershipMaxDuration -ne 0) { 
                [void]$body.Add('ownershipMaxDuration',$OwnershipMaxDuration)
            }
            
            $body = ConvertTo-Json -InputObject $body
    
            $uri = ($script:PortalBaseUrl + "api/v1/products")
            #$response = Invoke-RestMethod -Method Post -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false -Body $body
            $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $script:headers -ContentType 'application/json' -Verbose:$false -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) 

            $productId = $response.productId
            Write-Information "Selfservice Product '$selfserviceProductName' created$(if ($script:debugLogging -eq $true) { ": " + $productId })"
            $SelfserviceProductCreated = $true
            

        }
        else {
            # Get productId
            $productId = $response.productId
            Write-Warning "Selfservice Product '$selfserviceProductName' already exists$(if ($script:debugLogging -eq $true) { ": " + $productId })"
        }
    }
    catch {
        Write-Error "Selfservice Product '$selfserviceProductName', message: $_"
    }

    $returnObject.value.guid = $productId
    $returnObject.value.created = $SelfserviceProductCreated
}

'@

#Build All-in-one PS script
$PowershellScript += "<# Begin: HelloID Global Variables #>`n"
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
            $PowershellScript += "`$tmpStaticValue = @'`n" + (ConvertTo-Json -InputObject $item.datasource.value -Compress) + "`n'@ `n";
            $PowershellScript += "`$tmpModel = @'`n" + (ConvertTo-Json -InputObject $item.datasource.model -Compress) + "`n'@ `n";

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
            $PowershellScript += "`$tmpVariables = @'`n" + (ConvertTo-Json -InputObject $tmpVariables -Compress) + "`n'@ `n";
            $PowershellScript += "`n"

            # Output method call Automation task with parameters
            $PowershellScript += "`$taskGuid = [PSCustomObject]@{} `n"
            $PowershellScript += ($item.guidRef) + "_Name = @'`n" + $($item.Task.Name) + "`n'@ `n";
            $PowershellScript += "Invoke-HelloIDAutomationTask -TaskName " + ($item.guidRef) + "_Name -UseTemplate """ + ($item.task.variables | Where-Object { $_.name -eq "useTemplate" }).Value + """ -AutomationContainer ""$($item.Task.automationContainer)"" -Variables `$tmpVariables -PowershellScript `$tmpScript -returnObject ([Ref]`$taskGuid) `n"
            $PowershellScript += "`n"

            # Output data source input variables and model definition
            $PowershellScript += "`$tmpInput = @'`n" + (ConvertTo-Json -InputObject $item.datasource.input -Compress) + "`n'@ `n";
            $PowershellScript += "`$tmpModel = @'`n" + (ConvertTo-Json -InputObject $item.datasource.model -Compress) + "`n'@ `n";

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
            $PowershellScript += "`$tmpModel = @'`n" + (ConvertTo-Json -InputObject $item.datasource.model -Compress) + "`n'@ `n";
            $PowershellScript += "`$tmpInput = @'`n" + (ConvertTo-Json -InputObject $item.datasource.input -Compress) + "`n'@ `n";

            # Output method call Data source with parameters
            $PowershellScript += ($item.guidRef) + " = [PSCustomObject]@{} `n"
            $PowershellScript += ($item.guidRef) + "_Name = @'`n" + $($item.datasource.Name) + "`n'@ `n";
            $PowershellScript += "Invoke-HelloIDDatasource -DatasourceName " + ($item.guidRef) + "_Name -DatasourceType ""$($item.datasource.type)"" -DatasourceInput `$tmpInput -DatasourcePsScript `$tmpPsScript -DatasourceModel `$tmpModel -returnObject ([Ref]" + ($item.guidRef) + ") `n"

            break;
        }
    }
    $PowershellScript += "<# End: DataSource ""$($item.Datasource.Name)"" #>`n"
}
$PowershellScript += "<# End: HelloID Data sources #>`n`n"

if ($null -ne $SelfserviceProduct.dynamicForm) {
    $PowershellScript += "<# Begin: Dynamic Form ""$($dynamicForm.name)"" #>`n"
    $PowershellScript += "`$tmpSchema = @""`n" + (ConvertTo-Json -InputObject $dynamicForm.formSchema -Depth 100 -Compress) + "`n""@ `n";
    $PowershellScript += "`n"
    $PowershellScript += "`$dynamicFormNameReturned = [PSCustomObject]@{} `n"
    $PowershellScript += "`$dynamicFormName = @'`n" + $($dynamicForm.name) + "`n'@ `n";
    $PowershellScript += "Invoke-HelloIDDynamicForm -FormName `$dynamicFormName -FormSchema `$tmpSchema  -returnObject ([Ref]`$dynamicFormNameReturned) `n"
    $PowershellScript += "<# END: Dynamic Form #>`n`n"
}
$PowershellScript += "<# Begin: Selfservice Product Managed By Group and Categories #>`n"
$PowershellScript += @'
try {
    if ([string]::IsNullOrEmpty($SelfserviceProductManagedByGroupName)) {
        Write-Warning "No HelloID (managed by)group name specified. Skipping the group"
    }
    else {
        $uri = ($script:PortalBaseUrl + "api/v1/groups/$SelfserviceProductManagedByGroupName")
        $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false
        $selfserviceProductManagedByGroupGuid = $response.groupGuid

        if ($selfserviceProductManagedByGroupGuid.count -eq 1) {
            Write-Information "HelloID (managed by)group '$SelfserviceProductManagedByGroupName' successfully found$(if ($script:debugLogging -eq $true) { ": " + $selfserviceProductManagedByGroupGuid })"
        }
        elseif ($selfserviceProductManagedByGroupGuid.count -gt 1) {
            Write-Error "Multiple HelloID (managed by)groups found with name '$SelfserviceProductManagedByGroupName'. Please make sure this is unique"
        }
    }
}
catch {
    Write-Error "HelloID (managed by)group '$SelfserviceProductManagedByGroupName', message: $_"
}

$SelfserviceProductCategoryNames = @()
$SelfserviceProductCategoryGUID = [System.Collections.Generic.list[object]]@()
foreach ($category in $SelfserviceProductCategories) {
    $uri = ($script:PortalBaseUrl + "api/v1/selfservice/categories")
    $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false
    $response = $response | Where-Object { $_.name -eq $category }
    if ($null -ne $response) {
        $tmpName = $response.name
        $tmpGuid = $response.selfServiceCategoryGUID

        $SelfserviceProductCategoryNames += $tmpName
        [void]$SelfserviceProductCategoryGUID.Add([PSCustomObject]@{
            id          = $tmpGuid 

        })
        Write-Information "HelloID Selfservice Product category '$category' successfully found$(if ($script:debugLogging -eq $true) { ": " + $tmpGuid })"
    }
    else {
        Write-Warning "HelloID Selfservice Product category '$category' not found"

        $body = @{
            "Name"      = $category;
            "IsEnabled" = $true
        }
        $body = ConvertTo-Json -InputObject $body

        $uri = ($script:PortalBaseUrl + "api/v1/selfservice/categories")
        $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false -Body $body
        $tmpName = $response.name
        $SelfserviceProductCategoryNames += $tmpName

        Write-Information "HelloID Selfservice Product category '$category' successfully created$(if ($script:debugLogging -eq $true) { ": " + $tmpGuid })"
    }
}
'@
$PowershellScript += "`n<# End: Selfservice Product Managed By Group and Categories #>`n"
$PowershellScript += "`n<# Begin: Selfservice Product #>`n"
$PowershellScript += "`$SelfserviceProductRef = [PSCustomObject]@{guid = `$null; created = `$null} `n"

$PowershellScript += "`$onRequestActionsJson =  @'`n" + (ConvertTo-Json -InputObject ($SelfserviceProduct.onRequest | select-object name, script, agentPoolId, runInCloud) -Depth 10 -Compress) + "`n'@ `n";
$PowershellScript += "`$onRequestActions     =  `$onRequestActionsJson | ConvertFrom-Json `n"
$PowershellScript += "`$onApproveActionsJson =  @'`n" + (ConvertTo-Json -InputObject ($SelfserviceProduct.onApprove | select-object name, script, agentPoolId, runInCloud) -Depth 10 -Compress) + "`n'@ `n";
$PowershellScript += "`$onApproveActions     =  `$onApproveActionsJson | ConvertFrom-Json `n"
$PowershellScript += "`$onDenyActionsJson    =  @'`n" + (ConvertTo-Json -InputObject ($SelfserviceProduct.onDeny | select-object name, script, agentPoolId, runInCloud) -Depth 10 -Compress) + "`n'@ `n";
$PowershellScript += "`$onDenyActions        =  `$onDenyActionsJson | ConvertFrom-Json `n"
$PowershellScript += "`$onReturnActionsJson  =  @'`n" + (ConvertTo-Json -InputObject ($SelfserviceProduct.onReturn | select-object name, script, agentPoolId, runInCloud) -Depth 10 -Compress) + "`n'@ `n";
$PowershellScript += "`$onReturnActions      =  `$onReturnActionsJson | ConvertFrom-Json `n"
$PowershellScript += "`$onWithdrawnActionsJson =  @'`n" + (ConvertTo-Json -InputObject ($SelfserviceProduct.onWithdrawn | select-object name, script, agentPoolId, runInCloud) -Depth 10 -Compress) + "`n'@ `n";
$PowershellScript += "`$onWithdrawnActions   =  `$onWithdrawnActionsJson | ConvertFrom-Json `n"

$PowershellScript += "`$SelfserviceProductParams = @{ `n"
$PowershellScript += "`tselfserviceProductName          = `"$($SelfserviceProduct.name)`" `n"
$PowershellScript += "`tCode                            = (Get-Date -Format `"yyyyMMddHHmmss`") `n"
$PowershellScript += "`tDescription                     = `"$($SelfserviceProduct.description)`" `n"
$PowershellScript += "`tManagedByGroupGUID              = `"`$selfserviceProductManagedByGroupGuid`" `n"
$PowershellScript += "`tCategories                      = `$SelfserviceProductCategoryGUID `n"
$PowershellScript += "`tIcon                            = `"$($SelfserviceProduct.icon)`" `n"
$PowershellScript += "`tUseFaIcon                       = `"$($SelfserviceProduct.useFaIcon)`" `n"
$PowershellScript += "`tFaIcon                          = `"$($SelfserviceProduct.faIcon)`" `n"
$PowershellScript += "`tVisibility                      = `"$($SelfserviceProduct.visibility)`" `n"
$PowershellScript += "`tAllowMultipleRequests           = `"$($SelfserviceProduct.allowMultipleRequests)`" `n"
$PowershellScript += "`tHasTimeLimit                    = `"$($SelfserviceProduct.hasTimeLimit)`" `n"
$PowershellScript += "`tLimitType                       = `"$($SelfserviceProduct.limitType)`" `n"
$PowershellScript += "`tManagerCanOverrideDuration      = `"$($SelfserviceProduct.managerCanOverrideDuration)`" `n"
$PowershellScript += "`tOwnershipMaxDuration            = `"$($SelfserviceProduct.ownershipMaxDuration)`" `n"
$PowershellScript += "`tHasRiskFactor                   = `"$($SelfserviceProduct.hasRiskFactor)`" `n"
$PowershellScript += "`tRiskFactor                      = `"$($SelfserviceProduct.riskFactor)`" `n"
$PowershellScript += "`tMaxCount                        = `"$($SelfserviceProduct.maxCount)`" `n"
$PowershellScript += "`tShowPrice                       = `"$($SelfserviceProduct.showPrice)`" `n"
$PowershellScript += "`tPrice                           = `"$($SelfserviceProduct.price)`" `n"
$PowershellScript += "`tDynamicFormName                 = `$dynamicFormNameReturned `n"
$PowershellScript += "`tApprovalWorkflowName            = `"`$SelfserviceProductApprovalWorkflowName`" `n"
$PowershellScript += "`tonRequest                       = `$onRequestActions `n"
$PowershellScript += "`tonApprove                       = `$onApproveActions `n"
$PowershellScript += "`tonDeny                          = `$onDenyActions `n"
$PowershellScript += "`tonReturn                        = `$onReturnActions `n"
$PowershellScript += "`tonWithdrawn                     = `$onWithdrawnActions `n"

$PowershellScript += "} `n"
$PowershellScript += "Invoke-HelloIDSelfserviceProduct @SelfserviceProductParams -returnObject ([Ref]`$SelfserviceProductRef) `n"
$PowershellScript += "<# End: Selfservice Product #>`n"
set-content -LiteralPath "$allInOneFolder\createform.ps1" -Value $PowershellScript -Force