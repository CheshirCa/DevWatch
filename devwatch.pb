; ============================================================
;  DevWatch v1.0
;  Monitors Device Manager for newly connected hardware.
;  On any device arrival, captures a snapshot via SetupAPI,
;  compares it with the previous one and displays a popup
;  with device name, class, VID and PID for each new entry.
;  Supports one-click copy of results to clipboard.
;
;  Requires: Windows 7+, x86 or x64 (single source, both targets)
;
;  (c) CheshirCa 2026
; ============================================================

EnableExplicit  ; Require all variables to be explicitly declared (good practice, prevents typos)

; ── Windows API constants ─────────────────────────────────
; Flags for SetupDiGetClassDevs() — tell it to return all present devices from all classes
#DIGCF_PRESENT    = $00000002   ; Only return devices currently present in the system
#DIGCF_ALLCLASSES = $00000004   ; Return devices from all device classes

; SetupDiGetDeviceRegistryProperty() property codes — what info we want to retrieve
#SPDRP_DEVICEDESC   = 0   ; Device description (basic name, always present)
#SPDRP_CLASS        = 7   ; Device class string (e.g. "USB", "HIDClass", "MEDIA")
#SPDRP_FRIENDLYNAME = 12  ; Friendly name shown in Device Manager (more readable, may be absent)

; Windows messaging constants for device change notifications
#WM_DEVICECHANGE      = $0219  ; Windows message sent when hardware configuration changes
#DBT_DEVNODES_CHANGED = 7      ; Event type: device nodes added or removed in the device tree

; Debounce delay in milliseconds.
; A single USB device can trigger dozens of WM_DEVICECHANGE messages in a row
; (one per interface, driver load, etc.). We wait until the storm settles before scanning.
#DEBOUNCE_MS = 800

; ── UI element identifiers ────────────────────────────────
; PureBasic identifies windows and gadgets by integer numbers.
; Using named constants instead of raw numbers makes the code much easier to read.
#WIN_MAIN  = 0   ; Main (small, always-on) window
#WIN_POPUP = 1   ; Results popup window shown on device arrival

#GAD_LABEL = 0   ; Status label in the main window
#GAD_EDIT  = 1   ; Read-only text editor in the popup (shows device list)
#GAD_COPY  = 2   ; "Copy to clipboard" button
#GAD_CLOSE = 3   ; "Close" button

#FONT_MONO = 0   ; Monospace font handle (Consolas) for the results editor

; ── Windows API structures ────────────────────────────────
; GUID — a 128-bit globally unique identifier used to identify device classes
Structure GUID_
  d1.l       ; 32-bit data
  d2.w       ; 16-bit data
  d3.w       ; 16-bit data
  d4.b[8]    ; 8 bytes
EndStructure

; SP_DEVINFO_DATA — passed to SetupDiEnumDeviceInfo() to receive info about each device.
; The cbSize field MUST be set to SizeOf(SP_DEVINFO_DATA_) before use — Windows checks it.
Structure SP_DEVINFO_DATA_
  cbSize.l         ; Size of this structure in bytes (must be initialized before use)
  ClassGuid.GUID_  ; GUID of the device's setup class
  DevInst.l        ; Handle to the device instance (used internally by SetupAPI)
  Reserved.i       ; Reserved — size is pointer-sized (4 bytes on x86, 8 bytes on x64)
EndStructure        ; Using type 'i' here makes the struct layout correct on both architectures

; ── Global variables ──────────────────────────────────────
Global NewMap g_Snap.s()    ; Previous device snapshot: InstanceId -> "Name|Class"
Global NewMap g_Tmp.s()     ; Temporary snapshot used for comparison
Global g_ClipText.s         ; Text accumulated for clipboard copy
Global g_PopupOpen.i = 0    ; Flag: is the results popup currently open? (0=no, 1=yes)
Global g_ChangeTime.i = 0   ; Timestamp (ms) of the last WM_DEVICECHANGE event, 0 = idle

; ── Procedure: TakeSnapshot ──────────────────────────────
; Enumerates all currently present devices using SetupAPI and stores them in map M().
; Key   = InstanceId string (e.g. "USB\VID_0D8C&PID_000E\5&201B4142&0&8")
; Value = "FriendlyName|Class" (pipe-separated for easy splitting later)
Procedure TakeSnapshot(Map M.s())
  Protected hDev.i                 ; Handle to a device information set returned by SetupDiGetClassDevs
  Protected idx.l                  ; Loop counter for enumerating devices
  Protected di.SP_DEVINFO_DATA_    ; Structure filled by SetupDiEnumDeviceInfo for each device
  Protected *ib                    ; Memory buffer for InstanceId string
  Protected *pb                    ; Memory buffer for property strings (name, class, etc.)
  Protected reqSz.l, regType.l     ; Output variables required by SetupDiGetDeviceRegistryProperty
  Protected instId.s, name.s, cls.s

  ; Allocate raw memory buffers for Unicode strings (2048 bytes = up to 1023 UTF-16 chars each)
  *ib = AllocateMemory(2048)
  *pb = AllocateMemory(2048)

  ; Safety check — bail out if memory allocation failed
  If *ib = 0 Or *pb = 0
    If *ib : FreeMemory(*ib) : EndIf
    If *pb : FreeMemory(*pb) : EndIf
    ProcedureReturn
  EndIf

  ClearMap(M())  ; Wipe the map before filling it with a fresh snapshot

  ; Get a handle to the set of all currently present devices from all classes.
  ; Returns -1 (INVALID_HANDLE_VALUE) on failure.
  hDev = CallFunction(0, "SetupDiGetClassDevsW", 0, 0, 0, #DIGCF_PRESENT|#DIGCF_ALLCLASSES)

  If hDev <> -1

    di\cbSize = SizeOf(SP_DEVINFO_DATA_)  ; Required: tell Windows the struct size

    ; Iterate through all devices in the set (index 0, 1, 2, ...).
    ; SetupDiEnumDeviceInfo returns 0 when there are no more devices (GetLastError = 259).
    For idx = 0 To 65535
      If Not CallFunction(0, "SetupDiEnumDeviceInfo", hDev, idx, @di) : Break : EndIf

      ; ── Get the InstanceId (unique path-like string identifying this device node) ──
      FillMemory(*ib, 2048, 0)
      If Not CallFunction(0, "SetupDiGetDeviceInstanceIdW", hDev, @di, *ib, 1023, @reqSz)
        Continue  ; Skip this device if we can't get its ID
      EndIf
      instId = PeekS(*ib, -1, #PB_Unicode)  ; Read Unicode string from the buffer
      If instId = "" : Continue : EndIf      ; Skip if empty (shouldn't happen, but be safe)

      ; ── Get FriendlyName (shown in Device Manager, more user-friendly) ──
      ; Not all devices have it, so fall back to DeviceDesc if absent.
      name = ""
      FillMemory(*pb, 2048, 0)
      If CallFunction(0, "SetupDiGetDeviceRegistryPropertyW", hDev, @di, #SPDRP_FRIENDLYNAME, @regType, *pb, 2046, @reqSz)
        name = PeekS(*pb, -1, #PB_Unicode)
      EndIf

      If name = ""  ; FriendlyName not available — try the basic DeviceDesc
        FillMemory(*pb, 2048, 0)
        If CallFunction(0, "SetupDiGetDeviceRegistryPropertyW", hDev, @di, #SPDRP_DEVICEDESC, @regType, *pb, 2046, @reqSz)
          name = PeekS(*pb, -1, #PB_Unicode)
        EndIf
      EndIf

      ; ── Get device class string ──
      cls = ""
      FillMemory(*pb, 2048, 0)
      If CallFunction(0, "SetupDiGetDeviceRegistryPropertyW", hDev, @di, #SPDRP_CLASS, @regType, *pb, 2046, @reqSz)
        cls = PeekS(*pb, -1, #PB_Unicode)
      EndIf

      ; Store in the map. Pipe '|' is used as a field separator since it won't appear in IDs.
      M(instId) = name + "|" + cls

    Next

    ; Always destroy the device info set handle to avoid a resource leak
    CallFunction(0, "SetupDiDestroyDeviceInfoList", hDev)
  EndIf

  FreeMemory(*ib)
  FreeMemory(*pb)
EndProcedure

; ── Procedure: HexID ─────────────────────────────────────
; Extracts a 4-character hex value from an InstanceId string.
; Example: HexID("USB\VID_0D8C&PID_000E\...", "VID") returns "0D8C"
; Returns "----" if the prefix is not found (non-USB devices, virtual devices, etc.)
Procedure.s HexID(s.s, prefix.s)
  Protected p.i = FindString(UCase(s), prefix + "_")
  If p > 0
    ProcedureReturn UCase(Mid(s, p + Len(prefix) + 1, 4))
  EndIf
  ProcedureReturn "----"
EndProcedure

; ── Procedure: BuildReport ───────────────────────────────
; Compares two snapshots (New_ vs Old_) and builds a human-readable report
; of devices present in New_ but absent in Old_ (i.e. newly arrived devices).
; The result is stored in g_ClipText (for clipboard) and returned as a count.
Procedure.i BuildReport(Map New_.s(), Map Old_.s())
  Protected key.s, name.s, cls.s, vid.s, pid.s
  Protected count.i = 0
  Protected txt.s = ""

  ForEach New_()
    key = MapKey(New_())

    ; If this InstanceId was NOT in the old snapshot, it's a new device
    If Not FindMapElement(Old_(), key)
      name = StringField(New_(), 1, "|")   ; Extract name (field 1, split by '|')
      cls  = StringField(New_(), 2, "|")   ; Extract class (field 2)
      vid  = HexID(key, "VID")             ; Parse VID from InstanceId
      pid  = HexID(key, "PID")             ; Parse PID from InstanceId

      If name = "" : name = "(no name)"   : EndIf
      If cls  = "" : cls  = "(no class)"  : EndIf

      ; Build one text block per device
      txt + "Name:  " + name + #CRLF$
      txt + "Class: " + cls  + #CRLF$
      txt + "VID:   " + vid  + "   PID: " + pid + #CRLF$
      txt + "ID:    " + key  + #CRLF$
      txt + "-------------------------------------------" + #CRLF$
      count + 1
    EndIf
  Next

  g_ClipText = txt          ; Save for clipboard button
  ProcedureReturn count
EndProcedure

; ── Procedure: OpenPopup ─────────────────────────────────
; Creates (or re-creates) the results popup window and fills it with the report text.
Procedure OpenPopup(count.i)
  ; If a popup is already open, close it first so we don't stack windows
  If g_PopupOpen
    CloseWindow(#WIN_POPUP)
    g_PopupOpen = 0
  EndIf

  OpenWindow(#WIN_POPUP, 0, 0, 530, 370,
             "DevWatch — New devices: " + Str(count),
             #PB_Window_SystemMenu|#PB_Window_ScreenCentered,
             WindowID(#WIN_MAIN))

  ; Make the popup always stay on top of other windows using WinAPI
  ; #HWND_TOPMOST = -1 (insert after topmost), #SWP_NOMOVE | #SWP_NOSIZE = don't resize or move
  SetWindowPos_(WindowID(#WIN_POPUP), #HWND_TOPMOST, 0, 0, 0, 0, #SWP_NOMOVE | #SWP_NOSIZE)

  ; Read-only editor gadget to display the device list
  EditorGadget(#GAD_EDIT, 8, 8, 514, 308, #PB_Editor_ReadOnly)
  SetGadgetFont(#GAD_EDIT, FontID(#FONT_MONO))   ; Use monospace for alignment
  SetGadgetText(#GAD_EDIT, g_ClipText)

  ; Action buttons
  ButtonGadget(#GAD_COPY,  8,   326, 150, 28, "Copy to clipboard")
  ButtonGadget(#GAD_CLOSE, 166, 326, 100, 28, "Close")

  g_PopupOpen = 1
EndProcedure

; ── Procedure: WndCallback ───────────────────────────────
; This is a Windows message callback — called by Windows whenever a message is sent
; to our main window. We intercept WM_DEVICECHANGE here.
;
; IMPORTANT: Inside a Windows callback you must NOT call PureBasic GUI functions
; (like AddWindowTimer, OpenWindow, etc.) — this can cause crashes or deadlocks.
; Instead, we just record the timestamp and let the main loop handle the rest.
Procedure WndCallback(hWnd.i, uMsg.i, wParam.i, lParam.i)
  If uMsg = #WM_DEVICECHANGE And wParam = #DBT_DEVNODES_CHANGED
    ; Record the time of the event. The main loop polls this and waits DEBOUNCE_MS
    ; before actually scanning, absorbing the burst of events from one physical connection.
    g_ChangeTime = ElapsedMilliseconds()
  EndIf
  ProcedureReturn #PB_ProcessPureBasicEvents  ; Let PureBasic handle everything else normally
EndProcedure

; ════════════════════════════════════════════════════════════
; ENTRY POINT
; ════════════════════════════════════════════════════════════

; Load setupapi.dll from the system directory.
; GetSystemDirectory_ returns the correct folder automatically:
;   x64 process → C:\Windows\System32   (x64 DLL)
;   x86 process → C:\Windows\SysWOW64  (x86 DLL)
; So the same source compiles and runs correctly for both architectures.
Define sysDir.s = Space(260)
GetSystemDirectory_(@sysDir, 260)
If Not OpenLibrary(0, sysDir + "\setupapi.dll")
  MessageRequester("DevWatch", "Failed to load setupapi.dll from: " + sysDir + Chr(10) +
                               "GetLastError: " + Str(GetLastError_()), #PB_MessageRequester_Error)
  End
EndIf

; Load a monospace font for the results editor
LoadFont(#FONT_MONO, "Consolas", 9)

; Create the small main window — it stays open the whole time the app is running
OpenWindow(#WIN_MAIN, 0, 0, 300, 66, "DevWatch",
           #PB_Window_SystemMenu|#PB_Window_ScreenCentered|#PB_Window_MinimizeGadget)
TextGadget(#GAD_LABEL, 10, 10, 280, 18, "Scanning...")

; Install our custom Windows message callback for the main window
SetWindowCallback(@WndCallback(), #WIN_MAIN)

; Take the initial snapshot — this is our baseline to compare against later
TakeSnapshot(g_Snap())
SetGadgetText(#GAD_LABEL, "Waiting...  Devices in snapshot: " + Str(MapSize(g_Snap())))

; ── Main event loop ───────────────────────────────────────
Define ev.i, win.i, gad.i, cnt.i, running.i = 1

While running

  ; WaitWindowEvent(200) blocks for up to 200ms waiting for a UI event.
  ; Using a timeout (instead of waiting forever) lets us check g_ChangeTime regularly
  ; even when no UI events occur — this is how the debounce polling works.
  ev  = WaitWindowEvent(200)
  win = EventWindow()
  gad = EventGadget()

  ; ── Debounce check ───────────────────────────────────────
  ; If we received a device change notification (g_ChangeTime > 0)
  ; and enough time has passed since the last one, do the actual scan.
  If g_ChangeTime > 0 And (ElapsedMilliseconds() - g_ChangeTime) > #DEBOUNCE_MS
    g_ChangeTime = 0                          ; Reset the debounce timer
    TakeSnapshot(g_Tmp())                     ; Take a new snapshot
    cnt = BuildReport(g_Tmp(), g_Snap())      ; Find what's new
    CopyMap(g_Tmp(), g_Snap())                ; Update the baseline snapshot
    If cnt > 0
      OpenPopup(cnt)                          ; Show the results popup
      SetGadgetText(#GAD_LABEL, "Detected: " + Str(cnt) + "  [" + FormatDate("%hh:%ii:%ss", Date()) + "]")
    EndIf
  EndIf

  ; ── UI event handling ────────────────────────────────────
  Select ev

    Case #PB_Event_CloseWindow
      If win = #WIN_MAIN          ; User closed the main window → exit the app
        running = 0
      ElseIf win = #WIN_POPUP     ; User closed the popup → just hide it
        CloseWindow(#WIN_POPUP)
        g_PopupOpen = 0
      EndIf

    Case #PB_Event_Gadget
      If win = #WIN_POPUP
        Select gad
          Case #GAD_COPY          ; "Copy to clipboard" button
            SetClipboardText(g_ClipText)
            SetGadgetText(#GAD_COPY, "Copied!")

          Case #GAD_CLOSE         ; "Close" button
            CloseWindow(#WIN_POPUP)
            g_PopupOpen = 0
        EndSelect
      EndIf

  EndSelect

Wend

; ── Cleanup ───────────────────────────────────────────────
If g_PopupOpen : CloseWindow(#WIN_POPUP) : EndIf
CloseLibrary(0)   ; Unload setupapi.dll
End
