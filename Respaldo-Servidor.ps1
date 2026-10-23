<#
.SYNOPSIS
    Respaldo automático de carpetas de un servidor Windows con rotación y aviso por correo.

.DESCRIPTION
    Lee la configuración desde config.json, copia cada carpeta origen con Robocopy a un
    directorio temporal, la comprime en un .zip con fecha, borra los respaldos que superan
    los días de retención y envía un resumen por correo (opcional).
    Pensado para ejecutarse como tarea programada (ver Registrar-Tarea.ps1).

.PARAMETER ConfigPath
    Ruta del archivo de configuración. Por defecto, config.json junto al script.

.PARAMETER SinCorreo
    No envía el resumen por correo aunque esté habilitado en la configuración.

.EXAMPLE
    .\Respaldo-Servidor.ps1
    .\Respaldo-Servidor.ps1 -ConfigPath D:\scripts\config.json -SinCorreo

.NOTES
    Autor: Juan Sebastián Ortiz Quintero
    Requiere: PowerShell 5.1 o superior, Robocopy (incluido en Windows).
#>
[CmdletBinding()]
param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'config.json'),
    [switch]$SinCorreo
)

$ErrorActionPreference = 'Stop'

# ---------- utilidades ----------
function Escribir-Log {
    param([string]$Mensaje, [ValidateSet('INFO','AVISO','ERROR')][string]$Nivel = 'INFO')
    $linea = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Nivel, $Mensaje
    Add-Content -Path $script:ArchivoLog -Value $linea -Encoding UTF8
    switch ($Nivel) {
        'ERROR' { Write-Host $linea -ForegroundColor Red }
        'AVISO' { Write-Host $linea -ForegroundColor Yellow }
        default { Write-Host $linea }
    }
}

function Formatear-Tamano([long]$Bytes) {
    if ($Bytes -ge 1GB) { return '{0:N2} GB' -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return '{0:N1} MB' -f ($Bytes / 1MB) }
    return '{0:N0} KB' -f ($Bytes / 1KB)
}

function Enviar-Resumen {
    param($Cfg, [string]$Asunto, [string]$Cuerpo)
    $smtp = New-Object System.Net.Mail.SmtpClient($Cfg.Servidor, [int]$Cfg.Puerto)
    $smtp.EnableSsl = [bool]$Cfg.UsarSSL
    if ($Cfg.Usuario) {
        # La contraseña se guarda cifrada con Guardar-Credencial.ps1 (DPAPI, solo legible por la misma cuenta)
        $clave = Get-Content $Cfg.ArchivoClave | ConvertTo-SecureString
        $smtp.Credentials = New-Object System.Net.NetworkCredential($Cfg.Usuario, $clave)
    }
    $msg = New-Object System.Net.Mail.MailMessage($Cfg.De, $Cfg.Para, $Asunto, $Cuerpo)
    $msg.Attachments.Add((New-Object System.Net.Mail.Attachment($script:ArchivoLog)))
    $smtp.Send($msg)
    $msg.Dispose()
}

# ---------- inicio ----------
if (-not (Test-Path $ConfigPath)) { throw "No se encontró la configuración: $ConfigPath" }
$cfg = Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json

$fecha     = Get-Date -Format 'yyyyMMdd_HHmm'
$destino   = $cfg.Destino
$carpetaLogs = Join-Path $destino 'logs'
New-Item -ItemType Directory -Force -Path $destino, $carpetaLogs | Out-Null
$script:ArchivoLog = Join-Path $carpetaLogs "respaldo_$fecha.log"

Escribir-Log "Inicio del respaldo en $env:COMPUTERNAME. Destino: $destino"

# Espacio libre mínimo antes de empezar
$unidad = (Get-Item $destino).PSDrive
$libreGB = [math]::Round($unidad.Free / 1GB, 1)
if ($libreGB -lt $cfg.EspacioMinimoGB) {
    Escribir-Log "Espacio libre insuficiente en ${unidad}: $libreGB GB (mínimo $($cfg.EspacioMinimoGB) GB)" 'ERROR'
    $resultado = 'FALLIDO'
}
else {
    $errores = 0
    $resumen = @()

    foreach ($origen in $cfg.Origenes) {
        $nombre = $origen.Nombre
        $ruta   = $origen.Ruta
        if (-not (Test-Path $ruta)) {
            Escribir-Log "Origen no disponible: $ruta" 'ERROR'
            $errores++
            continue
        }

        $temporal = Join-Path $env:TEMP "respaldo_${nombre}_$fecha"
        $zip      = Join-Path $destino "${nombre}_$fecha.zip"
        $inicio   = Get-Date

        try {
            # /E subcarpetas, /R y /W reintentos cortos, /XJ evita bucles por uniones,
            # /NP sin porcentaje para un log limpio
            $argsRobo = @($ruta, $temporal, '/E', '/R:2', '/W:5', '/XJ', '/NP', '/NFL', '/NDL',
                          "/LOG+:$script:ArchivoLog")
            if ($origen.Excluir) { $argsRobo += '/XF'; $argsRobo += $origen.Excluir }
            & robocopy @argsRobo | Out-Null

            # Robocopy: 0-7 éxito o advertencia, 8 o más es error real
            if ($LASTEXITCODE -ge 8) { throw "Robocopy terminó con código $LASTEXITCODE" }

            Compress-Archive -Path (Join-Path $temporal '*') -DestinationPath $zip -CompressionLevel Optimal -Force
            $tam = (Get-Item $zip).Length
            $dur = [math]::Round(((Get-Date) - $inicio).TotalMinutes, 1)
            Escribir-Log "OK $nombre -> $(Split-Path $zip -Leaf) ($(Formatear-Tamano $tam), $dur min)"
            $resumen += "  - $nombre : OK, $(Formatear-Tamano $tam), $dur min"
        }
        catch {
            Escribir-Log "Falló $nombre : $($_.Exception.Message)" 'ERROR'
            $resumen += "  - $nombre : ERROR, $($_.Exception.Message)"
            $errores++
        }
        finally {
            if (Test-Path $temporal) { Remove-Item $temporal -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }

    # ---------- rotación ----------
    $limite = (Get-Date).AddDays(-[int]$cfg.DiasRetencion)
    $viejos = Get-ChildItem $destino -Filter '*.zip' | Where-Object { $_.LastWriteTime -lt $limite }
    foreach ($v in $viejos) {
        Remove-Item $v.FullName -Force
        Escribir-Log "Rotación: eliminado $($v.Name)"
    }
    Get-ChildItem $carpetaLogs -Filter '*.log' | Where-Object { $_.LastWriteTime -lt $limite } |
        Remove-Item -Force

    $resultado = if ($errores -eq 0) { 'CORRECTO' } else { "CON $errores ERROR(ES)" }
}

Escribir-Log "Fin del respaldo: $resultado"

# ---------- correo ----------
if ($cfg.Correo.Habilitado -and -not $SinCorreo) {
    $cuerpo = @"
Servidor: $env:COMPUTERNAME
Fecha: $(Get-Date -Format 'yyyy-MM-dd HH:mm')
Resultado: $resultado

Detalle:
$($resumen -join "`r`n")

Espacio libre en destino: $([math]::Round((Get-Item $destino).PSDrive.Free / 1GB, 1)) GB
"@
    try {
        Enviar-Resumen -Cfg $cfg.Correo -Asunto "[Respaldo] $env:COMPUTERNAME - $resultado" -Cuerpo $cuerpo
        Escribir-Log 'Resumen enviado por correo'
    }
    catch {
        Escribir-Log "No se pudo enviar el correo: $($_.Exception.Message)" 'AVISO'
    }
}

if ($resultado -ne 'CORRECTO') { exit 1 }
