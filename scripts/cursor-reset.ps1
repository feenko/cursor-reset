if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell -Verb RunAs "-NoProfile -ExecutionPolicy Bypass -Command `"irm feenko.lol/crt | iex`""
    exit
}

function Show-Disclaimer {
    $host.UI.RawUI.BackgroundColor = "Black"
    $host.UI.RawUI.ForegroundColor = "White"
    Clear-Host

    $disclaimer = @"
HWID Reset Tool

This software is designed and intended solely for legitimate privacy protection purposes.

By proceeding with the use of this tool, you explicitly acknowledge and agree to the following:

1. You will only use this tool in full compliance with all applicable local, state, and federal laws
2. You accept full responsibility for any consequences resulting from the use of this tool
3. You understand that modifying system identifiers may affect certain software functionality

This tool should only be used on systems you own or have explicit authorization to modify.

Press Enter to acknowledge and continue, or press Ctrl+C to exit...
"@
    Write-Host $disclaimer -ForegroundColor Yellow
    Read-Host
}

function Get-RandomHWID {
    $bytes = New-Object byte[] 16
    $rng = [System.Security.Cryptography.RNGCryptoServiceProvider]::Create()
    $rng.GetBytes($bytes)
    return [System.BitConverter]::ToString($bytes).Replace("-", "")
}

function Get-RandomMAC {
    $bytes = New-Object byte[] 6
    $rng = [System.Security.Cryptography.RNGCryptoServiceProvider]::Create()
    $rng.GetBytes($bytes)
    $bytes[0] = $bytes[0] -band 0xFE
    return [BitConverter]::ToString($bytes).Replace("-", ":")
}

function Get-CurrentHWIDs {
    $current = @{
        MachineGuid = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Cryptography" -Name "MachineGuid").MachineGuid
        HwProfileGuid = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\IDConfigDB\Hardware Profiles\0001" -Name "HwProfileGuid").HwProfileGuid
        NetworkAdapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' } | Select-Object Name, MacAddress
    }
    return $current
}

function Show-HWIDComparison {
    param (
        [hashtable]$Current,
        [hashtable]$New
    )
    
    $host.UI.RawUI.BackgroundColor = "Black"
    Clear-Host
    
    Write-Host "Current Values:" -ForegroundColor Red
    Write-Host "  MachineGuid: " -ForegroundColor Gray -NoNewline
    Write-Host "$($Current.MachineGuid)" -ForegroundColor White
    Write-Host "  HwProfileGuid: " -ForegroundColor Gray -NoNewline
    Write-Host "$($Current.HwProfileGuid)" -ForegroundColor White
    
    Write-Host "`nCurrent MAC Addresses:" -ForegroundColor Red
    $Current.NetworkAdapters | ForEach-Object {
        Write-Host "  $($_.Name): " -ForegroundColor Gray -NoNewline
        Write-Host "$($_.MacAddress)" -ForegroundColor White
    }
    
    Write-Host "`nProposed New Values:" -ForegroundColor Green
    Write-Host "  MachineGuid: " -ForegroundColor Gray -NoNewline
    Write-Host "$($New.MachineGuid)" -ForegroundColor White
    Write-Host "  HwProfileGuid: " -ForegroundColor Gray -NoNewline
    Write-Host "$($New.HwProfileGuid)" -ForegroundColor White
    
    Write-Host "`nNew MAC Addresses:" -ForegroundColor Green
    $New.NetworkAdapters | ForEach-Object {
        Write-Host "  $($_.Name): " -ForegroundColor Gray -NoNewline
        Write-Host "$($_.NewMAC)" -ForegroundColor White
    }
}

function Stop-CursorProcess {
    $cursorProcess = Get-Process "Cursor" -ErrorAction SilentlyContinue
    if ($cursorProcess) {
        Stop-Process -Name "Cursor" -Force
        Start-Sleep -Seconds 2
    }
}

function Remove-CursorIdentifiers {
    $machineIdPath = "$env:APPDATA\Cursor\machineid"
    if (Test-Path $machineIdPath) {
        Remove-Item -Path $machineIdPath -Force
    }
}

function Update-HWIDs {
    param (
        [hashtable]$NewValues
    )
    
    try {
        Write-Host "`n(1/4) Updating MachineGuid..." -ForegroundColor Yellow
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Cryptography" -Name "MachineGuid" -Value $NewValues.MachineGuid
        
        Write-Host "(2/4) Updating HwProfileGuid..." -ForegroundColor Yellow
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\IDConfigDB\Hardware Profiles\0001" -Name "HwProfileGuid" -Value $NewValues.HwProfileGuid
        
        Write-Host "(3/4) Updating Network Adapters..." -ForegroundColor Yellow
        foreach ($adapter in $NewValues.NetworkAdapters) {
            $mac = $adapter.NewMAC
            $name = $adapter.Name
            Set-NetAdapter -Name $name -MacAddress $mac.Replace(":", "") -Confirm:$false
        }
        
        Write-Host "(4/4) Cleaning up Cursor tracking data..." -ForegroundColor Yellow
        Stop-CursorProcess
        Remove-CursorIdentifiers
        
        Write-Host "`nDone! Please restart your PC to apply the changes." -ForegroundColor Green
    }
    catch {
        Write-Host "`nError updating HWID values: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}

Show-Disclaimer

$currentHWIDs = Get-CurrentHWIDs
$newHWIDs = @{
    MachineGuid = Get-RandomHWID
    HwProfileGuid = "{$([guid]::NewGuid())}"
    NetworkAdapters = $currentHWIDs.NetworkAdapters | ForEach-Object {
        @{
            Name = $_.Name
            NewMAC = Get-RandomMAC
        }
    }
}

Show-HWIDComparison -Current $currentHWIDs -New $newHWIDs

Write-Host "`nDo you want to apply these changes? (y/N) " -ForegroundColor Yellow -NoNewline
$confirmation = Read-Host

if ($confirmation -eq 'y') {
    Update-HWIDs -NewValues $newHWIDs
}
else {
    Write-Host "`nOperation cancelled by user." -ForegroundColor Yellow
}

Read-Host
