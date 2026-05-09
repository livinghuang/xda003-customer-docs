# Belt-Hook 參數結構 v2 vs v3 對照

> 本文件給已經依 v2 實作的後台 / 整合商，快速對照 v3 變了哪些欄位、要注意什麼。完整 v3 規格請見 [belt_hook_parameter_protocol.md](belt_hook_parameter_protocol.md)。

## 一句話總結

**Wire ABI（byte 偏移、欄位寬度、payload 長度）完全相容 v2，只有「欄位名稱」和「兩個保留語意」變了**：

1. byte 0：`system_cycle_time` 改名為 `alarm_window_s`（值 0 在 v3 多了「flag-only write」的哨兵語意）
2. byte 1：`advertising_duration` 改名為 `flags`（v0/v1/v2 該欄位已棄用；v3 重新定義為 transient 旗標位元組）

---

## hook_settings_struct_v3_t（17 bytes）— 欄位對照

| Byte | v0 / v1 / v2 名稱 | v3 名稱 | 寬度 | 行為差異 |
|------|--------------------|----------|------|----------|
| 0 | `system_cycle_time` | **`alarm_window_s`** | uint8 | v2：1–30 秒 alarm window（值 0 / >30 在 hook 端會被 clamp 回預設 10）<br>**v3 新增**：值 `0` 為「flag-only write」哨兵 — hook 不更動 settings flash，只處理 `flags` 副作用 |
| 1 | `advertising_duration` | **`flags`** | uint8 | v2：保留欄位，hook 韌體不使用，但 hook 仍會原樣存進 flash<br>**v3**：旗標位元組（transient，不存 flash）。bit `0x80` = `IN_SAFE_ZONE`；其他 bit 保留必須填 0 |
| 2 | `x.sensing_type` | 同 | uint8 | 不變 |
| 3–4 | `x.sensitivity_high` | 同 | uint16 LE | 不變 |
| 5–6 | `x.sensitivity_low` | 同 | uint16 LE | 不變 |
| 7–11 | `y.*` | 同 | 5 bytes | 不變 |
| 12–16 | `z.*` | 同 | 5 bytes | 不變 |

> **重要**：byte offset、欄位寬度、總長 17 bytes **皆未變**。v2 後台不修改任何程式碼也能繼續推設定，只是無法觸發 v3 的兩個新功能（flag-only write、SAFE-zone counter pin）。

---

## hook_downlink_command_struct_v3（25 bytes 外層）— 不變

```
byte 0..5    id[6]              hook base MAC（v3 接受 MSB-first 與 LSB-first 任一順序）
byte 6..7    reserve            填 0x0000
byte 8..24   hook_settings      上表 17 bytes
```

---

## belt_downlink_command_struct_v2（74 bytes payload）— 不變

```
byte 0..23   belt header        24 bytes（reboot_and_ignore_reed、sleep、scan filter ...）
byte 24..48  hook[0]            25 bytes
byte 49..73  hook[1]            25 bytes
```

LoRaWAN fPort=30 收到的 payload 長度判斷規則（**v2 / v3 共用**）：

- 24 bytes → 只更新 belt 自己
- 74 bytes → 更新 belt + 兩支 hook
- 其他長度 → Belt 直接丟棄

---

## v3 新增的兩個功能（v2 後台不會觸發）

### 1. Flag-only write（單純通知不改 settings）

```
hook_settings.alarm_window_s = 0x00      ← 哨兵
hook_settings.flags          = 0x80      ← 例：FLAG_IN_SAFE_ZONE
hook_settings.x / y / z      = 任意（hook 會忽略）
```

| | v2 收到此 payload 的行為 | v3 收到此 payload 的行為 |
|------|---------------------------|---------------------------|
| Hook 端 alarm_window 設定 | 寫入 settings；發現是 0 → clamp 回 DEFAULT 10s | 偵測到 byte 0 = 0 → 走 flag-only path，**不寫入** flash |
| Hook 端 XYZ 軸設定 | 寫入 settings（XYZ 全 0 會讓偵測壞掉！） | **完全忽略**，flash 不動 |
| Hook 端 flags 副作用 | 不處理（v2 該欄位是 `advertising_duration`） | 處理（例如 `0x80` 觸發 SAFE-zone counter pin） |
| Hook 端回 ACK | 0x00 + 17B 寫入後的 settings（XYZ 已被改成 0） | 0x00 + 17B 當下的 settings（**未變動**） |

> 結論：**永遠不要從 v2 後台送出 `system_cycle_time = 0` 的 payload 給 v3 hook**，雖然 v3 hook 不會壞，但會造成 v2 後台對 hook 狀態的理解不一致（後台以為剛寫進去 0 然後被 clamp 成 10，實際上 hook 完全沒寫）。反過來：**v2 hook 收到 v3 後台送的 flag-only write 會把 XYZ 全寫成 0，等同把 hook 偵測弄壞** — 升級必須先燒 hook 再上 v3 後台（見 [belt_hook_parameter_protocol.md §6](belt_hook_parameter_protocol.md#6-向後相容矩陣)）。

### 2. SAFE-zone counter pin（自動 / 手動）

Belt 韌體 v3 在偵測到 SAFE-role beacon 期間 **自動** 每 3 秒對連線中的 hook 各送一次 flag-only write（`alarm_window_s = 0`、`flags = 0x80`），維持 hook 端 10 秒的 grace window — counter / status 在 grace window 內被釘在 0，作業員在休息區不會觸發警報。

後台也可以用同樣的 fPort=30 payload **手動** 觸發 reset counter（例如排程性的「重置作業日」）：

```
hook[i].id[6]                    = 目標 hook MAC
hook[i].reserve                  = 0x0000
hook[i].alarm_window_s           = 0x00
hook[i].flags                    = 0x80
hook[i].x / y / z                = 全 0
```

Belt 收到後會比對 ID、把 17-byte block 透過 BLE 轉送給對應 hook，hook 走 flag-only path、reset counter。

---

## 升級檢查清單

| 元件 | v2 → v3 需要改什麼 |
|------|--------------------|
| Belt 韌體 | 重新燒錄 v3 (含 SAFE-zone 自動觸發 + 新 macro 名) |
| Hook 韌體 | **必須** 重新燒錄 v3 (理解 `alarm_window_s = 0` 哨兵；否則 v3 後台送 flag-only write 會打壞 settings) |
| 後台 / LoRa platform | 不需改，但建議：欄位名稱在內部資料表更新為 `alarm_window_s` / `flags` 以避免日後維護混淆 |
| 後台 / 想啟用 SAFE-zone 手動 reset | 在 hook block 模板上加「flag-only template」(`alarm_window_s=0`, `flags=0x80`) 給操作員選用 |
| 後台 payload generator (Python / Node) | 把 struct 定義裡的欄位名跟著改；wire bytes 不變所以不必動 generator 邏輯 |

---

## 相關文件

- [belt_hook_parameter_protocol.md](belt_hook_parameter_protocol.md) — v3 完整規格 + 範例 payload
- [belt_operation.md](belt_operation.md) — Belt 端使用者操作說明（含 SAFE / DANGER zone 行為）
- [`22_XDA003H/docs/hook_operation.md`](../hook/operation.md) — Hook 端使用者操作說明（含 SAFE-zone grace window 描述）
