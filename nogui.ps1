$ErrorActionPreference = "SilentlyContinue"

function Get-Signature {
    [CmdletBinding()]
    param (
        [string[]]$FilePath
    )

    $Existence = Test-Path -PathType "Leaf" -Path $FilePath
    $Authenticode = (Get-AuthenticodeSignature -FilePath $FilePath -ErrorAction SilentlyContinue).Status
    $Signature = "Invalid Signature (UnknownError)"

    if ($Existence) {
        if ($Authenticode -eq "Valid") {
            $Signature = "Valid Signature"
        } elseif ($Authenticode -eq "NotSigned") {
            $Signature = "Invalid Signature (NotSigned)"
        } elseif ($Authenticode -eq "HashMismatch") {
            $Signature = "Invalid Signature (HashMismatch)"
        } elseif ($Authenticode -eq "NotTrusted") {
            $Signature = "Invalid Signature (NotTrusted)"
        } elseif ($Authenticode -eq "UnknownError") {
            $Signature = "Invalid Signature (UnknownError)"
        }
        return $Signature
    } else {
        $Signature = "File Was Not Found"
        return $Signature
    }
}

function Test-Admin {
    $currentUser = New-Object Security.Principal.WindowsPrincipal $([Security.Principal.WindowsIdentity]::GetCurrent())
    $currentUser.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
}

if (!(Test-Admin)) {
    Start-Sleep 10
    Exit
}

$sw = [Diagnostics.Stopwatch]::StartNew()

if (!(Get-PSDrive -Name HKLM -PSProvider Registry)) {
    Try {
        New-PSDrive -Name HKLM -PSProvider Registry -Root HKEY_LOCAL_MACHINE
    } Catch {
        Exit
    }
}
$bv = ("bam", "bam\State")
Try {
    $Users = foreach($ii in $bv) {
        Get-ChildItem -Path "HKLM:\SYSTEM\CurrentControlSet\Services\$($ii)\UserSettings\" | Select-Object -ExpandProperty PSChildName
    }
} Catch {
    Exit
}
$rpath = @("HKLM:\SYSTEM\CurrentControlSet\Services\bam\","HKLM:\SYSTEM\CurrentControlSet\Services\bam\state\")

$UserTime = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\TimeZoneInformation").TimeZoneKeyName
$UserBias = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\TimeZoneInformation").ActiveTimeBias
$UserDay = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\TimeZoneInformation").DaylightBias

$Bam = Foreach ($Sid in $Users) {
    foreach($rp in $rpath) {
        $BamItems = Get-Item -Path "$($rp)UserSettings\$Sid" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Property
        Try {
            $objSID = New-Object System.Security.Principal.SecurityIdentifier($Sid)
            $User = $objSID.Translate([System.Security.Principal.NTAccount])
            $User = $User.Value
        } Catch {
            $User = ""
        }
        ForEach ($Item in $BamItems) {
            $Key = Get-ItemProperty -Path "$($rp)UserSettings\$Sid" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty $Item
            If($key.length -eq 24) {
                $Hex = [System.BitConverter]::ToString($key[7..0]) -replace "-",""
                $TimeLocal = Get-Date ([DateTime]::FromFileTime([Convert]::ToInt64($Hex, 16))) -Format "yyyy-MM-dd HH:mm:ss"
                $TimeUTC = Get-Date ([DateTime]::FromFileTimeUtc([Convert]::ToInt64($Hex, 16))) -Format "yyyy-MM-dd HH:mm:ss"
                $Bias = -([convert]::ToInt32([Convert]::ToString($UserBias,2),2))
                $Day = -([convert]::ToInt32([Convert]::ToString($UserDay,2),2))
                $Biasd = $Bias/60
                $Dayd = $Day/60
                $TImeUser = (Get-Date ([DateTime]::FromFileTimeUtc([Convert]::ToInt64($Hex, 16))).addminutes($Bias) -Format "yyyy-MM-dd HH:mm:ss")
                $d = if((((split-path -path $item) | ConvertFrom-String -Delimiter "\\").P3) -match '\d{1}') {
                    ((split-path -path $item).Remove(23)).trimstart("\Device\HarddiskVolume")
                } else {
                    $d = ""
                }
                $f = if((((split-path -path $item) | ConvertFrom-String -Delimiter "\\").P3) -match '\d{1}') {
                    Split-path -leaf ($item).TrimStart()
                } else {
                    $item
                }
                $cp = if((((split-path -path $item) | ConvertFrom-String -Delimiter "\\").P3) -match '\d{1}') {
                    ($item).Remove(1,23)
                } else {
                    $cp = ""
                }
                $path = if((((split-path -path $item) | ConvertFrom-String -Delimiter "\\").P3) -match '\d{1}') {
                    Join-Path -Path "C:" -ChildPath $cp
                } else {
                    $path = ""
                }
                $sig = if((((split-path -path $item) | ConvertFrom-String -Delimiter "\\").P3) -match '\d{1}') {
                    Get-Signature -FilePath $path
                } else {
                    $sig = ""
                }
                [PSCustomObject]@{
                    'Examiner Time' = $TimeLocal
                    'Last Execution Time (UTC)' = $TimeUTC
                    'Last Execution User Time' = $TimeUser
                    Application = $f
                    Path = $path
                    Signature = $sig
                    User = $User
                    SID = $Sid
                    Regpath = $rp
                }
            }
        }
    }
}

$Bam | Out-GridView -PassThru -Title "BAM key entries $($Bam.count)  - User TimeZone: ($UserTime) -> ActiveBias: ( $Bias) - DayLightTime: ($Day)"

$sw.stop()
$t = $sw.Elapsed.TotalMinutes