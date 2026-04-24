# DevWatch

**Monitors Device Manager for newly connected hardware and shows VID/PID instantly.**

---

## English

### What it does

DevWatch sits in the background and listens for hardware changes. When you plug in a new device, it waits for the system to finish loading drivers, then shows a popup with a list of all newly appeared device nodes — name, class, VID and PID included. Results can be copied to the clipboard in one click.

Useful when you connect a composite USB device that registers multiple nodes at once and you need to quickly identify what exactly appeared in Device Manager without digging through the full device list manually.

### Features

- Detects any new device node: USB, HID, audio, virtual (SWD), and others
- Shows device name, class, VID and PID for each entry
- Extracts VID/PID directly from the InstanceId string — no WMI, no registry queries
- One-click copy of the full report to clipboard
- Debounce (800 ms) absorbs the burst of events from a single physical connection
- No installation, no admin rights required
- Single source compiles to both x86 and x64

### How to use

1. Run `devwatch.exe`
2. The small main window appears and takes an initial device snapshot
3. Plug in any hardware
4. A popup appears with the list of new devices
5. Use **Copy to clipboard** to grab the results, then **Close**

The app keeps running and monitoring until you close the main window.

### Notes

- Devices with no VID/PID in their InstanceId (e.g. virtual audio endpoints `SWD\MMDEVAPI\...`) will show `----` — this is expected behavior
- Composite devices appear as multiple entries (one per interface) — same as Device Manager shows them
- Only device **arrivals** are reported; disconnection is tracked internally but does not trigger a popup

### Build

- **Compiler:** PureBasic 6.x
- **Target:** Windows x86 or x64 (same source, switch in Compiler Options)
- **Icon:** Set `devwatch.ico` in Compiler → Compiler Options → Executable Icon
- **Subsystem:** Windows (no console)
- No external libraries — `setupapi.dll` is loaded dynamically from System32 / SysWOW64

---

## Русский

### Что делает

DevWatch работает в фоне и слушает системные сообщения об изменении конфигурации оборудования. При подключении нового устройства ждёт, пока система закончит загружать драйверы, после чего показывает всплывающее окно со списком всех новых записей в Device Manager — имя, класс, VID и PID. Результат копируется в буфер одной кнопкой.

Удобно при подключении составных USB-устройств, которые сразу создают несколько записей, когда нужно быстро узнать идентификаторы не листая весь список Device Manager вручную.

### Возможности

- Обнаруживает любые новые узлы устройств: USB, HID, аудио, виртуальные (SWD) и прочие
- Показывает имя, класс, VID и PID для каждой записи
- VID/PID извлекается парсингом InstanceId — без WMI и обращений к реестру
- Копирование полного отчёта в буфер одной кнопкой
- Дебаунс 800 мс поглощает серию событий от одного физического подключения
- Не требует установки и прав администратора
- Один исходник собирается и под x86, и под x64

### Как использовать

1. Запустить `devwatch.exe`
2. Появится небольшое главное окно, программа снимет начальный снимок устройств
3. Подключить любое оборудование
4. Появится всплывающее окно со списком новых устройств
5. Нажать **Копировать в буфер**, затем **Закрыть**

Программа продолжает работать и мониторить до закрытия главного окна.

### Примечания

- Устройства без VID/PID в InstanceId (например виртуальные аудиоэндпоинты `SWD\MMDEVAPI\...`) покажут `----` — это штатное поведение
- Составные устройства отображаются несколькими записями (по одной на каждый интерфейс) — так же, как в Device Manager
- Отображаются только **появления** устройств; отключение отслеживается внутри, но всплывающего окна не вызывает

### Сборка

- **Компилятор:** PureBasic 6.x
- **Платформа:** Windows x86 или x64 (один исходник, переключается в Compiler Options)
- **Иконка:** указать `devwatch.ico` в Compiler → Compiler Options → Executable Icon
- **Подсистема:** Windows (без консоли)
- Сторонних библиотек нет — `setupapi.dll` загружается динамически из System32 / SysWOW64

---

*(c) CheshirCa 2026*
