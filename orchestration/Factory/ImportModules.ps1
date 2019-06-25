$rootPath = Split-Path -Path $MyInvocation.MyCommand.Definition -Parent

$modulePath = Join-Path $rootPath -ChildPath '..' -AdditionalChildPath @('RepositoryService', 'Interface', 'IStateRepository.ps1');
$scriptBlock = ". $modulePath";
$script = [scriptblock]::Create($scriptBlock);
. $script;
$modulePath = Join-Path $rootPath -ChildPath '..' -AdditionalChildPath @('RepositoryService', 'Implementations', 'BlobContainerStateRepository.ps1');
$scriptBlock = ". $modulePath";
$script = [scriptblock]::Create($scriptBlock);
. $script;
$modulePath = Join-Path $rootPath -ChildPath '..' -AdditionalChildPath @('RepositoryService', 'Interface', 'IAuditRepository.ps1');
$scriptBlock = ". $modulePath";
$script = [scriptblock]::Create($scriptBlock);
. $script;
$modulePath = Join-Path $rootPath -ChildPath '..' -AdditionalChildPath @('RepositoryService', 'Implementations', 'BlobContainerAuditRepository.ps1');
$scriptBlock = ". $modulePath";
$script = [scriptblock]::Create($scriptBlock);
. $script;
$modulePath = Join-Path $rootPath -ChildPath '..' -AdditionalChildPath @('RepositoryService', 'Implementations', 'LocalStorageStateRepository.ps1');
$scriptBlock = ". $modulePath";
$script = [scriptblock]::Create($scriptBlock);
. $script;
$modulePath = Join-Path $rootPath -ChildPath '..' -AdditionalChildPath @('RepositoryService', 'Implementations', 'LocalStorageAuditRepository.ps1');
$scriptBlock = ". $modulePath";
$script = [scriptblock]::Create($scriptBlock);
. $script;
$modulePath = Join-Path $rootPath -ChildPath '..' -AdditionalChildPath @('RepositoryService', 'Interface', 'ICacheRepository.ps1');
$scriptBlock = ". $modulePath";
$script = [scriptblock]::Create($scriptBlock);
. $script;
$modulePath = Join-Path $rootPath -ChildPath '..' -AdditionalChildPath @('RepositoryService', 'Implementations', 'AzureDevOpsCacheRepository.ps1');
$scriptBlock = ". $modulePath";
$script = [scriptblock]::Create($scriptBlock);
. $script;
$modulePath = Join-Path $rootPath -ChildPath '..' -AdditionalChildPath @('RepositoryService', 'Implementations', 'LocalCacheRepository.ps1');
$scriptBlock = ". $modulePath";
$script = [scriptblock]::Create($scriptBlock);
. $script;
$modulePath = Join-Path $rootPath -ChildPath '..' -AdditionalChildPath @('DataService', 'Interface', 'IModuleStateDataService.ps1');
$scriptBlock = ". $modulePath";
$script = [scriptblock]::Create($scriptBlock);
. $script;
$modulePath = Join-Path $rootPath -ChildPath '..' -AdditionalChildPath @('DataService', 'Implementations', 'ModuleStateDataService.ps1');
$scriptBlock = ". $modulePath";
$script = [scriptblock]::Create($scriptBlock);
. $script;
$modulePath = Join-Path $rootPath -ChildPath '..' -AdditionalChildPath @('DataService', 'Interface', 'IDeploymentAuditDataService.ps1');
$scriptBlock = ". $modulePath";
$script = [scriptblock]::Create($scriptBlock);
. $script;
$modulePath = Join-Path $rootPath -ChildPath '..' -AdditionalChildPath @('DataService', 'Implementations', 'DeploymentAuditDataService.ps1');
$scriptBlock = ". $modulePath";
$script = [scriptblock]::Create($scriptBlock);
. $script;
$modulePath = Join-Path $rootPath -ChildPath '..' -AdditionalChildPath @('DataService', 'Interface', 'ICacheDataService.ps1');
$scriptBlock = ". $modulePath";
$script = [scriptblock]::Create($scriptBlock);
. $script;
$modulePath = Join-Path $rootPath -ChildPath '..' -AdditionalChildPath @('DataService', 'Implementations', 'CacheDataService.ps1');
$scriptBlock = ". $modulePath";
$script = [scriptblock]::Create($scriptBlock);
. $script;
$modulePath = Join-Path $rootPath -ChildPath '..' -AdditionalChildPath @('IntegrationService', 'Interface', 'IDeploymentService.ps1');
$scriptBlock = ". $modulePath";
$script = [scriptblock]::Create($scriptBlock);
. $script;
$modulePath = Join-Path $rootPath -ChildPath '..' -AdditionalChildPath @('IntegrationService', 'Implementations', 'AzureResourceManagerDeploymentService.ps1');
$scriptBlock = ". $modulePath";
$script = [scriptblock]::Create($scriptBlock);
. $script;

$modulePath = Join-Path $rootPath -ChildPath '..' -AdditionalChildPath @('TokenReplacementService', 'Interface', 'ITokenReplacementService.ps1');
$scriptBlock = ". $modulePath";
$script = [scriptblock]::Create($scriptBlock);
. $script;

$modulePath = Join-Path $rootPath -ChildPath '..' -AdditionalChildPath @('TokenReplacementService', 'Implementations', 'TokenReplacementService.ps1');
$scriptBlock = ". $modulePath";
$script = [scriptblock]::Create($scriptBlock);
. $script;

$modulePath = Join-Path $rootPath -ChildPath '..' -AdditionalChildPath @('OrchestrationService', 'ConfigurationBuilder.ps1');
$scriptBlock = ". $modulePath";
$script = [scriptblock]::Create($scriptBlock);
. $script;

$modulePath = Join-Path $rootPath -ChildPath '..' -AdditionalChildPath @('OrchestrationService', 'ValidationResourceGroupSetup.ps1');
$scriptBlock = ". $modulePath";
$script = [scriptblock]::Create($scriptBlock);
. $script;