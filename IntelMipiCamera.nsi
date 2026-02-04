; IntelMipiCamera.nsi
; Repo layout:
;   IntelMipiCamera.nsi
;   drivers\        <-- submodule containing: kbl, jsl, tgl, adl-rpl, mtl folders
;   jsl-overlay\    <-- JSL overlay config files (xml/aiqb/cpf)

!include WinVer.nsh
!include x64.nsh
!include LogicLib.nsh
!include Sections.nsh
!include StrFunc.nsh

!define APPNAME  "IntelMipiCamera"
!define VERSION  "1.0.1"

Caption "${APPNAME} installer"
Name "${APPNAME} ${VERSION}"
OutFile "${APPNAME}.${VERSION}-installer.exe"
ManifestSupportedOS "all"
SpaceTexts "none"

; Product folder (stores only Uninstall.exe + ARP registration)
InstallDir "$PROGRAMFILES64\${APPNAME}"

RequestExecutionLevel admin

PageEx components
  ComponentText "Select which components you have. Autodetected platform core will be selected. Supported sensors will be enabled for selection." "" ""
PageExEnd
Page instfiles

UninstPage uninstConfirm
UninstPage instfiles

!define UNINST_ROOT "$INSTDIR"
!define UNINST_EXE  "$INSTDIR\Uninstall.exe"
!define ARP_KEY     "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APPNAME}"

; -----------------------
; Platform detection patterns (IPU PCI IDs)
; -----------------------
!define PAT_KBL "PCI\VEN_8086&DEV_1919&*"
!define PAT_TGL "PCI\VEN_8086&DEV_9A19&*"
!define PAT_JSL "PCI\VEN_8086&DEV_4E19&*"
!define PAT_ADL "PCI\VEN_8086&DEV_465D&*;PCI\VEN_8086&DEV_462E&*;PCI\VEN_8086&DEV_A75D&*"
!define PAT_MTL "PCI\VEN_8086&DEV_7D19&*"

; -----------------------
; Staged payload roots (in $PLUGINSDIR so nothing is left behind)
; -----------------------
!define ROOT_KBL "$PLUGINSDIR\drivers\kbl"
!define ROOT_JSL "$PLUGINSDIR\drivers\jsl"
!define ROOT_TGL "$PLUGINSDIR\drivers\tgl"
!define ROOT_ADL "$PLUGINSDIR\drivers\adl-rpl"
!define ROOT_MTL "$PLUGINSDIR\drivers\mtl"
!define ROOT_JSL_OVERLAY "$PLUGINSDIR\jsl-overlay"

; -----------------------
; Vars
; -----------------------
Var CamPlatform      ; "kbl" | "jsl" | "tgl" | "adl" | "mtl" | ""
Var DetOut           ; detection output string
Var CoreInstalled    ; "0"|"1"
Var InstalledHackJsl ; "0"|"1"
Var InstalledHackTgl ; "0"|"1"

${StrStr}

; -----------------------
; Helpers: locate system tools
; -----------------------
!macro GetPnPUtil _OutVar
  ${If} ${RunningX64}
    StrCpy ${_OutVar} "$WINDIR\Sysnative\pnputil.exe"
  ${Else}
    StrCpy ${_OutVar} "$SYSDIR\pnputil.exe"
  ${EndIf}
!macroend

!macro GetPowerShell _OutVar
  ${If} ${RunningX64}
    StrCpy ${_OutVar} "$WINDIR\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
  ${Else}
    StrCpy ${_OutVar} "$SYSDIR\WindowsPowerShell\v1.0\powershell.exe"
  ${EndIf}
!macroend

!macro GetRealSystem32 _OutVar
  ${If} ${RunningX64}
    StrCpy ${_OutVar} "$WINDIR\Sysnative"
  ${Else}
    StrCpy ${_OutVar} "$WINDIR\System32"
  ${EndIf}
!macroend

!macro GetRealDriversDir _OutVar
  !insertmacro GetRealSystem32 ${_OutVar}
  StrCpy ${_OutVar} "${_OutVar}\drivers\"
!macroend

; -----------------------
; Helper: install single INF from "foldername.inf_amd64_*" directory (first match)
;   _Root: root path like ${ROOT_ADL}
;   _DirGlob: directory glob like "iacamera64.inf_amd64_*"
;   _InfName: actual inf file name like "iacamera64.inf"
; -----------------------
!macro InstallInf _Root _DirGlob _InfName
  Push $0
  Push $1
  Push $9

  FindFirst $0 $1 "${_Root}\${_DirGlob}"
  ${If} $1 != ""
    !insertmacro GetPnPUtil $9
    nsExec::Exec '"$9" /add-driver "${_Root}\$1\${_InfName}" /install'
  ${EndIf}
  FindClose $0

  Pop $9
  Pop $1
  Pop $0
!macroend

; -----------------------
; Detection: one PowerShell run, emit a single line:
;   "MTL=0;ADL=1;TGL=0;JSL=0;KBL=0"
; -----------------------
!macro DetectHardwareOnce
  Push $0
  Push $1
  Push $2

  !insertmacro GetPowerShell $0

  GetTempFileName $1
  StrCpy $2 "$1.ps1"
  Rename $1 $2

  FileOpen $1 $2 w
  FileWrite $1 "$$ErrorActionPreference = 'SilentlyContinue'$\r$\n"
  FileWrite $1 "$$ids = @()$\r$\n"
  FileWrite $1 "try { $$ids = Get-PnpDevice -PresentOnly | ForEach-Object { $$_.InstanceId } } catch { $$ids = @() }$\r$\n"

  FileWrite $1 "function AnyMatch([string]$$raw){$\r$\n"
  FileWrite $1 "  if ([string]::IsNullOrWhiteSpace($$raw)) { return $$false }$\r$\n"
  FileWrite $1 "  $$pats = $$raw -split ';' | ForEach-Object { $$_.Trim() } | Where-Object { $$_.Length -gt 0 }$\r$\n"
  FileWrite $1 "  foreach ($$p in $$pats) {$\r$\n"
  FileWrite $1 "    foreach ($$id in $$ids) { if ($$id -like $$p) { return $$true } }$\r$\n"
  FileWrite $1 "  }$\r$\n"
  FileWrite $1 "  return $$false$\r$\n"
  FileWrite $1 "}$\r$\n"

  FileWrite $1 "$$rMTL = AnyMatch '${PAT_MTL}'$\r$\n"
  FileWrite $1 "$$rADL = AnyMatch '${PAT_ADL}'$\r$\n"
  FileWrite $1 "$$rTGL = AnyMatch '${PAT_TGL}'$\r$\n"
  FileWrite $1 "$$rJSL = AnyMatch '${PAT_JSL}'$\r$\n"
  FileWrite $1 "$$rKBL = AnyMatch '${PAT_KBL}'$\r$\n"

  FileWrite $1 "Write-Output ('MTL=' + [int]$$rMTL + ';ADL=' + [int]$$rADL + ';TGL=' + [int]$$rTGL + ';JSL=' + [int]$$rJSL + ';KBL=' + [int]$$rKBL)$\r$\n"
  FileClose $1

  nsExec::ExecToStack '"$0" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$2"'
  Pop $1 ; exit code
  Pop $DetOut

  Delete "$2"

  Pop $2
  Pop $1
  Pop $0
!macroend

; -----------------------
; Section selection helpers
; -----------------------
!macro DisableSection _SectionId
  Push $0
  SectionGetFlags ${_SectionId} $0
  IntOp $0 $0 & ~${SF_SELECTED}
  IntOp $0 $0 | ${SF_RO}
  SectionSetFlags ${_SectionId} $0
  Pop $0
!macroend

!macro SelectAndLockSection _SectionId
  Push $0
  SectionGetFlags ${_SectionId} $0
  IntOp $0 $0 | ${SF_SELECTED}
  IntOp $0 $0 | ${SF_RO}
  SectionSetFlags ${_SectionId} $0
  Pop $0
!macroend

!macro EnableSectionSelectable _SectionId
  Push $0
  SectionGetFlags ${_SectionId} $0
  IntOp $0 $0 & ~${SF_RO}
  SectionSetFlags ${_SectionId} $0
  Pop $0
!macroend

; -----------------------
; Core installer (deduped)
; -----------------------
Function EnsureCoreInstalled
  ${If} $CoreInstalled == "1"
    Return
  ${EndIf}

  ${If} $CamPlatform == "kbl"
    ; KBL core: CSI2 host + SKC controller + IA ISP + IA camera
    !insertmacro InstallInf "${ROOT_KBL}" "csi2hostcontrollerdriver.inf_amd64_*" "CSI2HostControllerDriver.inf"
    !insertmacro InstallInf "${ROOT_KBL}" "skccontroller.inf_amd64_*"           "SkcController.inf"
    !insertmacro InstallInf "${ROOT_KBL}" "iaisp64.inf_amd64_*"                 "iaisp64.inf"
    !insertmacro InstallInf "${ROOT_KBL}" "iacamera64.inf_amd64_*"              "iacamera64.inf"

  ${ElseIf} $CamPlatform == "jsl"
    ; JSL core: IA ISP + IA camera + ctrl logic
    !insertmacro InstallInf "${ROOT_JSL}" "iaisp64.inf_amd64_*"        "iaisp64.inf"
    !insertmacro InstallInf "${ROOT_JSL}" "iacamera64.inf_amd64_*"     "iacamera64.inf"
    !insertmacro InstallInf "${ROOT_JSL}" "iactrllogic64.inf_amd64_*"  "iactrllogic64.inf"

  ${ElseIf} $CamPlatform == "tgl"
    ; TGL core: IA ISP + IA camera + ctrl logic
    !insertmacro InstallInf "${ROOT_TGL}" "iaisp64.inf_amd64_*"        "iaisp64.inf"
    !insertmacro InstallInf "${ROOT_TGL}" "iacamera64.inf_amd64_*"     "iacamera64.inf"
    !insertmacro InstallInf "${ROOT_TGL}" "iactrllogic64.inf_amd64_*"  "iactrllogic64.inf"

  ${ElseIf} $CamPlatform == "adl"
    ; ADL core: IA ISP + IA camera + ctrl logic
    !insertmacro InstallInf "${ROOT_ADL}" "iaisp64.inf_amd64_*"        "iaisp64.inf"
    !insertmacro InstallInf "${ROOT_ADL}" "iacamera64.inf_amd64_*"     "iacamera64.inf"
    !insertmacro InstallInf "${ROOT_ADL}" "iactrllogic64.inf_amd64_*"  "iactrllogic64.inf"

  ${ElseIf} $CamPlatform == "mtl"
    ; MTL core: IA ISP + IA camera + ctrl logic
    !insertmacro InstallInf "${ROOT_MTL}" "iaisp64.inf_amd64_*"        "iaisp64.inf"
    !insertmacro InstallInf "${ROOT_MTL}" "iacamera64.inf_amd64_*"     "iacamera64.inf"
    !insertmacro InstallInf "${ROOT_MTL}" "iactrllogic64.inf_amd64_*"  "iactrllogic64.inf"
  ${EndIf}

  StrCpy $CoreInstalled "1"
FunctionEnd

; =========================================================
; Payload staging (TEMP only, auto-cleaned)
; =========================================================
Section "-Payload (internal)" SecPayload
  SectionIn RO
  InitPluginsDir

  ; Put the 'drivers' tree under $PLUGINSDIR\drivers\...
  SetOutPath "$PLUGINSDIR\drivers"
  File /r "drivers\*"

  ; Put the 'jsl-overlay' tree under $PLUGINSDIR\jsl-overlay\...
  SetOutPath "$PLUGINSDIR\jsl-overlay"
  File /r "jsl-overlay\*"
SectionEnd

; =========================================================
; Core section (single, platform-aware)
; =========================================================
Section /o "Camera Core (autodetected platform)" SecCore
  Call EnsureCoreInstalled
SectionEnd

; =========================================================
; Sensors (deduped across platforms)
; =========================================================

; KBL only
Section /o "IMX258 (KBL)" SecImx258
  ${If} $CamPlatform == "kbl"
    Call EnsureCoreInstalled
    !insertmacro InstallInf "${ROOT_KBL}" "imx258.inf_amd64_*" "imx258.inf"
  ${EndIf}
SectionEnd

; KBL only
Section /o "OV5670 (KBL)" SecOv5670
  ${If} $CamPlatform == "kbl"
    Call EnsureCoreInstalled
    ; exact folder name as provided
    !insertmacro InstallInf "${ROOT_KBL}" "ov5670.inf_amd64_38cd25de8946b8dd" "ov5670.inf"
  ${EndIf}
SectionEnd

; KBL only
Section /o "OV13858 (KBL)" SecOv13858
  ${If} $CamPlatform == "kbl"
    Call EnsureCoreInstalled
    ; exact folder name as provided
    !insertmacro InstallInf "${ROOT_KBL}" "ov13858.inf_amd64_17de33df6e2ea206" "ov13858.inf"
  ${EndIf}
SectionEnd

; OV2740: ADL OR TGL
; =========================================================
Section /o "OV2740 (ADL / TGL)" SecOv2740

  ${If} $CamPlatform == "adl"

    Call EnsureCoreInstalled

    ; Base sensor + extensions
    !insertmacro InstallInf "${ROOT_ADL}" "ov2740.inf_amd64_*" "ov2740.inf"
    !insertmacro InstallInf "${ROOT_ADL}" "ov2740_extension_lenovo_jp2.inf_amd64_*" "ov2740_extension_Lenovo_JP2.inf"
    !insertmacro InstallInf "${ROOT_ADL}" "iacamera64_extension_lenovo.inf_amd64_*" "iacamera64_extension_lenovo.inf"

  ${ElseIf} $CamPlatform == "tgl"

    Call EnsureCoreInstalled

    ; --------------------------------------------
    ; Copy + rename graph / aiqb / cpf
    ; --------------------------------------------

    Push $0
    Push $1
    Push $R0
    Push $R1

    FindFirst $0 $1 "${ROOT_ADL}\ov2740_extension_lenovo_jp2.inf_amd64_*"
    ${If} $1 != ""

      ; Real directories (NO redirection possible)
      !insertmacro GetRealDriversDir $R0
      !insertmacro GetRealSystem32  $R1

      ; graph → System32\drivers
      CopyFiles /SILENT \
        "${ROOT_ADL}\$1\graph_settings_OV2740_CJFLE23_ADL.xml" \
        "$R0graph_settings_OV2740_CJFLE23_TGL.xml"

      ; aiqb / cpf → System32 root
      CopyFiles /SILENT \
        "${ROOT_ADL}\$1\OV2740_CJFLE23_ADL.aiqb" \
        "$R1\OV2740_CJFLE23_TGL.aiqb"

      CopyFiles /SILENT \
        "${ROOT_ADL}\$1\OV2740_CJFLE23_ADL.cpf" \
        "$R1\OV2740_CJFLE23_TGL.cpf"

      ; aiqb / cpf → SysWOW64 root
      CopyFiles /SILENT \
        "${ROOT_ADL}\$1\OV2740_CJFLE23_ADL.aiqb" \
        "$WINDIR\SysWOW64\OV2740_CJFLE23_TGL.aiqb"

      CopyFiles /SILENT \
        "${ROOT_ADL}\$1\OV2740_CJFLE23_ADL.cpf" \
        "$WINDIR\SysWOW64\OV2740_CJFLE23_TGL.cpf"

      StrCpy $InstalledHackTgl "1"

      FindClose $0
    ${EndIf}

    Pop $R1
    Pop $R0
    Pop $1
    Pop $0

    ; Use ADL sensor + iacamera extension
    !insertmacro InstallInf "${ROOT_ADL}" "ov2740.inf_amd64_*" "ov2740.inf"
    !insertmacro InstallInf "${ROOT_ADL}" "iacamera64_extension_lenovo.inf_amd64_*" "iacamera64_extension_lenovo.inf"

  ${EndIf}

SectionEnd

; OV5675: ADL OR JSL
;   - ADL: install ov5675 + sensor extension + iacamera64 extension
;   - JSL: install ADL ov5675 (NO sensor extension) + ADL iacamera64 extension
;          then copy JSL overlay graph_settings + aiqb/cpf to System32\drivers
Section /o "OV5675 (ADL / JSL)" SecOv5675
  ${If} $CamPlatform == "adl"
    Call EnsureCoreInstalled
    !insertmacro InstallInf "${ROOT_ADL}" "ov5675.inf_amd64_*" "ov5675.inf"
    !insertmacro InstallInf "${ROOT_ADL}" "ov5675_extension_lenovo.inf_amd64_*" "ov5675_extension_Lenovo.inf"
    !insertmacro InstallInf "${ROOT_ADL}" "iacamera64_extension_lenovo.inf_amd64_*" "iacamera64_extension_lenovo.inf"

  ${ElseIf} $CamPlatform == "jsl"
    Call EnsureCoreInstalled

    ; Copy overlay graph_settings + aiqb + cpf into System32\drivers
    Push $R0
    !insertmacro GetRealDriversDir $R0

    CopyFiles /SILENT "${ROOT_JSL_OVERLAY}\graph_settings_OV5675_CJFLE39_JSLP.xml" "$R0"
    CopyFiles /SILENT "${ROOT_JSL_OVERLAY}\OV5675_CJFLE39_JSLP.aiqb"              "$R0"
    CopyFiles /SILENT "${ROOT_JSL_OVERLAY}\OV5675_CJFLE39_JSLP.cpf"               "$R0"

    Pop $R0
    StrCpy $InstalledHackJsl "1"

    ; JSL: install ADL sensor INF (no sensor extension), plus ADL iacamera64 extension
    !insertmacro InstallInf "${ROOT_ADL}" "ov5675.inf_amd64_*" "ov5675.inf"
    !insertmacro InstallInf "${ROOT_ADL}" "iacamera64_extension_lenovo.inf_amd64_*" "iacamera64_extension_lenovo.inf"
  ${EndIf}
SectionEnd

; OV8856: ADL OR JSL
;   - ADL: install ov8856 + iacamera64 extension
;   - JSL: install ADL ov8856 (NO sensor extension) + ADL iacamera64 extension
;          then copy JSL overlay graph_settings + aiqb/cpf to System32\drivers
Section /o "OV8856 (ADL / JSL)" SecOv8856
  ${If} $CamPlatform == "adl"
    Call EnsureCoreInstalled
    !insertmacro InstallInf "${ROOT_ADL}" "ov8856.inf_amd64_*" "ov8856.inf"
    !insertmacro InstallInf "${ROOT_ADL}" "iacamera64_extension_lenovo.inf_amd64_*" "iacamera64_extension_lenovo.inf"

  ${ElseIf} $CamPlatform == "jsl"
    Call EnsureCoreInstalled
    ; Copy overlay graph_settings + aiqb + cpf into System32\drivers
    Push $R0
    !insertmacro GetRealDriversDir $R0

    CopyFiles /SILENT "${ROOT_JSL_OVERLAY}\graph_settings_OV8856_CJAJ813_JSLP.xml" "$R0"
    CopyFiles /SILENT "${ROOT_JSL_OVERLAY}\OV8856_CJAJ813_JSLP.aiqb"              "$R0"
    CopyFiles /SILENT "${ROOT_JSL_OVERLAY}\OV8856_CJAJ813_JSLP.cpf"               "$R0"

    Pop $R0
    StrCpy $InstalledHackJsl "1"

    ; JSL: install ADL sensor INF (no sensor extension), plus ADL iacamera64 extension
    !insertmacro InstallInf "${ROOT_ADL}" "ov8856.inf_amd64_*" "ov8856.inf"
    !insertmacro InstallInf "${ROOT_ADL}" "iacamera64_extension_lenovo.inf_amd64_*" "iacamera64_extension_lenovo.inf"
  ${EndIf}
SectionEnd

; HI556: ADL OR MTL
Section /o "HI556 (ADL / MTL)" SecHi556
  ${If} $CamPlatform == "adl"
    Call EnsureCoreInstalled
    !insertmacro InstallInf "${ROOT_ADL}" "hi556.inf_amd64_*" "hi556.inf"
    !insertmacro InstallInf "${ROOT_ADL}" "hi556_extension_dell.inf_amd64_*" "hi556_extension_dell.inf"
    !insertmacro InstallInf "${ROOT_ADL}" "iacamera64_extension_dell_millennio.inf_amd64_*" "iacamera64_extension_dell_millennio.inf"

  ${ElseIf} $CamPlatform == "mtl"
    Call EnsureCoreInstalled
    !insertmacro InstallInf "${ROOT_MTL}" "hi556.inf_amd64_*" "hi556.inf"
    !insertmacro InstallInf "${ROOT_MTL}" "hi556_extension_dell.inf_amd64_*" "hi556_extension_dell.inf"
    !insertmacro InstallInf "${ROOT_MTL}" "iacamera64_extension_dell_oasismlk.inf_amd64_*" "iacamera64_extension_dell_oasismlk.inf"
  ${EndIf}
SectionEnd

; OV08x40: MTL only
Section /o "OV08x40 (MTL)" SecOv08x40
  ${If} $CamPlatform == "mtl"
    Call EnsureCoreInstalled
    !insertmacro InstallInf "${ROOT_MTL}" "ov08x40.inf_amd64_*" "ov08x40.inf"
    !insertmacro InstallInf "${ROOT_MTL}" "ov08x40_extension_lenovo.inf_amd64_*" "ov08x40_extension_Lenovo.inf"
    !insertmacro InstallInf "${ROOT_MTL}" "iacamera64_extension_lenovo_vc.inf_amd64_*" "iacamera64_extension_lenovo_VC.inf"
  ${EndIf}
SectionEnd

; =========================================================
; Init: autodetect platform and enable/disable modules
; =========================================================
Function .onInit
  ${IfNot} ${RunningX64}
    MessageBox MB_ICONSTOP "64-bit Windows required."
    Abort
  ${EndIf}

  !insertmacro DisableX64FSRedirection

  StrCpy $InstalledHackJsl "0"
  StrCpy $InstalledHackTgl "0"
  StrCpy $CoreInstalled    "0"

  !insertmacro DetectHardwareOnce
  StrCpy $CamPlatform ""

  ; Determine platform with priority (MTL > ADL > TGL > JSL > KBL)
  ${StrStr} $0 $DetOut "MTL=1"
  ${If} $0 != ""
    StrCpy $CamPlatform "mtl"
  ${EndIf}

  ${If} $CamPlatform == ""
    ${StrStr} $0 $DetOut "ADL=1"
    ${If} $0 != ""
      StrCpy $CamPlatform "adl"
    ${EndIf}
  ${EndIf}

  ${If} $CamPlatform == ""
    ${StrStr} $0 $DetOut "TGL=1"
    ${If} $0 != ""
      StrCpy $CamPlatform "tgl"
    ${EndIf}
  ${EndIf}

  ${If} $CamPlatform == ""
    ${StrStr} $0 $DetOut "JSL=1"
    ${If} $0 != ""
      StrCpy $CamPlatform "jsl"
    ${EndIf}
  ${EndIf}

  ${If} $CamPlatform == ""
    ${StrStr} $0 $DetOut "KBL=1"
    ${If} $0 != ""
      StrCpy $CamPlatform "kbl"
    ${EndIf}
  ${EndIf}

  ${If} $CamPlatform == ""
    MessageBox MB_ICONEXCLAMATION "Intel IPU PCI device not detected. You may manually select components, but installs may not match your hardware."
  ${EndIf}

  ; Core: select+lock if platform detected, else leave selectable
  ${If} $CamPlatform != ""
    !insertmacro SelectAndLockSection ${SecCore}
  ${Else}
    !insertmacro EnableSectionSelectable ${SecCore}
  ${EndIf}

    ; Sensors: enable+select valid ones.
  ; If platform not detected, enable+select all sensors.
  ${If} $CamPlatform == ""
    !insertmacro EnableSectionSelectable ${SecImx258}
    !insertmacro EnableSectionSelectable ${SecOv5670}
    !insertmacro EnableSectionSelectable ${SecOv13858}

    !insertmacro EnableSectionSelectable ${SecOv2740}
    !insertmacro EnableSectionSelectable ${SecOv5675}
    !insertmacro EnableSectionSelectable ${SecOv8856}
    !insertmacro EnableSectionSelectable ${SecHi556}
    !insertmacro EnableSectionSelectable ${SecOv08x40}

    !insertmacro SelectSection ${SecImx258}
    !insertmacro SelectSection ${SecOv5670}
    !insertmacro SelectSection ${SecOv13858}

    !insertmacro SelectSection ${SecOv2740}
    !insertmacro SelectSection ${SecOv5675}
    !insertmacro SelectSection ${SecOv8856}
    !insertmacro SelectSection ${SecHi556}
    !insertmacro SelectSection ${SecOv08x40}
  ${Else}
    ; Start with everything disabled/unselected
    !insertmacro DisableSection ${SecImx258}
    !insertmacro DisableSection ${SecOv5670}
    !insertmacro DisableSection ${SecOv13858}
    !insertmacro DisableSection ${SecOv2740}
    !insertmacro DisableSection ${SecOv5675}
    !insertmacro DisableSection ${SecOv8856}
    !insertmacro DisableSection ${SecHi556}
    !insertmacro DisableSection ${SecOv08x40}

    ${If} $CamPlatform == "kbl"
      !insertmacro EnableSectionSelectable ${SecImx258}
      !insertmacro EnableSectionSelectable ${SecOv5670}
      !insertmacro EnableSectionSelectable ${SecOv13858}

      !insertmacro SelectSection ${SecImx258}
      !insertmacro SelectSection ${SecOv5670}
      !insertmacro SelectSection ${SecOv13858}
    ${EndIf}

    ${If} $CamPlatform == "tgl"
      !insertmacro EnableSectionSelectable ${SecOv2740}
      !insertmacro SelectSection ${SecOv2740}
    ${EndIf}

    ${If} $CamPlatform == "jsl"
      !insertmacro EnableSectionSelectable ${SecOv5675}
      !insertmacro EnableSectionSelectable ${SecOv8856}
      !insertmacro SelectSection ${SecOv5675}
      !insertmacro SelectSection ${SecOv8856}
    ${EndIf}

    ${If} $CamPlatform == "adl"
      !insertmacro EnableSectionSelectable ${SecOv2740}
      !insertmacro EnableSectionSelectable ${SecOv5675}
      !insertmacro EnableSectionSelectable ${SecOv8856}
      !insertmacro EnableSectionSelectable ${SecHi556}

      !insertmacro SelectSection ${SecOv2740}
      !insertmacro SelectSection ${SecOv5675}
      !insertmacro SelectSection ${SecOv8856}
      !insertmacro SelectSection ${SecHi556}
    ${EndIf}

    ${If} $CamPlatform == "mtl"
      !insertmacro EnableSectionSelectable ${SecOv08x40}
      !insertmacro EnableSectionSelectable ${SecHi556}

      !insertmacro SelectSection ${SecOv08x40}
      !insertmacro SelectSection ${SecHi556}
    ${EndIf}
  ${EndIf}
FunctionEnd

; =========================================================
; Uninstaller write-out + ARP registration
; =========================================================
Section -Post
  SetOutPath "${UNINST_ROOT}"
  WriteUninstaller "${UNINST_EXE}"

  WriteRegStr HKLM "${ARP_KEY}" "DisplayName" "${APPNAME}"
  WriteRegStr HKLM "${ARP_KEY}" "Publisher"  "vibecoder"
  WriteRegStr HKLM "${ARP_KEY}" "DisplayVersion" "${VERSION}"
  WriteRegStr HKLM "${ARP_KEY}" "UninstallString" '"${UNINST_EXE}"'
  WriteRegStr HKLM "${ARP_KEY}" "InstallLocation" "${UNINST_ROOT}"
SectionEnd

Function un.onInit
  ${If} ${RunningX64}
    !insertmacro DisableX64FSRedirection
  ${EndIf}
FunctionEnd

; =========================================================
; Uninstaller: remove only the config files this installer copies for JSL/TGL
; =========================================================
Section "Uninstall"
  Push $R0
  Push $R1
  !insertmacro GetRealDriversDir $R0
  !insertmacro GetRealSystem32   $R1

  ; JSL overlay (real System32\drivers)
  Delete /REBOOTOK "$R0graph_settings_OV5675_CJFLE39_JSLP.xml"
  Delete /REBOOTOK "$R0OV5675_CJFLE39_JSLP.aiqb"
  Delete /REBOOTOK "$R0OV5675_CJFLE39_JSLP.cpf"
  Delete /REBOOTOK "$R0graph_settings_OV8856_CJAJ813_JSLP.xml"
  Delete /REBOOTOK "$R0OV8856_CJAJ813_JSLP.aiqb"
  Delete /REBOOTOK "$R0OV8856_CJAJ813_JSLP.cpf"

  ; TGL (graph in real drivers, aiqb/cpf in real system32 + syswow64)
  Delete /REBOOTOK "$R0graph_settings_OV2740_CJFLE23_TGL.xml"
  Delete /REBOOTOK "$R1\OV2740_CJFLE23_TGL.aiqb"
  Delete /REBOOTOK "$R1\OV2740_CJFLE23_TGL.cpf"
  Delete /REBOOTOK "$WINDIR\SysWOW64\OV2740_CJFLE23_TGL.aiqb"
  Delete /REBOOTOK "$WINDIR\SysWOW64\OV2740_CJFLE23_TGL.cpf"

  Pop $R1
  Pop $R0

  ; ARP/uninstaller removal...
  DeleteRegKey HKLM "${ARP_KEY}"
  Delete "${UNINST_EXE}"
  RMDir "${UNINST_ROOT}"
SectionEnd