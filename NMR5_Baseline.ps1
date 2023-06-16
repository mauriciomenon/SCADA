# Baseline_NMR5 8.8
# Autor: Mauricio Menon
# 15/06/2023  SMIN.DT
# Desenvolvido para PowerShell 5.1, versão instalada por padrão no WS2012R2 e W10
# Versao 1.0  utilizada no TAF e Comissionamento do SCADA NMR5
# TO DO
# - Setar codificação para caracteres diacríticos
# - Reimplantar scriptblock que foi retirado para debug
# - Padronziar nome do csv

# Definicao de lista de consoles e servidores do EMS(inclui DTS) e PDS
# EMS Console and Server Lists
$EMSConsoleList = ('bitcon1', 'bitcon2', 'bitcon3', 'bitcon4', 'bitcon5', 'bitcon6', 'bitcon7', 'bitcon8', 'bitcon9', 'bitcon10', 'bitcon11', 'bitcon12', 'bitcon13', 'bitcon14', 'bitcon15', 'bitcon16', 'bitcon17', 'bitcon18', 'bitcon19', 'bitcon20', 'bitcon21', 'bitcon22', 'bitcon23', 'bitcon24', 'bitcon25', 'bitcon26', 'bitcon27', 'bitcon28', 'bitcon29', 'bitcon30', 'bitdtcon1', 'bitdtcon2', 'bitdtcon3', 'bitdtcon4', 'bitdtcon5', 'bitdtcon6', 'bitdtvaps1')
$EMSServerList = ('bitora1', 'bitora2', 'bithis1', 'bithis2', 'bitood1', 'bitood2', 'bitaps1', 'bitaps2', 'biticcp1', 'biticcp2', 'bitdmc1', 'bitdmc2', 'bitpcu1', 'bitpcu2', 'bitims1', 'bitims2', 'bitdtaps1')
    
# PDS Console and Server Lists
$PDSConsoleList = ('bitpdcon1', 'bitpdcon2', 'bitpdcon3', 'bitpdcon4')
$PDSServerList = ('bitpdaps1', 'bitpdvaps1', 'bitpdpcu1', 'bitpdora1', 'bitpdviccp1', 'bitpdvhis1')

# Limpar todas as variáveis da sessão atual
function Clear-AllVariables {
    $variables = Get-Variable -Scope Global -Exclude PWD, OLDPWD
    $variables | ForEach-Object {
        if ($_.Options -ne "Constant" -and $_.Options -ne "ReadOnly") {
            Set-Variable -Name $_.Name -Value $null -Force -ErrorAction SilentlyContinue
        }
    }
}

# Verificar execução como administrador
function Check-AdminPrivileges {
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-Host 'Este script deve ser executado com privilégios de administrador.'
    }
    else {
        write-warning 'Usuario Administrador'
    }
}

# Verificar a versão do PowerShell
function Check-PowerShellVersion {
        $psVersion = $PSVersionTable.PSVersion
        $versionFlag = 0

    # Imprimir a versão para o usuário
    Write-Host "Versao do PowerShell: $psVersion"

    # Verificar se é uma versão compatível (5.1, 6 ou 7)
    if ($psVersion.Major -eq 5 -and $psVersion.Minor -eq 1) {
        $versionFlag = 1
    }
    elseif ($psVersion.Major -gt 5 -or ($psVersion.Major -eq 5 -and $psVersion.Minor -ge 1)) {
        # elseif ($psVersion.Major -ge 6) {         #para pw 6 e acima existe o operador -ge
        #para implementação futura com powershell 6 ou 7
        $versionFlag = 2
    }
    else {
        # Versão inferior a 5
        Write-Host "A versao do PowerShell nao e suportada."
        return
    }
    return $versionFlag
}

# Obter o tempo limite de conexão, utilizado para PS6/7. PS51 nao tem suporte a esse parametro
# Sera utilizado em futura versao do SIMBA
function Get-Timeout {
    param (     [int]$defaultTimeout = 500     )
    # Verificar a versão do PowerShell
    $psVersion = $PSVersionTable.PSVersion
    $isPowerShell6OrAbove = $psVersion.Major -ge 6

    # Verificar se a versão é igual a 2 (PowerShell 6 ou superior)
    if ($isPowerShell6OrAbove) {
        $timeout = Read-Host 'Digite o tempo limite de conexão em milissegundos (padrão:'($defaultTimeout)')'
        if ([string]::IsNullOrEmpty($timeout)) {
            $timeout = $defaultTimeout
        }
        else {
            $timeout = [int]$timeout
        }
    }
    else {
        Write-Host "Definir Timeout requer PowerShell 6 ou superior."
        return
    }
    return $timeout
}

# Obter o nome do Domain/Environment  
function Get-Environment {
    $domain = $env:USERDNSDOMAIN
    $domain = $domain.ToLower()

    if ($domain -match 'ems') {  
        return "ems"
    }
    elseif ($domain -match 'pds') {
        return "pds"
    }
    elseif ($domain -match 'itaipu') {              # para criar lista para a máquina local no caso de debug do script
        return "itaipu"                             # depende de habilitação de serviço na máquina local
    }
    else {
        return "Dominio nao pertencente ao SCADA"      
    }
}

function Get-TargetList {
    param (   [string]$domain    )

    $ConsoleList = @()
    $ServerList = @()

    if ($domain -match 'ems') {  
        $ConsoleList = $EMSConsoleList              # Para futura lista separada de console e servidor
        $ServerList = $EMSServerList
    }
    elseif ($domain -match 'pds') {
        $ConsoleList = $PDSConsoleList              # Para futura lista separada de console e servidor
        $ServerList = $PDSServerList
    }
    elseif ($domain -match 'itaipu') {              # para criar lista para a máquina local no caso de debug do script
        $ConsoleList  = ('localhost')               # Somente para teste de execução local
    }
    else {
        Write-Host ""
        return @()
    }

    $targets = $ConsoleList + $ServerList           # Nesta versão cria lista unica
    return $targets
}

# Função para obter a lista de programas remotos
# Adaptado de Get-RemoteProgram Author: Jaap Brasser
function Get-RemoteProgram {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true,
            Position = 0
        )]
        [string[]]
        $ComputerName = $env:COMPUTERNAME,
        [Parameter(Position = 0)]
        [string[]]
        $Property,
        [string[]]
        $IncludeProgram,
        [string[]]
        $ExcludeProgram,
        [switch]
        $ProgramRegExMatch,
        [switch]
        $LastAccessTime,
        [switch]
        $ExcludeSimilar,
        [int]
        $SimilarWord
    )

    begin {
        $RegistryLocation = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\',
        'SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\'

        if ($psversiontable.psversion.major -gt 2) {
            $HashProperty = [ordered]@{}    
        }
        else {
            $HashProperty = @{}
            $SelectProperty = @('ComputerName', 'ProgramName')
            if ($Property) {
                $SelectProperty += $Property
            }
            if ($LastAccessTime) {
                $SelectProperty += 'LastAccessTime'
            }
        }
    }

    process {
        foreach ($Computer in $ComputerName) {
            try {
                $socket = New-Object Net.Sockets.TcpClient($Computer, 445)
                if ($socket.Connected) {
                    $RegBase = [Microsoft.Win32.RegistryKey]::OpenRemoteBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, $Computer)
                    $RegistryLocation | ForEach-Object {
                        $CurrentReg = $_
                        if ($RegBase) {
                            $CurrentRegKey = $RegBase.OpenSubKey($CurrentReg)
                            if ($CurrentRegKey) {
                                $CurrentRegKey.GetSubKeyNames() | ForEach-Object {
                                    $HashProperty.ProgramName = ($DisplayName = ($RegBase.OpenSubKey("$CurrentReg" + $_)).GetValue('DisplayName'))
                                    
                                    if ($IncludeProgram) {
                                        if ($ProgramRegExMatch) {
                                            $IncludeProgram | ForEach-Object {
                                                if ($DisplayName -notmatch $_) {
                                                    $DisplayName = $null
                                                }
                                            }
                                        }
                                        else {
                                            $IncludeProgram | ForEach-Object {
                                                if ($DisplayName -notlike $_) {
                                                    $DisplayName = $null
                                                }
                                            }
                                        }
                                    }

                                    if ($ExcludeProgram) {
                                        if ($ProgramRegExMatch) {
                                            $ExcludeProgram | ForEach-Object {
                                                if ($DisplayName -match $_) {
                                                    $DisplayName = $null
                                                }
                                            }
                                        }
                                        else {
                                            $ExcludeProgram | ForEach-Object {
                                                if ($DisplayName -like $_) {
                                                    $DisplayName = $null
                                                }
                                            }
                                        }
                                    }

                                    if ($DisplayName) {
                                        if ($Property) {
                                            foreach ($CurrentProperty in $Property) {
                                                $HashProperty.$CurrentProperty = ($RegBase.OpenSubKey("$CurrentReg" + $_)).GetValue($CurrentProperty)
                                            }
                                        }
                                        if ($LastAccessTime) {
                                            $InstallPath = ($RegBase.OpenSubKey("$CurrentReg" + $_)).GetValue('InstallLocation') -replace '\\$', ''
                                            if ($InstallPath) {
                                                $WmiSplat = @{
                                                    ComputerName = $Computer
                                                    Query        = $("ASSOCIATORS OF {Win32_Directory.Name='$InstallPath'} Where ResultClass = CIM_DataFile")
                                                    ErrorAction  = 'SilentlyContinue'
                                                }
                                                $HashProperty.LastAccessTime = Get-WmiObject @WmiSplat |
                                                    Where-Object { $_.Extension -eq 'exe' -and $_.LastAccessed } |
                                                        Sort-Object -Property LastAccessed |
                                                            Select-Object -Last 1 | ForEach-Object {
                                                                $_.ConvertToDateTime($_.LastAccessed)
                                                            }
                                                        }
                                                        else {
                                                            $HashProperty.LastAccessTime = $null
                                                        }
                                                    }

                                                    if ($psversiontable.psversion.major -gt 2) {
                                                        [pscustomobject]$HashProperty
                                                    }
                                                    else {
                                                        New-Object -TypeName PSCustomObject -Property $HashProperty |
                                                            Select-Object -Property $SelectProperty
                                                        }
                                                    }
                                                    $socket.Close()
                                                }
                                            }
                                        }
                                    }
                }
            }
                            catch {
                                Write-Error $_
                            }
        }
            }
}


function Get-ConnectionResult {
    param (      [string]$target     )
    $connected = $false

    try {
        $targetFileNameFormat = '{0}\{1}_{2}_{3}'
        #$targetFileName = $targetFileNameFormat -f $OutputPath, $domain, $target, (Get-Date).ToString('yyyyMMddHHmm')
        $targetFileName = $targetFileNameFormat -f $OutputPath, $domain, $target, (Get-Date).ToString('yyyyMMdd_HHmm')
        
        # Obter a lista de programas
        $softwareList = Get-RemoteProgram -ComputerName $target -Property DisplayVersion

        # Exportar para um arquivo CSV
        $softwareList | Export-Csv -Path "${targetFileName}.csv" -NoTypeInformation

        #Filtrar a lista de programas e escrever em um arquivo .txt
        $target | Out-File -FilePath "$OutputPath\${target}.txt" -Append
        $softwareList | Out-File "$OutputPath\${target}.txt" -Append
       
        # Adicionar a lista de programas ao arquivo Consoles_$domain.txt 
        $target | Out-File       "$OutputPath\Software_$domain.txt" -Append
        $softwareList | Out-File "$OutputPath\Software_$domain.txt" -Append

        $connected = $true
    }
    catch {
        Write-Host "Falha ao conectar-se ao alvo $target."
    }

    $connected
}

function Connect-ToTargets {
    param (
        [string]$OutputPath,
        [int]$attempts = 2,         #Duas tentivas de conexão                        
        [int]$timeout,
        [string]$domain,
        [string[]]$targets
    )

    $FailedConnections = @()

    foreach ($target in $targets) {
        Write-Host "Conectando ao alvo $($target)..."
        $connectionAttempts = 0
        $connected = $false

        do {
            $connectionAttempts++
            $connected = Get-ConnectionResult -target $target

            if (-not $connected -and $connectionAttempts -lt $attempts) {
                Write-Host 'Tentando novamente...'
                Start-Sleep -Milliseconds $timeout
            }
        }
        while (-not $connected -and $connectionAttempts -lt $attempts)

        if (-not $connected) {
            $FailedConnections += $target
        }
    }

    $FailedConnections | Out-File "$OutputPath\Falhas_comunicacao_$domain.txt"

    Write-Host 'Processo concluido.'
}
    
 function Main {
    Check-AdminPrivileges
    $timeout = Get-Timeout
    $domain  = Get-Environment
    Write-Host $domain
    $targets = Get-TargetList -domain $domain
    #$OutputPath = $PSScriptRoot + '\Resultados_' + $domain + '_' + (Get-Date -Format 'yyyyMMdd_HHmm')
                    $OutputPath = $PSScriptRoot + '\Resultados_' + (Get-Date -Format 'yyyyMMdd_HHmm') + '_' + $domain

    if (-not (Test-Path -Path $OutputPath -PathType Container)) {
        $null = New-Item -ItemType Directory -Path $OutputPath
    }

    Connect-ToTargets -OutputPath $OutputPath -attempts $attempts -timeout $timeout -domain $domain -targets $targets
 }
 
 Main