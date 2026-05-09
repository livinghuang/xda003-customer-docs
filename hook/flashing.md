# XDA003-H Hook 韌體燒錄說明

## 檔案

每個釋出版本提供 **兩個** 變體：

| 檔名 | 用途 | 內容 |
|------|------|------|
| `xda003h-hook-<sha>-<YYYYMMDD>-FULL.bin` | **USB 燒錄**（首次安裝、出廠、維修、回復出廠） | bootloader + partition table + boot_app0 + factory firmware（合併後直接寫 offset 0x0） |
| `xda003h-hook-<sha>-<YYYYMMDD>-app.bin` | **BLE OTA 推送**（透過 Web Bluetooth 主控台 / `nimbleota.py`） | 純 firmware app（factory partition 內容），由裝置端 NimBLEOta 接收後自動寫入 OTA partition |

**選哪一個？**
- 從來沒 OTA 過的全新裝置 / 想完全重置 / 維修：用 `-FULL.bin` 走 USB（見下文方式 A/B/C）
- 已部署在現場、想透過藍牙無線升級：用 `-app.bin` 走 BLE OTA（見 [hook_operation.md §5](../../docs/hook_operation.md) 之「韌體無線更新」段）

> **注意**：曾經透過 BLE OTA 升過韌體的 Hook，再用 USB 燒入時請務必選 `-FULL.bin`（merged bin 內含預設 ota_data，bootloader 會改 boot factory 而不是舊 OTA app）；或先 `esptool.py erase_flash` 再燒。詳見最後一節。

## 硬體需求

- XDA003-H Hook 主板（ESP32-C3 + QMC5883L 磁力計）
- USB-C 連接線到 PC（內建 CH340 USB-serial）
- macOS / Windows / Linux

## 三種燒錄方式擇一

### 方式 A — 命令列 esptool（最直接，所有平台適用）

```bash
pip install esptool

# Hook 接上電腦後
esptool.py --chip esp32c3 --port /dev/cu.usbserial-XXXX --baud 460800 \
  --before default_reset --after hard_reset \
  write_flash --flash_mode dio --flash_freq 80m --flash_size 4MB \
  0x0 xda003h-hook-XXXXXXX-YYYYMMDD-FULL.bin
```

如果連不上需要進 download mode：按住 BOOT → 短按 RESET → 放開 BOOT。

### 方式 B — Espressif Flash Download Tool（Windows）

從 <https://www.espressif.com/en/support/download/other-tools> 下載 → 選 ESP32-C3 →
SPIDownload 分頁拖入 `.bin` 檔，offset `0x0`，SPI SPEED 80 MHz / MODE DIO / SIZE 32Mbit。

### 方式 C — Web 瀏覽器燒錄

開 <https://espressif.github.io/esptool-js/> → Connect → Add File（offset 0x0） → Program。

## 燒錄成功確認

Serial monitor (115200 baud)：

```
======hook  initial settings=======
alarm_window_s: 10
X sensing_type: EXCLUSIVE
X sensitivity_low: 0  high: 32767
Y sensing_type: EXCLUSIVE
Y sensitivity_low: 23000  high: 32767
Z sensing_type: EXCLUSIVE
Z sensitivity_low: 0  high: 3000
======hook  initial settings=======
Hook ID: XX XX XX XX XX XX
[ble] BLE service started.
[ble] BLE advertising started.
```

BLE 廣播名稱 `HOOK-XXYYZZ`（XX/YY/ZZ 為 chip ID 前 3 byte）。

## 出廠初始狀態

- magnetometer 採樣 2 Hz（背景 task）
- alarm window：10 秒（連續 10 秒沒偵測到金屬就升 status=ALARM）
- 三軸閾值（EXCLUSIVE，「值在範圍外」算「偵測到金屬」）：
  - X：[0, 32767]（永遠在範圍內 = 不貢獻偵測，留作 Belt 運行時 GATT 推設定）
  - Y：[23000, 32767]（金屬掛上時 \|Y\| 應在範圍內 = 不偵測；脫離後 \|Y\| 跌出範圍 = 偵測到 = NORMAL）
  - Z：[0, 3000]（同 X）
- BLE-idle deep-sleep cycle：4 秒醒 / 1 秒深睡（無 GATT client 連線時省電）
- 充電模式：偵測 charging pin → 進深睡 5 秒 cycle，電池滿 4.10V 後常亮 LED

## 常見問題

**Q：esptool 顯示成功但 Hook 跑舊韌體（DIS 版本不對）**
A：先前用過 BLE OTA 的裝置，flash 的 `ota_data` partition 會繼續指向某個 OTA slot，
USB 燒到 factory partition (0x10000) 不會生效 — bootloader 看 ota_data 還是 boot
OTA slot。

**修法（兩擇一）**：

1. **用 `-FULL.bin`** — merged bin 含 bootloader + partition table + boot_app0 + factory app；其中 partition table 把 ota_data 重設為「未指定」，bootloader 因此會回去 boot factory，等價於 erase_flash 的效果。建議優先用這個方法，一次燒到位。

2. **先 erase_flash 再燒**：
   ```bash
   esptool.py --chip esp32c3 --port /dev/cu.usbserial-XXXX erase_flash
   esptool.py --chip esp32c3 --port /dev/cu.usbserial-XXXX --baud 460800 \
     write_flash 0x0 xda003h-hook-XXXXXXX-YYYYMMDD-FULL.bin
   ```

> **`-app.bin` 不要直接 USB 燒到 0x0**，那是 BLE OTA 專用 — `-app.bin` 沒有 bootloader / partition table，硬燒到 0x0 會 brick。USB 燒錄永遠用 `-FULL.bin`。

**Q：Hook 沒辦法被 Belt 連上**
A：確認：
1. Hook BLE name 是 `HOOK-XXYYZZ`（用手機 BLE scanner App 看一下）
2. Hook 沒在 charging mode（拔掉充電線）
3. Belt 的 NVS 已綁定這支 hook 的 chipId（Belt 收過 fPort=10 INITIAL downlink）

**Q：Hook 一直 ALARM**
A：檢查 magnetometer Y 軸 baseline。如果 \|Y\| 落在 [23000, 32767] 區間（沒掛金屬時的典型值），EXCLUSIVE 邏輯就會持續偵測到金屬 = NORMAL。如果 baseline 跑掉了，可以透過 BLE web console（hook_ble_console.html）調整三軸閾值。

**Q：要怎麼回到 factory default？**
A：整片 erase_flash 後重燒：
```bash
esptool.py --chip esp32c3 --port /dev/cu.usbserial-XXXX erase_flash
# 然後重新 write_flash
```
這會清掉 LittleFS（包含上次保存的 hook_storage.bin）。

## 配對 Belt

Hook 不需要與特定 Belt 預先配對；Belt 從伺服器收到 INITIAL downlink 時就會帶兩支
Hook 的 chipId 過來，符合的 Hook 自然會被 Belt 的 BLE scan callback 認出來並建立
GATT 連線。
