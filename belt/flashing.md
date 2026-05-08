# XDA003-B Belt 韌體燒錄說明

## 檔案

`xda003b-belt-<git-sha>-<YYYYMMDD>.bin` — 已合併好的單一燒錄檔
（包含 bootloader + partition table + boot app + main firmware）。

整顆檔案直接寫到 ESP32-C3 flash 的 **offset 0x0**，不需要分段。

## 硬體需求

- XDA003-B Belt 主板（ESP32-C3）
- USB-C 連接線到 PC（內建 CH340 USB-serial 轉接）
- macOS / Windows / Linux

## 三種燒錄方式擇一

### 方式 A — 命令列 esptool（最直接，所有平台適用）

先安裝 `esptool`（一次性）：
```bash
pip install esptool
```

把 Belt 接上電腦並進 download mode（按住 BOOT 鍵 → 短按 RESET 鍵 → 放開 BOOT），然後執行：

```bash
esptool.py --chip esp32c3 --port /dev/cu.usbserial-XXXX --baud 460800 \
  --before default_reset --after hard_reset \
  write_flash --flash_mode dio --flash_freq 80m --flash_size 4MB \
  0x0 xda003b-belt-XXXXXXX-YYYYMMDD.bin
```

把 `/dev/cu.usbserial-XXXX` 換成實際的 serial port（macOS：`ls /dev/cu.usbserial-*`；Windows：裝置管理員 → COM port）。

### 方式 B — Espressif Flash Download Tool（Windows）

1. 從 <https://www.espressif.com/en/support/download/other-tools> 下載 Flash Download Tool
2. 開啟 → 選 **ESP32-C3** chip
3. 設定：
   - 在「SPIDownload」分頁，把 `xda003b-belt-XXXXXXX.bin` 拖進去，offset 填 `0x0`
   - SPI SPEED: **80 MHz**
   - SPI MODE: **DIO**
   - FLASH SIZE: **32Mbit**（= 4MB）
   - 勾選「DoNotChgBin」
4. COM port 選 Belt → BAUD `460800` → **START**
5. 看到 FINISH 即可。

### 方式 C — Web 瀏覽器燒錄（Chrome / Edge）

無需安裝任何工具，但只能在支援 Web Serial 的瀏覽器（Chrome 或 Edge）執行：

1. 開啟 <https://espressif.github.io/esptool-js/>
2. **Connect** → 選 Belt 的 COM port
3. **Add File** → 選 `xda003b-belt-XXXXXXX.bin`，offset `0x0`
4. **Program** → 等完成 → **Reset**

## 燒錄成功確認

開啟 serial monitor（115200 baud）應該看到：

```
=== XDA003-B Belt v1 (Phase 1 scaffold) ===
Chip   : ESP32-C3 rev 4, 160MHz, 1 core(s)
Flash  : 4MB
[bcn] whitelist loaded (...)
[bcn] seeded N factory-default entries (now 7 total)
[LoRa] ABP active. devAddr=0x... DR5 (SF7BW125) ...
[ble] central up as 'BELT-XXXXXX'
[BOOT] entering operational loop.
```

並且 BLE 應該開始 advertising 名稱 `BELT-XXXXXX`，可以從手機 / Web BLE Console 連上。

## 出廠初始狀態

剛燒進去的 Belt：
- 7 支內建 factory-default beacon（B5B182C7…0822 / 0833 / 0844 / 0855 / 08D5 / 08D8 / 08D9）
- 未綁定任何 hook，必須先讓伺服器發 fPort=10 INITIAL downlink 才會開始連線
- LoRa report 間隔預設 60 秒，alarm 期間自動切到 15 秒
- BLE α 平滑預設 0.20

## 常見問題

**Q：燒錄時卡在「Connecting...」**
A：Belt 沒進 download mode。按住 BOOT 鍵 → 短按 RESET → 放開 BOOT，再立刻按 esptool 的執行鍵。或拔 USB → 按住 BOOT → 插 USB → 過 2 秒放開 BOOT。

**Q：esptool 顯示「Hash of data verified / Hard resetting」成功，但 Belt 卻跑舊韌體（DIS 版本不對）**
A：這台 Belt 之前用過 BLE OTA，flash 內的 `ota_data` partition 還指向某個 OTA slot。
USB 燒錄寫到 factory partition (0x10000) 但 bootloader 看 `ota_data` 還是先去 OTA slot
boot → 跑舊韌體。

**症狀**：燒錄程序回 SUCCESS、serial 也印新韌體 boot banner，但 DIS 顯示舊版號、LoRa 上行也是舊 DevAddr。

**修法**：用 app-only bin 燒之前先一次 erase_flash（會把 ota_data 一起清掉）：

```bash
esptool.py --chip esp32c3 --port /dev/cu.usbserial-XXXX erase_flash
# 接著正常燒錄
esptool.py --chip esp32c3 --port /dev/cu.usbserial-XXXX --baud 460800 \
  write_flash 0x0 xda003b-belt-XXXXXXX-YYYYMMDD.bin
```

**或乾脆用 FULL bin**（檔名帶 `-FULL.bin` 那個，含 bootloader + partitions + app 合併到 0x0）—— FULL bin 的 partitions section 預設 ota_data 為「未指定」，bootloader 會回去 boot factory，等價於 erase_flash 的效果。

**Q：燒錄成功但 Belt 開機卡住**
A：可能是 LittleFS partition 沒清空，舊資料 corrupt。重燒一次並加 `--erase-all`：
```bash
esptool.py --chip esp32c3 --port /dev/cu.usbserial-XXXX erase_flash
```
然後再跑一次 write_flash。

**Q：要怎麼回廠 reset？**
A：兩種方式：
1. LoRa 從伺服器推 fPort=30 reset 命令（byte[1]=1）
2. 整片 erase_flash 後重燒

兩者都會清掉 NVS（包含 hook bindings、report interval、α）以及 LittleFS（包含 beacon whitelist、hook settings）。
