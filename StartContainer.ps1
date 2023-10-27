function Login() {
	
	try
	{
		Connect-AzAccount -Identity -Tenant '9ba01adb-d315-4fe1-b776-a5870167b2d2' -Subscription 'cee51a66-31cb-48b4-9f1d-829d356e6d07'
	}
	catch {
		Write-Error -Message $_.Exception
		throw $_.Exception
	}
}

Login

Start-AzContainerGroup -Name 'rclone' -ResourceGroupName 'DBAdmin'