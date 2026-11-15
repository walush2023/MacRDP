# MacRDP - Windows host setup
# Run in an elevated PowerShell on the Windows PC you connect to:
#   Set-ExecutionPolicy -Scope Process Bypass; .\windows-setup.ps1
# Then sign out of Windows (or reboot) so new sessions pick up the changes.
# Undo everything with:  .\windows-setup.ps1 -Undo

param([switch]$Undo)

$ErrorActionPreference = 'Stop'
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Please run this script as Administrator.'
}

$ts     = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server'
$ws     = "$ts\WinStations"
$policy = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services'

$values = @(
    # path,    name,                         value  # what it does
    @($ts,     'fDenyTSConnections',          0),    # 1. allow Remote Desktop connections
    @($ws,     'DWMFRAMEINTERVAL',            15),   # 2. lift the 30 fps cap (15 => up to 60+ fps)
    @($policy, 'SelectTransport',             0),    # 3. use both UDP and TCP
    @($policy, 'AVC444ModePreferred',         1),    # 4. prefer H.264/AVC 4:4:4
    @($policy, 'AVCHardwareEncodePreferred',  1),    # 5. use the GPU encoder when there is one
    @($policy, 'bEnumerateHWBeforeSW',        1)     # 6. use the hardware GPU for RDP sessions
)

if ($Undo) {
    foreach ($v in $values | Select-Object -Skip 1) {
        Remove-ItemProperty -Path $v[0] -Name $v[1] -ErrorAction SilentlyContinue
    }
    Write-Host 'Performance tweaks removed (Remote Desktop itself left enabled).'
    return
}

New-Item -Path $policy -Force | Out-Null
foreach ($v in $values) {
    Set-ItemProperty -Path $v[0] -Name $v[1] -Value $v[2] -Type DWord
    Write-Host ("{0,-28} = {1}" -f $v[1], $v[2])
}

# Firewall: RDP over TCP and UDP 3389
Enable-NetFirewallRule -DisplayGroup 'Remote Desktop' -ErrorAction SilentlyContinue
foreach ($proto in 'TCP', 'UDP') {
    if (-not (Get-NetFirewallRule -DisplayName "MacRDP RDP $proto" -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -DisplayName "MacRDP RDP $proto" -Direction Inbound -Protocol $proto `
            -LocalPort 3389 -Action Allow | Out-Null
    }
}
Write-Host 'Firewall: TCP and UDP 3389 allowed.'
Write-Host 'Done. Sign out of Windows (or reboot) before connecting again.'
