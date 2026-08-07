param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$workflowPath = Join-Path $repositoryRoot '.github\workflows\windows-installer-smoke.yml'
$workflow = Get-Content -LiteralPath $workflowPath -Raw -Encoding UTF8

function Assert-WorkflowPattern {
  param(
    [Parameter(Mandatory = $true)][string]$Pattern,
    [Parameter(Mandatory = $true)][string]$Failure
  )
  if ($workflow -notmatch $Pattern) { throw $Failure }
}

Assert-WorkflowPattern '(?m)^\s{6}release_id:\s*$' 'release_id input is missing.'
Assert-WorkflowPattern '(?m)^\s{6}asset_id:\s*$' 'asset_id input is missing.'
Assert-WorkflowPattern '(?ms)options:\s*\r?\n\s*- c-default\s*\r?\n\s*- d-custom' 'Both destination choices are required.'
Assert-WorkflowPattern 'releases/\$env:RELEASE_ID/assets\?per_page=100' 'The workflow does not enumerate the selected release assets.'
Assert-WorkflowPattern '\[long\]\$_\.id -eq \[long\]\$env:ASSET_ID' 'The exact asset ID is not bound to the selected release asset list.'
Assert-WorkflowPattern 'matchingAssets\.Count -ne 1' 'The release-to-asset relationship is not fail-closed.'
Assert-WorkflowPattern 'Release tag.*does not match' 'The release tag is not bound to the requested version.'
Assert-WorkflowPattern 'assetPagesInspected' 'Release asset pagination evidence is missing.'
Assert-WorkflowPattern 'downloadedBytes' 'Downloaded byte-count evidence is missing.'
Assert-WorkflowPattern 'sizeMatched' 'Downloaded byte-count validation is missing.'
Assert-WorkflowPattern 'installer-smoke-result\.json' 'The JSON evidence path is missing.'
Assert-WorkflowPattern '(?m)^\s+if: \$\{\{ always\(\) \}\}\s*$' 'Evidence must upload even after a failed smoke step.'
Assert-WorkflowPattern 'uses: actions/upload-artifact@v4' 'The workflow must upload its evidence with upload-artifact v4.'

foreach ($requiredSection in @(
  'release',
  'asset',
  'version',
  'hash',
  'paths',
  'install',
  'registry',
  'launch',
  'uninstall',
  'cleanup',
  'ok'
)) {
  Assert-WorkflowPattern "(?m)^\s+$requiredSection =" "Evidence section '$requiredSection' is missing."
}

Assert-WorkflowPattern 'exactEntriesBeforeInstall' 'Clean registry precondition evidence is missing.'
Assert-WorkflowPattern 'recordedInstallLocation' 'InstallLocation evidence is missing.'
Assert-WorkflowPattern 'quietUninstallString' 'QuietUninstallString evidence is missing.'
Assert-WorkflowPattern 'registeredUninstallerMatched' 'The registered uninstaller is not validated.'
Assert-WorkflowPattern 'productVersion' 'ProductVersion evidence is missing.'
Assert-WorkflowPattern 'allowedProductVersions -ccontains \$productVersion' 'ProductVersion must use an exact allowlist.'
if ($workflow -match 'ProductVersion\.StartsWith') { throw 'Prefix ProductVersion matching is forbidden.' }
Assert-WorkflowPattern 'remainedAliveDuringSmoke' 'Launch-liveness evidence is missing.'
Assert-WorkflowPattern 'process-liveness-only-no-visible-ui-assertion' 'Launch evidence scope is overstated.'
Assert-WorkflowPattern 'oppositeRootAbsentAfterInstall' 'The unselected C/D destination is not checked.'
Assert-WorkflowPattern 'installRootAbsent' 'Install-root cleanup evidence is missing.'
Assert-WorkflowPattern 'uninstallRegistryAbsent' 'Registry cleanup evidence is missing.'
Assert-WorkflowPattern 'Invoke-BestEffortFailureCleanup' 'Failure cleanup is missing.'
Assert-WorkflowPattern 'inputId = \$env:RELEASE_ID[\s\S]*?id = \$null' 'Release ID must not be converted before the initial report exists.'
Assert-WorkflowPattern 'inputId = \$env:ASSET_ID[\s\S]*?id = \$null' 'Asset ID must not be converted before the initial report exists.'
Assert-WorkflowPattern '\$installerVerbatimArguments = "/S /D=\$installRoot"' 'd-custom must keep /D as the final raw NSIS argument.'

$runMarker = "        run: |`n"
$runStart = $workflow.IndexOf($runMarker, [StringComparison]::Ordinal)
if ($runStart -lt 0) {
  $runMarker = "        run: |`r`n"
  $runStart = $workflow.IndexOf($runMarker, [StringComparison]::Ordinal)
}
if ($runStart -lt 0) { throw 'The PowerShell run block is missing.' }
$runStart += $runMarker.Length
$uploadMarker = "`n      - name: Upload installer smoke evidence"
$runEnd = $workflow.IndexOf($uploadMarker, $runStart, [StringComparison]::Ordinal)
if ($runEnd -lt 0) {
  $uploadMarker = "`r`n      - name: Upload installer smoke evidence"
  $runEnd = $workflow.IndexOf($uploadMarker, $runStart, [StringComparison]::Ordinal)
}
if ($runEnd -lt 0) { throw 'The end of the PowerShell run block is missing.' }

$embeddedLines = $workflow.Substring($runStart, $runEnd - $runStart) -split '\r?\n'
$embeddedPowerShell = ($embeddedLines | ForEach-Object {
  if ($_ -eq '') { return '' }
  if (-not $_.StartsWith('          ', [StringComparison]::Ordinal)) {
    throw "Unexpected indentation in embedded PowerShell: $_"
  }
  return $_.Substring(10)
}) -join [Environment]::NewLine

$parseErrors = $null
[void][Management.Automation.Language.Parser]::ParseInput(
  $embeddedPowerShell,
  [ref]$null,
  [ref]$parseErrors
)
if ($parseErrors.Count -ne 0) {
  throw "Embedded PowerShell has syntax errors: $($parseErrors.Message -join '; ')"
}

Write-Host 'WINDOWS_INSTALLER_SMOKE_CONTRACT_OK'
