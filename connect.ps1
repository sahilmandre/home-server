# One-time link from this Windows PC to the Ubuntu server, the way a cloud VPS is set up:
#   - a dedicated SSH key (C:\Users\<you>\.ssh\id_ed25519_homeserver) copied to the server
#   - password-free sudo for your Ubuntu user (cloud VPS images do the same; sign-in is key-only)
#   - an SSH shortcut so that `ssh homeserver` just works
#
# Run it in your own terminal (it asks for your Ubuntu password twice - once to copy the key,
# once for sudo):
#   powershell -ExecutionPolicy Bypass -File .\connect.ps1
#   powershell -ExecutionPolicy Bypass -File .\connect.ps1 -HostAddress 192.168.1.42 -User sahil
param(
  [string]$HostAddress,
  [string]$User,
  [string]$Alias = "homeserver"
)
$ErrorActionPreference = "Stop"

function Step($text) { Write-Host "`n==> $text" -ForegroundColor Cyan }
function Fail($text) { Write-Host $text -ForegroundColor Red; exit 1 }

if (-not (Get-Command ssh -ErrorAction SilentlyContinue)) {
  Fail "The OpenSSH client isn't installed. Settings -> System -> Optional features -> add 'OpenSSH Client'."
}
if (-not $HostAddress) { $HostAddress = (Read-Host "Server IP address (run 'hostname -I' on the laptop)").Trim() }
if (-not $User) { $User = (Read-Host "Your username on the server (run 'whoami' on the laptop)").Trim() }
if ($User -notmatch '^[a-z_][a-z0-9_.-]*$') { Fail "'$User' doesn't look like a Linux username." }
if ($HostAddress -notmatch '^[A-Za-z0-9.:-]+$') { Fail "'$HostAddress' doesn't look like an IP address or host name." }

$sshDir = Join-Path $env:USERPROFILE ".ssh"
$key = Join-Path $sshDir "id_ed25519_$Alias"
$target = "$User@$HostAddress"
New-Item -ItemType Directory -Force -Path $sshDir | Out-Null

Step "SSH key"
if (Test-Path $key) {
  Write-Host "Using the existing key $key"
} else {
  # cmd passes the empty passphrase reliably on both Windows PowerShell 5.1 and PowerShell 7.
  cmd /c "ssh-keygen -q -t ed25519 -N `"`" -C `"$env:USERNAME@$env:COMPUTERNAME to $Alias`" -f `"$key`""
  if ($LASTEXITCODE -ne 0) { Fail "ssh-keygen failed." }
  Write-Host "Created $key"
}
$publicKey = (Get-Content "$key.pub" -Raw).Trim()

Step "Copying the key to $target (enter your Ubuntu password)"
$install = "umask 077; mkdir -p ~/.ssh; touch ~/.ssh/authorized_keys; grep -qxF '$publicKey' ~/.ssh/authorized_keys || echo '$publicKey' >> ~/.ssh/authorized_keys"
# Offering only this key means a re-run works once the server is key-only, and other keys in
# ~/.ssh can't use up the server's sign-in attempts before the password prompt.
ssh -i $key -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new $target $install
if ($LASTEXITCODE -ne 0) {
  Write-Host "Couldn't sign in to $target." -ForegroundColor Red
  Write-Host "If the server already accepts keys only (it was set up from another PC), run this on that PC, then run this script here again:"
  Write-Host "  echo '$publicKey' | ssh $Alias `"tr -d '\r' >> ~/.ssh/authorized_keys`""
  Write-Host "Otherwise: is SSH running on the laptop, and are both on the same network?"
  exit 1
}

Step "Password-free sudo for $User (enter your Ubuntu password once more)"
$sudoers = "/etc/sudoers.d/90-$User-nopasswd"
$grant = "echo '$User ALL=(ALL) NOPASSWD:ALL' | sudo tee $sudoers >/dev/null && sudo chmod 440 $sudoers && sudo visudo -cf $sudoers >/dev/null && echo sudo-ok"
ssh -t -i $key -o IdentitiesOnly=yes $target $grant
if ($LASTEXITCODE -ne 0) { Fail "Setting up sudo failed." }

Step "SSH shortcut '$Alias'"
$configPath = Join-Path $sshDir "config"
$existing = if (Test-Path $configPath) { Get-Content $configPath -Raw } else { "" }
if ($existing -match "(?m)^\s*Host\s+$([regex]::Escape($Alias))\s*$") {
  Write-Host "There's already a 'Host $Alias' entry in $configPath - leaving it as it is."
} else {
  $entry = @"

Host $Alias
  HostName $HostAddress
  User $User
  IdentityFile ~/.ssh/id_ed25519_$Alias
  IdentitiesOnly yes
  ServerAliveInterval 30
  ServerAliveCountMax 4
"@
  # OpenSSH for Windows rejects a config file that starts with a byte-order mark.
  [IO.File]::AppendAllText($configPath, $entry, (New-Object Text.UTF8Encoding($false)))
  Write-Host "Added 'Host $Alias' to $configPath"
}

Step "Checking"
$check = ssh -o BatchMode=yes $Alias "sudo -n true && echo ok"
if ($check -ne "ok") { Fail "The key works for sign-in but password-free sudo doesn't - run this script again." }
Write-Host "Connected. 'ssh $Alias' signs in without a password and sudo works." -ForegroundColor Green
