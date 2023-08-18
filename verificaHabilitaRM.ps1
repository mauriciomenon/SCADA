# verifica servicos remotos e tenta habilitar para SSA 202312444
# Autor: Mauricio Menon
# Versao 1.4 17/08/2023
# Desenvolvido para PowerShell 5.1

$logFile = Join-Path -Path $PSScriptRoot -ChildPath ("logfile_" + (Get-Date -Format 'yyyyMMdd_HHmm') + ".txt")

Start-Transcript -Path $logFile

# Definicao de lista de consoles do CCR e Despacho
#$allConsoles = @('bitcon1', 'bitcon2', 'bitcon3', 'bitcon4', 'bitcon5', 'bitcon6', 'bitcon7', 'bitcon8', 'bitcon9', 'bitcon10', 'bitcon11', 'bitcon12', 'bitco31', 'bitcon32')
$allConsoles = @('localhost')

function Test-AdminPrivilege {
    # Se nao for Windows, simplesmente retorne
    if ($PSVersionTable.Platform -ne "Win32NT") {
        Write-Output "A verificacao de privilegios de administrador e aplicavel apenas em sistemas Windows."
        return
    }
    
    try {
        $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        if (-not $isAdmin) {
            Write-Error 'Este script deve ser executado com privilegio de Administrador.'
            exit
        }
        else {
            Write-Output 'Executado como usuario administrador'
        }
    } catch {
        Write-Error "Erro ao verificar privilegios de administrador: $_"
        exit
    }
}

function Get-Environment {
    $domain = $env:USERDNSDOMAIN
    if ($null -eq $domain) {
        Write-Error "Variavel de dominio nao esta definida."
        return $null
    }
    $domain = $domain.ToLower()

    if ($domain -match 'ems') {
        return "ems"
    }
    elseif ($domain -match 'itaipu') {       
        return "itaipu"                             
    }
    else {
        Write-Error "Dominio nao pertencente ao EMS-SCADA"
        return $null
    }
}

# Somente para a sessao atual
function Set-ExecutionPolicyIfRequired {
    if ((Get-ExecutionPolicy -Scope Process) -ne 'Unrestricted') {
        Set-ExecutionPolicy Unrestricted -Scope Process -Force
    }
}

function Test-BasicConnectivity {
    param (
        [Parameter(Mandatory=$true)]
        [string]$ComputerName
    )
    if (!(Test-Connection -ComputerName $ComputerName -Count 1 -Quiet)) {
        Write-Error "Falha na conectividade básica com $ComputerName."
        return $false
    }
    Write-Output "Conectividade basica com $ComputerName verificada com sucesso!"
    return $true
}

function Get-ServiceStatusViaWMI {
    param (
        [Parameter(Mandatory=$true)]
        [string]$ComputerName,
        [Parameter(Mandatory=$true)]
        [string]$ServiceName
    )
    
    try {
        $service = Get-WmiObject -Class Win32_Service -Filter "Name='$ServiceName'" -ComputerName $ComputerName
        if ($null -ne $service) {
            return $service.State
        } else {
            Write-Warning "O servico $ServiceName nao foi encontrado em $ComputerName."
            return $null
        }
    } catch {
        Write-Warning "Erro ao tentar obter o status do servico $ServiceName em $ComputerName."
        return $null
    }
}

function Start-ServiceViaWMI {
    param (
        [Parameter(Mandatory=$true)]
        [string]$ComputerName,
        [Parameter(Mandatory=$true)]
        [string]$ServiceName
    )
    
    try {
        $service = Get-WmiObject -Class Win32_Service -Filter "Name='$ServiceName'" -ComputerName $ComputerName
        if ($null -ne $service) {
            $service.StartService()
            Write-Output "O servico $ServiceName foi iniciado em $ComputerName."
        } else {
            Write-Warning "O servico $ServiceName nao foi encontrado em $ComputerName."
        }
    } catch {
        Write-Warning "Erro ao tentar iniciar o servico $ServiceName em $ComputerName."
    }
}

function Get-ServiceStatusViaDCOM {
    param (
        [Parameter(Mandatory=$true)]
        [string]$ComputerName,
        [Parameter(Mandatory=$true)]
        [string]$ServiceName
    )

    try {
        $service = New-Object System.ServiceProcess.ServiceController $ServiceName, $ComputerName
        return $service.Status
    } catch {
        Write-Warning "Erro ao tentar obter o status do servico $ServiceName em $ComputerName via DCOM."
        return $null
    }
}

function Start-ServiceViaDCOM {
    param (
        [Parameter(Mandatory=$true)]
        [string]$ComputerName,
        [Parameter(Mandatory=$true)]
        [string]$ServiceName
    )

    try {
        $service = New-Object System.ServiceProcess.ServiceController $ServiceName, $ComputerName
        if ($service.Status -eq 'Stopped') {
            $service.Start()
            $service.WaitForStatus('Running', '00:02:00')
            Write-Output "O servico $ServiceName foi iniciado em $ComputerName via DCOM."
        } else {
            Write-Output "O servico $ServiceName ja esta em execucao em $ComputerName."
        }
    } catch {
        Write-Warning "Erro ao tentar iniciar o servico $ServiceName em $ComputerName via DCOM."
    }
}

function Start-ServiceViaPsExec {
    param (
        [Parameter(Mandatory=$true)]
        [string]$ComputerName,
        [Parameter(Mandatory=$true)]
        [string]$ServiceName
    )

    try {
        $psexecPath = "C:\Path\To\PsExec.exe" # Substitua pelo caminho correto para o PsExec em seu sistema
        & $psexecPath \\$ComputerName net start $ServiceName
        Write-Output "O servico $ServiceName foi iniciado em $ComputerName via PsExec."
    } catch {
        Write-Warning "Erro ao tentar iniciar o servico $ServiceName em $ComputerName via PsExec."
    }
}

function Start-ServiceViaCIM {
    param (
        [Parameter(Mandatory=$true)]
        [string]$ComputerName,
        [Parameter(Mandatory=$true)]
        [string]$ServiceName
    )

    try {
        $service = Get-CimInstance -ClassName Win32_Service -Filter "Name='$ServiceName'" -ComputerName $ComputerName
        if ($null -ne $service) {
            if ($service.State -eq 'Stopped') {
                Invoke-CimMethod -InputObject $service -MethodName 'StartService'
                Write-Output "O servico $ServiceName foi iniciado em $ComputerName via CIM."
            } else {
                Write-Output "O servico $ServiceName ja esta em execucao em $ComputerName."
            }
        } else {
            Write-Warning "O servico $ServiceName nao foi encontrado em $ComputerName."
        }
    } catch {
        Write-Warning "Erro ao tentar iniciar o servico $ServiceName em $ComputerName via CIM."
    }
}

function Main {
    Test-AdminPrivilege
    $env = Get-Environment
    if ($env -eq "ems" -or $env -eq "itaipu") {
        Set-ExecutionPolicyIfRequired
        foreach ($console in $allConsoles) {
            # Teste de conectividade básica
            if (-not (Test-BasicConnectivity -ComputerName $console)) {
                continue
            }

            # Verificar o status dos servicos
            $servicesToCheck = @('WinRM', 'WS-Management')
            foreach ($service in $servicesToCheck) {
                $status = Get-ServiceStatusViaWMI -ComputerName $console -ServiceName $service
                if ($status -eq $null) {
                    # Tentar via DCOM se o WMI falhar
                    $status = Get-ServiceStatusViaDCOM -ComputerName $console -ServiceName $service
                }
                if ($status -eq "Stopped") {
                    Write-Warning "O servico $service em $console está parado. Tentando iniciá-lo..."
                    Start-ServiceViaWMI -ComputerName $console -ServiceName $service
                    # Tentar via DCOM se o WMI falhar
                    if ($status -eq $null) {
                        Start-ServiceViaDCOM -ComputerName $console -ServiceName $service
                    }
                    # Tentativa adicional via PsExec se as outras falharem
                    if ($status -eq $null) {
                        Start-ServiceViaPsExec -ComputerName $console -ServiceName $service
                    }
                    # Tentativa adicional via CIM se as outras falharem
                    if ($status -eq $null) {
                        Start-ServiceViaCIM -ComputerName $console -ServiceName $service
                    }
                } elseif ($status -eq "Running") {
                    Write-Output "O servico $service em $console já está em execucaoo."
                } else {
                    Write-Warning "Nao foi possivel determinar o status do servico $service em $console."
                }
            }
        }
    } else {
        Write-Warning "O script foi encerrado porque o dominio nao pertence ao EMS-SCADA."
    }
}

Main

Stop-Transcript

