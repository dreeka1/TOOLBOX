# Instalador de CONTPAQi Toolbox v6.6

El instalador se genera con NSIS 3.12 y Modern UI 2. No descarga componentes durante la instalación.

## Compilar

1. Compila primero `TOOLBOXV6.6.exe` en la raíz del proyecto.
2. Instala NSIS con `winget install --exact --id NSIS.NSIS`.
3. Ejecuta `Build-Installer.ps1` desde Windows PowerShell 5.1.

El resultado se guarda en:

```text
output\installer\CONTPAQi_Toolbox_Setup_v6.6.exe
```

## Comportamiento

- Requiere permisos de administrador.
- Instala en `C:\Program Files\CONTPAQi Toolbox`.
- Crea accesos en el menú Inicio y, opcionalmente, en el escritorio.
- Registra un desinstalador compatible con Aplicaciones instaladas de Windows.
- Impide actualizar o desinstalar mientras Toolbox está ejecutando una operación.
- Conserva diagnósticos, logs y reportes ubicados en `C:\ProgramData\CONTPAQiToolbox`.
- Admite instalación y desinstalación silenciosas mediante `/S`.

El ejecutable portable y el instalador no están firmados digitalmente hasta que se proporcione un certificado de firma de código confiable.
