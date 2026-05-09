# XDA003 Belt / Hook 參數設定說明 v3

> **適用版本**：Belt v_new（2026-05-09 起的韌體）+ Hook v_new
>
> v3 與 v2 的關鍵差異：v2 hook 把 byte 0 / byte 1 用來下發「系統循環秒數」與「BLE 廣播時間」；v3 hook 把這兩件事改成韌體寫死，那兩個 byte 因此釋出，**重新指派為全新欄位** `alarm_window_s` 與 `flags`，搭配新的「BLE-connected 即時訊息交換」路徑（例如 SAFE-zone 通知）。**Wire ABI 與 v2 完全相容** — payload 長度、byte 偏移皆未動 — 但 byte 0 / byte 1 的「意義」整個換了，不是改名而是 byte 重用。詳細對照見 [parameter_protocol_v2_vs_v3.md](parameter_protocol_v2_vs_v3.md)。

---

## 1. 用途與通道

本協定描述後台如何透過 **LoRaWAN downlink fPort=30** 設定 Belt 與其綁定的 Hook 參數。Belt 收到 fPort=30 packet 後會：

1. 依 payload 長度決定解析方式：
   - **24 bytes** — 只更新 Belt 自身參數
   - **74 bytes** — 更新 Belt 自身參數 **加** 至多 2 支 Hook 的參數
2. Hook 參數區塊會比對 `id[6]`，**只有與當下綁定 Hook ID 相符的區塊**才會被 Belt 透過 BLE 轉送到對應 Hook；不相符的區塊會被靜默丟棄。

> **嚴格長度檢查**：非 24 / 74 byte 的 fPort=30 packet 必須被 Belt 韌體忽略；不允許部分解析。

---

## 2. Wire 結構

### 2.1 Belt header（24 bytes）

```c
struct PACKED belt_downlink_header_v3
{
    uint8_t  reboot;                    // 1   != 0 → reboot
    uint8_t  reset;                     // 1   != 0 → factory reset (wipe NVS + LittleFS)
    uint16_t power_test_sleep_s;        // 2   > 0 → one-shot deep sleep N seconds (LE)
    uint16_t uplink_report_interval_s;  // 2   1–3600 LoRa uplink period seconds (LE), persisted
    uint8_t  reserved_a;                // 1   was beacon_scan_duration (abandoned in v3)
    uint8_t  beacon_smooth_alpha_x100;  // 1   1–100 → EWMA α 0.01–1.00, persisted
    uint8_t  reserved_b[8];             // 8   was beacon_name_filter (abandoned)
    uint8_t  reserved_c[8];             // 8   was hook_name_filter (abandoned)
};
```

| 欄位 | 大小 | 說明 |
|------|------|------|
| `reboot` | 1 | 非 0 → 立即重開機（v2 此 byte 為 `reboot_and_ignore_reed`，含已棄用的磁簧開關控制） |
| `reset` | 1 | 非 0 → factory reset（清除 NVS + LittleFS 中的 beacon whitelist 後重開機） |
| `power_test_sleep_s` | 2 | 大於 0 → 進入 deep sleep 該秒數做電流量測，喚醒等同重開機（little-endian）。**不持久化**。v2 此欄位為 `belt_sleep_duration`（系統循環秒數，v_new always-on 後重新指派為一次性測試觸發） |
| `uplink_report_interval_s` | 2 | LoRa 上行週期秒數，1–3600（little-endian），持久化。v2 此欄位為 `uplink_report_interval`，語意未變僅補上 `_s` 單位後綴 |
| `reserved_a` | 1 | 保留。v2 此 byte 為 `beacon_scan_duration`（單次掃描秒數），v_new 連續掃描不再按 cycle，已棄用 |
| `beacon_smooth_alpha_x100` | 1 | 1–100 → BLE-RSSI EWMA α 0.01–1.00，持久化。v2 此 byte 為 `beacon_scan_times`（每循環掃描次數），v1 起已偷偷重用為 alpha；v3 給予正式名稱 |
| `reserved_b[8]` | 8 | 保留。v2 此區塊為 `beacon_name_filter`（beacon 名稱前綴過濾），v3 改用 UUID 比對，已棄用 |
| `reserved_c[8]` | 8 | 保留。v2 此區塊為 `hook_name_filter`（Hook 名稱前綴過濾），v3 改用 6-byte ID 綁定，已棄用 |

> **v2 → v3 byte 重用 / 棄用**：wire 24 bytes 完全不變，v2 後台不需修改 payload 長度也能繼續推 — 但「scan_times → alpha_x100」這個 byte 的解讀已從「掃描次數」變成「α × 100」，v2 後台若仍按舊語意填 1–10 之類的小整數，會被 v3 belt 解讀為非常低的 alpha（~0.01–0.10 強平滑），請改用 v3 命名。

### 2.2 Hook 區塊（25 bytes，最多 2 支）

```c
struct PACKED hook_downlink_command_struct_v3
{
    uint8_t  id[6];
    uint16_t reserve;
    hook_settings_struct_v3_t hook_settings;
};                                  // 25 bytes
```

| 欄位 | 大小 | 說明 |
|------|------|------|
| `id[6]` | 6 | Hook 的 base MAC（**MSB-first**）。Belt 會同時嘗試 MSB-first 與 LSB-first 比對綁定，所以後台兩種順序皆可接受 |
| `reserve` | 2 | 保留欄位，目前全填 `0x0000` |
| `hook_settings` | 17 | 內嵌的 hook 設定結構，見 §2.3 |

### 2.3 hook_settings_struct_v3_t（17 bytes）— **v3 變更**

```c
typedef struct PACKED hook_sensing_axis_struct
{
    uint8_t  sensing_type;        // 0 = EXCLUSIVE, 1 = INCLUSIVE
    uint16_t sensitivity_high;
    uint16_t sensitivity_low;
} hook_sensing_axis_struct_t;     // 5 bytes

typedef struct PACKED hook_settings_struct_v3
{
    uint8_t alarm_window_s;       // 1–30 秒，0 為哨兵值（見 §3）；v3 新欄位（v2 此 byte 為 system_cycle_time）
    uint8_t flags;                // 旗標位元組；v3 新欄位（v2 此 byte 為 advertising_duration）
    hook_sensing_axis_struct_t x;
    hook_sensing_axis_struct_t y;
    hook_sensing_axis_struct_t z;
} hook_settings_struct_v3_t;      // 17 bytes
```

| 欄位 | 大小 | 說明 |
|------|------|------|
| `alarm_window_s` | 1 | **v3 新欄位**（v2 此 byte 為 `system_cycle_time`，v3 韌體不再支援由後台調整 system cycle，改成寫死在韌體內）。Hook alarm window（秒），1–30；超過會被 Hook 端 clamp。**值 0** 為哨兵 = flag-only write，見 §3 |
| `flags` | 1 | **v3 新欄位**（v2 此 byte 為 `advertising_duration`，v3 韌體 BLE 廣播改成 always-on 寫死）。各 bit 定義見 §3。**transient 不持久化** — Hook 收到後執行 side-effect，存進 flash 時固定為 0 |
| `x` / `y` / `z` | 各 5 | 三軸磁場感測參數：`sensing_type` + `sensitivity_high` + `sensitivity_low`（uint16 little-endian） |

> **v2 → v3 ABI 相容**：`alarm_window_s` / `flags` 在 byte 0 / byte 1 的位置與寬度跟 v2 的 `system_cycle_time` / `advertising_duration` 完全相同。v2 後台若送出 byte 1 = 1 或 2 等典型 `advertising_duration` 值，bit `0x80` 不會被誤觸發，所以 v3 hook 不會被誤判為 SAFE-zone；byte 0 = 1–30 也會被 v3 hook 視為合法 alarm_window_s。**反向不安全**：v3 後台送 `byte 0 = 0` flag-only write 給 v2 hook 會被解讀為 `system_cycle_time = 0`，hook clamp + 把 XYZ 軸全寫成 0，請務必先燒 hook 再上 v3 後台。

### 2.4 完整 74-byte payload

```c
struct PACKED belt_downlink_command_struct_v3
{
    belt_downlink_header_v3 header;          // 24 bytes
    hook_downlink_command_struct_v3 hook[2]; // 50 bytes
};
```

`hook[0]` 與 `hook[1]` 各自獨立比對綁定 ID，可單獨設定；不需要的 slot 把 `id[6]` 全填 `0x00` 即會被忽略。

---

## 3. v3 新增：`flags` 與 flag-only write

### 3.1 旗標位元定義

```c
#define HOOK_SETTINGS_FLAG_IN_SAFE_ZONE  0x80   // 作業員位於 SAFE zone，請 pin 住 counter
// 其餘 bit 保留，必須填 0
```

| Bit | 名稱 | 行為 |
|-----|------|------|
| `0x80` | `IN_SAFE_ZONE` | Hook 收到後設定 SAFE-zone grace window（10 秒），期間 mag task 強制將 `not_detected_counter` 與 `status` 釘在 0；同時刷新內部 `last_metal_seen_ms`，讓 grace 過期時也是從 0 開始重新計時 |
| `0x01–0x40` | 保留 | 必須填 0；Hook 端會忽略 |

### 3.2 Flag-only write（`alarm_window_s = 0` 哨兵）

`alarm_window_s` 原本範圍是 1–30；當值為 **0** 時 Hook v3 將其視為「flag-only write」哨兵：

- Hook **不會** 把 17 byte 寫進 settings flash（XYZ 軸與 alarm_window_s 全部忽略）
- Hook **僅** 處理 `flags` 欄位的副作用
- 仍會回傳一筆 ACK（`0x00 + 17B 當下實際 settings`）讓送方確認 hook 還活著；ACK 中的 settings 維持原值

這允許 Belt（或後台）在 **不知道 Hook 當下完整 settings** 的情況下單純通知一個 side-effect，不必先讀回設定再原樣回寫。

### 3.3 Belt 的自動 SAFE-zone 觸發

Belt v_new 韌體在「看到任一 SAFE-role beacon 為 fresh」期間，會 **自動** 透過本機 BLE 對所有已連線的 Hook slot 每 3 秒送一次 flag-only write（`alarm_window_s=0`、`flags=0x80`），維持 Hook 端的 grace window：

```
SAFE 進入：       [flag] [flag] [flag] [flag] ... 每 3s
                    │
                    ▼
Hook grace window: ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓
                    │ 10s │ 10s │ 10s │ ...
                  每收到 flag 就刷新

SAFE 離開：       (停止送 flag)
                                          ▼
Hook grace window: ▓▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░░░  ← 最後一次 flag 後 10s 自動失效
```

這個流程 **不需要後台介入**：只要場域 SAFE beacon 部署正確，Belt 就會自己處理。

### 3.4 後台手動觸發（可選）

如需後台主動 reset 某支 Hook 的 counter（例如測試或排程性「重置作業日」），可以透過 fPort=30 推一筆 74-byte payload，其中對應的 hook 區塊：

```
id[6]:                  目標 Hook 的 base MAC
reserve:                0x0000
hook_settings:
  alarm_window_s:    0x00            ← 哨兵
  flags:                0x80            ← FLAG_IN_SAFE_ZONE
  x / y / z:            (忽略，建議全填 0)
```

Belt 收到後會比對 ID、轉送這個 17-byte block 到對應 Hook 的 BLE RX；Hook 看到 `alarm_window_s=0` 會走 flag-only path，不更動 settings、僅執行 reset counter。

---

## 4. 範例 payload

### 4.1 純更新 Belt 設定（24 bytes，header only）

把 LoRa 上行週期改成 60 秒、smoothing α 設為 0.20、然後重開機：

```
01 00 00 00 3C 00 00 14 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
│  │  └──┘ └──┘ │  │  └──────── reserved_b[8] ────────┘└── reserved_c[8] ──┘
│  │   │    │   │  └─ beacon_smooth_alpha_x100 = 0x14 (20 → α 0.20)
│  │   │    │   └──── reserved_a (was beacon_scan_duration; 必須填 0)
│  │   │    └─ uplink_report_interval_s = 0x003C = 60 秒
│  │   └─ power_test_sleep_s = 0（不觸發 deep-sleep 測試）
│  └─ reset = 0
└─ reboot = 1（重開機）
```

### 4.2 設定 Belt + 一支 Hook 的感測參數（74 bytes）

不重開機、上行週期沿用、α 不動，只改 hook[0] 的 alarm_window_s + XYZ 軸：

```
header (24B):  00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
                  (整段 header 全 0 → 不觸發任何 belt-side 動作)
hook[0] (25B): DC 06 75 F8 2C C8 00 00 0A 00 01 64 00 32 00 01 64 00 32 00 01 64 00 32 00
                └─── id ──────┘ └rsv┘ │  │  └────────── x / y / z 各 5 byte ──────────┘
                                       │  └─ flags = 0（不觸發任何 side-effect）
                                       └─── alarm_window_s = 10 s
hook[1] (25B): 00 00 00 00 00 00 00 00 ... (id 全 0 → Belt 忽略)
```

### 4.3 後台手動 reset hook[0] 的 counter（74 bytes）

```
header (24B):  00 00 00 00 00 00 00 00 ... (header 全 0)
hook[0] (25B): DC 06 75 F8 2C C8 00 00 00 80 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
                └─── id ──────┘ └rsv┘ │  │
                                       │  └─ flags = 0x80 (IN_SAFE_ZONE)
                                       └─── alarm_window_s = 0（flag-only 哨兵）
hook[1] (25B): 00 00 00 00 00 00 00 00 ...
```

---

## 5. 韌體側驗證 / clamp

| 條件 | Belt 端行為 | Hook 端行為 |
|------|-------------|-------------|
| payload 長度 ≠ 24 / 74 | 整包丟棄 | — |
| `header.reset != 0` | 清 NVS + LittleFS + 重開機（最高優先） | — |
| `header.reboot != 0`（且 reset = 0） | 立即重開機 | — |
| `header.power_test_sleep_s > 0` | Deep sleep 該秒數，喚醒等同重開機 | — |
| `header.uplink_report_interval_s > 0` | 套用為 LoRa 上行週期，持久化到 NVS | — |
| `header.beacon_smooth_alpha_x100 > 100` | clamp 到 100（α = 1.00） | — |
| `header.reserved_a / b / c` | 完全忽略 | — |
| Hook ID 不在綁定列表 | 該 hook block 不轉送 | — |
| `alarm_window_s = 0` | 直接轉送 17 bytes | 觸發 flag-only path，不 persist settings |
| `alarm_window_s > 30` | 直接轉送 | clamp 回 `DEFAULT_HOOK_CYCLE_TIME / 1000`（10 秒） |
| `flags & 0x80` 為 1 | — | 設定 SAFE-zone grace window 10 秒 |
| `flags & 0x7F` 非 0 | — | 忽略（保留位元） |
| 任何寫入到 flash 之前 | — | `flags` 強制歸 0（transient 不持久化） |

---

## 6. 向後相容矩陣

| 後台版本 | Belt 韌體版本 | Hook 韌體版本 | 行為 |
|----------|---------------|---------------|------|
| v2 | v_new | v_new | OK；`flags` 在 v2 後台填的是舊 `advertising_duration` 值（通常 1 或 2），不會觸發 `0x80` bit |
| v3 | v_new | v_new | OK；完整支援 SAFE-zone reset 與 flag-only write |
| v3 | v_new | **舊版** | **不安全** — 舊 Hook 看到 `alarm_window_s=0` 不會走 flag-only path，會把 settings 全打成 0（XYZ sensitivity 都 0 → 偵測失效）。必須先把 Hook 升到 v_new |
| v2 | **舊版** | v_new | OK；Belt 把 17 bytes 原樣轉送，Hook 仍可解析 |

**升級順序建議**：先燒 Hook → 再燒 Belt → 最後切換後台到 v3 推 payload。

---

## 7. 相關文件

- `docs/belt_operation.md` — Belt 端使用者操作說明（含 SAFE / DANGER zone 行為描述）
- `docs/hook_operation.md` — Hook 端使用者操作說明
- `firmware/src/data_types.h` — Belt 端 wire struct 權威定義
- `22_XDA003H/firmware/library/data_types.h` — Hook 端 wire struct 權威定義
