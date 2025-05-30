<#
##############################################################################
# Win11Readiness.ps1
#
# Script to check system compatability with Windows 11
# Checks for:
#
# - Processor speed > 1Ghz
# - Ram Capacity > 4GB
# - TPM Version 2.0
# - Local Disk > 64GB
# - DirectX 12 capability
# - WDDM version > 2.0
# - DIsplay Resolution and colour depth
# - UEFI Firmware with Secureboot capability
#
#
# VERSION 1.1
#
# (C) Copyright 2024 Charles Miller (ch@rles.pro)
##############################################################################
Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:
 
The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.
 
THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
##############################################################################
#>

$TESTING = $true

if ($TESTING) {
# Self-Elevation wizardry. Only required for Testing...
    if (!(New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Start-Process -FilePath 'powershell' -ArgumentList ('-File', $MyInvocation.MyCommand.Source, $args | % { $_ }) -Verb RunAs
        exit
    }
}

# Get Hostname and Domain.
$hostname = ""
$hostname = $env:COMPUTERNAME
try {
    $domain = (Get-WmiObject -Namespace root\cimv2 -Class Win32_ComputerSystem).Domain
    if($domain == "WORKGROUP") {
        if(dsregcmd /status | Select-String "AzureAdJoined : YES"){
        $domain = "Azure Joined"
        }
    }
}
catch {
    if(dsregcmd /status | Select-String "AzureAdJoined : YES"){
        $domain = "Azure Joined"
        }
}

# WMI Query options for the processor query
$procprops = "Name, MaxClockSpeed, AddressWidth, numberOfCores, NumberOfLogicalProcessors"

# WMI Queries
$processor = Get-WmiObject -Namespace "root\CIMV2:Win32_Processor" -Class Win32_Processor -Property $procprops
$TPM = Get-WmiObject -Namespace "root\CIMV2\Security\MicrosoftTpm" -Class Win32_TPM
$RAM = Get-WmiObject -Namespace "root\CIMV2:Win32_PhysicalMemory" -Class Win32_PhysicalMemory
$disk = Get-WmiObject -Namespace "root\CIMV2:Win32_DiskDrive" -Class Win32_DiskDrive
$display = Get-WmiObject -Namespace "root\CIMV2:Win32_VideoController" -Class Win32_VideoController

if ($TPM) {
    $tpmcheck = $TPM.SpecVersion.Split()[0].Trim(",")
} else {
    $tpmcheck = "NO TPM"
    }

$secureBoot = Confirm-SecureBootUEFI
if ($secureBoot) {
    $sbcheck = "TRUE"
} else {
    $sbcheck = "FALSE"
    }

$firmware = bcdedit | Select-String "path.*efi"
if ($firmware) {
    $fwcheck = "UEFI"
} else {
    $fwcheck = "BIOS"
    }

# Create a folder to hold the dxdiag output
if (!(Test-Path -Path C:\WIN11\Win11)) {
    New-Item -ItemType Directory -Path C:\WIN11\Win11 | Out-Null
}

# Create the dxdiag output
dxdiag.exe /x C:\WIN11\Win11\dx.xml

# Wait for the file to be created
$counter = 0
Write-Host "Generating dxdiag output."
Write-Host "Waiting for filesystem." -NoNewline
while (!(Test-Path -Path C:\WIN11\Win11\dx.xml)) {
    if ($counter -ge 120) {
        exit
    }
    Write-Host "." -NoNewline
    $counter += 1
    Start-Sleep -Seconds 1
}

Write-Host

# Parse the XML output to obtain GPU and driver info
[xml]$directX = Get-Content C:\WIN11\Win11\dx.xml
$dxVersion = $directX.DxDiag.SystemInformation.DirectXVersion
$wddm = $directX.DxDiag.DisplayDevices.DisplayDevice
if($wddm.Count -gt 1){
    $wddm = $directX.DxDiag.DisplayDevices.DisplayDevice[0].DriverModel
} else {
    $wddm = $directX.DxDiag.DisplayDevices.DisplayDevice.DriverModel
    }

# Output IDs
Write-Host "Hostname: $hostname"
Write-Host "Domain: $domain"


# Processor Check
Write-Host "Processor: " -NoNewline
if ($processor.MaxClockSpeed / 1000 -ge 1) {
    Write-Host "Pass" -ForegroundColor Green
}
else {
    Write-Host "Fail" -ForegroundColor Red
}

# TPM Check
Write-Host "Trusted Platform Module: " -NoNewline
if(!($TPM)){
    $TPM = "NONE"
    } else {
if (($TPM.SpecVersion).Contains("2.0")) {
    Write-Host "Pass" -ForegroundColor Green
}
else {
    Write-Host "Fail" -ForegroundColor Red
}}

# RAM Check
Write-Host "Physical Memory: " -NoNewline
$expo = [Math]::Pow(1024, 3)
if ((($RAM | Measure-Object -Property Capacity -Sum).sum / $expo) -ge 4) {
    Write-Host "Pass" -ForegroundColor Green
}
else {
    Write-Host "Fail" -ForegroundColor Red
}

# Disk Check
Write-Host "Disk Size: " -NoNewline
if (($disk | Measure-Object).Count -gt 1){
    $disksize = $disk[0].Size
    } else {
    $disksize = $disk.Size
    }
if (($disksize / $expo) -ge 64) {
    Write-Host "Pass" -ForegroundColor Green
}
else {
    Write-Host "Fail" -ForegroundColor Red
}

# Secure Boot (UEFI) Check
Write-Host "Secure Boot and UEFI: " -NoNewline
if ($secureBoot -and $firmware) {
    Write-Host "Pass" -ForegroundColor Green
}
else {
    Write-Host "Fail" -ForegroundColor Red
}

# DirectX12 Check
Write-Host "DirectX12: " -NoNewline
if ($dxVersion = "DirectX 12") {
    Write-Host "Pass" -ForegroundColor Green
}
else {
    Write-Host "Fail" -ForegroundColor Red
}

# WDDM Check
Write-Host "WDDM: " -NoNewline
$wddmVersion = ($wddm.Split(" "))[1]
if ((($wddm).Contains("WDDM")) -and $wddmVersion -ge 2.0) {
    Write-Host "Pass" -ForegroundColor Green
}
else {
    Write-Host "Fail" -ForegroundColor Red
    Write-Host "WDDM Version : " -NoNewline
    Write-Host $wddmVersion
}

# Display Check
if(($display | Measure-Object).Count -gt 1){
    $height = $display[0].CurrentVerticalResolution
    $width = $display[0].CurrentHorizontalResolution
    $depth = $display[0].CurrentBitsPerPixel
} else {
    $height = $display.CurrentVerticalResolution
    $width = $display.CurrentHorizontalResolution
    $depth = $display.CurrentBitsPerPixel
}
Write-Host "Resolution: " -NoNewline
if (($height -ge 720) -and ($width -ge 1200) -and ($depth -eq 32)) {
    Write-Host "Pass" -ForegroundColor Green
}
else {
    Write-Host "Fail" -ForegroundColor Red
}

$result = New-Object -TypeName PSObject -Property @{

    'Hostname'        = $hostname
    'Domain'          = $domain
    'Processor Speed' = $processor.MaxClockSpeed
    'Processor Cores' = $processor.numberOfCores
    'Processor Name'  = $processor.Name
    'Address Width'   = $processor.AddressWidth
    'TPM Version'     = $tpmcheck
    'Memory(GB)'      = (($RAM | Measure-Object -Property Capacity -Sum).sum / $expo)
    'Disk'            = ($disksize / $expo)
    'DisplayHeight'   = $height
    'DisplayWidth'    = $width
    'DisplayDepth'    = $depth
    'DirectX Version' = $dxVersion
    'SecureBoot'      = $sbcheck
    'Firmware'        = $fwcheck
}

Read-Host "Press any key to continue..."
