# changeSvcLink para SSA 202312444
# Autor: Mauricio Menon
# Versão 1.0 31/07/2023
# Desenvolvido para PowerShell 5.1

$logFile = Join-Path -Path (Get-Location).Path -ChildPath "logfile.txt"
Start-Transcript -Path $logFile

# Definicao de lista de consoles do CCR e Despacho
$ccrConsoleList = @('bitcon1', 'bitcon2', 'bitcon3', 'bitcon4', 'bitcon5', 'bitcon6', 'bitco11', 'bitcon12')
$ldrConsoleList = @('bitcon7', 'bitcon8', 'bitcon9', 'bitcon10')
$allConsoles = $ccrConsoleList + $ldrConsoleList

function Test-AdminPrivilege {
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-Host 'Este script deve ser executado com privilegio de Administrador.'
    }
    else {
        Write-Warning 'Execucao como usuario Administrador'
    }
}

function Get-Environment {
    $domain = $env:USERDNSDOMAIN
    $domain = $domain.ToLower()

    if ($domain -match 'ems') {
        return "ems"
    }
    elseif ($domain -match 'itaipu') {
        # para criar lista para a máquina local no caso de debug do script
        return "itaipu"                            
    }
    else {
        return "Dominio nao pertencente ao EMS-SCADA"
    }
}

function Process-Consoles {
    foreach ($console in $allConsoles) {
        Write-Output "Processando console $console"

        # Alterando o link do SCV
        $shortcutPath = Join-Path -Path $console -ChildPath "c:\Users\ibuser\Desktop\SCV.lnk"
        if (Test-Path -Path $shortcutPath) {
            $shell = New-Object -ComObject WScript.Shell
            $shortcut = $shell.CreateShortcut($shortcutPath)
            $shortcut.TargetPath = "\\bitaps1\scv\bin\SCV.exe"
            $shortcut.Save()
            Write-Output "Link do aplicativo SCV alterado com sucesso em $console"
        }
        else {
            Write-Output "Link do aplicativo SCV nao encontrado em $console"
        }

        # Remover as pastas
        $foldersToRemove = @("c:\aplicativos\scv\bin", "c:\aplicativos\scv\Xml")
        foreach ($folder in $foldersToRemove) {
            $folderPath = Join-Path -Path $console -ChildPath $folder
            if (Test-Path -Path $folderPath) {
                Remove-Item -Path $folderPath -Recurse -Force
                Write-Output "Pasta $folder removida com sucesso de $console"
            }
            else {
                Write-Output "Pasta $folder nao encontrada em $console"
            }
        }
    }
}

function main {
    Test-AdminPrivilege
    $env = Get-Environment
    if ($env -ne "Dominio nao pertencente ao EMS-SCADA") {
        Process-Consoles
    }
}

main

Stop-Transcript
