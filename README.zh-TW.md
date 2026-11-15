# MacRDP

**開源的 macOS 遠端桌面用戶端，取代 Microsoft「Windows App」，專為高幀率調校。**

[English](README.md) | 繁體中文

MacRDP 的用法和 Windows App 一樣（儲存電腦、群組、相同的每台電腦設定），但把 Windows App 藏起來的效能選項開放出來：**UDP 傳輸**、**H.264 AVC444**、**不限幀率**。搭配幾項 Windows 端設定，原本被 Windows 鎖在約 30 fps 的 1080p 桌面，在區域網路上可以跑到 **75 fps 以上**。

## 和 Windows App 的差別

| | Windows App（Microsoft） | MacRDP |
|---|---|---|
| 傳輸方式 | 自動選擇 | **每台電腦可選 UDP 優先或只用 TCP** |
| 影像編碼 | 自動選擇 | **每台電腦可選 AVC444 / AVC420 / RemoteFX / Progressive / 傳統點陣圖** |
| 幀率 | 每一幀都等伺服器確認 | **可選不限幀率**（`frame-ack:0`） |
| Windows 端調校 | 沒有說明 | **一鍵腳本**：解除 30 fps 上限，開啟 H.264、UDP、GPU 編碼 |
| 剪貼簿 | 開或關 | **文字圖片和檔案可分別設定方向**（雙向 / 只到遠端 / 只到 Mac / 關閉） |
| 全螢幕 | 原生 | 原生：每個連線有自己的 Space，可以滑動切換 |
| 其他 | — | `.rdp` 匯入匯出、`--connect` 指令列（可接 Shortcuts、Alfred、Raycast）、自訂 FreeRDP 參數 |
| 原始碼 | 不公開 | **開源**（Apache-2.0），以 [FreeRDP 3](https://github.com/FreeRDP/FreeRDP) 為核心 |
| Azure Virtual Desktop / Windows 365 | 支援 | **不支援**：MacRDP 直接連線到電腦，或經過 RD Gateway |
| 攝影機重新導向、交換滑鼠左右鍵 | 支援 | **不支援**（FreeRDP 在 macOS 上沒有這些功能） |
| 介面語言 | 多國語言 | 目前只有繁體中文 |

### 實測

1920×1080，Windows 11（QEMU 虛擬機、無 GPU）全螢幕播放動畫，Mac mini 有線區域網路：

| 設定 | 平均 fps | 編碼 |
|---|---|---|
| Windows 預設 | 32 | ClearCodec |
| 套用 Windows 端設定，TCP | 78 | AVC444 |
| 套用 Windows 端設定，UDP | 75 | AVC444 |
| 套用 Windows 端設定，UDP，經 MacRDP 本機轉送（預設） | 72 | AVC444 |

在延遲低於 1 ms 的區域網路，UDP 和 TCP 差不多；UDP 的好處在延遲較高或會掉封包的網路，例如 Wi-Fi 或從外面連回家。

## 功能

- **儲存多組電腦**：格狀或清單檢視、群組、搜尋、最近使用、複製、刪除
- **每台電腦的設定**，對應 Windows App 的「新增電腦」對話框：

| 分頁 | 設定 |
|---|---|
| 一般 | 主機 / IP、埠號、易記名稱、群組、使用者名稱、網域、密碼（存在鑰匙圈）、自動重新連線、系統管理工作階段 |
| 顯示 | 解析度（與顯示器相同 / 與視窗相同 / 常用解析度 / 自訂）、視窗大小改變時更新解析度、顯示比例、全螢幕、使用所有顯示器、符合視窗大小、色彩品質 |
| 裝置與音訊 | 剪貼簿（文字圖片、檔案各自可設雙向 / 只到遠端 / 只到 Mac / 關閉）、印表機、智慧卡、麥克風、聲音播放位置 |
| 資料夾 | 重新導向任意資料夾、分享家目錄 |
| 效能 | UDP 優先或只用 TCP、影像編碼、不限幀率、網路類型、桌布 / 佈景主題 / ClearType / 動畫 |
| 閘道 | RD Gateway 主機、埠號、獨立帳號密碼、區域網路略過閘道 |
| 進階 | 憑證政策、安全性通訊協定（NLA / TLS / RDP）、RemoteApp、替代殼層、負載平衡資訊、鍵盤配置、其他 FreeRDP 參數 |

- 密碼只存在 macOS 鑰匙圈，經由 stdin 傳給 FreeRDP，不會出現在檔案或程序列表裡
- 可以在 Finder 直接打開 `.rdp` 檔，也能匯入匯出
- `MacRDP.app/Contents/MacOS/MacRDP --connect "<名稱或主機>"` 直接連線

## 下載

到 [Releases](https://github.com/walush2023/MacRDP/releases) 下載經過 Apple 公證的 DMG。需要 Apple Silicon Mac、macOS 14 以上，不需要 Homebrew。

第一次連到區域網路上的電腦時，macOS 會詢問 MacRDP 能不能存取區域網路，請按**允許**。如果按了拒絕，到「系統設定 → 隱私權與安全性 → 區域網路」把 MacRDP 打開。

## Windows 端設定

MacRDP 預設就用 UDP、AVC444、不限幀率，但 **Windows 預設會把遠端桌面鎖在約 30 fps，也不一定用 H.264**，要在被連線的 Windows 上調整。

### 一鍵設定

在 Windows 上用**系統管理員**身分開 PowerShell，執行 [`tools/windows-setup.ps1`](tools/windows-setup.ps1)：

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\windows-setup.ps1          # 套用
.\windows-setup.ps1 -Undo    # 還原效能設定
```

執行後**登出 Windows（或重新開機）**，下一次連線才會生效。

### 腳本改了什麼

1. **開啟遠端桌面**：需要 Windows 專業版、企業版或教育版，家用版不能當 RDP 主機。
2. **防火牆**：允許 **TCP 3389** 和 **UDP 3389** 輸入。如果電腦在路由器、Docker 或 VM 後面，**UDP 3389 也要轉送**，否則只會走 TCP。
3. **UDP**：群組原則 `電腦設定 → 系統管理範本 → Windows 元件 → 遠端桌面服務 → 遠端桌面工作階段主機 → 連線 → 選取 RDP 傳輸通訊協定` = **使用 UDP 和 TCP**
   （登錄：`HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services\SelectTransport = 0`）
4. **解除 30 fps 上限**：
   `HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\DWMFRAMEINTERVAL`（DWORD）= **15**
5. **優先使用 H.264/AVC 4:4:4**：`…遠端桌面工作階段主機 → 遠端工作階段環境 → 為遠端桌面連線排定 H.264/AVC 444 圖形模式的優先順序` = 啟用
   （登錄：`…\Terminal Services\AVC444ModePreferred = 1`）
6. **GPU 硬體編碼**（有獨立顯示卡時）：`…遠端工作階段環境 → 設定遠端桌面連線的 H.264/AVC 硬體編碼` = 啟用，以及 `針對所有遠端桌面服務工作階段使用硬體圖形配接器` = 啟用
   （登錄：`AVCHardwareEncodePreferred = 1`、`bEnumerateHWBeforeSW = 1`）

要登入的帳號必須有密碼。用 Microsoft 帳號登入時，使用者名稱填 email，密碼填 Microsoft 帳號密碼（不是 PIN）。

### 確認 UDP 有在用

在電腦上按右鍵 →「顯示連線記錄」（`~/Library/Logs/MacRDP/<ID>.log`）。看到這行代表畫面走 UDP：

```
UDP multitransport tunnel ready
```

想自己量幀率，可以在 Windows 用瀏覽器全螢幕打開 [`tools/fps-test.html`](tools/fps-test.html)。

## 從原始碼建置

需求：macOS 14 以上、Apple Silicon、Xcode Command Line Tools（`xcode-select --install`，不需要完整 Xcode）、[Homebrew](https://brew.sh)。

```bash
git clone https://github.com/walush2023/MacRDP.git
cd MacRDP
scripts/build-freerdp.sh   # 編譯 FreeRDP（UDP + macOS 補丁），約 3–5 分鐘
scripts/build-app.sh       # 建置 build/MacRDP.app，FreeRDP 包在裡面
open build/MacRDP.app
```

- `build-app.sh` 會先跑 `MacRDP --self-test`（參數組合與 `.rdp` 的檢查），並把 FreeRDP 需要的 Homebrew 函式庫（ffmpeg、SDL3、OpenSSL 等，約 46 個）複製進 App（[`scripts/bundle-dylibs.sh`](scripts/bundle-dylibs.sh)）。只有建置需要 Homebrew。
- 會用鑰匙圈裡的 Developer ID 或 Apple Development 憑證簽章（可用 `SIGN_IDENTITY=<憑證>` 指定）。簽章固定，鑰匙圈才會一直信任 MacRDP；用臨時簽章的話，每次重新建置後 macOS 都會再問一次鑰匙圈密碼。

**為什麼要本機轉送？** macOS 的區域網路權限是依執行檔判斷的，自己編譯的 `sdl-freerdp` 不會跳出詢問，而是直接被擋（錯誤是 `Couldn't get socket ip address`）。所以 FreeRDP 連到 `127.0.0.1`，再由 MacRDP 把 TCP 和 UDP 轉送到真正的主機。可以在「設定」關閉；經過 RD Gateway 的連線不使用轉送。

### 發佈（簽章、公證、DMG）

```bash
scripts/release.sh
```

產生 `build/MacRDP-<版本>.dmg`：用 Developer ID 簽章並開啟 hardened runtime，送 Apple 公證後把結果附加到 DMG。需要「Developer ID Application」憑證，並先存一次公證帳號（App 專用密碼在 [account.apple.com](https://account.apple.com) →「登入與安全性」建立）：

```bash
xcrun notarytool store-credentials macrdp-notary --apple-id <Apple ID> --team-id <Team ID> --password <App 專用密碼>
```

`SKIP_NOTARIZE=1` 只簽章、不公證；`NOTARY_PROFILE=<名稱>` 使用其他已存的帳號設定。版本號在 `VERSION` 檔。

## 專案結構

```
Sources/MacRDP/
  MacRDPApp.swift               App 進入點、選單、開啟 .rdp 檔
  Model/                        Connection（所有設定）、ConnectionStore（JSON）、Keychain、RDPFile
  Session/FreeRDPCommand.swift  設定 → FreeRDP 參數
  Session/SessionManager.swift  啟動 / 追蹤 sdl-freerdp、連線檢查、錯誤提示
  Session/LocalRelay.swift      在 127.0.0.1 轉送 TCP + UDP
  Views/                        主視窗、電腦設定、密碼輸入
  SelfTest.swift                `--self-test` 檢查
Resources/                      App 圖示（AppIcon.icns，用 scripts/make-icon.swift 從 icon-source.png 產生）
patches/                        FreeRDP 補丁（原生全螢幕、不閃爍的啟動）
scripts/                        build-freerdp.sh、build-app.sh、bundle-dylibs.sh、release.sh、make-icon.swift
tools/                          windows-setup.ps1、fps-test.html
```

設定存在 `~/Library/Application Support/MacRDP/connections.json`，密碼存在鑰匙圈（服務名稱 `MacRDP`）。

## 授權

Apache License 2.0，與 FreeRDP 相同。見 [LICENSE](LICENSE)。
