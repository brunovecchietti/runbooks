param(
	[parameter(Mandatory=$true)] [String] $SqlUserCredName,
	[parameter(Mandatory=$true)] [String] $StorageCredName,
	[parameter(Mandatory=$true)] [String] $SubscriptionName,
    [parameter(Mandatory=$true)] [String] $ResourceGroupName,
    [parameter(Mandatory=$true)] [String] $DatabaseServerName,
	[parameter(Mandatory=$true)] [String] $DatabaseName,	
	[parameter(Mandatory=$true)] [String] $StorageAccountName,
    [parameter(Mandatory=$true)] [String] $BlobStorageEndpoint,
	[parameter(Mandatory=$true)] [string] $BlobContainerName
)

$SqlUserCred = Get-AutomationPSCredential -Name $sqlUserCredName
$DatabaseAdminUsername = $sqlUserCred.UserName
$SecurePassword = $sqlUserCred.Password
$DatabaseAdminPassword = $sqlUserCred.GetNetworkCredential().Password

$StorageCred = Get-AutomationPSCredential -Name $StorageCredName
$SecurePassword = $storageCred.Password
$StorageKey = $storageCred.GetNetworkCredential().Password

function Login() {

    Write-Output "Log In"
	
	try
	{
		Connect-AzAccount -Identity -Subscription $SubscriptionName
	}
	catch {
		Write-Error -Message $_.Exception
		throw $_.Exception
	}
}

function Delete-Old-Backups([string]$blobContainerName, $storageContext) {
	
    Write-Output "Removing backups from blob: '$blobContainerName'"
    Write-Output ""

	$isOldDate = [DateTime]::UtcNow.AddDays(-$retentionDays)
	$blobs = Get-AzureStorageBlob -Container $blobContainerName -Context $storageContext

	foreach ($blob in ($blobs | Where-Object { $_.BlobType -eq "BlockBlob" })) {
		Write-Output ("Removing blob: " + $blob.Name)
        Write-Output ""
		Remove-AzureStorageBlob -Blob $blob.Name -Container $blobContainerName -Context $storageContext
	}
}

function Export-To-Blob-Storage([string]$resourceGroupName, [string]$databaseServerName, [string]$databaseAdminUsername, [string]$databaseAdminPassword, [string]$databaseName, [string]$storageKey, [string]$blobStorageEndpoint, [string]$blobContainerName) {
	
    Write-Output "Starting database backup"
    Write-Output ""

	$securePassword = ConvertTo-SecureString –String $databaseAdminPassword –AsPlainText -Force 
	$creds = New-Object –TypeName System.Management.Automation.PSCredential –ArgumentList $databaseAdminUsername, $securePassword

	Write-Output "Creating request to export database '$databaseName'"
    Write-Output ""

	$bacpacFilename = $databaseName + (Get-Date).ToString("yyyyMMddHHmm") + ".bacpac"
	$bacpacUri = $blobStorageEndpoint + $blobContainerName + "/" + $bacpacFilename

	$exportRequest = New-AzSqlDatabaseExport `
		-ResourceGroupName $resourceGroupName `
		–ServerName $databaseServerName `
		–DatabaseName $databaseName `
		–StorageKeytype "StorageAccessKey" `
		–storageKey $storageKey `
		-StorageUri $BacpacUri `
        -AuthenticationType "AdPassword" `
		–AdministratorLogin $creds.UserName `
		–AdministratorLoginPassword $creds.Password `
		-ErrorAction "Stop"
	
	$exportStatus = Get-AzSqlDatabaseImportExportStatus -OperationStatusLink $exportRequest.OperationStatusLink

    Write-Output "Exporting ..."
    Write-Output ""

    while ($exportStatus.Status -eq "InProgress") {
        Start-Sleep -s 60
        $exportStatus = Get-AzSqlDatabaseImportExportStatus -OperationStatusLink $exportRequest.OperationStatusLink   
        $exportStatus.StatusMessage
    }

    if ($exportStatus.StatusMessage -eq "Completed") {
        $exportStatus
    }
    else {
        Write-Output "Revoke permissions to backup user"    
        Invoke-SqlCmd -ServerInstance $fullServerName -Database $databaseName -AccessToken $access_token.token -Query 'ALTER ROLE db_owner DROP MEMBER [db_backupoperator@cloud.terra.insure]'     
        Throw "Error exporting database"	
    }
    
}

$StorageContext = New-AzureStorageContext -StorageAccountName $storageAccountName -StorageAccountKey $storageKey

Login

$access_token = Get-AzAccessToken -ResourceUrl "https://database.windows.net/"
$fullServerName = $databaseServerName + ".database.windows.net"

Write-Output ""
Write-Output "Grant permissions to backup user"
Write-Output ""

Invoke-SqlCmd -ServerInstance $fullServerName -Database $databaseName -AccessToken $access_token.token -Query 'ALTER ROLE db_owner ADD MEMBER [db_backupoperator@cloud.terra.insure]' 

Delete-Old-Backups `
	-storageContext $StorageContext `
	-blobContainerName $BlobContainerName

Export-To-Blob-Storage `
	-resourceGroupName $ResourceGroupName `
	-databaseServerName $DatabaseServerName `
	-databaseAdminUsername $DatabaseAdminUsername `
	-databaseAdminPassword $DatabaseAdminPassword `
	-databaseName $DatabaseName `
	-storageKey $StorageKey `
	-blobStorageEndpoint $BlobStorageEndpoint `
	-blobContainerName $BlobContainerName

Write-Output "Revoke permissions to backup user"    

Invoke-SqlCmd -ServerInstance $fullServerName -Database $databaseName -AccessToken $access_token.token -Query 'ALTER ROLE db_owner DROP MEMBER [db_backupoperator@cloud.terra.insure]'     
	
Write-Verbose "Database backup script finished" -Verbose