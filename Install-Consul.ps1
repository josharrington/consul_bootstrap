# This script will fully bootstrap the consul client on a Windows machine. This can also
# be used to upgrade consul or the service wrapper (NSSM)

Param(
  [Parameter(Mandatory=$True,Position=1)]
    [string]$EncryptKey,
  [Parameter(Mandatory=$True,Position=2)]
    [string]$JoinIP,
  [Parameter(Mandatory=$True,Position=3)]
    [string]$Datacenter
)

# Check for admin rights
If (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(`
    [Security.Principal.WindowsBuiltInRole] "Administrator"))
{
    Write-Warning "You do not have Administrator rights to run this script!`nPlease re-run this script as an Administrator!"
    Break
}

Add-Type -assembly "system.io.compression.filesystem"

#region User Editable variables
$ServiceName="consul"
$ServiceBin="c:\consul\consul.exe"
$ServiceDir="c:\consul"
$GOMAXPROCS=2
$ConsulDLZip="https://releases.hashicorp.com/consul/0.6.3/consul_0.6.3_windows_amd64.zip"
$ConsulTempZip=(Join-Path $env:TEMP "consul.zip")
$ServiceWrapperExe="nssm.exe"
$ServiceWrapperDLZip="http://nssm.cc/release/nssm-2.24.zip"
$ServiceWrapperTempZip=(Join-Path $env:TEMP "nssm.zip")
$ServiceWrapperNestedExe="nssm-2.24\win64\nssm.exe"
$ServiceWrapper=(Join-Path $ServiceDir $ServiceWrapperExe)
$TempSWdir=(Join-Path $env:TEMP "nssm")

$ConsulClientConfigFile=(Join-Path $ServiceDir "consul_client.json")
$ConsulClientConfig=@"
{
  "datacenter": "$Datacenter",
  "data_dir": "c:\\consul\\data",
  "log_level": "INFO",
  "server": false,
  "start_join": ["$JoinIP"],
  "disable_remote_exec": true,
  "leave_on_terminate": true,
  "encrypt": "$EncryptKey"
}
"@.Trim()

#endregion

#region functions
function Convert-LineEnding{
    Param(
      [Parameter(Mandatory=$True,Position=1)]
        [ValidateSet("mac","unix","win")] 
        [string]$lineEnding,
      [Parameter(Mandatory=$True)]
        [string]$file
    )

    # Convert the friendly name into a PowerShell EOL character
    Switch ($lineEnding) {
      "mac"  { $eol="`r" }
      "unix" { $eol="`n" }
      "win"  { $eol="`r`n" }
    } 

    # Replace CR+LF with LF
    $text = [IO.File]::ReadAllText($file) -replace "`r`n", "`n"
    [IO.File]::WriteAllText($file, $text)

    # Replace CR with LF
    $text = [IO.File]::ReadAllText($file) -replace "`r", "`n"
    [IO.File]::WriteAllText($file, $text)

    #  At this point all line-endings should be LF.

    # Replace LF with intended EOL char
    if ($eol -ne "`n") {
      $text = [IO.File]::ReadAllText($file) -replace "`n", $eol
      [IO.File]::WriteAllText($file, $text)
    }
}
#endregion


# Try to stop and remove the service before continuing
try {
    . $ServiceWrapper stop $ServiceName
    . $ServiceWrapper remove $ServiceName confirm
}
catch{ 
    Write-Output "Consul service not installed, proceeding..."
}

#region Consul setup
if(Test-Path $ServiceDir){
    Remove-Item $ServiceDir -Recurse -Force
}

Invoke-WebRequest $ConsulDLZip -OutFile $ConsulTempZip
[io.compression.zipfile]::ExtractToDirectory($ConsulTempZip, $ServiceDir)

$ConsulClientConfig | Out-File $ConsulClientConfigFile -Force
Convert-LineEnding -lineEnding unix -file $ConsulClientConfigFile

# Figure out the number of cores for Consul to use

#endregion

#region ServiveWrapper setup

if(!(Test-Path -Path $env:TEMP )){
    New-Item -ItemType directory -Path $env:TEMP
}

if(Test-Path -Path $TempSWdir){
    Remove-Item $TempSWdir -Force -Recurse
}

if(!(Test-Path -Path $ServiceDir)){
    New-Item -ItemType directory -Path $ServiceDir
}

Invoke-WebRequest $ServiceWrapperDLZip -OutFile $ServiceWrapperTempZip
[io.compression.zipfile]::ExtractToDirectory($ServiceWrapperTempZip, $TempSWdir)
Move-Item -Force (Join-Path $TempSWdir $ServiceWrapperNestedExe) (join-path $ServiceDir $ServiceWrapperExe) 

. $ServiceWrapper install $ServiceName c:\consul\consul.exe
. $ServiceWrapper set $ServiceName AppParameters "agent -config-dir $ServiceDir"
. $ServiceWrapper set $ServiceName DisplayName $ServiceName
. $ServiceWrapper set $ServiceName ObjectName LocalSystem
. $ServiceWrapper set $ServiceName AppStdout "$ServiceDir\$ServiceName.log"
. $ServiceWrapper set $ServiceName AppStderr "$ServiceDir\$ServiceName.log"
. $ServiceWrapper set $ServiceName AppRotateFiles 1
. $ServiceWrapper set $ServiceName AppRotateOnline 1
. $ServiceWrapper set $ServiceName AppRotateSeconds 86400
. $ServiceWrapper set $ServiceName AppEnvironmentExtra GOMAXPROCS=$GOMAXPROCS
. $ServiceWrapper start $ServiceName
#endregion