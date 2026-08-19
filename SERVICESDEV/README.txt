ServicesDev 1.2 - Monitor de servicios CONTPAQi
================================================
Dev Derek Salinas

Instalación:
1. Copie y descomprima la carpeta localmente en el VDI.
2. Ejecute Instalar.cmd con doble clic y acepte los permisos de administrador.
3. Revise la lista detectada y escriba SI únicamente si es correcta.

La detección excluye explícitamente los servicios de Microsoft SQL Server, incluso
cuando la instancia se llama COMPAC.

El servicio se ejecuta como LocalSystem y no necesita que un usuario inicie sesión.
Configuración y logs: C:\Program Files\ServicesDev

Diagnóstico en vivo para soporte:
Ejecute Diagnostico.cmd con doble clic desde la carpeta descomprimida. La pantalla
se actualiza cada 5 segundos y es de solo lectura: Q sale y R actualiza al momento.

Integracion con CONTPAQi Toolbox v6.8:
Abra [W] ServicesDev para instalar o actualizar el watchdog directamente desde
Toolbox. El panel muestra el estado y la bitacora cada 5 segundos e incluye las
opciones Iniciar, Detener, Reiniciar, Actualizar y Salir. La version portable de
Toolbox contiene ServicesDev.exe como recurso embebido.

Para indicar servicios concretos:
.\Install.ps1 -ServiceNames 'NombreInterno1','NombreInterno2'

Use Get-Service o services.msc para consultar los nombres internos. Para cambiar la
lista después de instalar, edite watchdog.json como administrador y reinicie el
servicio ServicesDev.

Desinstalación:
Ejecute Desinstalar.cmd con doble clic y acepte los permisos de administrador.

Compilación después de modificar el código (desde la carpeta del proyecto):
dotnet publish .\ContpaqiWatchdog.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -o .\publicado --source https://api.nuget.org/v3/index.json

El ejecutable nuevo quedará en: .\publicado\ServicesDev.exe

VDI no persistente: instale en la imagen maestra/dorada y selle la imagen. Si la
máquina se recompone al cerrar sesión o reiniciar, una instalación local desaparecerá.

Importante: este watchdog recupera servicios detenidos; no corrige credenciales,
licencias, dependencias, bases de datos o fallas propias de CONTPAQi.
