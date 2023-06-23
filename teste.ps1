function Get-RemoteSystemInfo {
    param(
        [Parameter(Mandatory = $true)]
        [string]
        $ComputerName
    )
    try {
        $socket = New-Object Net.Sockets.TcpClient($ComputerName, 445)
        if ($socket.Connected) {
            Write-Host "Conexão estabelecida com $ComputerName"
            Invoke-Command -ComputerName $ComputerName -ScriptBlock {
                $os = Get-CimInstance -ClassName Win32_OperatingSystem
                $bios = Get-CimInstance -ClassName Win32_BIOS
                $software = Get-WmiObject -Class Win32_Product
                $services = Get-Service

                $os | Export-Csv -Path "C:\Users\menon\git\SCADA\SOPHO_OS.csv" -NoTypeInformation
                $bios | Export-Csv -Path "C:\Users\menon\git\SCADA\SOPHO_BIOS.csv" -NoTypeInformation
                $software | Export-Csv -Path "C:\Users\menon\git\SCADA\SOPHO_software.csv" -NoTypeInformation
                $services | Export-Csv -Path "C:\Users\menon\git\SCADA\SOPHO_Services.csv" -NoTypeInformation
            }
        }
        else {
            Write-Host "Não foi possível conectar ao computador: $ComputerName"
        }
    }
    catch {
        Write-Error $_
    }
    finally {
        if ($socket) {
            $socket.Close()
        }
    }
}

# Muda o diretório de trabalho
Set-Location "C:\Users\menon\git\SCADA"

# Main
# $computers = "Computer1", "Computer2", "Computer3"
$computers = 'localhost'
foreach ($computer in $computers) {
    Get-RemoteSystemInfo -ComputerName $computer
}
