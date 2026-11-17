# Points the option A host names at the VM (Windows hosts file). Run through hosts-konga.cmd (it asks for
# administrator rights). Re-run when the VM IP changes: only the block between the kong-poc-option-a markers is
# replaced; everything else in the hosts file (including the option C block) stays as it is.
param([Parameter(Mandatory = $true)][string]$Ip)
$ErrorActionPreference = 'Stop'
if ($Ip -notmatch '^\d{1,3}(\.\d{1,3}){3}$') { throw "not an IPv4 address: $Ip" }
$hostsFile = "$env:SystemRoot\System32\drivers\etc\hosts"
$names = @(
  'kong-manager-konga-cp.apps-crc.testing',
  'kong-admin-konga-cp.apps-crc.testing'
)
$begin = '# >>> kong-poc-option-a >>>'
$end   = '# <<< kong-poc-option-a <<<'
Copy-Item $hostsFile "$hostsFile.kong-poc-option-a.bak" -Force
$lines = Get-Content $hostsFile
$out = New-Object System.Collections.Generic.List[string]
$skip = $false
foreach ($l in $lines) {
  if ($l -eq $begin) { $skip = $true; continue }
  if ($l -eq $end) { $skip = $false; continue }
  if (-not $skip) { $out.Add($l) }
}
$out.Add($begin)
foreach ($n in $names) { $out.Add("$Ip`t$n") }
$out.Add($end)
Set-Content -Path $hostsFile -Value $out -Encoding ASCII
ipconfig /flushdns | Out-Null
Write-Host "hosts updated: $($names.Count) names -> $Ip (backup: hosts.kong-poc-option-a.bak)"
Write-Host "Open first:  https://kong-admin-konga-cp.apps-crc.testing  (accept the certificate warning)"
Write-Host "then:        https://kong-manager-konga-cp.apps-crc.testing"
