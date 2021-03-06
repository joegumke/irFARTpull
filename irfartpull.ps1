<#  
.SYNOPSIS  
    IR Forensic ARTifact pull (irFArtpull)

.DESCRIPTION
irFARTpull is a PowerShell script utilized to pull several forensic artifacts from a live WinXP-Win7 system on your network. It DOES NOT utilize WinRM capabilities.

Artifacts it grabs:
	- Disk Information
	- System Information
	- User Information
	- Network Configuration
	- Netstat info
	- Route Table, ARP Table, DNS Cache, HOSTS file
	- Running Processes
	- Services
	- Event Logs (System, Security, Application)
	- Prefetch Files
	- MFT$
	- Registry Files
	- User NTUSER.dat files
	- Java IDX files
	- Internet History Files (IE, Firefox, Chrome)
	
When done collecting the artifacts, it will 7zip the data and pull the info off the box for offline analysis. 
		
NOTEs:  
    
	All testing done on PowerShell v3
	Requires Remote Registry PowerShell Module for collecting XP remote registy entries
	Requires RawCopy64.exe for the extraction of MFT$ and NTUSER.DAT files.
	Requires 7za.exe (7zip cmd line) for compression w/ password protection
	
	Assumed Directories:
	c:\tools\resp\ - where the RawCopy64.exe and 7za.exe exist
	c:\windows\temp\IR - Where the work will be done
		
	Must be ran as a user that will have Admin creds on the remote system. The assumption is that the target system is part of a domain.
	
LINKs:  
	
	irFARTpull main - https://github.com/n3l5/irFARTpull
	
	Links to required tools:
	Remote Registry PowerShell Module - https://psremoteregistry.codeplex.com/
	mft2csv - Part of the mft2csv suite, RawCopy can be downloaded here: https://code.google.com/p/mft2csv/
	7-Zip - Part of the 7-Zip archiver, 7za can be downloaded from here: http://www.7-zip.org/
	
	Various tools for analysis of the artifacts:
	RegRipper - Tool for extracting data from Registry and NTUSER.dat files. https://code.google.com/p/regripper/
	WinPrefetchView - utility to read Prefetch files. http://www.nirsoft.net/utils/win_prefetch_view.html
	MFTDump - tool to dump the contents of the $MFT. http://malware-hunters.net/2012/09/

FUTURE Enhancements:

	PowerShell v4 testing and enhancements
	Credential Request

#>

echo "=============================================="
echo "=============================================="
Write-Host -Fore Magenta "

  _      ______           _               _ _ 
 (_)    |  ____/\        | |             | | |
  _ _ __| |__ /  \   _ __| |_ _ __  _   _| | |
 | | '__|  __/ /\ \ | '__| __| '_ \| | | | | |
 | | |  | | / ____ \| |  | |_| |_) | |_| | | |
 |_|_|  |_|/_/    \_\_|   \__| .__/ \__,_|_|_|
                             | |              
                             |_|              

 "
echo "=============================================="
Write-Host -Fore Yellow "Run as administrator/elevated privileges!!!"
echo "=============================================="
echo ""
Write-Host -Fore Cyan ">>>>> Press a key to begin...."
[void][System.Console]::ReadKey($TRUE)
echo ""
echo ""
$userDom = Read-Host "Enter your target DOMAIN (if any)..."
$username = Read-Host "Enter you UserID..."
$combCred = "$userDom" + "\$username"
$cred = Get-Credential $combCred
$target = read-host ">>>>> Please enter a HOSTNAME or IP..."
$irFolder = "c:\Windows\Temp\IR\"
echo ""
Write-Host -Fore Yellow ">>>>> pinging $target...."
echo ""
c:\TOOLS\tcping.exe -s -i 10 -r 10 $target 445
echo ""
echo "=============================================="

$targetName = Get-WMIObject Win32_ComputerSystem -ComputerName $target -Credential $cred | ForEach-Object Name
$targetIP = Get-WMIObject -Class Win32_NetworkAdapterConfiguration -ComputerName $target -Filter "IPEnabled='TRUE'" | Where {$_.IPAddress} | Select -ExpandProperty IPAddress | Where{$_ -notlike "*:*"}
Write-Host -ForegroundColor Magenta "==[ $targetName - $targetIP ]=="

################
##Set up environment on remote system. IR folder for tools and art folder for artifacts.##
################
##For consistency, the working directory will be located in the "c:\windows\temp\IR" folder on both the target and initiator system.
##Tools will stored directly in the "IR" folder for use. Artifacts collected on the local environment of the remote system will be dropped in the workingdir.

##Determine x32 or x64
$arch = Get-WmiObject -Class Win32_Processor -ComputerName $target -Credential $cred | foreach {$_.AddressWidth}

#Determine XP or Win7
$OSvers = Get-WMIObject -Class Win32_OperatingSystem -ComputerName $target -Credential $cred | foreach {$_.Version}
	if ($OSvers -like "5*"){
	Write-Host -ForegroundColor Magenta "==[ Host OS: Windows XP $arch  ]=="
	}
	if ($OSvers -like "6*"){
	Write-Host -ForegroundColor Magenta "==[ Host OS: Windows 7 $arch    ]=="
	}
echo "=============================================="
echo ""
##Set up PSDrive mapping to remote drive
New-PSDrive -Name X -PSProvider filesystem -Root \\$target\c$ -Credential $cred | Out-Null

$remoteIRfold = "X:\windows\Temp\IR"
$date = Get-Date -format yyyy-MM-dd_HHmm_
$irFolder = "c:\Windows\Temp\IR\"
$artFolder = $date + $targetName
$workingDir = $irFolder + $artFolder
$dirList = ("$remoteIRfold\$artFolder\logs","$remoteIRfold\$artFolder\network","$remoteIRfold\$artFolder\prefetch","$remoteIRfold\$artFolder\reg")
New-Item -Path $dirList -ItemType Directory | Out-Null

##connect and move software to target client
Write-Host -Fore Green "Copying tools...."
$tools = "c:\tools\resp\*.*"
Copy-Item $tools $remoteIRfold -recurse

##SystemInformation
Write-Host -Fore Green "Pulling system information...."
Get-WMIObject Win32_LogicalDisk -ComputerName $target -Credential $cred | Select DeviceID,DriveType,@{l="Drive Size";e={$_.Size / 1GB -join ""}},@{l="Free Space";e={$_.FreeSpace / 1GB -join ""}} | Export-CSV $remoteIRfold\$artFolder\diskInfo.csv -NoTypeInformation | Out-Null
Get-WMIObject Win32_ComputerSystem -ComputerName $target -Credential $cred | Select Name,UserName,Domain,Manufacturer,Model,PCSystemType | Export-CSV $remoteIRfold\$artFolder\systemInfo.csv -NoTypeInformation | Out-Null
if ($OSvers -like "5*"){
	Get-RegValue -ComputerName $target -Key "SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\" -Recurse -Value ProfileImagePath | Where {$_.Key -match "S-1-5-21-"} | Select Key,Data | Export-CSV $remoteIRfold\$artFolder\userinfo.csv -NoTypeInformation | Out-Null
	}
else {Get-WmiObject Win32_UserProfile -ComputerName $target -Credential $cred | select Localpath,SID,LastUseTime | Export-CSV $remoteIRfold\$artFolder\users.csv -NoTypeInformation | Out-Null
}

##gather network  & adapter info
Write-Host -Fore Green "Pulling network information...."
Get-WMIObject Win32_NetworkAdapterConfiguration -ComputerName $target -Filter "IPEnabled='TRUE'" -Credential $cred | select DNSHostName,ServiceName,MacAddress,@{l="IPAddress";e={$_.IPAddress -join ","}},@{l="DefaultIPGateway";e={$_.DefaultIPGateway -join ","}},DNSDomain,@{l="DNSServerSearchOrder";e={$_.DNSServerSearchOrder -join ","}},Description | Export-CSV $remoteIRfold\$artFolder\network\netinfo.csv -NoTypeInformation | Out-Null

$netstat = "c:\windows\system32\netstat.exe -anob > $workingDir\network\netstats.txt"
InVoke-WmiMethod -class Win32_process -name Create -ArgumentList $netstat -ComputerName $target -Credential $cred | Out-Null
$netroute = "c:\windows\system32\netstat.exe -r > $workingDir\network\routetable.txt"
InVoke-WmiMethod -class Win32_process -name Create -ArgumentList $netroute -ComputerName $target -Credential $cred | Out-Null
$dnscache = "c:\windows\system32\ipconfig /displaydns > $workingDir\network\dnscache.txt"
InVoke-WmiMethod -class Win32_process -name Create -ArgumentList $dnscache -ComputerName $target -Credential $cred | Out-Null
$arpdata =  "c:\windows\system32\arp.exe -a > $workingDir\network\arpdata.txt"
InVoke-WmiMethod -class Win32_process -name Create -ArgumentList $arpdata -ComputerName $target -Credential $cred | Out-Null
Copy-Item x:\windows\system32\drivers\etc\hosts $remoteIRfold\$artFolder\network\hosts 

##gather Process info
Write-Host -Fore Green "Pulling process info...."
Get-WMIObject Win32_Process -Computername $target -Credential $cred | select-object CreationDate,ProcessName,parentprocessid,processid,@{n='Owner';e={$_.GetOwner().User}},ExecutablePath,commandline| Export-CSV $remoteIRfold\$artFolder\procs.csv -NoTypeInformation | Out-Null

##gather Services info
Write-Host -Fore Green "Pulling service info...."
Get-WMIObject Win32_Service -Computername $target -Credential $cred | Select processid,name,state,displayname,pathname,startmode | Export-CSV $remoteIRfold\$artFolder\services.csv -NoTypeInformation | Out-Null

##Copy Log Files
Write-Host -Fore Green "Pulling event logs...."
if ($OSvers -like "5*"){
	$xplogLoc = "x:\windows\system32\Config"
	$xploglist = @("$xplogLoc\AppEvent.evt","$xplogLoc\SecEvent.evt","$xplogLoc\SysEvent.evt")
	Copy-Item -Path $xploglist -Destination $remoteIRfold\$artFolder\logs\ -Force
	}
else {
$logLoc = "x:\windows\system32\Winevt\Logs"
$loglist = @("$logLoc\application.evtx","$logLoc\security.evtx","$logLoc\system.evtx")
Copy-Item -Path $loglist -Destination $remoteIRfold\$artFolder\logs\ -Force
}

##Copy Prefetch files
Write-Host -Fore Green "Pulling prefetch files...."
Copy-Item x:\windows\prefetch\*.pf $remoteIRfold\$artFolder\prefetch -recurse

##Copy $MFT
Write-Host -Fore Green "Pulling the MFT...."
if ($arch –like “5*”) 
{
InVoke-WmiMethod -class Win32_process -name Create -ArgumentList "$irFolder\RawCopy.exe c:0 $workingDir" -ComputerName $target -Credential $cred | Out-Null
}
if ($arch –like “6*”) 
{
InVoke-WmiMethod -class Win32_process -name Create -ArgumentList "$irFolder\RawCopy64.exe c:0 $workingDir" -ComputerName $target -Credential $cred | Out-Null
}
do {(Write-Host -ForegroundColor Yellow "  waiting for MFT copy to complete..."),(Start-Sleep -Seconds 5)}
until ((Get-WMIobject -Class Win32_process -Filter "Name='RawCopy64.exe'" -ComputerName $target -Credential $cred | where {$_.Name -eq "RawCopy64.exe"}).ProcessID -eq $null)
Write-Host "  [done]"

##Copy Reg files
Write-Host -Fore Green "Pulling registry files...."
$regLoc = "c:\windows\system32\config\"
if ($arch –like “5*”) 
{
InVoke-WmiMethod -class Win32_process -name Create -ArgumentList "$irFolder\RawCopy.exe $regLoc\SOFTWARE $workingDir\reg" -ComputerName $target -Credential $cred | Out-Null
InVoke-WmiMethod -class Win32_process -name Create -ArgumentList "$irFolder\RawCopy.exe $regLoc\SYSTEM $workingDir\reg" -ComputerName $target -Credential $cred | Out-Null
InVoke-WmiMethod -class Win32_process -name Create -ArgumentList "$irFolder\RawCopy.exe $regLoc\SAM $workingDir\reg" -ComputerName $target -Credential $cred | Out-Null
InVoke-WmiMethod -class Win32_process -name Create -ArgumentList "$irFolder\RawCopy.exe $regLoc\SECURITY $workingDir\reg" -ComputerName $target -Credential $cred | Out-Null
do {(Write-Host -ForegroundColor Yellow "  waiting for Reg Files copy to complete..."),(Start-Sleep -Seconds 5)}
until ((Get-WMIobject -Class Win32_process -Filter "Name='RawCopy.exe'" -ComputerName $target -Credential $cred | where {$_.Name -eq "RawCopy.exe"}).ProcessID -eq $null)
}
if ($arch –like “6*”) 
{
InVoke-WmiMethod -class Win32_process -name Create -ArgumentList "$irFolder\RawCopy64.exe $regLoc\SOFTWARE $workingDir\reg" -ComputerName $target -Credential $cred | Out-Null
InVoke-WmiMethod -class Win32_process -name Create -ArgumentList "$irFolder\RawCopy64.exe $regLoc\SYSTEM $workingDir\reg" -ComputerName $target -Credential $cred | Out-Null
InVoke-WmiMethod -class Win32_process -name Create -ArgumentList "$irFolder\RawCopy64.exe $regLoc\SAM $workingDir\reg" -ComputerName $target -Credential $cred | Out-Null
InVoke-WmiMethod -class Win32_process -name Create -ArgumentList "$irFolder\RawCopy64.exe $regLoc\SECURITY $workingDir\reg" -ComputerName $target -Credential $cred | Out-Null
do {(Write-Host -ForegroundColor Yellow "  waiting for Reg Files copy to complete..."),(Start-Sleep -Seconds 5)}
until ((Get-WMIobject -Class Win32_process -Filter "Name='RawCopy64.exe'" -ComputerName $target -Credential $cred | where {$_.Name -eq "RawCopy64.exe"}).ProcessID -eq $null)
}
Write-Host "  [done]"

##Copy Symantec Quarantine Files (default location)##
$symQ = "x:\ProgramData\Symantec\Symantec Endpoint Protection\*\Data\Quarantine"
if (Test-Path -Path "$symQ\*.vbn") {
	Write-Host -Fore Green "Pulling Symantec Quarantine files...."
	New-Item -Path $remoteIRfold\$artFolder\SymantecQuarantine -ItemType Directory  | Out-Null
	Copy-Item -Path "$symQ\*.vbn" $remoteIRfold\$artFolder\SymantecQuarantine -Force -Recurse
}
else
{
Write-Host -Fore Red "No Symantec Quarantine files...."
}

##Copy Symantec Log Files (default location)##
$symLog = "x:\ProgramData\Symantec\Symantec Endpoint Protection\*\Data\Logs"
if (Test-Path -Path "$symLog\*.log") {
	Write-Host -Fore Green "Pulling Symantec Log files...."
	New-Item -Path $remoteIRfold\$artFolder\SymantecLogs -ItemType Directory  | Out-Null
	Copy-Item -Path "$symLog\*.Log" $remoteIRfold\$artFolder\SymantecLogs -Force -Recurse
}
else
{
Write-Host -Fore Red "No Symantec Log files...."
}

##Copy McAfee Quarantine Files (default location)##
$mcafQ = "x:\Quarantine"
if (Test-Path -Path "$symQ\*.bup") {
	Write-Host -Fore Green "Pulling McAfee Quarantine files...."
	New-Item -Path $remoteIRfold\$artFolder\McAfeeQuarantine -ItemType Directory  | Out-Null
	Copy-Item -Path "$symQ\*.bup" $remoteIRfold\$artFolder\McAfeeQuarantine -Force -Recurse
}
else
{
Write-Host -Fore Red "No McAfee Quarantine files...."
}
##Copy McAfee Log Files (default location)##
$mcafLog = "x:\ProgramData\McAfee\DesktopProtection"
if (Test-Path -Path "$mcafLog\*.txt") {
	Write-Host -Fore Green "Pulling McAfee Log files...."
	New-Item -Path $remoteIRfold\$artFolder\McAfeeAVLogs -ItemType Directory  | Out-Null
	Copy-Item -Path "$symQ\*.bup" $remoteIRfold\$artFolder\McAfeeAVLogs -Force -Recurse
}
else
{
Write-Host -Fore Red "No McAfee Log files...."
}

###################
##Perform Operations on user files
###################
echo ""
echo "=============================================="
Write-Host -Fore Magenta ">>>[Pulling user profile items]<<<"
echo "=============================================="

###################
#####!!!<<<<<Win7>>>>>>!!!!#######
###################
if ($OSvers -like "6*"){
		$W7path = "x:\users"
		$localprofiles = Get-WMIObject Win32_UserProfile -filter "Special != 'true'" -ComputerName $target -Credential $cred | Where {$_.LocalPath -and ($_.ConvertToDateTime($_.LastUseTime)) -gt (get-date).AddDays(-15) }
		foreach ($localprofile in $localprofiles){
		$temppath = $localprofile.localpath
		$source = $temppath + "\ntuser.dat"
		$eof = $temppath.Length
		$last = $temppath.LastIndexOf('\')
		$count = $eof - $last
		$user = $temppath.Substring($last,$count)
		$destination = "$workingDir\users" + $user
		Write-Host -ForegroundColor Magenta "Pulling items for >> [ $user ]"
		Write-Host -Fore Green "  Pulling NTUSER.DAT file for $user...."
		New-Item -Path $remoteIRfold\$artFolder\users\$user -ItemType Directory  | Out-Null
		InVoke-WmiMethod -class Win32_process -name Create -ArgumentList "$irFolder\RawCopy64.exe $source $destination" -ComputerName $target -Credential $cred | Out-Null

##Pull IDX Files##
		$W7idxpath = "$W7path\$user\AppData\LocalLow\Sun\Java\Deployment\cache\"
		if(Test-Path $W7idxpath -PathType Container) {
			Write-Host -Fore Green "  Pulling IDX files for $user....(W7)"
			New-Item -Path $remoteIRfold\$artFolder\users\$user\idx -ItemType Directory  | Out-Null
			$idxFiles = Get-ChildItem -Path $W7idxpath -Filter "*.idx" -Force -Recurse | Where-Object {$_.Length -gt 0 -and $_.LastWriteTime -gt (get-date).AddDays(-15)} | foreach {$_.Fullname}
			Write-Host -Fore Yellow "    pulling IDX files...."
		foreach ($idx in $idxFiles){
			Copy-Item -Path $idx -Destination $remoteIRfold\$artFolder\users\$user\idx\
				}
			}
		else {
	 	 	Write-Host -Fore Red "  No IDX files newer than 15 days for $user...."
	 	 	}

## Copy Win7 INET files
		$Win7inet = "$W7path\$user\AppData\Local\Microsoft\Windows\History\"
		Write-Host -Fore Green "  Pulling Internet Explorer History files for $user...."
		New-Item -Path $remoteIRfold\$artFolder\users\$user\InternetHistory\IE -ItemType Directory | Out-Null
		$inethist = Get-ChildItem -Path $Win7inet -ReCurse -Force | foreach {$_.Fullname}
		foreach ($inet in $inethist) {
			Copy-Item -Path $inet -Destination $remoteIRfold\$artFolder\users\$user\InternetHistory\IE -Force -Recurse
			}

##Copy FireFox History files##
		$w7foxpath = "$W7path\$user\AppData\Roaming\Mozilla\Firefox\profiles"
		if (Test-Path -Path $w7foxpath -PathType Container) {
			Write-Host -Fore Green "  Pulling FireFox Internet History files for $user....(W7)"
			New-Item -Path $remoteIRfold\$artFolder\users\$user\InternetHistory\Firefox -ItemType Directory  | Out-Null
			$ffinet = Get-ChildItem $w7foxpath -Filter "places.sqlite" -Force -Recurse | foreach {$_.Fullname}
			Foreach ($ffi in $ffinet) {
				Copy-Item -Path $ffi -Destination $remoteIRfold\$artFolder\users\$user\InternetHistory\Firefox
				$ffdown = Get-ChildItem $w7foxpath -Filter "downloads.sqlite" -Force -Recurse | foreach {$_.Fullname}
				}
			Foreach ($ffd in $ffdown) {
				Copy-Item -Path $ffd -Destination $remoteIRfold\$artFolder\users\$user\InternetHistory\Firefox
				}
			}
		else {
		 	Write-Host -Fore Red "  No FireFox Internet History files for $user...."
	 	 	}

##Copy Chrome History files##
	$W7chromepath = "$W7path\$user\AppData\Local\Google\Chrome\User Data\Default"
		if ($OSvers -like "6*" -and (Test-Path -Path $W7chromepath -PathType Container)) {
			Write-Host -Fore Green "  Pulling Chrome Internet History files for $user....(W7)"
			New-Item -Path $remoteIRfold\$artFolder\users\$user\InternetHistory\Chrome -ItemType Directory  | Out-Null
			$chromeInet = Get-ChildItem $W7chromepath -Filter "History" -Force -Recurse | foreach {$_.Fullname}
			Foreach ($chrmi in $chromeInet) {
			Copy-Item -Path $chrmi -Destination $remoteIRfold\$artFolder\users\$user\InternetHistory\Chrome
				}
			}
		else {
		 Write-Host -Fore Red "  No Chrome Internet History files $user...."
		 }
	}
}

####################
#####!!!<<<<<WinXP>>>>>>!!!!#######
####################

else {
		$XPpath = "x:\documents and settings"
		$XPprofiles = Get-ChildItem -Path "x:\Documents and settings\" -Force -Exclude "All Users" | Where-Object {$_.Length -gt 0 -and $_.LastWriteTime -gt (get-date).AddDays(-15)} | foreach {$_.Fullname}
		foreach ($XPprofile in $XPprofiles){
		$source = $XPprofile + "\ntuser.dat"
		$eof = $XPprofile.Length
		$last = $XPprofile.LastIndexOf('\')
		$count = $eof - $last
		$xpuser = $XPprofile.Substring($last,$count)
		$destination = "$workingDir\users" + $xpuser
		echo ""
		Write-Host -ForegroundColor Magenta "Pulling items for >> [ $xpuser ]"
		Write-Host -Fore Green "  Pulling NTUSER.DAT file for $xpuser...."
		New-Item -Path $remoteIRfold\$artFolder\users\$xpuser -ItemType Directory  | Out-Null
		InVoke-WmiMethod -class Win32_process -name Create -ArgumentList "$irFolder\RawCopy.exe $source $destination" -ComputerName $target -Credential $cred | Out-Null
	
##Pull XP IDX files##
		$XPidxpath = "$XPpath\$xpuser\Application Data\Sun\Java\Deployment\cache\"
		if (Test-Path -Path $XPidxpath -PathType Container) {
			Write-Host -Fore Green "  Pulling IDX files for $xpuser....(XP)"
			$idxFiles = Get-ChildItem -Path $XPidxpath -Filter "*.idx" -Force -Recurse | Where-Object {$_.Length -gt 0 -and $_.LastWriteTime -gt (get-date).AddDays(-15)} | foreach {$_.Fullname}
			Write-Host -Fore Yellow "    pulling IDX files...."
			foreach ($idx in $idxFiles){
				Copy-Item -Path $idx -Destination $remoteIRfold\$artFolder\users\$xpuser
				}
			}
		else {
	 	 Write-Host -Fore Red "  No IDX files newer than 15 days for $xpuser...."
	 	 }
##Copy Internet History files##	
		$XPinet = "$XPpath\$xpuser\Local Settings\History\"
		Write-Host -Fore Green "  Pulling Internet Explorer History files for $xpuser...."
		New-Item -Path $remoteIRfold\$artFolder\users\$xpuser\InternetHistory\IE -ItemType Directory | Out-Null
		$inethist = Get-ChildItem -Path $XPinet -Recurse -Force | foreach {$_.Fullname}
		foreach ($inet in $inethist) {
			Copy-Item -Path $inet -Destination $remoteIRfold\$artFolder\users\$xpuser\InternetHistory\IE -Force -Recurse
			}

##Copy FireFox History files##
	$XPfoxpath = "$XPpath\$xpuser\Application Data\Mozilla\Firefox\profiles"
		if (Test-Path -Path $XPfoxpath -PathType Container) {
			Write-Host -Fore Green "  Pulling FireFox Internet History files (XP) for $xpuser...."
			New-Item -Path $remoteIRfold\$artFolder\users\$xpuser\InternetHistory\Firefox -ItemType Directory  | Out-Null
			$ffinet = Get-ChildItem $XPfoxpath -Filter "places.sqlite" -Force -Recurse | foreach {$_.Fullname}
			Foreach ($ffi in $ffinet) {
				Copy-Item -Path $ffi -Destination $remoteIRfold\$artFolder\users\$xpuser\InternetHistory\Firefox
				$ffdown = Get-ChildItem $XPfoxpath -Filter "downloads.sqlite" -Force -Recurse | foreach {$_.Fullname}
				}
				Foreach ($ffd in $ffdown) {
					Copy-Item -Path $ffd -Destination $remoteIRfold\$artFolder\users\$xpuser\InternetHistory\Firefox
				}
			}
	else {
		 Write-Host -Fore Red "  No FireFox Internet History files for $xpuser...."
	 	 }

##Copy Chrome History files##
		$XPchromepath = "$XPpath\$xpuser\Local Settings\Application Data\Google\Chrome\User Data\Default"
		if (Test-Path -Path $XPchromepath -PathType Container) {
			Write-Host -Fore Green "  Pulling Chrome Internet History files for $xpuser....(XP)"
			New-Item -Path $remoteIRfold\$artFolder\users\$xpuser\InternetHistory\Chrome -ItemType Directory  | Out-Null
			$chromeInet = Get-ChildItem $XPchromepath -Filter "History" -Force -Recurse | foreach {$_.Fullname}
			Foreach ($chrmi in $chromeInet) {
				Copy-Item -Path $chrmi -Destination $remoteIRfold\$artFolder\users\$xpuser\InternetHistory\Chrome
				}
			}
		else {
		 	Write-Host -Fore Red "  No Chrome Internet History files $xpuser...."
		 	}
		}
}
Get-ChildItem $remoteIRfold -Force -Recurse | Export-CSV $remoteIRfold\$artFolder\FileReport.csv
echo ""
Write-Host -Fore Magenta ">>>[Tactical pause]<<<"
do {(Write-Host -ForegroundColor Yellow "  Please wait...pausing for previous collection processes to complete..."),(Start-Sleep -Seconds 10)}
until ((Get-WMIobject -Class Win32_process -ComputerName $target -Credential $cred | Where-Object {$_.GetOwner().User -eq "$username"}).Count -eq 0)
Write-Host -ForegroundColor Yellow "  [done]"



###################
##Package up the data and pull
###################
echo ""
echo "=============================================="
Write-Host -Fore Magenta ">>>[Packaging the collection]<<<"
echo "=============================================="
echo ""

##7zip the artifact collection##
$passwd = read-host ">>>>> Please supply a password"
$7z = "c:\Windows\temp\IR\7za.exe a $workingDir.7z -p$passwd -mhe $workingDir -y > null"
if ($OSvers -like "6*") {
	InVoke-WmiMethod -class Win32_process -name Create -ArgumentList $7z -ComputerName $target -Credential $cred | Out-Null
 	}
elseif ($OSvers -like "5*") {
	7za a x:\windows\temp\ir\$artFolder.7z -p$passwd -mhe $artFolder
	}
do {(Write-Host -ForegroundColor Yellow "  packing the collected artifacts..."),(Start-Sleep -Seconds 10)}
until ((Get-WMIobject -Class Win32_process -Filter "Name='7za.exe'" -ComputerName $target -Credential $cred | where {$_.Name -eq "7za.exe"}).ProcessID -eq $null)
Write-Host -ForegroundColor Yellow "  Packing complete..."

##size it up
Write-Host -ForegroundColor Cyan "  [Package Stats]"
$dirsize = "{0:N2}" -f ((Get-ChildItem $remoteIRfold\$artFolder | Measure-Object -property length -sum ).Sum / 1MB) + " MB"
Write-Host -ForegroundColor Cyan "  Working Dir: $dirsize "
$7zsize = "{0:N2}" -f ((Get-ChildItem $remoteIRfold\$artfolder.7z | Measure-Object -property length -sum ).Sum / 1MB) + " MB"
Write-Host -ForegroundColor Cyan "  Package size: $7zsize "

Write-Host -Fore Green "Transfering the package...."
Move-Item $remoteIRfold\$artfolder.7z $irFolder
Write-Host -Fore Yellow "  [done]"

###Delete the IR folder##
Write-Host -Fore Green "Removing the working environment...."
Remove-Item $remoteIRfold -Recurse -Force 

##Disconnect the PSDrive X mapping##
Remove-PSDrive X

##Ending##
echo "=============================================="
Write-Host -ForegroundColor Magenta ">>>>>>>>>>[[ irFArtPull complete ]]<<<<<<<<<<<"
echo "=============================================="