Unicode True
RequestExecutionLevel admin
ManifestDPIAware true
ManifestSupportedOS all

!include "MUI2.nsh"
!include "LogicLib.nsh"
!include "WinVer.nsh"

!define APP_NAME "TOOLBOX"
!define APP_VERSION "6.6.1"
!define APP_PUBLISHER "Derek Salinas"
!define APP_EXE "TOOLBOXV6.6.1.exe"
!define APP_REG_KEY "Software\CONTPAQi Toolbox"
!define APP_UNINSTALL_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\CONTPAQi Toolbox"

Name "${APP_NAME} ${APP_VERSION}"
OutFile "..\output\installer\TOOLBOX_Setup_v6.6.1.exe"
InstallDir "$PROGRAMFILES64\TOOLBOX"
InstallDirRegKey HKLM "${APP_REG_KEY}" "InstallLocation"
BrandingText "${APP_NAME} v${APP_VERSION} | Derek Salinas"
ShowInstDetails show
ShowUninstDetails show
SetCompressor /SOLID lzma
SetCompressorDictSize 64

VIProductVersion "6.6.1.0"
VIAddVersionKey /LANG=1034 "ProductName" "${APP_NAME}"
VIAddVersionKey /LANG=1034 "ProductVersion" "${APP_VERSION}"
VIAddVersionKey /LANG=1034 "FileDescription" "Instalador de TOOLBOX para soporte CONTPAQi"
VIAddVersionKey /LANG=1034 "FileVersion" "6.6.1.0"
VIAddVersionKey /LANG=1034 "CompanyName" "${APP_PUBLISHER}"
VIAddVersionKey /LANG=1034 "LegalCopyright" "${APP_PUBLISHER}"

!define MUI_ICON "..\ASSETS\DS.ico"
!define MUI_UNICON "..\ASSETS\DS.ico"
!define MUI_ABORTWARNING
!define MUI_WELCOMEFINISHPAGE_BITMAP "assets\toolbox-welcome.bmp"
!define MUI_UNWELCOMEFINISHPAGE_BITMAP "assets\toolbox-welcome.bmp"
!define MUI_HEADERIMAGE
!define MUI_HEADERIMAGE_RIGHT
!define MUI_HEADERIMAGE_BITMAP "assets\toolbox-header.bmp"
!define MUI_HEADERIMAGE_UNBITMAP "assets\toolbox-header.bmp"
!define MUI_WELCOMEPAGE_TITLE "Instalar ${APP_NAME} v${APP_VERSION}"
!define MUI_WELCOMEPAGE_TEXT "Este asistente instalará TOOLBOX en tu equipo.$\r$\n$\r$\nIncluye diagnóstico, reparación, salud de SQL, reportes PDF y monitoreo de ServicesDev.$\r$\n$\r$\nCierra TOOLBOX antes de continuar."
!define MUI_FINISHPAGE_TITLE "${APP_NAME} está listo"
!define MUI_FINISHPAGE_TEXT "La instalación finalizó correctamente.$\r$\n$\r$\nPuedes abrir TOOLBOX desde el menú Inicio o desde el acceso directo del escritorio."
!define MUI_FINISHPAGE_RUN "$INSTDIR\${APP_EXE}"
!define MUI_FINISHPAGE_RUN_TEXT "Abrir TOOLBOX"
!define MUI_FINISHPAGE_RUN_NOTCHECKED
!define MUI_INSTFILESPAGE_COLORS "A78BFA 07070B"

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_COMPONENTS
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_UNPAGE_FINISH

!insertmacro MUI_LANGUAGE "Spanish"

Function CheckToolboxRunning
  System::Call 'kernel32::OpenMutexW(i 0x00100000, i 0, w "Global\CONTPAQiToolbox.SingleInstance") p.r0'
  ${If} $0 = 0
    System::Call 'kernel32::OpenMutexW(i 0x00100000, i 0, w "Local\CONTPAQiToolbox.SingleInstance") p.r0'
  ${EndIf}
  ${If} $0 <> 0
    System::Call 'kernel32::CloseHandle(p r0)'
    MessageBox MB_OK|MB_ICONEXCLAMATION "TOOLBOX está abierto.$\r$\n$\r$\nEspera a que finalice cualquier operación, cierra la aplicación y vuelve a intentarlo."
    Abort
  ${EndIf}
FunctionEnd

Function .onInit
  ${IfNot} ${AtLeastWin10}
    MessageBox MB_OK|MB_ICONSTOP "${APP_NAME} requiere Windows 10, Windows 11 o Windows Server equivalente."
    Abort
  ${EndIf}
  Call CheckToolboxRunning
  SetShellVarContext all
FunctionEnd

Function un.onInit
  System::Call 'kernel32::OpenMutexW(i 0x00100000, i 0, w "Global\CONTPAQiToolbox.SingleInstance") p.r0'
  ${If} $0 = 0
    System::Call 'kernel32::OpenMutexW(i 0x00100000, i 0, w "Local\CONTPAQiToolbox.SingleInstance") p.r0'
  ${EndIf}
  ${If} $0 <> 0
    System::Call 'kernel32::CloseHandle(p r0)'
    MessageBox MB_OK|MB_ICONEXCLAMATION "Cierra TOOLBOX antes de desinstalarlo."
    Abort
  ${EndIf}
  SetShellVarContext all
FunctionEnd

Section "TOOLBOX (requerido)" SEC_MAIN
  SectionIn RO
  SetShellVarContext all
  SetRegView 64
  SetOutPath "$INSTDIR"
  SetOverwrite on
  File /oname=${APP_EXE} "..\TOOLBOXV6.6.1.exe"

  WriteUninstaller "$INSTDIR\Desinstalar.exe"
  ; Limpia accesos heredados del primer instalador v6.6 antes de crear la identidad TOOLBOX.
  Delete "$DESKTOP\CONTPAQi Toolbox.lnk"
  Delete "$SMPROGRAMS\CONTPAQi Toolbox\CONTPAQi Toolbox.lnk"
  Delete "$SMPROGRAMS\CONTPAQi Toolbox\Desinstalar.lnk"
  RMDir "$SMPROGRAMS\CONTPAQi Toolbox"
  CreateDirectory "$SMPROGRAMS\TOOLBOX"
  CreateShortcut "$SMPROGRAMS\TOOLBOX\TOOLBOX.lnk" "$INSTDIR\${APP_EXE}" "" "$INSTDIR\${APP_EXE}" 0 SW_SHOWNORMAL
  CreateShortcut "$SMPROGRAMS\TOOLBOX\Desinstalar.lnk" "$INSTDIR\Desinstalar.exe"

  WriteRegStr HKLM "${APP_REG_KEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKLM "${APP_REG_KEY}" "Version" "${APP_VERSION}"
  WriteRegStr HKLM "${APP_UNINSTALL_KEY}" "DisplayName" "${APP_NAME}"
  WriteRegStr HKLM "${APP_UNINSTALL_KEY}" "DisplayVersion" "${APP_VERSION}"
  WriteRegStr HKLM "${APP_UNINSTALL_KEY}" "Publisher" "${APP_PUBLISHER}"
  WriteRegStr HKLM "${APP_UNINSTALL_KEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKLM "${APP_UNINSTALL_KEY}" "DisplayIcon" "$INSTDIR\${APP_EXE},0"
  WriteRegStr HKLM "${APP_UNINSTALL_KEY}" "UninstallString" "$\"$INSTDIR\Desinstalar.exe$\""
  WriteRegStr HKLM "${APP_UNINSTALL_KEY}" "QuietUninstallString" "$\"$INSTDIR\Desinstalar.exe$\" /S"
  WriteRegStr HKLM "${APP_UNINSTALL_KEY}" "URLInfoAbout" "https://github.com/dreeka1/TOOLBOX"
  WriteRegDWORD HKLM "${APP_UNINSTALL_KEY}" "NoModify" 1
  WriteRegDWORD HKLM "${APP_UNINSTALL_KEY}" "NoRepair" 1
  WriteRegDWORD HKLM "${APP_UNINSTALL_KEY}" "EstimatedSize" 75350
SectionEnd

Section "Acceso directo en el escritorio" SEC_DESKTOP
  SetShellVarContext all
  CreateShortcut "$DESKTOP\TOOLBOX.lnk" "$INSTDIR\${APP_EXE}" "" "$INSTDIR\${APP_EXE}" 0 SW_SHOWNORMAL
SectionEnd

LangString DESC_SEC_MAIN ${LANG_SPANISH} "Instala la aplicación, el desinstalador y los accesos del menú Inicio."
LangString DESC_SEC_DESKTOP ${LANG_SPANISH} "Crea un acceso directo para todos los usuarios en el escritorio."

!insertmacro MUI_FUNCTION_DESCRIPTION_BEGIN
  !insertmacro MUI_DESCRIPTION_TEXT ${SEC_MAIN} $(DESC_SEC_MAIN)
  !insertmacro MUI_DESCRIPTION_TEXT ${SEC_DESKTOP} $(DESC_SEC_DESKTOP)
!insertmacro MUI_FUNCTION_DESCRIPTION_END

Section "Uninstall"
  SetShellVarContext all
  SetRegView 64
  Delete "$DESKTOP\TOOLBOX.lnk"
  Delete "$DESKTOP\CONTPAQi Toolbox.lnk"
  Delete "$SMPROGRAMS\TOOLBOX\TOOLBOX.lnk"
  Delete "$SMPROGRAMS\TOOLBOX\Desinstalar.lnk"
  RMDir "$SMPROGRAMS\TOOLBOX"
  Delete "$SMPROGRAMS\CONTPAQi Toolbox\CONTPAQi Toolbox.lnk"
  Delete "$SMPROGRAMS\CONTPAQi Toolbox\Desinstalar.lnk"
  RMDir "$SMPROGRAMS\CONTPAQi Toolbox"
  Delete "$INSTDIR\${APP_EXE}"
  Delete "$INSTDIR\Desinstalar.exe"
  RMDir "$INSTDIR"
  DeleteRegKey HKLM "${APP_UNINSTALL_KEY}"
  DeleteRegKey HKLM "${APP_REG_KEY}"
  ; Los diagnósticos, logs y reportes de ProgramData se conservan a propósito.
SectionEnd
