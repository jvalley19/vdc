Import-Module "$($rootPath)/../Common/Helper.psd1" -Force;

Class AzureResourceManagerDeploymentService: IDeploymentService {
 
    [string] $armResourceGroupDeploymentUri = ""
    [string] $armSubscriptionDeploymentUri = ""
    [string] $armResourceGroupValidationUri = ""
    [string] $armSubscriptionValidationUri = ""
    
    [bool] $isSubscriptionDeployment = $false;    
 
    [hashtable] ExecuteDeployment([string] $tenantId, `
                        [string] $subscriptionId, `
                        [string] $resourceGroupName, `
                        [string] $deploymentTemplate, `
                        [string] $deploymentParameters, `
                        [string] $location,
                        [string] $azureManagementUrl) {
       
        try {
            # set the URL's from Discovery REST API call
            $this.SetAzureEnvironmentBasedManagementUrls($azureManagementUrl);

            # call arm deployment
            $deployment = `
            $this.InvokeARMOperation(
                $tenantId,
                $subscriptionId,
                $resourceGroupName,
                $deploymentTemplate,
                $deploymentParameters,
                $location,
                "deploy");
        
            # retrieve the state of the resource and return state and deployment id that is
            # generated by arm
            # if it fails, throw an exception
            $resourceState = `
                $this.RetrieveDeploymentData(
                    $deployment.Id,
                    $deployment.Name,
                    $resourceGroupName,
                    $subscriptionId,
                    $this.isSubscriptionDeployment);

            $resourceState += @{
                TenantId = $tenantId
                SubscriptionId = $subscriptionId
                ResourceGroupName = $resourceGroupName
                DeploymentTemplate = ConvertFrom-Json $deploymentTemplate -Depth 100
                DeploymentParameters = ConvertFrom-Json $deploymentParameters -Depth 100
            }

            return $resourceState;
        }
        catch {
            throw $(Get-Exception -ErrorObject $_);
        }
    }

    [void] ExecuteValidation([string] $tenantId, `
                            [string] $subscriptionId, `
                            [string] $validationResourceGroupName, `
                            [string] $deploymentTemplate, `
                            [string] $deploymentParameters, `
                            [string] $location) {
        
        try {
           
            # call arm validation
            $validation = `
                $this.InvokeARMOperation(
                    $tenantId,
                    $subscriptionId,
                    $validationResourceGroupName,
                    $deploymentTemplate,
                    $deploymentParameters,
                    $location,
                    "validate");

            # Did the validation succeed?
            if($validation.error.code -eq "InvalidTemplateDeployment") {
                # Throw an exception and pass the exception message from the 
                # ARM validation
                Throw ("Validation failed with the error below: {0}" -f (ConvertTo-Json $validation -Depth 50));
            }
            else {
                Write-Host "Validation Passed";
            }
        }
        catch {
            throw $(Get-Exception -ErrorObject $_);
        }
    }
 
    hidden [string] GenerateUniqueDeploymentName() {
        # generate a new guid
        return [Guid]::NewGuid();
    }
 
    hidden [object] InvokeARMOperation([string] $tenantId, `
                                        [string] $subscriptionId, `
                                        [string] $resourceGroupName, `
                                        [string] $deploymentTemplate, `
                                        [string] $deploymentParameters,
                                        [string] $location, `
                                        [string] $operation) {
        $deployment = $null;
        $parametersJson = "";
 
        # Check for invariant
        if([string]::IsNullOrEmpty($deploymentTemplate)) {
            throw "Deployment template contents cannot be empty";
        }
        else {
 
            # Let's check if we are in a subscription or
            # resource group level deployment by inspecting
            # the schema
 
            $deploymentTemplateJson = `
                ConvertFrom-Json $deploymentTemplate `
                    -AsHashtable `
                    -Depth 100;

            # Concatenating the strings, because
            # "$schema" will try to resolve to a
            # variable
            $schema = "$" + "schema";
            $requestBody = "";
            $this.isSubscriptionDeployment = `
                $false;

            # By default, the scope is assumed to be 
            # resource group unless template schema 
            # contains the schema for subscription. 
            $scope = "resource-group";

            # Check for the scope of the operation
            if($deploymentTemplateJson.$schema.Contains("subscriptionDeploymentTemplate")) {
                # If template schema contains the schema for 
                # subscription, then the scope is set to 
                # subscription
                $scope = "subscription";
            }


            # If the scope is resource-group, check if the resource group exists before proceeding.
            # If the scope is subscription, resource group is not expected.
            if((![string]::IsNullOrEmpty($resourceGroupName) -and `
                $scope -eq "resource-group") -or `
                $scope -eq "subscription") {

                # Contruct the uri for the desired operation (deploy 
                # or validate) and for the desired scope (resource-group
                # or subscription)
                $uri = $this.ConstructUri(
                    $subscriptionId,
                    $resourceGroupName,
                    $operation,
                    $scope
                );
                
                # Prepare the request body for the REST API
                $requestBody = $this.PrepareRequestBodyForArm(
                    $deploymentTemplate,
                    $deploymentParameters,
                    $location,
                    $scope
                );
            
                # Get Access Token
                $accessToken = $this.GetAccessToken($tenantId);
    
                # header will need the access token of the sp or user performing the deployment
                $headers = @{
                    "authorization" = "Bearer $accessToken";
                }

                # Switch REST Verb based on operation type
                if($operation -eq "deploy") {
                    $method = "Put";
                }
                else {
                    $method = "Post";
                }
                
                try
                {  
                    Write-Debug "Invoking ARM REST API with Uri: $uri";
                    Write-Debug "Request Body: $requestBody";

                    # Call REST API to start the deployment
                    $deployment = `
                        Invoke-RestMethod `
                            -Method $method `
                            -Uri $uri `
                            -Body $requestBody `
                            -Headers $headers `
                            -ContentType "application/json";

                    Write-Debug "Result of ARM Invocation is: $(ConvertTo-Json $deployment -Depth 50)";
    
                    # wait for arm deployment
                    if($deployment.Id -ne $null `
                        -and $operation -eq "deploy") {
                        # if the $deployment object's id is not null, then wait for the deployment to continue
                        # at this step, the REST call was accepted and being processed. The process can be tracked
                        # through the deployment object's id provided.
                        # Only two failures can result:
                        # 1. Template / Parameters Validation failure
                        # 2. Deployment failure
                        Write-Host "Running a deployment ..." -ForegroundColor Yellow;
                        $this.WaitForDeploymentToComplete(
                            $deployment,
                            $this.isSubscriptionDeployment);
                        Write-Host "Deployment complete"  -ForegroundColor Yellow;
                    }
                    return $deployment;
                
                }
                catch {
                    # For deploy operation, the error is due malformed or incorrect inputs
                    if($operation -eq "deploy") {
                        Write-Host "An Exception Occurred While Invoking the Deployment. Please see the error below:";
                        throw $(Get-Exception $_);
                    }
                    # For validate operation, the error is due to validation failure
                    else {
                        return $_;
                    }
                }

            }
            else {
                # Fail early if the validation resource group does not
                # exists
                Throw "Validation resource group - $resourceGroupName is not setup. Create the validation resource `
                    group before invoking the ARM validation.";
            }
        }
    }
    
    hidden [string] PrepareRequestBodyForArm([string] $deploymentTemplate, `
                                                [string] $deploymentParameters, `
                                                [string] $location, `
                                                [string] $scope) {
        
        # Let's check if we are in a subscription or
        # resource group level deployment by inspecting
        # the schema
        $deploymentTemplateJson = `
            ConvertFrom-Json $deploymentTemplate `
                -AsHashtable `
                -Depth 100;
        # Concatenating the strings, because
        # "$schema" will try to resolve to a
        # variable
        $schema = "$" + "schema";
        $requestBody = "";
        $this.isSubscriptionDeployment = `
            $false;

        # generate a random guid to be used as deployment name
        $uniqueDeploymentName = `
            $this.GenerateUniqueDeploymentName();

        # Let's analyze the deployment parameters
        # if there's a schema, remove it

        if($deploymentParameters) {
            # if the parameters json contains $schema, etc as the first level properties,
            # we traverse one level down to retrieve only the parameters property of parent
            # and use the parameters object for deployment
            $parametersJson = `
                ConvertFrom-Json $deploymentParameters `
                    -AsHashtable;

            # falsy
            if($parametersJson.parameters) {
                $deploymentParameters = `
                    ConvertTo-Json $parametersJson.parameters `
                        -Compress `
                        -Depth 50;
            }
        }

        # Subscription level deployment
        if($scope -eq "subscription") {
                    
            $this.isSubscriptionDeployment = `
                $true;
            # prepare the REST Call's body content format
            $requestBody = "{
                'location': '$location',
                'properties': {
                    'mode': 'Incremental',
                    'template': $deploymentTemplate,
                    'parameters': $deploymentParameters
                }
            }";
        }
        else {
            # prepare the REST Call's body content format
            $requestBody = "{
                'properties': {
                    'mode': 'Incremental',
                    'template': $deploymentTemplate,
                    'parameters': $deploymentParameters
                }
            }";
        }

        return $requestBody;
    }

    hidden [string] ConstructUri([string] $subscriptionId, `
                                    [string] $resourceGroupName, `
                                    [string] $operation, `
                                    [string] $scope) {

        $uniqueDeploymentName = $this.GenerateUniqueDeploymentName();

        $uri = '';

        Write-Debug "Operation scope: $scope; Operation: $operation";

        # Subscription level deployment
        if($scope -eq "subscription") {
                    
            $this.isSubscriptionDeployment = `
                $true;

            if($operation -eq "deploy") {
                $uri = $this.armSubscriptionDeploymentUri;
            }
            else {
                $uri = $this.armSubscriptionValidationUri;
            }

            # construct the uri using the format for armSubscriptionDeploymentUri
            $uri = `
                $uri `
                    -f $subscriptionId, `
                    $uniqueDeploymentName;
        }
        else {

            if($operation -eq "deploy") {
                $uri = $this.armResourceGroupDeploymentUri;
            }
            else {
                $uri = $this.armResourceGroupValidationUri;
            }

            # construct the uri using the format for armResourceGroupDeploymentUri
            $uri = `
                $uri `
                    -f $subscriptionId, `
                    $resourceGroupName, `
                    $uniqueDeploymentName;
        }

        Write-Debug "Uri for deployment / validation operation: $uri";

        return $uri;
    }

    hidden [string] GetAccessToken([string] $tenantId) {
      
        # will need to perform Login-AzAccount from the terminal
        $context = Get-AzContext;
        $tokenCache = $context.TokenCache;
        $cacheItems = $tokenCache.ReadItems();
        $accessToken = '';

        # Let's filter based on management endpoint (resource
        # management)
        $cacheItems = 
            $cacheItems | `
            Where-Object -Property "Resource" -Like "*management*"

        $cacheItems | ForEach-Object {
            # Cache Items object's TenantId is null when run in
            # an AzDO Agent

            # Note, doing a break; in Powershell, exits the entire
            # script execution, not only the function.
            if([string]::IsNullOrEmpty($accessToken))
            {
                if ($null -ne $_.TenantId `
                    -and $_.TenantId -eq $tenantId `
                    -and $_.ExpiresOn -gt (Get-Date)) {
                    $accessToken = $_.AccessToken;
                    Write-Debug "Access token found with tenant id filter";
                }
                elseif ($null -eq $_.TenantId `
                        -and $_.ExpiresOn -gt (Get-Date))
                {
                    $accessToken = $_.AccessToken;
                    Write-Debug "Access token found without tenant id filter";
                }
            }
        }
        Write-Debug "Access token is: $(ConvertTo-Json $accessToken)";
        if([string]::IsNullOrEmpty($accessToken)) {
            Throw "Login to the right tenant. Tenant specified in the `
            subscription file may be different from the logged in Tenant `
            or you might have failed to login";
        }
        return $accessToken;
    }
 
    hidden [void] WaitForDeploymentToComplete([object] $deployment,
                                              [bool] $isSubscriptionDeployment) {
       
        $currentDeployment = $null;
        # loop until the deployment succeeds or fails
        $wait = 10;
        $loop = 0;
        $phase = 1;
        do {
            $loop++;
            Write-Debug "Loop #: $loop";
            # Increment the phase number after
            # 10 loops
            if($loop%10 -eq 0) {
                Write-Debug "Wait phase: $phase, complete";
                # Phase complete
                # new phase:
                $phase += 1;

                # let's increate the wait time
                $wait = ($wait * 2);
                
                Write-Debug "Moving to next wait phase: $phase";
                Write-Debug "New wait time: $wait seconds";
            }
            Write-Debug "Waiting for deployment: $($deployment.Name) to complete. Will check in $wait seconds.";
            Start-Sleep -s $wait;
            
            # Get-AzResourceGroupDeployment will only return minimal details about the deployment
            # This includes the ProvisioningState and DeploymentId
            if ($isSubscriptionDeployment) {
                $currentDeployment = `
                    Get-AzDeployment `
                        -Id $deployment.Id;
            }
            else {
                $currentDeployment = `
                    Get-AzResourceGroupDeployment `
                        -Id $deployment.Id;
            }
        }
        while (@("Running", "Accepted") -match $currentDeployment.ProvisioningState)
        
        if ((($currentDeployment.ProvisioningState -eq "Failed") -or `
            ($currentDeployment.ProvisioningState -eq "Canceled") -or `
            ($currentDeployment.ProvisioningState -eq "Conflict")) -and `
             $isSubscriptionDeployment -eq $false) {
            
            # If the deployment fails, get the deployment details again.
            # But this time, call Get-AzResourceGroupDeploymentOperation, to get the error information which is
            # not available through the Get-AzResourceGroupDeployment AzureRm Cmdlet return object
            $allDeploymentDetails = Get-AzResourceGroupDeploymentOperation -ResourceGroupName $currentDeployment.ResourceGroupName -DeploymentName $currentDeployment.DeploymentName;
            $failedDeploymentDetails = $allDeploymentDetails | ? { $_.Properties.ProvisioningState -eq "Failed" }
            $errorDetails = " $($currentDeployment.DeploymentName) has failed."
            Write-Debug "Error details from resource group deployment: $errorDetails"
            $errorDetails = $this.GetErrorMessage($failedDeploymentDetails);
            Throw $errorDetails;
        }
        elseif ((($currentDeployment.ProvisioningState -eq "Failed") -or `
                ($currentDeployment.ProvisioningState -eq "Canceled") -or `
                ($currentDeployment.ProvisioningState -eq "Conflict")) -and `
                $isSubscriptionDeployment -eq $true) {
            
            # If the deployment fails, get the deployment details again.
            # But this time, call Get-AzResourceGroupDeploymentOperation, to get the error information which is
            # not available through the Get-AzResourceGroupDeployment AzureRm Cmdlet return object
            $allDeploymentDetails = Get-AzDeploymentOperation -DeploymentName $currentDeployment.DeploymentName;
            $failedDeploymentDetails = $allDeploymentDetails | ? { $_.ProvisioningState -eq "Failed" }
            $errorDetails = " $($currentDeployment.DeploymentName) has failed."
            Write-Debug "Error details from subscription deployment: $errorDetails"
            $errorDetails = $this.GetErrorMessage($failedDeploymentDetails);
            Throw $errorDetails;
        }
    }
 
    hidden [string] GetErrorMessage([object] $deploymentDetails) {
 
        $errorDetails = $null;
        # Iterate through all the deployments to retrieve the errors from deployments that have failed
        for($index=0;$index -lt $deploymentDetails.Count; $index++)
        {
            $errorDetail = $deploymentDetails[$index].Properties;
            
            if ($null -eq $errorDetail) {
                # Attempt to retrieve StatusMessage from the root
                $errorDetail = $deploymentDetails[$index];
            }
            
            $message = $errorDetail.statusMessage;
            Write-Debug "Error message is: $message"
            # Loop until details is not found. If the property "details" is not found, then we have hit the object with the message to retrieve.
            $continueTraversingErrorObject = $true;
            while($continueTraversingErrorObject -eq $true) {
                # Iterate until you find an object that does not contain details property of type array.
                # If not found, try to parse the message into a Json.
                # If you cannot parse the message into a Json, that is the innermost exception we are looking for.
                if($message.PSObject.Properties.Name -match "details" -and `
                   $message.details.Count -gt 0){
                    Write-Debug "Found error details"
                    $message = $message.details[0];
                    Write-Debug $message
                }
                elseif($message.PSObject.Properties.Name -match "error"){
                    Write-Debug "Found error message"
                    $message = $message.error;
                    Write-Debug $message
                }
                elseif(Test-JsonContent ((ConvertTo-Json $message -Compress))){
                    $message = ConvertFrom-Json (ConvertTo-Json $message) -Depth 10
                    Write-Host "Initial error message is: $(ConvertTo-Json $message)"
                    $recursive = $true;
                    
                    while ($recursive -eq $true) {
                        if ($null -ne $message.error){
                            Write-Debug "Error: $($message.error)";
                            $message = $message.error;
                        }
                        elseif ($null -ne $message.details -and `
                                $message.details.Count -gt 0) {
                            Write-Debug "Details: $($message.details[0])";
                            $message = $message.details[0];
                        }
                        elseif ($null -ne $message.message) {
                            # Stop when we find a message property
                            Write-Debug "Message: $($message.message)";
                            $recursive = $false;

                            # Let's stop the main recursion
                            $continueTraversingErrorObject = $false;
                        }
                        else {
                            Write-Debug "Stopping all recursions"
                            $recursive = $false;

                            # Let's stop the main recursion
                            $continueTraversingErrorObject = $false;
                        }
                    }
                }
                else {
                    Write-Debug "Let's check if is a valid Json message"
                    $continueTraversingErrorObject = $this.IsMessageAValidJson([ref]$message);
                    Write-Debug $message
                }
            }
            # Double line breaks are for formatting purpose only
            $errorDetails += "`r`n`r`n";
            $errorDetails += "----------------------------------------------------------------------";
            $errorDetails += "`r`n`r`n";
            $errorDetails += "$($message.message)";
        }
        return $errorDetails;
    }
 
    hidden [hashtable] RetrieveDeploymentData([string] $deploymentId,
                                              [string] $deploymentName,
                                              [string] $resourceGroupName,
                                              [string] $subscriptionId,
                                              [bool] $isSubscriptionDeployment) {
 
        # hashtable to store the deployment id and state
        # to be returned
        $dataToReturn = @{
            DeploymentId = $null
            DeploymentName = $null
            ResourceStates = $null
            ResourceIds = $null
            DeploymentOutputs = $null
        };
 
        # set the deployment id value in the data to return
        $dataToReturn.DeploymentId = $deploymentId;
        $dataToReturn.DeploymentName = $deploymentName;
       
        $resourceIds = @();
 
        if ($isSubscriptionDeployment) {
            # Let's get all resource Ids created in a given
            # deployment
            Get-AzDeploymentOperation `
                -DeploymentName $deploymentName `
            | Select TargetResource `
            | ForEach-Object {
                $resourceIds += $_.TargetResource;
            }
        }
        else {
            # Let's get all resource Ids created in a given
            # deployment
            Get-AzResourceGroupDeploymentOperation `
                -Name $deploymentName `
                -ResourceGroupName $resourceGroupName `
                -SubscriptionId $subscriptionId `
            | Select Properties `
            | ForEach-Object {
                $resourceIds += $_.properties.targetResource.id;
            }
        }
 
        # Remove any duplicate ids
        $resourceIds = $resourceIds | Select -Unique
 
        # Convert to JSON resourceIds array.
        $dataToReturn.ResourceIds = $resourceIds;
 
        $resourceStates = @();

        $allResourceIds = @();
        
        # Adding single quotes to resource ids
        $resourceIds | ForEach-Object {
            $allResourceIds += "'$_'" 
        }

        # Adding comma in between array items
        $formattedResourceIds = $allResourceIds -join ",";
        
        Write-Debug "Query to execute is: where id in ($formattedResourceIds)";
        
        $resourceStates = `
                Start-ExponentialBackoff `
                    -Expression { Search-AzGraph -Query "where id in ($formattedResourceIds)"; }
        
        Write-Debug "Resource states from Resource Graph: $(ConvertTo-Json $resourceStates -Depth 10)"
        $dataToReturn.ResourceStates = $resourceStates;
       
        # Let's retrieve deployment outputs
        $resourceGroupInformation = `
            Get-AzResourceGroupDeployment `
                -Id $deploymentId;
       
        # $resourceGroupInformation.Outputs contains a list of custom
        # objects, if one of these objects is a JSON array, the type of it
        # will be a JArray, which is an unknown Powershell type, therefore
        # converting the JArray into a string value (ConvertTo-Json) will 
        # return an empty array, the reason is because 
        # ConvertTo-Json doesn't know how to treat a JArray. The solution
        # is to check the object's type and if is an Array, the code
        # should create a Powershell array object by using @() syntax. 
        # Call Format-DeploymentOutputs function, this function
        # will analyze if there are arrays as outputs, if yes
        # the function will create a Powershell array.
        $dataToReturn.DeploymentOutputs = `
            Format-DeploymentOutputs `
                -DeploymentOutputs $resourceGroupInformation.Outputs;
       
        return $dataToReturn;
    }
 
    hidden [bool] IsMessageAValidJson($message) {
        try {
            $Message.Value = ConvertFrom-Json $Message.Value.message -ErrorAction Stop;
            $validJson = $true;
        } catch {
            $validJson = $false;
        }
        return $validJson;
    }
 
    [void] CreateResourceGroup([string] $resourceGroupName,
                               [string] $location,
                               [object] $tags) {
        try {
            $resourceGroupFound = `
                Get-AzResourceGroup $resourceGroupName `
                    -ErrorAction SilentlyContinue;
            
            # Convert the object to hashtable
            $tags = `
                ConvertTo-HashTable -InputObject $tags;
            
            if($null -eq $resourceGroupFound) {
                Start-ExponentialBackoff `
                    -Expression { New-AzResourceGroup `
                                    -Name $resourceGroupName `
                                    -Location $location `
                                    -Tag $tags `
                                    -Force; }
            }
        }
        catch {
            Write-Host "An error ocurred while running CreateResourceGroup";
            Write-Host $_;
            throw $_;
        }
    }

    [void] SetSubscriptionContext([guid] $subscriptionId,
                                  [guid] $tenantId) {
        try {
            Start-ExponentialBackoff `
            -Expression { Select-AzSubscription `
                            -Subscription $subscriptionId `
                            -Tenant $tenantId; }
        }
        catch {
            Write-Host "An error ocurred while running SetSubscriptionContext";
            Write-Host $_;
            throw $_;
        }
    }

    [void] RemoveResourceGroupLock([guid] $subscriptionId,
                                   [string] $resourceGroupName) {
        try {
            $scope = "/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName"
            $allLocks = Get-AzResourceLock -Scope $scope -ErrorAction SilentlyContinue | Where-Object "ProvisioningState" -ne "Deleting"

            if ($null -ne $allLocks) {
                $allLocks | ForEach-Object { Remove-AzResourceLock -LockId $_.ResourceId -Force -ErrorAction SilentlyContinue }
            }
        }
        catch {
            Write-Host "An error ocurred while running RemoveResourceGroupLock";
            Write-Host $_;
            throw $_;
        }
    }

    [void] RemoveResourceGroup([guid] $subscriptionId,
                               [string] $resourceGroupName) {
        try {
            $id = "/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName"
            $resourceGroup = $this.GetResourceGroup($subscriptionId, $resourceGroupName)
            if ($null -ne $resourceGroup) {
                Remove-AzResourceGroup -Id $id -Force -ErrorAction SilentlyContinue -AsJob
            }
        }
        catch {
            Write-Host "An error ocurred while running RemoveResourceGroup";
            Write-Host $_;
            throw $_;
        }
    }

    [object] GetResourceGroup([guid] $subscriptionId,
                              [string] $resourceGroupName) {
        try {
            return `
                Get-AzResourceGroup `
                    -Id "/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName" `
                    -ErrorAction SilentlyContinue
        }
        catch {
            Write-Host "An error ocurred while running GetResourceGroup";
            Write-Host $_;
            throw $_;
        }
    }

    hidden [void] SetAzureEnvironmentBasedManagementUrls([string] $mngtUrl)
    {
        if(![string]::IsNullOrEmpty($mngtUrl)) {
            $this.armResourceGroupDeploymentUri = $mngtUrl + "/subscriptions/{0}/resourcegroups/{1}/providers/Microsoft.Resources/deployments/{2}?api-version=2019-05-10";
            $this.armSubscriptionDeploymentUri = $mngtUrl + "/subscriptions/{0}/providers/Microsoft.Resources/deployments/{1}?api-version=2019-05-10";
            $this.armResourceGroupValidationUri = $mngtUrl + "/subscriptions/{0}/resourcegroups/{1}/providers/Microsoft.Resources/deployments/{2}/validate?api-version=2019-05-10";
            $this.armSubscriptionValidationUri = $mngtUrl + "/subscriptions/{0}/providers/Microsoft.Resources/deployments/{1}/validate?api-version=2019-05-10";
        }
        else
        {
            $this.armResourceGroupDeploymentUri = "https://management.azure.com/subscriptions/{0}/resourcegroups/{1}/providers/Microsoft.Resources/deployments/{2}?api-version=2019-05-10";
            $this.armSubscriptionDeploymentUri = "https://management.azure.com/subscriptions/{0}/providers/Microsoft.Resources/deployments/{1}?api-version=2019-05-10";
            $this.armResourceGroupValidationUri = "https://management.azure.com/subscriptions/{0}/resourcegroups/{1}/providers/Microsoft.Resources/deployments/{2}/validate?api-version=2019-05-10";
            $this.armSubscriptionValidationUri = "https://management.azure.com/subscriptions/{0}/providers/Microsoft.Resources/deployments/{1}/validate?api-version=2019-05-10";
        }

        Write-Debug "Management URL: $mngtUrl";
    }
}