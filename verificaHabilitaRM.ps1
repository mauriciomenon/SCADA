# verifica servicos remotos e tenta habilitar para SSA 202312444
# Autor: Mauricio Menon
# Versao 1.5 17/08/2023
# Desenvolvido para PowerShell 5.1

$logFile = Join-Path -Path $PSScriptRoot -ChildPath ("logfile_" + (Get-Date -Format 'yyyyMMdd_HHmm') + ".txt")

Start-Transcript -Path $logFile

Add-Type -AssemblyName "System.ServiceProcess"

# Definicao de lista de consoles do CCR e Despacho
#$allConsoles = @('bitcon1', 'bitcon2', 'bitcon3', 'bitcon4', 'bitcon5', 'bitcon6', 'bitcon7', 'bitcon8', 'bitcon9', 'bitcon10', 'bitcon11', 'bitcon12', 'bitco31', 'bitcon32')
$allConsoles = @('localhost')

function Test-AdminPrivilege {
    # Se nao for Windows, simplesmente retorne
    if ($PSVersionTable.Platform -ne "Win32NT") {
        Write-Host "A verificacao de privilegios de administrador e aplicavel apenas em sistemas Windows."
        return
    }
    
    try {
        $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        if (-not $isAdmin) {
            Write-Error 'Este script deve ser executado com privilegio de Administrador.'
            exit
        }
        else {
            Write-Host 'Executado como usuario administrador'
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
        [Parameter(Mandatory = $true)]
        [string]$ComputerName
    )
    if (!(Test-Connection -ComputerName $ComputerName -Count 1 -Quiet)) {
        Write-Host "Falha na conectividade básica com $ComputerName." -ForegroundColor Red
        return $false
    }
    Write-Host "Conectividade basica com $ComputerName verificada com sucesso!" -ForegroundColor Green
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
            Write-Host "O servico $ServiceName nao foi encontrado em $ComputerName via WMI." 
            return $null
        }
    } catch {
        Write-Host "Erro ao tentar obter o status do servico $ServiceName em $ComputerName via WMI."
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
            Write-Host "O servico $ServiceName foi iniciado em $ComputerName. via WMI"
        } else {
            Write-Warning "O servico $ServiceName nao foi iniciado/encontrado em $ComputerName via WMI. "
        }
    } catch {
        Write-Warning "Erro ao tentar iniciar o servico $ServiceName em $ComputerName via WMI."
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
        echo $service.Status
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
            Write-Host "O servico $ServiceName foi iniciado em $ComputerName via DCOM."
        } else {
            Write-Host "O servico $ServiceName tem estado inconclusivo. (DCOM)"
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
        $psexecPath = "C:\Windows\System32\PSTools"
        & $psexecPath \\$ComputerName net start $ServiceName
        Write-Host "O servico $ServiceName foi iniciado em $ComputerName via PsExec."
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
                Write-Host "O servico $ServiceName foi iniciado em $ComputerName via CIM."
            } else {
                Write-Host "O servico $ServiceName ja esta em execucao em $ComputerName  (verificacao via CIM)."
            }
        } else {
            Write-Host "O servico $ServiceName nao foi encontrado em $ComputerName (verificacao via CIM)."
        }
    } catch {
        Write-Warning "Erro ao tentar iniciar o servico $ServiceName em $ComputerName via CIM."
    }
}

function Main_Status {
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
                Write-Host "$service"
                Write-Host "Obtendo Status de $service via WMI"
                $status = Get-ServiceStatusViaWMI -ComputerName $console -ServiceName $service
                
                if ($status -ne "Running") {
                    Write-Host "Fallback, tentativa de obter status de $service via DCOM"
                    $status = Get-ServiceStatusViaDCOM -ComputerName $console -ServiceName $service
                                    }
               
                if ($status -ne "Running") {
                    Write-Host "O servico $service em $console tem o estado diferente de Running. Tentando inicia-lo via WMI."
                    Start-ServiceViaWMI -ComputerName $console -ServiceName $service

                    if ($status -ne "Running") {
                        Start-ServiceViaDCOM -ComputerName $console -ServiceName $service
                        Write-Host "Tentativa adicional via DCOM"
                    }
                    # Tentativa adicional via PsExec se as outras falharem
                    if ($status -ne "Running") {
                        Start-ServiceViaPsExec -ComputerName $console -ServiceName $service
                        Write-Host "Tentativa adicional via PsExec"
                    }
                    # Tentativa adicional via CIM se as outras falharem
                    if ($status -ne "Running") {
                        Start-ServiceViaCIM -ComputerName $console -ServiceName $service
                        Write-Host "Tentativa adicional via CIM"
                    }
                } elseif ($status -eq "Running") {
                    Write-Host "O servico $service em $console esta em execucao (Running)." 
                } else {
                    Write-Warning "Nao foi possivel determinar o status do servico $service em $console (WMI, DCOM, PsExec e CIM)."
                }
            }
        }
    } else {
        Write-Warning "O script foi encerrado porque o dominio nao pertence ao EMS-SCADA."
    }
}

Main

Stop-Transcript

