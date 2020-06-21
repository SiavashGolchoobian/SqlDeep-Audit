# sqldeep.com
# Author: golchoobian@sqldeep.com
#--------------------------------------------------------------Parameters.
Param(
	[switch]$UI, #Use interactive mode
	[switch]$ODBC, #Use ODBC driver for logging counters
    [string]$ServerName, #the server name to monitor (default is $env:COMPUTERNAME)
    [PSCredential]$PerfmonCred, #Perfmon credential
	[string]$ServerFilePath, #the Server wide counter config file path
	[string]$InstanceFilePath, #the Instance wide counter config file path
	[string]$ODBCName, #ODBC DSN name of Target MSSQL To storing Perfmon Data Collector (default is DBA)
    [string]$SqlServerInstance, #Target SQL Instance FQDN To storing Perfmon Data Collector
    [string]$SqlServerInstanceDB, #Database name of Target MSSQL To storing Perfmon Data Collector (default is DBA)
	[PSCredential]$SqlServerInstanceCred #ODBC related Credential for connecting to specified SQL Server Instance
    )
	
#--------------------------------------------------------------Functions start here.
#Retrun first Left characters of input text
Function Left
{
    Param
        (
        [Parameter(Mandatory=$true)][string]$Text,
        [Parameter(Mandatory=$true)][int]$Length
        )
    $Left = $Text.SubString(0, [math]::min($Length,$Text.length))
    return $Left
}

#Retrun first Rightt characters of input text
Function Right
{
    Param
        (
        [Parameter(Mandatory=$true)][string]$Text,
        [Parameter(Mandatory=$true)][int]$Length
        )
    $startchar = [math]::min($Text.length - $Length,$Text.length)
    $startchar = [math]::max(0, $startchar)
    $Right = $text.SubString($startchar ,[math]::min($Text.length, $Length))
    return $Right
}

#Raise Warning message and if required exit from app
Function RaiseMessage
{
    Param
        (
        [Parameter(Mandatory=$true)][string]$Message,
        [switch]$Info,
        [switch]$Warning,
        [switch]$Error,
        [switch]$Exit
        )

    If($Warning) 
        {Write-Host $Message -ForegroundColor Yellow}
    ElseIf($Error) 
        {Write-Host $Message -ForegroundColor Red}
    Else
        {Write-Host $Message -ForegroundColor Green}

    If ($Exit){Exit}
}

# Create ODBC Driver
Function CreateODBC
{
    Param
        (
        [Parameter(Mandatory=$true)][string]$ODBCName,
        [Parameter(Mandatory=$true)][string]$SqlServerInstance,
        [Parameter(Mandatory=$true)][string]$SqlServerInstanceDB
        )

    try
    {
        $RootPath = "HKLM:\SOFTWARE\ODBC\ODBC.INI" 
        If(!(Test-Path "$RootPath\$ODBCName"))
        {
	        New-Item $RootPath -Name $ODBCName | Out-Null
        }
        if (!(Test-Path "$RootPath\ODBC Data Sources"))
        {
	        New-Item $RootPath -Name "ODBC Data Sources" | Out-Null
        }
        New-ItemProperty -Path "$RootPath\ODBC Data Sources" -Name $ODBCName -PropertyType String -Value "SQL Server"  -Force | Out-Null
        New-ItemProperty -Path $RootPath\$ODBCName -Name "Database" -PropertyType String -Value $SqlServerInstanceDB  -Force | Out-Null
        New-ItemProperty -Path $RootPath\$ODBCName -Name "Driver" -PropertyType String -Value "C:\Windows\system32\SQLSRV32.dll"  -Force | Out-Null
        New-ItemProperty -Path $RootPath\$ODBCName -Name "LastUser" -PropertyType String -Value "SQL_Monitor"  -Force | Out-Null
        New-ItemProperty -Path $RootPath\$ODBCName -Name "Server" -PropertyType String -Value $SqlServerInstance  -Force | Out-Null
        New-ItemProperty -Path $RootPath\$ODBCName -Name "Trusted_Connection" -PropertyType String -Value "Yes"  -Force | Out-Null           
    }
    catch
    {
        RaiseMessage -Message "Exception caught: $_.Exception" -Error -Exit
        return
    }
}

# Create directories if they do not exist.
Function CreateDirectory 
{
    Param
        (
        [Parameter(Mandatory=$true)][string]$Server,
        [Parameter(Mandatory=$true)][string]$SubDir
        )

    Invoke-Command -ComputerName $Server -ArgumentList $SubDir -ScriptBlock {
        Param($SubDir)
        If (!(Test-Path -PathType Container $SubDir))
        {
            New-Item -ItemType Directory -Path $SubDir | Out-Null
        }
    }
}

#Create Data Collector Set
Function CreateDataCollectorSet
{
    Param
        (
        [Parameter(Mandatory=$true)][string]$Server,
        [Parameter(Mandatory=$true)][string]$DataCollectorSetName,
        [Parameter(Mandatory=$true)][string]$PerfmonLogPath
        )
    
    try
    {
        CreateDirectory -Server "$Server" -SubDir "$PerfmonLogPath" #Create $PerfmonLogPath directory f not existed.
        $myDataCollectorSet = New-Object -ComObject Pla.DataCollectorSet # DataCollectorSet Check and Creation
        $myDataCollectorSet.DisplayName = $DataCollectorSetName #display name of the data collector set.
        $myDataCollectorSet.Description = "Capture counters used for database performance troubleshootng."
        $myDataCollectorSet.Duration = 0 #duration that the data collector set runs, 0 for non-stop running
        $myDataCollectorSet.RootPath = $PerfmonLogPath #base path where the subdirectories are created
        $myDataCollectorSet.LatestOutputLocation = $PerfmonLogPath #fully decorated folder name that PLA used the last time logs were written.
        $myDataCollectorSet.SchedulesEnabled = -1 #indicates whether the schedules are enabled.
        $myDataCollectorSet.Segment = $true # indicates whether PLA creates new logs if the maximum size or segment duration is reached before the data collector set is stopped.
        $myDataCollectorSet.SegmentMaxDuration = 86400 #duration that the data collector set can run before it begins writing to new log files (sec), 24 Hour.
        $myDataCollectorSet.SegmentMaxSize = 0 #maximum size of any log file in the data collector set.
        $myDataCollectorSet.SerialNumber = 10 #number of times that this data collector set has been started, including segments.
        $myDataCollectorSet.SubdirectoryFormat = 1 #describe how to decorate the subdirectory name. 1 is plaPattern or empty pattern, but use the $PerfmonLogPath (https://docs.microsoft.com/en-us/windows/win32/api/pla/ne-pla-autopathformat)
        $myDataCollectorSet.StopOnCompletion = 0 #determines whether the data collector set stops when all the data collectors in the set are in a completed state.
        return $myDataCollectorSet
    }
    catch
    {
        RaiseMessage -Message "Exception caught: $_.Exception" -Error -Exit
        return
    }
}

#Create Data Collector
Function CreateDataCollector
{
    Param
        (
        [Parameter(Mandatory=$true)][System.Object]$DataCollectorSet,
        [Parameter(Mandatory=$true)][string]$DataCollectorName,
        [Parameter(Mandatory=$true)][string]$ConfigFile,
        [Parameter(Mandatory=$false)][string]$ODBCName,
        [Parameter(Mandatory=$false)][string]$InstanceName
        )

     If (!($InstanceName))
     {
        $myXML = Get-Content $ConfigFile
     }
     ELSE
     {
        $myXML = (Get-Content $ConfigFile) -replace "%instance%", $InstanceName
     }
     $myDataCollector = $DataCollectorSet.DataCollectors.CreateDataCollector(0)
     $myDataCollector.Name = $DataCollectorName #name of the data collector.
     $myDataCollector.FileName = $DataCollectorName + "_"; #base name of the file that will contain the data collector data.
     $myDataCollector.FileNameFormat = 3; #flags that describe how to decorate the file name.
     $myDataCollector.FileNameFormatPattern = "yyyyMMddHHmm"; #the format pattern to use when decorating the file name.
     $myDataCollector.SampleInterval = 15;
     $myDataCollector.SetXML($myXML);
     If ($ODBCName)
     {
         $myDataCollector.LogFileFormat = 2; #PlaSql
	     $myDataCollector.LatestOutputLocation = "SQL:$ODBCName!$DataCollectorName"
         $myDataCollector.DataSourceName = "$ODBCName"
     }
     else
     {
         $myDataCollector.LogFileFormat = 3; #plaBinary
     }
     $DataCollectorSet.DataCollectors.Add($myDataCollector)
}

#Commit Data Collector Set Changes
Function CommitChanges
{
    Param
        (
        [Parameter(Mandatory=$true)][string]$Server,
        [Parameter(Mandatory=$true)][System.Object]$DataCollectorSet,
        [Parameter(Mandatory=$true)][string]$DataCollectorSetName,
        [Parameter(Mandatory=$true)][System.Object]$PerfmonCredential
        )

    try #Commit changes
    {
        if($PerfmonCredential -ne $null) #Bind Credebtial to DataCollectorSet
        {
            $DataCollectorSet.SetCredentials("$($PerfmonCredential.UserName)","$($PerfmonCredential.GetNetworkCredential().Password)") #user account under which the data collector set runs.
        }
        $DataCollectorSet.Commit($DataCollectorSetName,$Server,3) | Out-Null  #3 is plaCreateOrModify
        $DataCollectorSet.Query($DataCollectorSetName,$Server) #refresh with updates (Retrieves the specified data collector set.).
    }
    catch
    {
        RaiseMessage -Message "Exception caught: $_.Exception" -Error -Exit
        return
    }
}

#Check Data Collector existance
Function CheckDataCollector
{
    Param
        (
        [Parameter(Mandatory=$true)][System.Object]$DataCollectorSet,
        [Parameter(Mandatory=$true)][string]$DataCollectorName
        )

    # Check if the data collector exists in the DataCollectorSet
    If (($DataCollectorSet.DataCollectors | Select Name) -match $DataCollectorName) 
        { Return $true } 
    ELSE
        { Return $false } 
}

#Return list of SQL Server instances
Function Get-SqlInstances {
    Param
        (
        [Parameter(Mandatory=$true)][string]$Server
        )
 
  $myInstances = @()
  [array]$captions = gwmi win32_service -computerName $Server | ?{$_.Caption -match "SQL Server*" -and $_.PathName -match "sqlservr.exe"} | %{$_.Caption}
  foreach ($caption in $captions) 
  {
    If ($caption -eq "MSSQLSERVER") 
        {$myInstances += "MSSQLSERVER"}
    ELSE
        {$myInstances += $caption | %{$_.split(" ")[-1]} | %{$_.trimStart("(")} | %{$_.trimEnd(")")}}
  }
  return $myInstances
}

#--------------------------------------------------------------Collecting required parameters via console
$myODBCFeature=$ODBC
$myDCSName="SqlDeep"
$myRootXMLPath=If ((Right -Text "$PSScriptRoot" -Length 2) -eq ":\") {"$PSScriptRoot"} else {"$PSScriptRoot\"}
$myRootXMLPathOfServer="$myRootXMLPath" + "SqlDeepAudit-Server.xml"
$myRootXMLPathOfInstance="$myRootXMLPath" + "SqlDeepAudit-Instance.xml"
$myDefaultServerName="$env:COMPUTERNAME"
$myDefaultServerFilePath=$myRootXMLPathOfServer
$myDefaultInstanceFilePath=$myRootXMLPathOfInstance
$myDefaultODBCName="DBA"
$myDefaultSqlServerInstance="$env:COMPUTERNAME"
$myDefaultSqlServerInstanceDB="DBA"

If ($UI)
{
    $ServerName=Read-Host -Prompt "Enter the server name to monitor (default is $myDefaultServerName)"
    $PerfmonCred=Get-Credential -Message "Perfmon Credential"
    $ServerFilePath=Read-Host -Prompt "Enter the Server wide counter config file path (default is $myDefaultServerFilePath)"
    $InstanceFilePath=Read-Host -Prompt "Enter the Instance wide counter config file path (default is $myDefaultInstanceFilePath)"
    If ($myODBCFeature)
    {
        $ODBCName=Read-Host -Prompt "ODBC DSN name of Target MSSQL To storing Perfmon Data Collector (default is $myDefaultODBCName)"
        $SqlServerInstance=Read-Host -Prompt "ODBC related SQL Instance address to storing Perfmon Data Collector (server\instance default is $myDefaultSqlServerInstance)"
        $SqlServerInstanceDB=Read-Host -Prompt "ODBC related database name to storing Perfmon Data Collector (default is $myDefaultSqlServerInstanceDB)"
        $SqlServerInstanceCred=Get-Credential -Message "ODBC related Credential for connecting to specified SQL Server Instance"
    }
}

If(-not($ServerName)) {$ServerName=$myDefaultServerName}
If(-not($ServerFilePath)) {$ServerFilePath=$myDefaultServerFilePath}
If(-not($InstanceFilePath)) {$InstanceFilePath=$myDefaultServerFilePath}
If (!($PerfmonCred) -and ($PerfmonCred.UserName).Length>0)
{
    $myUser=$PerfmonCred.UserName
    $PerfmonCred=Get-Credential -UserName $myUser -Message "Perfmon Credential"
}
If ($myODBCFeature)
{
    If(-not($ODBCName)) {$ODBCName=$myDefaultODBCName}
    If(-not($SqlServerInstance)) {$SqlServerInstance=$myDefaultSqlServerInstance}
    If(-not($SqlServerInstanceDB)) {$SqlServerInstanceDB=$myDefaultSqlServerInstanceDB}
    If(!($SqlServerInstanceCred) -and ($SqlServerInstanceCred.UserName).Length>0)
    {
        $myUser=$SqlServerInstanceCred.UserName
        $SqlServerInstanceCred=Get-Credential -UserName $myUser -Message "ODBC related Credential for connecting to specified SQL Server Instance"
    }
}


#--------------------------------------------------------------Main Body
RaiseMessage -Message "==========Perfmon Informtion==========" -Info
RaiseMessage -Message "ServerName: $ServerName" -Info
RaiseMessage -Message "PerfmonCred: $($PerfmonCred.UserName)" -Info
RaiseMessage -Message "ServerFilePath: $ServerFilePath" -Info
RaiseMessage -Message "InstanceFilePath: $InstanceFilePath" -Info
RaiseMessage -Message "ODBCName: $ODBCName" -Info
RaiseMessage -Message "SqlServerInstance: $SqlServerInstance" -Info
RaiseMessage -Message "SqlServerInstanceDB: $SqlServerInstanceDB" -Info
RaiseMessage -Message "SqlServerInstanceCred: $($SqlServerInstanceCred.UserName)" -Info
RaiseMessage -Message "=====================================" -Info

#Validating input parameters
If(-not($PerfmonCred)) {RaiseMessage -Message "Perfmon credential is missing" -Error -Exit}
If(($myODBCFeature) -and -not($SqlServerInstanceCred)) {RaiseMessage -Message "ODBC related Credential for connecting to specified SQL Server Instance is missing" -Error -Exit}
RaiseMessage -Message "Testing $ServerName connection..." -Info
If (!(Test-Connection -ComputerName $ServerName -Quiet)) {RaiseMessage -Message "Specified Server name ($ServerName) does not respond." -Error -Exit}
If (!(Test-Path -PathType Leaf $ServerFilePath)) {RaiseMessage -Message "Server config file path ($ServerFilePath) is invalid." -Error -Exit}
If (!(Test-Path -PathType Leaf $InstanceFilePath)) {RaiseMessage -Message "Instance config file path($InstanceFilePath) is invalid." -Error -Exit}


#Create ODBC connection
If ($myODBCFeature)
{
    RaiseMessage -Message "Creating ODBC connection '$ODBCName'..." -Info
    try
    {
        CreateODBC -ODBCName "$ODBCName" -SqlServerInstance "$SqlServerInstance" -SqlServerInstanceDB "$SqlServerInstanceDB" #Create ODBC Driver
        RaiseMessage -Message "ODBC connection '$ODBCName' is created." -Info
    }
    catch
    {
        RaiseMessage -Message "ODBC connection creation $ODBCName is failed, Exception caught: $_.Exception" -Error -Exit
    }
}

#Create Data Collector set
RaiseMessage -Message "Creating Data Collector Set '$myDCSName'..." -Info
$myDCS = CreateDataCollectorSet -Server "$ServerName" -DataCollectorSetName "$myDCSName" -PerfmonLogPath "C:\Perfmon" #Create Data Collector Set
CommitChanges -Server "$ServerName" -DataCollectorSet $myDCS -DataCollectorSetName "$myDCSName" -PerfmonCredential $PerfmonCred #Commit Data Collector Set changes
RaiseMessage -Message "Data Collector Set '$myDCSName' is created." -Info

#Create Data Collector set schedule
RaiseMessage -Message "Creating Data Collector Set Scheduler..." -Info
Invoke-Command -ComputerName $ServerName -ArgumentList ($myDCSName,$PerfmonCred) -ScriptBlock {
    Param($myDCSName,$PerfmonCred)
    $Trigger = @()
    #Start when server starts.
    $Trigger += New-ScheduledTaskTrigger -AtStartup
    #Restart Daily at 5AM. Note: I have not used Segments.
    $Trigger += New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday,Tuesday,Wednesday,Thursday,Friday,Saturday,Sunday -at 05:00
    $Path = (Get-ScheduledTask -TaskName $myDCSName).TaskPath
    #This setting in the Windows Scheduler forces the existing Data Collector Set to stop, and a new one to start
    $StopExisting = New-ScheduledTaskSettingsSet
    $StopExisting.CimInstanceProperties['MultipleInstances'].Value=3
    $myUser=$PerfmonCred.UserName
    $myPassword=[Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($PerfmonCred.password))
    Set-ScheduledTask -TaskName $myDCSName -TaskPath $Path -Trigger $Trigger -Settings $StopExisting -User $myUser -Password $myPassword | Out-Null
}
#$myDCS.Query($myDCSName,$ServerName) #refresh with updates.
RaiseMessage -Message "Data Collector Set Scheduler is created." -Info

#Create Server wide Data Collector
$myDCName = "$myDCSName-Server Audit"
# If the Data Collector does not exist, create it!
If (!(CheckDataCollector -DataCollectorSet $myDCS -DataCollectorName $myDCName)) 
{
    RaiseMessage -Message "Creating server wide Data Collector set '$myDCName'..." -Info
    If ($myODBCFeature)
    {
        CreateDataCollector -DataCollectorSet $myDCS -DataCollectorName $myDCName -ConfigFile $ServerFilePath -ODBCName $ODBCName
    }
    else
    {
        CreateDataCollector -DataCollectorSet $myDCS -DataCollectorName $myDCName -ConfigFile $ServerFilePath
    }
    CommitChanges -Server "$ServerName" -DataCollectorSet $myDCS -DataCollectorSetName $myDCSName -PerfmonCredential $PerfmonCred  #Commit Data Collector Set changes
    RaiseMessage -Message "Server wide Data Collector '$myDCSName' is created." -Info
}


#Create SQL Instance wide Data Collector
$myInstances = Get-SQLInstances -Server $ServerName
foreach ($myInstance in $myInstances) 
{
    If ($myInstance -eq "MSSQLSERVER") {
        $myReplaceString = "SQLServer";
        }
        ELSE {
        $myReplaceString = "MSSQL`$$myInstance"; 
        }
    $myDCName = "$myDCSName-$myInstance";
    If (!(CheckDataCollector -DataCollectorSet $myDCS -DataCollectorName $myDCName))
    {
        RaiseMessage -Message "Creating SQL instance wide data collector set '$myDCName'..." -Info
        If ($myODBCFeature)
        {
            CreateDataCollector -DataCollectorSet $myDCS -DataCollectorName $myDCName -ConfigFile $InstanceFilePath -ODBCName $ODBCName -InstanceName $myReplaceString
        }
        Else
        {
            CreateDataCollector -DataCollectorSet $myDCS -DataCollectorName $myDCName -ConfigFile $InstanceFilePath -InstanceName $myReplaceString
        }
        CommitChanges -Server "$ServerName" -DataCollectorSet $myDCS -DataCollectorSetName $myDCSName -PerfmonCredential $PerfmonCred  #Commit Data Collector Set changes
        RaiseMessage -Message "SQL instance wide data collector set '$myDCName' is created." -Info
    }
}

#Set Data Collector set scheduler to run with 1 minute delay after server reboot
$myInterval = (New-TimeSpan -Minutes 2)
$myScheduledTask = Get-ScheduledTask -TaskName $myDCSName
$myScheduledTarget = New-ScheduledTaskTrigger -AtStartup
$myScheduledTarget.Delay = "PT2M"
$myScheduledSettingSet = New-ScheduledTaskSettingsSet -RestartCount 10 -RestartInterval $myInterval
Set-ScheduledTask -TaskName $myDCSName -TaskPath $myScheduledTask.TaskPath -Trigger $myScheduledTarget -Settings $myScheduledSettingSet -User $PerfmonCred.UserName -Password $PerfmonCred.GetNetworkCredential().Password

#Start the data collector set.
try 
{
    If ($myDCS.Status -eq 0) 
    {
        RaiseMessage -Message "Starting Data Collector Set '$myDCSName' ..." -Info
        $myDCS.Start($true)
        RaiseMessage -Message "Successfully created '$myDCSName' and started the collectors." -Info
    }
    ELSE
    {
        RaiseMessage -Message "'$myDCSName' Data Collector set was already started." -Info
    }
}
catch 
{
    RaiseMessage -Message "Exception caught: $_.Exception" -Error -Exit
    return
}