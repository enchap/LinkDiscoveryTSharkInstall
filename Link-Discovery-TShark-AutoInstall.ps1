# =============================================
#  Link-Discovery-TShark.ps1
#  High-Precision Link Discovery (TShark/Npcap)
# =============================================

# 1. Check for Administrator privileges
if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Warning "This script requires Administrator privileges to access the Npcap driver."
    Start-Sleep -Seconds 3
    Exit
}

# 2. TShark.exe Path Variable
$tsharkPaths = @(
    "${env:ProgramFiles}\Wireshark\tshark.exe",
    "${env:ProgramFiles(x86)}\Wireshark\tshark.exe"
)
$tsharkBinary = $tsharkPaths | Where-Object { Test-Path $_ } | Select-Object -First 1

if (!$tsharkBinary) {
    Clear-Host
    Write-Host "`n==================================================" -ForegroundColor Cyan
    Write-Host "`n           Wireshark (TShark) Not Found" -ForegroundColor Cyan
    Write-Host "`n Initiating automatic download and installation..." -ForegroundColor Yellow
    Write-Host "`n=================================================="

    # Define Download Variables
    # Note: We link to a specific stable version to ensure the link doesn't break.
    $wsURL = "https://2.na.dl.wireshark.org/win64/Wireshark-4.6.2-x64.exe"
    $npcapURL = "https://npcap.com/dist/npcap-1.85.exe"
    $wsInstallerPath = "$env:TEMP\Wireshark-Installer.exe"
    $npcapInstallerPath = "$env:TEMP\Npcap-Installer.exe"

    # Download Npcap
    try {
        Write-Host "`nDownloading Npcap" -ForegroundColor White
        Invoke-WebRequest -Uri $npcapURL -OutFile $npcapInstallerPath -ErrorAction Stop
        Write-Host "`nDownload complete." -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to download Npcap."
        Start-Sleep -Seconds 10
        Exit
    }

    # Download Wireshark
    try {
        Write-Host "`nDownloading Wireshark" -ForegroundColor White
        Invoke-WebRequest -Uri $wsURL -OutFile $wsInstallerPath -ErrorAction Stop
        Write-Host "`nDownload complete." -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to download Wireshark."
        Start-Sleep -Seconds 10
        Exit
    }

    # Install Npcap
    Write-Host "`nInstalling Npcap and Wireshark..." -ForegroundColor White

    $npcapInstallProcess = Start-Process -FilePath $npcapInstallerPath -Wait

    if ($npcapInstallProcess.ExitCode -eq 0) {
        Write-Host "   Npcap installation finished." -ForegroundColor Green
    }
    else {
        Write-Warning "   Installation exited with code $($npcapInstallProcess.ExitCode). It may still have worked."
    }
    
    # Install Wireshark
    $wsInstallProcess = Start-Process -FilePath $wsInstallerPath -ArgumentList "/S /desktopicon=yes" -PassThru -Wait

    if ($wsInstallProcess.ExitCode -eq 0) {
        Write-Host "   Wireshark installation finished." -ForegroundColor Green
    }
    else {
        Write-Warning "   Installation exited with code $($wsInstallProcess.ExitCode). It may still have worked."
    }

    # Refresh Environment Variables (so we can find the new exe without rebooting)
    foreach($level in "Machine","User") {
       [Environment]::GetEnvironmentVariables($level).GetEnumerator() | % {
          Set-Item -Path "env:$($_.Name)" -Value $_.Value
       }
    }

    # Re-Locate TShark
    $tsharkBinary = "${env:ProgramFiles}\Wireshark\tshark.exe"
    if (-not (Test-Path $tsharkBinary)) {
        Write-Error "Could not locate TShark.exe after installation. You may need to restart the script."
        Start-Sleep -Seconds 10
        Exit
    }
}

# 3. User input adapter selection
Clear-Host
Write-Host "`n============================================" -ForegroundColor Cyan
Write-Host "`n   Select Network Adapter for Capture" -ForegroundColor Cyan
Write-Host "`n============================================" -ForegroundColor Cyan

$interfaces = & $tsharkBinary -D

if (!$interfaces) {
    Write-Error "TShark could not find any interfaces. Ensure Npcap is installed."
    Start-Sleep -Seconds 5
    Exit
}

# Display adapters
foreach ($iface in $interfaces) {
    Write-Host $iface -ForegroundColor White
}

Write-Host "`n--------------------------------------------" -ForegroundColor Gray

# Prompt the user for input
$validInput = $false
while (-not $validInput) {
    $targetIndex = Read-Host "Enter the number of the adapter to use (e.g. 1)"
    
    # Basic validation to ensure proper number input
    if ($targetIndex -match "^\d+$") {
        $validInput = $true
    } else {
        Write-Warning "Invalid input. Please enter a number."
    }
}

# 4. Start Capture
$htmlFile = "$env:USERPROFILE\Desktop\Link-Discovery-Report.html"
Write-Host "`nStarting 60s capture on Interface #$targetIndex..." -ForegroundColor Yellow

# Add Augments to the execution
$tsharkArgs = @(
    "-i", $targetIndex,
    "-a", "duration:60",
    "-Y", "lldp || cdp",
    "-T", "fields",
    "-E", "separator=|",
    "-e", "lldp.tlv.system.name", 
    "-e", "lldp.port.id", 
    "-e", "lldp.port.desc", 
    "-e", "lldp.chassis.id.mac",
    "-e", "cdp.deviceid", 
    "-e", "cdp.portid", 
    "-e", "cdp.platform",
    "-e", "cdp.address"
)

# Run TShark
$captureData = & $tsharkBinary $tsharkArgs 2>$null

# 6. Parse Results
$resultsHTML = ""
$packetCount = 0

if ($captureData) {
    foreach ($line in $captureData) {
        # Split the pipe-separated values
        $fields = $line -split "\|"
        
        # Map fields to variables for readability
        $lldpName = $fields[0]
        $lldpPort = $fields[1]
        $lldpDesc = $fields[2]
        $lldpMac  = $fields[3]
        $cdpName  = $fields[4]
        $cdpPort  = $fields[5]
        $cdpPlat  = $fields[6]
        $cdpIP    = $fields[7]

        # Construct a HTML block for this packet
        $resultsHTML += "<div class='packet-block'>"
        
        if ($lldpName -or $lldpPort) {
            $resultsHTML += "<h3>LLDP Packet Detected</h3>"
            $resultsHTML += "<b>Switch Name:</b> $lldpName<br>"
            $resultsHTML += "<b>Port ID:</b> $lldpPort<br>"
            $resultsHTML += "<b>Description:</b> $lldpDesc<br>"
            $resultsHTML += "<b>Chassis MAC:</b> $lldpMac<br>"
        }
        
        if ($cdpName -or $cdpPort) {
            $resultsHTML += "<h3>CDP Packet Detected</h3>"
            $resultsHTML += "<b>Device ID:</b> $cdpName<br>"
            $resultsHTML += "<b>Port ID:</b> $cdpPort<br>"
            $resultsHTML += "<b>Platform:</b> $cdpPlat<br>"
            $resultsHTML += "<b>Mgmt IP:</b> $cdpIP<br>"
        }
        $resultsHTML += "</div><hr>"
    }
}
else {
    $resultsHTML = "<span class='no-data'>
        Time out reached (60s).<br>
        No LLDP or CDP packets received.<br>
        Verify the interface selected is correct and the cable is secure.
    </span>"
}

# 7. Generate HTML Report
$computerName = $env:COMPUTERNAME
$dateGen = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

$htmlContent = @"
<!DOCTYPE html>
<html>
<head>
    <title>Npcap Link Report</title>
    <style>
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background-color: #f2f2f2; color: #333; margin: 0; padding: 40px; }
        .container { background-color: #fff; max-width: 800px; margin: 0 auto; padding: 40px; box-shadow: 0 4px 10px rgba(0,0,0,0.1); }
        h1 { font-weight: 300; margin-bottom: 5px; color: #0078d7; }
        .subtitle { font-size: 14px; color: #666; margin-bottom: 30px; display: block;}
        .packet-block { background-color: #e6f7ff; border-left: 5px solid #0078d7; padding: 15px; margin-bottom: 15px; }
        .no-data { color: #d90000; font-weight: bold; }
        hr { border: 0; border-top: 1px solid #eee; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Link Discovery (Npcap Engine)</h1>
        <span class="subtitle">Generated by TShark</span>
        
        <div class="info-grid">
            <div class="label">Computer Name: $computerName</div>
            <div class="label">Report Time: $dateGen</div>
            <div class="label">Network Interface: $targetIndex</div>
        </div>

        <h2>Captured Packet Data</h2>
        $resultsHTML
        
    </div>
</body>
</html>
"@

# 8. Save and Open
Write-Host "`nDisplaying results in browser." -ForegroundColor Green
$htmlContent | Out-File -FilePath $htmlFile -Encoding utf8
Invoke-Item $htmlFile