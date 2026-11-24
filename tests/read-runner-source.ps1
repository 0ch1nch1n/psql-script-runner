param([Parameter(Mandatory = $true)][string]$Path)

$file = [IO.File]::ReadAllText($Path, [Text.UTF8Encoding]::new($false, $true))
$marker = [regex]::Match($file, '(?m)^:POWERSHELL_PAYLOAD\r?$')
if (-not $marker.Success) { throw "Embedded PowerShell payload was not found in $Path." }
$file.Substring($marker.Index + $marker.Length)
