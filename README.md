# Respaldos automáticos para Windows Server

Scripts en PowerShell para respaldar carpetas de un servidor de archivos todos los días, guardar varias versiones y avisar por correo si algo falla.

Los armé a partir de lo que necesitaba en el día a día administrando servidores de archivos: que el respaldo corra solo, que no llene el disco y que me entere temprano cuando algo no salió bien.

## Qué hace

- Copia cada carpeta configurada con **Robocopy** (reintentos, sin seguir uniones, log detallado).
- Comprime cada copia en un `.zip` con fecha: `Contabilidad_20261023_2300.zip`.
- **Verifica el espacio libre** en el destino antes de empezar.
- **Rotación**: borra respaldos y logs con más de N días.
- Envía un **resumen por correo** con el log adjunto (opcional).
- Devuelve código de salida `1` si hubo errores, para que la tarea programada lo marque como fallida.

## Archivos

| Archivo | Para qué sirve |
|---|---|
| `Respaldo-Servidor.ps1` | Script principal |
| `config.json` | Orígenes, destino, retención y correo |
| `Registrar-Tarea.ps1` | Crea la tarea programada diaria |
| `Guardar-Credencial.ps1` | Guarda la contraseña SMTP cifrada (DPAPI) |

## Uso

1. Copie la carpeta al servidor, por ejemplo en `C:\Scripts\Respaldos`.
2. Edite `config.json` con sus rutas:

```json
"Destino": "E:\\Respaldos",
"DiasRetencion": 14,
"Origenes": [
  { "Nombre": "Contabilidad", "Ruta": "D:\\Contabilidad" }
]
```

3. Pruebe una ejecución manual:

```powershell
.\Respaldo-Servidor.ps1 -SinCorreo
```

4. Registre la tarea (PowerShell como administrador):

```powershell
.\Registrar-Tarea.ps1 -Hora '23:30'
```

### Correo (opcional)

Ponga `"Habilitado": true` en la sección `Correo` y guarde la contraseña cifrada:

```powershell
.\Guardar-Credencial.ps1 -Ruta C:\Scripts\Respaldos\smtp.clave
```

La contraseña nunca queda en texto plano: se cifra con DPAPI y solo la puede leer la misma cuenta en el mismo equipo.

## Buenas prácticas

- Guarde el destino en **otro disco** distinto al de los datos, y si es posible copie los `.zip` a un segundo lugar (NAS o nube). Regla 3-2-1.
- **Pruebe restaurar** un archivo al menos una vez al mes. Un respaldo que no se ha probado no es un respaldo.
- Para bases de datos SQL Server respalde con `BACKUP DATABASE` y luego deje que este script copie los `.bak`.

## Requisitos

- Windows Server 2012 R2 o superior (o Windows 10/11)
- PowerShell 5.1 o superior

---
Juan Sebastián Ortiz Quintero · Ingeniero en Mecatrónica · [Industrias Ortiz](https://jsortizq.github.io)
