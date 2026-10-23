<#
.SYNOPSIS
    Registra el respaldo como tarea programada diaria con la cuenta SYSTEM.

.EXAMPLE
    # En una consola de PowerShell como administrador:
    .\Registrar-Tarea.ps1 -Hora '23:30'
#>
[CmdletBinding()]
param(
    [string]$Hora = '23:00',
    [string]$NombreTarea = 'Respaldo diario del servidor'
)

#Requires -RunAsAdministrator

$script = Join-Path $PSScriptRoot 'Respaldo-Servidor.ps1'
$accion = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$script`"" `
    -WorkingDirectory $PSScriptRoot
$disparador = New-ScheduledTaskTrigger -Daily -At $Hora
$ajustes = New-ScheduledTaskSettingsSet -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Hours 6) `
    -RestartCount 2 -RestartInterval (New-TimeSpan -Minutes 15)

Register-ScheduledTask -TaskName $NombreTarea -Action $accion -Trigger $disparador -Settings $ajustes `
    -User 'SYSTEM' -RunLevel Highest -Force | Out-Null

Write-Host "Tarea '$NombreTarea' registrada para las $Hora todos los días." -ForegroundColor Green
