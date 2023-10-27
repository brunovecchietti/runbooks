param(
    [parameter(Mandatory=$true)] [String] $SubscriptionName,
	[parameter(Mandatory=$true)] [String] $ServerName,
	[parameter(Mandatory=$true)] [String] $databaseName	
)

function Login() {
	
	try
	{
		Connect-AzAccount -Identity -Subscription $SubscriptionName
		
		
	}
	catch {
		Write-Error -Message $_.Exception
		throw $_.Exception
	}
}

Login

$access_token = Get-AzAccessToken -ResourceUrl "https://database.windows.net/"

Write-Output ""
Write-Output "EXECUTE IndexOptimize on $ServerName/$databaseName"
Write-Output ""

try
{
    Invoke-SqlCmd -ServerInstance $ServerName -Database $databaseName -AccessToken $access_token.token -Query 'EXECUTE dbo.IndexOptimize @Databases = ''USER_DATABASES'', @MinNumberOfPages = 0, @UpdateStatistics = ''ALL'', @OnlyModifiedStatistics = ''Y''' 
}
catch {
    Write-Error -Message $_.Exception
    throw $_.Exception
}