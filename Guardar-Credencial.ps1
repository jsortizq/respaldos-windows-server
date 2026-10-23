<#
.SYNOPSIS
    Guarda la contraseña SMTP cifrada con DPAPI para que el respaldo pueda enviar correos.

.DESCRIPTION
    El archivo resultante solo lo puede descifrar la misma cuenta de Windows en el mismo equipo.
    Si la tarea corre como SYSTEM, ejecute este script como SYSTEM (por ejemplo con PsExec -s).

.EXAMPLE
    .\Guardar-Credencial.ps1 -Ruta C:\Scripts\Respaldos\smtp.clave
#>
param([Parameter(Mandatory)][string]$Ruta)

$clave = Read-Host 'Contraseña de la cuenta SMTP' -AsSecureString
$clave | ConvertFrom-SecureString | Set-Content -Path $Ruta -Encoding ASCII
Write-Host "Credencial guardada en $Ruta" -ForegroundColor Green
