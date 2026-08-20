# CONTPAQi Toolbox

> Soporte técnico, diagnóstico y operación diaria de CONTPAQi desde una sola interfaz ligera.

**Versión definitiva 6.6 · PowerShell 5.1 · Windows Forms**

CONTPAQi Toolbox es una herramienta desarrollada en PowerShell para concentrar tareas frecuentes de soporte y administración en equipos con sistemas CONTPAQi. Su interfaz gráfica busca reducir pasos manuales, organizar utilidades y facilitar el trabajo del consultor sin depender de una aplicación pesada.

## ¿Por qué existe?

En soporte técnico es común saltar entre consolas, rutas, servicios y herramientas. Toolbox reúne ese flujo en un panel visual para que el diagnóstico sea más rápido, repetible y fácil de documentar.

## Características

- Interfaz nativa construida con Windows Forms.
- Script único y portable: `TOOLBOX.ps1`.
- Compatible con Windows PowerShell 5.1.
- Acceso centralizado a rutinas de soporte para entornos CONTPAQi.
- Registro de actividad en `C:\ProgramData\CONTPAQiToolbox\Logs`.
- Diseño ligero con indicadores visuales de estado, advertencia y error.
- Preparado para distinguir funciones de servidor y terminal.
- Diagnóstico terminal-servidor de puertos, firewall, SMB, rutas compartidas y licencias.
- Integración opcional con Nmap y comprobación TCP nativa cuando no está instalado.
- Diagnóstico inteligente con reporte PDF y análisis de salud SQL.
- Reparaciones con confirmación escrita, actividad visible y validación final.
- Monitor ServicesDev integrado en el mismo ejecutable portable.

## Requisitos

- Windows 10, Windows 11 o Windows Server.
- Windows PowerShell 5.1 o posterior.
- Permisos de administrador para las acciones que modifican servicios o configuración.
- Componentes de CONTPAQi instalados cuando la función seleccionada los requiera.

## Ejecución

Descarga `TOOLBOX.ps1`, revisa su contenido y ejecútalo desde PowerShell:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\TOOLBOX.ps1
```

Para las funciones administrativas, abre PowerShell como administrador antes de iniciar el script.

## Estructura del proyecto

```text
TOOLBOX.ps1    Aplicación completa: interfaz, navegación y utilidades
README.md      Descripción, requisitos y guía de uso
```

Este repositorio publica únicamente el desarrollo en PowerShell. Los ejecutables compilados, resultados de diagnóstico, recursos locales y archivos temporales no forman parte del código fuente.

## Seguridad

Toolbox puede ejecutar tareas con privilegios elevados. Antes de usarlo en producción:

1. Revisa el código fuente.
2. Prueba primero en un ambiente controlado.
3. Respeta las políticas de respaldo y cambio de tu organización.
4. No agregues contraseñas, tokens ni datos de clientes al script.

## Registro y soporte

Las sesiones y eventos relevantes se almacenan en:

```text
C:\ProgramData\CONTPAQiToolbox\Logs
```

Incluye la versión de Toolbox y el registro correspondiente cuando reportes una incidencia.

## Estado del proyecto

La versión 6.6 es la edición definitiva estable de esta línea: conserva el enfoque de una sola herramienta portable, visual y práctica para soporte CONTPAQi.

---

Desarrollado por **Derek Salinas** para convertir tareas repetitivas de soporte en un flujo más claro y eficiente.
