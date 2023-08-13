# changeSvcLink para SSA 202312444
# Autor: Mauricio Menon
# Versão 1.2 31/07/2023
# Desenvolvido para PowerShell 5.1

$logFile = Join-Path -Path (Get-Location).Path -ChildPath "logfile.txt"
Start-Transcript -Path $logFile

# Definicao de lista de consoles do CCR e Despacho
$allConsoles = @('bitcon1', 'bitcon2', 'bitcon3', 'bitcon4', 'bitcon5', 'bitcon6', 'bitcon7', 'bitcon8', 'bitcon9', 'bitcon10', 'bitcon11', 'bitcon12', 'bitco31', 'bitcon32')

function Test-AdminPrivilege {
    # Se não for Windows, simplesmente retorne
    if ($PSVersionTable.Platform -ne "Win32NT") {
        Write-Warning "A verificação de privilégios de administrador é aplicável apenas em sistemas Windows."
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
        Write-Warning "Erro ao verificar privilégios de administrador: $_"
        exit
    }
}

function Get-Environment {
    $domain = $env:USERDNSDOMAIN
    if ($null -eq $domain) {
        Write-Warning "Variável de domínio não está definida."
        return $null
    }
    $domain = $domain.ToLower()

    if ($domain -match 'ems') {
        return "ems"
    } else {
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


function Process-Consoles {
    foreach ($console in $allConsoles) {
        Write-Output "Processando console $console"

        Invoke-Command -ComputerName $console -ScriptBlock {

            # Alterando o link do SCV
            $shortcutPath = "c:\Users\ibuser\Desktop\SCV.lnk"
            if (Test-Path -Path $shortcutPath) {
                $shell = New-Object -ComObject WScript.Shell
                $shortcut = $shell.CreateShortcut($shortcutPath)
                $shortcut.TargetPath = "\\bitaps1\scv\bin\SCV.exe"
                $shortcut.WorkingDirectory = "\\bitaps1\scv\bin\"
                $shortcut.Save()
                Write-Output "Link do aplicativo SCV alterado com sucesso em $using:console"
            }
            else {
                Write-Output "Link do aplicativo SCV nao encontrado em $using:console"
            }

            # Remover as pastas
            $foldersToRemove = @("c:\aplicativos\scv\bin", "c:\aplicativos\scv\Xml")
            foreach ($folder in $foldersToRemove) {
                if (Test-Path -Path $folder) {
                    Remove-Item -Path $folder -Recurse -Force
                    Write-Output "Pasta $folder removida com sucesso de $using:console"
                }
                else {
                    Write-Output "Pasta $folder nao encontrada em $using:console"
                }
            }
        }
    }
}

function main {
    Test-AdminPrivilege
    $env = Get-Environment
    if ($env -eq "ems") {
        Set-ExecutionPolicyIfRequired
        Process-Consoles
    }
}

main

Stop-Transcript
