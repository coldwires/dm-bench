<#
.SYNOPSIS
Fetch a BYOND release into byond-standalones\<version>\ so run.ps1 can find it.

.DESCRIPTION
The binaries are Byond Software's and are not redistributed with this
repository. This downloads a published release zip and extracts it into a
per-build directory, which is the layout run.ps1 discovers.

The folder is named after the version you asked for, and run.ps1 then refuses
to run if the extracted binaries report a different version, so a wrong or
moved download cannot quietly produce a baseline attributed to the wrong
engine.

URL shape verified 2026-08-01 by HEAD request against 516.1666, for both this
Windows zip and the _byond_linux.zip variant the Linux setup uses. A full
download has not been exercised; if packaging has changed, pass -Url with the
real one and open an issue so this default can be corrected.

.EXAMPLE
.\fetch-byond.ps1 -Version 516.1666
.\fetch-byond.ps1 -Version 516.1685 -Force
.\fetch-byond.ps1 -Version 516.1685 -Url https://www.byond.com/download/build/516/516.1685_byond.zip
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Version,
    [string]$Url,
    [switch]$Force
)

$ErrorActionPreference = "Stop"
# This script lives in tools/; byond-standalones/ is at the root, one level up.
$Root = Split-Path $PSScriptRoot -Parent

if ($Version -notmatch '^(\d{3})\.(\d+)$') {
    throw "version must look like 516.1666, got '$Version'"
}
$major = $Matches[1]

if (-not $Url) { $Url = "https://www.byond.com/download/build/$major/${Version}_byond.zip" }

$dest = Join-Path $Root "byond-standalones\$Version"
if ((Test-Path (Join-Path $dest "bin\dm.exe")) -and -not $Force) {
    "already present: $dest (pass -Force to replace)"
    return
}

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) "byond-$Version.zip"
"fetching $Url"
Invoke-WebRequest -Uri $Url -OutFile $tmp -UseBasicParsing

$stage = Join-Path ([System.IO.Path]::GetTempPath()) "byond-$Version-stage"
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
Expand-Archive -Path $tmp -DestinationPath $stage -Force

# The zip carries a top-level byond\ directory. Find the one holding bin\dm.exe
# rather than assuming a depth, so a change in packaging fails loudly here
# instead of producing an empty build directory that run.ps1 skips silently.
$dm = Get-ChildItem $stage -Recurse -Filter "dm.exe" -File | Select-Object -First 1
if (-not $dm) { throw "no dm.exe inside $Url; the package layout has changed" }
$src = Split-Path (Split-Path $dm.FullName -Parent) -Parent

if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
New-Item -ItemType Directory -Path $dest -Force | Out-Null
Copy-Item (Join-Path $src "*") $dest -Recurse -Force
Remove-Item $stage -Recurse -Force
Remove-Item $tmp -Force

# Same check run.ps1 makes, reported here so a mismatch is caught at fetch time.
$raw = (Get-Item (Join-Path $dest "bin\dm.exe")).VersionInfo.ProductVersion
$reported = if ($raw -match '(\d+)\.(\d+)\.(\d+)\.(\d+)') { "$($Matches[3]).$($Matches[4])" } else { "unknown" }
if ($reported -ne $Version) {
    throw "extracted binaries report $reported but the folder is named $Version. Delete $dest and fetch again."
}

"installed $Version -> $dest (binaries report $reported)"
".\run.ps1 -List to confirm"
