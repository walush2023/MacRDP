# MacRDP

macOS 原生的遠端桌面（RDP）用戶端，參考 Microsoft「Windows App」的介面與設定，額外開放 **UDP 傳輸**、**H.264 AVC444** 與**不限幀率**，在區域網路上可以跑到 60 fps 以上。

連線核心是 [FreeRDP 3](https://github.com/FreeRDP/FreeRDP)，以開啟 UDP（MS-RDPEUDP）的方式自行編譯，並加上「macOS 原生全螢幕」補丁。

> A native macOS Remote Desktop client modelled on Microsoft's Windows App, with saved connections, every per-PC setting, UDP transport, H.264 AVC444 and uncapped frame rate. Built on a patched FreeRDP 3. UI is in Traditional Chinese.

## 功能

- **儲存多組連線**：格狀或清單檢視、群組、搜尋、「最近使用」、複製、刪除
- **每台電腦的設定**（對應 Windows App 的「新增電腦」對話框）

| 分頁 | 設定 |
|---|---|
| 一般 | 主機 / IP、埠號、易記名稱、群組、使用者名稱、網域、密碼（存在鑰匙圈）、自動重新連線、系統管理工作階段 |
| 顯示 | 解析度（與顯示器相同 / 與視窗相同 / 常用解析度 / 自訂）、視窗大小改變時更新解析度、顯示比例、全螢幕、使用所有顯示器、符合視窗大小（縮放）、色彩品質 |
| 裝置與音訊 | 剪貼簿（文字與圖片、檔案，可分別設為雙向 / 只到遠端 / 只到 Mac / 關閉）、印表機、智慧卡、麥克風、聲音播放位置 |
| 資料夾 | 重新導向任意資料夾、分享家目錄 |
| 效能 | UDP 優先或只用 TCP、影像編碼（AVC444 / AVC420 / RemoteFX…）、不限幀率、網路類型、桌布 / 佈景主題 / ClearType / 動畫等視覺效果 |
| 閘道 | RD Gateway：主機、埠號、獨立帳號密碼、區域網路略過閘道 |
| 進階 | 憑證政策、安全性通訊協定（NLA / TLS / RDP）、RemoteApp、替代殼層、負載平衡資訊、鍵盤配置、任意 FreeRDP 參數 |

- **macOS 原生全螢幕**：每個工作階段有自己的 Space，可以用四指滑動或 `Control-←/→` 在多個全螢幕視窗間切換；`Control-Option-Return` 切換全螢幕
- **匯入 / 匯出 `.rdp` 檔**，也可以在 Finder 直接打開 `.rdp`
- 密碼只存在 macOS 鑰匙圈，經由 stdin 傳給 FreeRDP，不會出現在設定檔或 `ps` 裡
- 指令列：`MacRDP.app/Contents/MacOS/MacRDP --connect "名稱或 IP"` 直接連線（可接 Shortcuts、Alfred、Raycast）

## 需求

- macOS 14 以上、Apple Silicon
- Xcode Command Line Tools（`xcode-select --install`），不需要完整 Xcode
- [Homebrew](https://brew.sh)

## 建置

```bash
git clone https://github.com/<you>/MacRDP.git
cd MacRDP
scripts/build-freerdp.sh   # 編譯 FreeRDP（UDP + 原生全螢幕補丁），約 3–5 分鐘
scripts/build-app.sh       # 編譯 App 並把 FreeRDP 打包進去
open build/MacRDP.app
```

`build-app.sh` 會自動用鑰匙圈裡的 Developer ID 或 Apple Development 憑證簽章（也可以用 `SIGN_IDENTITY=<憑證>` 指定）。簽章身分固定，鑰匙圈才會記得「MacRDP 可以讀密碼」；如果找不到憑證就用臨時簽章，每次重新建置後 macOS 都會再問一次鑰匙圈密碼。

`build-app.sh` 會先跑 `MacRDP --self-test`（指令組合與 `.rdp` 解析的檢查）。

FreeRDP 的動態函式庫仍然連結到 Homebrew 的 `ffmpeg`、`sdl3`、`openssl@4` 等，所以執行的電腦也需要用 Homebrew 裝好這些套件（`build-freerdp.sh` 會自動安裝）。

第一次連線時，macOS 會詢問是否允許 MacRDP 存取區域網路，請按「允許」。如果按了拒絕，到「系統設定 → 隱私權與安全性 → 區域網路」把 MacRDP 打開。

> **為什麼要轉送**：macOS 的區域網路權限是依執行檔判斷的，自己編譯的 `sdl-freerdp` 不會跳出詢問，而是直接被擋（錯誤是 `Couldn't get socket ip address`）。所以 MacRDP 預設讓 FreeRDP 連到 `127.0.0.1`，再由 MacRDP 把 TCP 和 UDP 轉送到真正的主機。實測轉送後仍有約 72 fps（直連 75 fps）。可以在「設定」關閉轉送；使用 RD Gateway 時不轉送。

## Windows 端設定

Mac 端預設就會用 UDP、AVC444、不限幀率，但 **Windows 預設會把幀率鎖在 30 fps，也不一定用 H.264**，必須在被連線的 Windows 上調整。

### 一鍵設定

在 Windows 上用**系統管理員**身分開 PowerShell，執行 [`tools/windows-setup.ps1`](tools/windows-setup.ps1)：

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\windows-setup.ps1          # 套用
.\windows-setup.ps1 -Undo    # 還原效能設定
```

執行後**登出 Windows（或重新開機）**，下一次連線才會生效。

### 手動設定（腳本做的事）

1. **開啟遠端桌面**：設定 → 系統 → 遠端桌面 → 開啟。需要 Windows 專業版、企業版或教育版，家用版不能當 RDP 主機。
2. **防火牆**：允許 **TCP 3389** 和 **UDP 3389** 輸入。如果 Windows 在路由器、Docker 或 VM 後面，**UDP 3389 也要轉送**，否則只會走 TCP。
3. **啟用 UDP**：群組原則 `電腦設定 → 系統管理範本 → Windows 元件 → 遠端桌面服務 → 遠端桌面工作階段主機 → 連線 → 選取 RDP 傳輸通訊協定` = **使用 UDP 和 TCP**
   （登錄：`HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services\SelectTransport = 0`）
4. **解除 30 fps 上限**：
   `HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\DWMFRAMEINTERVAL`（DWORD）= **15**
5. **優先使用 H.264/AVC 4:4:4**：群組原則 `…遠端桌面工作階段主機 → 遠端工作階段環境 → 為遠端桌面連線排定 H.264/AVC 444 圖形模式的優先順序` = 啟用
   （登錄：`…\Terminal Services\AVC444ModePreferred = 1`）
6. **使用 GPU 硬體編碼**（有獨立顯示卡時）：`…遠端工作階段環境 → 設定遠端桌面連線的 H.264/AVC 硬體編碼` = 啟用，以及 `針對所有遠端桌面服務工作階段使用硬體圖形配接器` = 啟用
   （登錄：`AVCHardwareEncodePreferred = 1`、`bEnumerateHWBeforeSW = 1`）
7. **帳號**：要登入的帳號必須有密碼。用 Microsoft 帳號登入 Windows 時，使用者名稱填 email，密碼填 Microsoft 帳號密碼（不是 PIN）。

### 確認 UDP 有在用

MacRDP 的連線記錄在 `~/Library/Logs/MacRDP/<連線 ID>.log`（在連線上按右鍵 →「顯示連線記錄」）。看到下面這行就代表畫面走 UDP：

```
UDP multitransport tunnel ready
```

## 實測

1920×1080，Windows 11（QEMU 虛擬機、無 GPU）全螢幕播放動畫，Mac mini 有線區域網路：

| 設定 | 平均 fps | 編碼 |
|---|---|---|
| Windows 預設 | 32 | ClearCodec |
| 套用 Windows 端設定，TCP | 78 | AVC444 |
| 套用 Windows 端設定，UDP | 75 | AVC444 |

在延遲低於 1 ms 的區域網路，UDP 和 TCP 差不多；UDP 的好處在延遲較高或會掉封包的網路（Wi-Fi、從外面連回家）。

用 [`tools/fps-test.html`](tools/fps-test.html) 可以自己測：在 Windows 上用瀏覽器全螢幕打開它，再看連線記錄的幀數。

## 專案結構

```
Sources/MacRDP/
  MacRDPApp.swift            App 進入點、選單、.rdp 檔開啟
  Model/                     Connection（所有設定）、ConnectionStore（JSON）、Keychain、RDPFile（.rdp 匯入匯出）
  Session/FreeRDPCommand.swift  設定 → FreeRDP 參數
  Session/SessionManager.swift  啟動 / 追蹤 sdl-freerdp、區域網路檢查、錯誤提示
  Session/LocalRelay.swift   在 127.0.0.1 轉送 TCP + UDP（避開 macOS 區域網路權限問題）
  Views/                     主視窗、連線設定、密碼輸入
  SelfTest.swift             `--self-test` 檢查
Resources/                   App 圖示（AppIcon.icns，用 scripts/make-icon.swift 從 icon-source.png 產生）
patches/                     FreeRDP 補丁（原生全螢幕）
scripts/                     build-freerdp.sh、build-app.sh、make-icon.swift
tools/                       windows-setup.ps1、fps-test.html
```

設定存在 `~/Library/Application Support/MacRDP/connections.json`，密碼存在鑰匙圈（服務名稱 `MacRDP`）。

## 尚未支援

- Azure Virtual Desktop / Windows 365 的「工作區」訂閱（需要 Microsoft 帳號登入流程）
- 攝影機重新導向、交換滑鼠左右鍵（FreeRDP 在 macOS 上沒有對應功能）
- 把 FreeRDP 的 Homebrew 相依套件完整打包進 App（目前需要 Homebrew）

## 授權

Apache License 2.0，與 FreeRDP 相同。見 [LICENSE](LICENSE)。
