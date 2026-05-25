$ErrorActionPreference = "Stop"

function Merge-ConfigObject {
    param(
        [pscustomobject]$Base,
        [pscustomobject]$Override
    )

    foreach ($property in $Override.PSObject.Properties) {
        $name = $property.Name
        $overrideValue = $property.Value

        if ($Base.PSObject.Properties.Name.Contains($name)) {
            $baseValue = $Base.$name
            if ($baseValue -is [pscustomobject] -and $overrideValue -is [pscustomobject]) {
                Merge-ConfigObject -Base $baseValue -Override $overrideValue
            }
            else {
                $Base.$name = $overrideValue
            }
        }
        else {
            $Base | Add-Member -NotePropertyName $name -NotePropertyValue $overrideValue
        }
    }
}

$projectRoot = Split-Path $PSScriptRoot -Parent
$configPath = Join-Path $projectRoot "dispatcher\config.json"
$localConfigPath = Join-Path $projectRoot "dispatcher\config.local.json"

if (-not (Test-Path $configPath)) {
    throw "Missing config file: $configPath"
}

$config = Get-Content $configPath -Raw | ConvertFrom-Json

if (Test-Path $localConfigPath) {
    $localConfig = Get-Content $localConfigPath -Raw | ConvertFrom-Json
    Merge-ConfigObject -Base $config -Override $localConfig
}

return $config
