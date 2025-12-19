# =============================================
#  Link-Discovery-TShark-AutoInstall.ps1
#  High-Precision Link Discovery (TShark/Npcap)
# =============================================

# =============================================
# 1. PRE-FLIGHT CHECKLIST
# =============================================

# Check Administrator privileges
if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Warning "Administrator privileges required for Npcap driver access."
    Start-Sleep -Seconds 2
    Exit
}

# Define TShark Paths
$tsharkPaths = @(
    "${env:ProgramFiles}\Wireshark\tshark.exe",
    "${env:ProgramFiles(x86)}\Wireshark\tshark.exe"
)
$global:tsharkBinary = $tsharkPaths | Where-Object { Test-Path $_ } | Select-Object -First 1

# Auto-Install Logic (Console Mode before GUI)
if (!$global:tsharkBinary) {
    Clear-Host
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host "           Wireshark (TShark) Not Found" -ForegroundColor Cyan
    Write-Host " Initiating automatic download and installation..." -ForegroundColor Yellow
    Write-Host "=================================================="

    $wsURL = "https://2.na.dl.wireshark.org/win64/Wireshark-4.6.2-x64.exe"
    $npcapURL = "https://npcap.com/dist/npcap-1.85.exe"
    $wsInstallerPath = "$env:TEMP\Wireshark-Installer.exe"
    $npcapInstallerPath = "$env:TEMP\Npcap-Installer.exe"

    try {
        Write-Host "Downloading Npcap..." -ForegroundColor White
        Invoke-WebRequest -Uri $npcapURL -OutFile $npcapInstallerPath -ErrorAction Stop
        Write-Host "Downloading Wireshark..." -ForegroundColor White
        Invoke-WebRequest -Uri $wsURL -OutFile $wsInstallerPath -ErrorAction Stop
    }
    catch {
        Write-Error "Download failed. Check internet connection."
        Start-Sleep -Seconds 5
        Exit
    }

    Write-Host "Installing Npcap..." -ForegroundColor White
    Start-Process -FilePath $npcapInstallerPath -Wait
    
    Write-Host "Installing Wireshark..." -ForegroundColor White
    Start-Process -FilePath $wsInstallerPath -ArgumentList "/S /desktopicon=yes" -PassThru -Wait

    # Refresh Env
    foreach($level in "Machine","User") {
       [Environment]::GetEnvironmentVariables($level).GetEnumerator() | % { Set-Item -Path "env:$($_.Name)" -Value $_.Value }
    }
    
    $global:tsharkBinary = "${env:ProgramFiles}\Wireshark\tshark.exe"
    if (-not (Test-Path $global:tsharkBinary)) {
        Write-Error "Installation failed or path not found. Please restart script."
        Exit
    }
}

# =============================================
# 2. GUI SETUP
# =============================================

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Create Main Form
$form = New-Object System.Windows.Forms.Form
$form.Text = " LDTShark by enchap"
$form.Size = New-Object System.Drawing.Size(700, 600)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false

# Fonts
$fontHeader = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$fontNormal = New-Object System.Drawing.Font("Segoe UI", 9)
$fontMono   = New-Object System.Drawing.Font("Consolas", 9)

# Label: Select Adapter
$lblAdapter = New-Object System.Windows.Forms.Label
$lblAdapter.Text = "Select Network Adapter:"
$lblAdapter.Location = New-Object System.Drawing.Point(20, 20)
$lblAdapter.Size = New-Object System.Drawing.Size(200, 20)
$lblAdapter.Font = $fontHeader
$form.Controls.Add($lblAdapter)

# ComboBox: Adapter List
$comboAdapters = New-Object System.Windows.Forms.ComboBox
$comboAdapters.Location = New-Object System.Drawing.Point(20, 45)
$comboAdapters.Size = New-Object System.Drawing.Size(640, 25)
$comboAdapters.DropDownStyle = "DropDownList"
$comboAdapters.Font = $fontNormal
$form.Controls.Add($comboAdapters)

# Button: Scan LLDP/CDP
$btnScanLink = New-Object System.Windows.Forms.Button
$btnScanLink.Text = "Network Device"
$btnScanLink.Location = New-Object System.Drawing.Point(20, 80)
$btnScanLink.Size = New-Object System.Drawing.Size(200, 35)
$btnScanLink.BackColor = "#0078d7"
$btnScanLink.ForeColor = "White"
$btnScanLink.FlatStyle = "Flat"
$btnScanLink.Font = $fontHeader
$form.Controls.Add($btnScanLink)

# Button: Get ARP Table
$btnArp = New-Object System.Windows.Forms.Button
$btnArp.Text = "Local Hosts"
$btnArp.Location = New-Object System.Drawing.Point(230, 80)
$btnArp.Size = New-Object System.Drawing.Size(200, 35)
$btnArp.BackColor = "#28a745"
$btnArp.ForeColor = "White"
$btnArp.FlatStyle = "Flat"
$btnArp.Font = $fontHeader
$form.Controls.Add($btnArp)

# Status Label
$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Text = "Ready"
$lblStatus.Location = New-Object System.Drawing.Point(440, 90)
$lblStatus.Size = New-Object System.Drawing.Size(220, 20)
$lblStatus.ForeColor = "Gray"
$lblStatus.Font = $fontNormal
$form.Controls.Add($lblStatus)

# RichTextBox: Output
$txtOutput = New-Object System.Windows.Forms.RichTextBox
$txtOutput.Location = New-Object System.Drawing.Point(20, 130)
$txtOutput.Size = New-Object System.Drawing.Size(640, 400)
$txtOutput.Font = $fontMono
$txtOutput.ReadOnly = $true
$txtOutput.BackColor = "#f5f5f5"
$txtOutput.ScrollBars = "Vertical"
$form.Controls.Add($txtOutput)

# Timer for Background Job Check
$timerJob = New-Object System.Windows.Forms.Timer
$timerJob.Interval = 1000 # Check every 1 second

# =============================================
# 3. HELPER FUNCTIONS & LOGIC
# =============================================

# Populate Adapters
function Load-Adapters {
    $lblStatus.Text = "Loading adapters..."
    $form.Refresh()
    
    try {
        $rawAdapters = & $global:tsharkBinary -D
        $comboAdapters.Items.Clear()
        if ($rawAdapters) {
            foreach ($line in $rawAdapters) {
                [void]$comboAdapters.Items.Add($line)
            }
            $comboAdapters.SelectedIndex = 0
        } else {
            [void]$comboAdapters.Items.Add("No adapters found. Check Npcap.")
        }
    } catch {
        [void]$comboAdapters.Items.Add("Error running TShark.")
    }
    $lblStatus.Text = "Ready"
}

# Initial Load
Load-Adapters

# =============================================
# 4. EVENT HANDLERS
# =============================================

# ACTION: GET ARP TABLE
$btnArp.Add_Click({
    $txtOutput.Clear()
    $lblStatus.Text = "Fetching ARP table..."
    $form.Refresh()

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("=== HOST DISCOVERY (ARP TABLE) ===")
    [void]$sb.AppendLine("Time: $(Get-Date -Format 'hh:mm:ss:tt')")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine(("{0,-20} {1,-20} {2,-15}" -f "IP Address", "MAC Address", "State"))
    [void]$sb.AppendLine(("{0,-20} {1,-20} {2,-15}" -f "----------", "-----------", "-----"))

    # Try modern Get-NetNeighbor
    if (Get-Command Get-NetNeighbor -ErrorAction SilentlyContinue) {
        $neighbors = Get-NetNeighbor -AddressFamily IPv4 | Sort-Object IPAddress
        foreach ($n in $neighbors) {
            if ($n.State -ne "Unreachable") {
                [void]$sb.AppendLine(("{0,-20} {1,-20} {2,-15}" -f $n.IPAddress, $n.LinkLayerAddress, $n.State))
            }
        }
    } 
    # Fallback to legacy arp -a
    else {
        $arpOutput = arp -a
        [void]$sb.AppendLine($arpOutput -join "`n")
    }

    $txtOutput.Text = $sb.ToString()
    $lblStatus.Text = "ARP Table Loaded."
})

# ACTION: START LINK SCAN (LLDP/CDP)
$btnScanLink.Add_Click({
    if ($comboAdapters.SelectedItem -eq $null) {
        [System.Windows.Forms.MessageBox]::Show("Please select an adapter first.", "Error", "OK", "Error")
        return
    }

    # Lock UI
    $btnScanLink.Enabled = $false
    $btnArp.Enabled = $false
    $comboAdapters.Enabled = $false
    $txtOutput.Clear()
    $txtOutput.Text = "Listening for LLDP/CDP packets.`nThis will take 60 seconds.`n`nPlease wait..."
    $lblStatus.Text = "Scanning (Time remaining: 60s)..."

    # Extract Index from Selection (e.g. "1. \Device\...")
    $selectedIndex = $comboAdapters.SelectedItem.ToString().Split(".")[0]

    # ScriptBlock for Background Job
    $jobScript = {
        param($bin, $idx)
        $args = @(
            "-i", $idx,
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
        return & $bin $args 2>$null
    }

    # Start Job
    $global:scanJob = Start-Job -ScriptBlock $jobScript -ArgumentList $global:tsharkBinary, $selectedIndex
    $timerJob.Start()
})

# TIMER TICK: CHECK JOB STATUS
$timerJob.Add_Tick({
    if ($global:scanJob.State -eq 'Completed' -or $global:scanJob.State -eq 'Failed') {
        $timerJob.Stop()
        
        # Unlock UI
        $btnScanLink.Enabled = $true
        $btnArp.Enabled = $true
        $comboAdapters.Enabled = $true
        $lblStatus.Text = "Scan Complete."

        # Process Results
        $results = Receive-Job -Job $global:scanJob
        Remove-Job -Job $global:scanJob
        
        $sb = New-Object System.Text.StringBuilder
        [void]$sb.AppendLine("=== LINK DISCOVERY RESULTS ===")
        [void]$sb.AppendLine("Time: $(Get-Date -Format 'hh:mm:ss:tt')")
        [void]$sb.AppendLine("")

        if ($results) {
            foreach ($line in $results) {
                if ([string]::IsNullOrWhiteSpace($line)) { continue }
                
                $fields = $line -split "\|"
                # Handle possible missing fields by padding array
                while ($fields.Count -lt 8) { $fields += "" }

                $lldpName = $fields[0]
                $lldpPort = $fields[1]
                $lldpDesc = $fields[2]
                $lldpMac  = $fields[3]
                $cdpName  = $fields[4]
                $cdpPort  = $fields[5]
                $cdpPlat  = $fields[6]
                $cdpIP    = $fields[7]

                if ($lldpName -or $lldpPort) {
                    [void]$sb.AppendLine(">>> LLDP PACKET DETECTED")
                    [void]$sb.AppendLine("    Switch Name : $lldpName")
                    [void]$sb.AppendLine("    Port ID     : $lldpPort")
                    [void]$sb.AppendLine("    Description : $lldpDesc")
                    [void]$sb.AppendLine("    Chassis MAC : $lldpMac")
                    [void]$sb.AppendLine("----------------------------------")
                }
                
                if ($cdpName -or $cdpPort) {
                    [void]$sb.AppendLine(">>> CDP PACKET DETECTED")
                    [void]$sb.AppendLine("    Device ID   : $cdpName")
                    [void]$sb.AppendLine("    Port ID     : $cdpPort")
                    [void]$sb.AppendLine("    Platform    : $cdpPlat")
                    [void]$sb.AppendLine("    Mgmt IP     : $cdpIP")
                    [void]$sb.AppendLine("----------------------------------")
                }
            }
        } else {
             [void]$sb.AppendLine("No LLDP or CDP packets received.")
             [void]$sb.AppendLine("Verify the interface selected is correct and the cable is secure.")
        }

        $txtOutput.Text = $sb.ToString()
    }
    else {
        # Optional: Update UI with simple animation or counter could go here
        $lblStatus.Text = "Scanning..."
    }
})

# =============================================
# 5. RUN GUI
# =============================================
[void]$form.ShowDialog()
