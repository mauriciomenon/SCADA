# Função para verificar a conectividade básica
function Test-BasicConnectivity {
    param (
        [Parameter(Mandatory=$true)]
        [string] $ComputerName
    )

    Write-Output "Verificando conectividade básica com $ComputerName..."
    # Verifique se o host responde ao ping
    $pingResult = Test-Connection -ComputerName $ComputerName -Count 1 -Quiet
    if (-not $pingResult) {
        Write-Warning "Ping falhou para $ComputerName."
        return $false
    }

    # Verifique a conectividade na porta 5985
    try {
        $portResult = Test-NetConnection -ComputerName $ComputerName -Port 5985
        if ($portResult.TcpTestSucceeded) {
            Write-Output "Porta 5985 está aberta em $ComputerName."
            return $true
        }
    } catch {
        Write-Warning "Falha ao testar a porta 5985 em $ComputerName."
        return $false
    }

    return $false
}

# Função para obter o status do serviço via WMI
function Get-ServiceStatusViaWMI {
    param (
        [Parameter(Mandatory=$true)]
        [string] $ComputerName,
        [Parameter(Mandatory=$true)]
        [string] $ServiceName
    )

    try {
        $service = Get-WmiObject -Class Win32_Service -Filter "Name='$ServiceName'" -ComputerName $ComputerName
        Write-Output "$ServiceName em $ComputerName está $($service.State)."
        return $service.State
    } catch {
        Write-Warning "Falha ao obter status de $ServiceName em $ComputerName via WMI."
        return $null
    }
}

# Função para iniciar um serviço via WMI
function Start-ServiceViaWMI {
    param (
        [Parameter(Mandatory=$true)]
        [string] $ComputerName,
        [Parameter(Mandatory=$true)]
        [string] $ServiceName
    )

    try {
        $service = Get-WmiObject -Class Win32_Service -Filter "Name='$ServiceName'" -ComputerName $ComputerName
        $service.StartService()
        Write-Output "$ServiceName foi iniciado em $ComputerName."
    } catch {
        Write-Warning "Falha ao iniciar $ServiceName em $ComputerName via WMI."
    }
}

# Roteiro principal
$allConsoles = @('bitcon1', 'bitcon2') # Lista reduzida para brevidade

foreach ($console in $allConsoles) {
    # Teste de conectividade básica
    if (-not (Test-BasicConnectivity -ComputerName $console)) {
        continue
    }

    # Testando WS-Management e WinRM via Invoke-Command ou WMI como fallback
    try {
        Write-Output "Verificando WS-Management em $console via Invoke-Command..."
        $wsManStatus = Invoke-Command -ComputerName $console -ScriptBlock {
            (Get-Service -Name "winmgmt").Status
        }
        Write-Output "WS-Management em $console está $wsManStatus."
    } catch {
        Write-Warning "Invoke-Command falhou para WS-Management em $console. Tentando WMI."
        $wsManStatus = Get-ServiceStatusViaWMI -ComputerName $console -ServiceName "winmgmt"
    }

    # Se os serviços não estiverem rodando, tente iniciá-los
    if ($wsManStatus -ne 'Running') {
        Write-Output "Tentando iniciar WS-Management em $console via Invoke-Command..."
        try {
            Invoke-Command -ComputerName $console -ScriptBlock {
                Start-Service -Name "winmgmt"
            }
            Write-Output "WS-Management iniciado com sucesso em $console."
        } catch {
            Write-Warning "Invoke-Command falhou ao iniciar WS-Management em $console. Tentando via WMI."
            Start-ServiceViaWMI -ComputerName $console -ServiceName "winmgmt"
        }
    }

    # Lógica similar para WinRM
    try {
        Write-Output "Verificando WinRM em $console via Invoke-Command..."
        $winRMStatus = Invoke-Command -ComputerName $console -ScriptBlock {
            (Get-Service -Name "WinRM").Status
        }
        Write-Output "WinRM em $console está $winRMStatus."
    } catch {
        Write-Warning "Invoke-Command falhou para WinRM em $console. Tentando WMI."
        $winRMStatus = Get-ServiceStatusViaWMI -ComputerName $console -ServiceName "WinRM"
    }

    if ($winRMStatus -ne 'Running') {
        Write-Output "Tentando iniciar WinRM em $console via Invoke-Command..."
        try {
            Invoke-Command -ComputerName $console -ScriptBlock {
                Start-Service -Name "WinRM"
            }
            Write-Output "WinRM iniciado com sucesso em $console."
        } catch {
            Write-Warning "Invoke-Command falhou ao iniciar WinRM em $console. Tentando via WMI."
            Start-ServiceViaWMI -ComputerName $console -ServiceName "WinRM"
        }
    }
}

