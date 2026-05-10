# XDA003 工安穿戴系統 — 操作文件

公開的客戶端 / 整合商文件入口。涵蓋 XDA003 工安穿戴系統兩個元件：

- **XDA003-B Belt（腰帶）** — 主控裝置，與場域 BLE beacon、LoRaWAN 後台溝通
- **XDA003-H Hook（掛鉤）** — 偵測作業員是否確實掛在合格金屬結構上

> 本 repo 只放給最終使用者、施工人員、後台整合商看的內容。內部開發歷程、bug log、設計決策不在此公開，請洽 SiliQs。

---

## Belt（腰帶端）

| 文件 | 對象 | 說明 |
|------|------|------|
| [belt/operation.md](belt/operation.md) · [PDF](belt/operation.pdf) | 工地作業員、場域管理者 | Belt 整體運作邏輯、區域定位、告警流程、低功耗 / 充電行為 |
| [belt/parameter_protocol.md](belt/parameter_protocol.md) · [PDF](belt/parameter_protocol.pdf) | 後台 / LoRa 平台整合商 | LoRaWAN fPort=30 設定協定（v3）、wire 結構、payload 範例、向後相容矩陣 |
| [belt/parameter_protocol_v2_vs_v3.md](belt/parameter_protocol_v2_vs_v3.md) · [PDF](belt/parameter_protocol_v2_vs_v3.pdf) | v2 後台升級者 | v2 ↔ v3 欄位對照、wire ABI 變動、升級檢查清單 |
| [belt/flashing.md](belt/flashing.md) | 出廠 / 維修人員 | Belt 韌體燒錄三種方式（esptool、PlatformIO、Arduino IDE） |

## Hook（掛鉤端）

| 文件 | 對象 | 說明 |
|------|------|------|
| [hook/operation.md](hook/operation.md) · [PDF](hook/operation.pdf) | 工地作業員、場域管理者 | Hook 三軸磁場偵測邏輯、狀態回報、低功耗、充電 |
| [hook/flashing.md](hook/flashing.md) | 出廠 / 維修人員 | Hook 韌體燒錄方式 |

---

## 韌體下載

每個正式版本的韌體 `.bin` 檔請到本 repo 的 [Releases](../../releases) 頁面取得；附隨的 PDF 文件也會一併附在當期 release 的 assets 中，方便整批存檔。

文件版本與韌體版本的對應關係寫在每個 release 的 release note。

---

## Web BLE 維護工具

兩支單檔 HTML，下載到本機後用 **Chrome / Edge 桌面版**直接開（Web Bluetooth 不支援 Safari）。連 Belt / Hook 不需要安裝任何 app。

| 工具 | 用途 |
|------|------|
| [tools/belt_ble_console.html](tools/belt_ble_console.html) | 連 Belt → 即時看區域偵測、Hook slot 狀態（connected / advertisement / disappear 三態）、live beacon RSSI、推下行設定、推 OTA 升級 |
| [tools/hook_ble_console.html](tools/hook_ble_console.html) | 連 Hook → 即時看磁場 X/Y/Z 三軸 + 圖表、警報狀態、推三軸靈敏度設定、推 OTA 升級 |

每個版本的 release 也會把這兩個檔附在 assets，跟韌體 / PDF 一起整批下載。

---

## 文件版次

文件採用 markdown 為來源、PDF 為列印 / 歸檔附件，兩者由相同 markdown 產出。每次更新時 markdown 與 PDF 同步推送。

如需引用，建議引用 commit SHA + 檔名（例：`belt/operation.md @ a1b2c3d`）以鎖定特定版本。
