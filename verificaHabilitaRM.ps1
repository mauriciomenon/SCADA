# verifica servicos remotos e tenta habilitar para SSA 202312444
# Autor: Mauricio Menon
# Versão 1.3 13/08/2023
# Desenvolvido para PowerShell 5.1

$logFile = Join-Path -Path (Get-Location).Path -ChildPath "logfile.txt"
Start-Transcript -Path $logFile

# Definicao de lista de consoles do CCR e Despacho
#$allConsoles = @('bitcon1', 'bitcon2', 'bitcon3', 'bitcon4', 'bitcon5', 'bitcon6', 'bitcon7', 'bitcon8', 'bitcon9', 'bitcon10', 'bitcon11', 'bitcon12', 'bitco31', 'bitcon32')
$allConsoles = @('localhost')

function Test-AdminPrivilege {
    # Se não for Windows, simplesmente retorne
    if ($PSVersionTable.Platform -ne "Win32NT") {
        Write-Warning "A verificacao de privilegios de administrador e aplicavel apenas em sistemas Windows."
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
        Write-Warning "Erro ao verificar privilegios de administrador: $_"
        exit
    }
}

function Get-Environment {
    $domain = $env:USERDNSDOMAIN
    if ($null -eq $domain) {
        Write-Warning "Variavel de domínio nao esta definida."
        return $null
    }
    $domain = $domain.ToLower()

    if ($domain -match 'ems') {
        return "ems"
    }      elseif ($domain -match 'itaipu') {       # para criar lista para a máquina local no caso de debug do script
        return "itaipu"                             # depende de habilitação de serviço na máquina local
    }    else {
        Write-Warning "Dominio nao pertencente ao EMS-SCADA"
        return $null
    }
}

# Somente para a sessão atual
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
        Write-Warning "Falha na conectividade básica com $ComputerName."
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
        if ($service) {
            return $service.State
        } else {
            Write-Warning "O servico $ServiceName não foi encontrado em $ComputerName."
            return $null
        }
    } catch {
        Write-Warning "Erro ao tentar obter o status do serviço $ServiceName em $ComputerName."
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
        if ($service) {
            $service.StartService()
            Write-Output "O servico $ServiceName foi iniciado em $ComputerName."
        } else {
            Write-Warning "O servico $ServiceName nao foi encontrado em $ComputerName."
        }
    } catch {
        Write-Warning "Erro ao tentar iniciar o servico $ServiceName em $ComputerName."
    }
}

function Main {
    Test-AdminPrivilege
    $env = Get-Environment
    if ($env -eq "ems") {
        Set-ExecutionPolicyIfRequired
        foreach ($console in $allConsoles) {
            # Teste de conectividade básica
            if (-not (Test-BasicConnectivity -ComputerName $console)) {
                continue
            }

            # Verificar o status dos serviços
            $servicesToCheck = @('WinRM', 'WS-Management')
            foreach ($service in $servicesToCheck) {
                $status = Get-ServiceStatusViaWMI -ComputerName $console -ServiceName $service
                if ($status -eq "Stopped") {
                    Write-Warning "O servico $service em $console esta parado. Tentando inicia-lo..."
                    Start-ServiceViaWMI -ComputerName $console -ServiceName $service
                } elseif ($status -eq "Running") {
                    Write-Output "O servico $service em $console ja está em execucao."
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
