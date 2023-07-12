#$remoteComputerName = 'localhost' # substitua 'RemoteComputer' pelo nome do seu computador remoto
#$credential = Get-Credential # isso solicitará seu nome de usuário e senha




$remoteComputerName = 'localhost' # substitua 'localhost' pelo nome do seu computador

# Comando para obter a lista completa de Servicepack
$hotfixes = Get-CimInstance -ClassName Win32_QuickFixEngineering -ComputerName $remoteComputerName 

# Exporta todas as propriedades para CSV
$hotfixes | Export-Csv -Path C:\Users\menon\git\SCADA\SOPHO_kb.csv -NoTypeInformation

# Exibe ou exporta apenas as propriedades específicas para TXT
$hotfixes | Select-Object Description, FixComments, HotFixID, InstalledBy, InstalledOn | Out-File -FilePath C:\Users\menon\git\SCADA\SOPHO_kb.txt
