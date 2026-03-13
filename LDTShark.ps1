# ==============================================
#  Link-Discovery-TShark.ps1
#  High-Precision Link Discovery (TShark/Npcap)
# ==============================================

# ==============================================
# 1. PRE-FLIGHT CHECKLIST (Admin & Dependencies)
# ==============================================

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

# Auto-Install Npcap and Wireshark
if (!$global:tsharkBinary) {
    Clear-Host
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host "           Wireshark (TShark) Not Found" -ForegroundColor Cyan
    Write-Host " Initiating automatic download and installation..." -ForegroundColor Yellow
    Write-Host "=================================================="

    $wsURL = "https://2.na.dl.wireshark.org/win64/Wireshark-latest-x64.exe"
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
        Write-Host "Download failed. Check internet connection or verify Npcap & Wireshark links still exist.`n$npcapURL `n$wsURL" -ForegroundColor Red
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

# ==========================================
# 2. GUI SETUP
# ==========================================

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Create Main Form
$form = New-Object System.Windows.Forms.Form
$form.Text = " LDTShark by enchap"
$form.Size = New-Object System.Drawing.Size(700, 700)
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
$lblAdapter.Size = New-Object System.Drawing.Size(250, 20)
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
$btnScanLink.Location = New-Object System.Drawing.Point(20, 85)
$btnScanLink.Size = New-Object System.Drawing.Size(220, 35)
$btnScanLink.BackColor = "#0078d7"
$btnScanLink.ForeColor = "White"
$btnScanLink.FlatStyle = "Flat"
$btnScanLink.Font = $fontHeader
$form.Controls.Add($btnScanLink)

# Button: Get ARP Table
$btnArp = New-Object System.Windows.Forms.Button
$btnArp.Text = "Local Hosts"
$btnArp.Location = New-Object System.Drawing.Point(250, 85)
$btnArp.Size = New-Object System.Drawing.Size(220, 35)
$btnArp.BackColor = "#28a745"
$btnArp.ForeColor = "White"
$btnArp.FlatStyle = "Flat"
$btnArp.Font = $fontHeader
$form.Controls.Add($btnArp)

# Button: Scan Specific Subnet
$grpSubnet = New-Object System.Windows.Forms.GroupBox
$grpSubnet.Text = "Active Subnet Scan"
$grpSubnet.Location = New-Object System.Drawing.Point(20, 140)
$grpSubnet.Size = New-Object System.Drawing.Size(640, 70)
$form.Controls.Add($grpSubnet)

$txtSubnet = New-Object System.Windows.Forms.TextBox
$txtSubnet.Text = "ex. 192.168.1."
$txtSubnet.ForeColor = "Gray"        # Start with Gray text
$txtSubnet.Location = New-Object System.Drawing.Point(20, 30)
$txtSubnet.Size = New-Object System.Drawing.Size(130, 25)

# Event: When user clicks inside the box
$txtSubnet.Add_GotFocus({
    if ($this.Text -eq "ex. 192.168.1.") {
        $this.Text = ""              # Clear the placeholder
        $this.ForeColor = "Black"    # Switch to normal text color
    }
})

# Event: When user clicks outside the box
$txtSubnet.Add_LostFocus({
    if ([string]::IsNullOrWhiteSpace($this.Text)) {
        $this.Text = "ex. 192.168.1." # Restore placeholder if empty
        $this.ForeColor = "Gray"
    }
})

$grpSubnet.Controls.Add($txtSubnet)

$btnScanSubnet = New-Object System.Windows.Forms.Button
$btnScanSubnet.Text = "Scan Network"
$btnScanSubnet.Location = New-Object System.Drawing.Point(170, 25)
$btnScanSubnet.Size = New-Object System.Drawing.Size(150, 35)
$btnScanSubnet.BackColor = "#d63384"
$btnScanSubnet.ForeColor = "White"
$btnScanSubnet.FlatStyle = "Flat"
$grpSubnet.Controls.Add($btnScanSubnet)

# Status Label
$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Text = "Ready"
$lblStatus.Location = New-Object System.Drawing.Point(20, 225)
$lblStatus.Size = New-Object System.Drawing.Size(350, 20)
$lblStatus.ForeColor = "Gray"
$lblStatus.Font = $fontNormal
$form.Controls.Add($lblStatus)

# Stop Button
$btnStop = New-Object System.Windows.Forms.Button
$btnStop.Text = "Stop"
$btnStop.Location = New-Object System.Drawing.Point(380, 220)
$btnStop.Size = New-Object System.Drawing.Size(70, 25)
$btnStop.BackColor = "Red"
$btnStop.ForeColor = "White"
$btnStop.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
$btnStop.Enabled = $false
$form.Controls.Add($btnStop)

# Progress Bar
$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Location = New-Object System.Drawing.Point(460, 225)
$progressBar.Size = New-Object System.Drawing.Size(200, 15)
$progressBar.Style = "Continuous" 
$progressBar.Maximum = 60
$form.Controls.Add($progressBar)

# RichTextBox: Output
$txtOutput = New-Object System.Windows.Forms.RichTextBox
$txtOutput.Location = New-Object System.Drawing.Point(20, 250)
$txtOutput.Size = New-Object System.Drawing.Size(640, 380)
$txtOutput.Font = $fontMono
$txtOutput.ReadOnly = $true
$txtOutput.BackColor = "#f5f5f5"
$txtOutput.ScrollBars = "Vertical"
$form.Controls.Add($txtOutput)

# Timers for Background Job Check
$timerJob = New-Object System.Windows.Forms.Timer
$timerJob.Interval = 1000

$timerSubnet = New-Object System.Windows.Forms.Timer
$timerSubnet.Interval = 100

# ==========================================
# 3. HELPER FUNCTIONS & LOGIC
# ==========================================

# Toggle UI Function
# $State = $true (Unlock/Ready), $false (Lock/Busy)
function Toggle-Inputs {
    param([bool]$State)
    
    # Inputs/Action Buttons
    $btnScanLink.Enabled   = $State
    $btnArp.Enabled        = $State
    $btnScanSubnet.Enabled = $State
    $comboAdapters.Enabled = $State
    $txtSubnet.Enabled     = $State
    
    # Stop Button is Opposite of State
    # If UI is UNLOCKED ($true), Stop is DISABLED
    # If UI is LOCKED ($false), Stop is ENABLED
    $btnStop.Enabled = -not $State
    
    $form.Refresh()
}

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
        } 
        else {
            [void]$comboAdapters.Items.Add("No adapters found. Check Npcap.")
        }
    } 
    catch {
        [void]$comboAdapters.Items.Add("Error running TShark.")
    }
    $lblStatus.Text = "Ready"
}

# Initial Load
Load-Adapters

# ==========================================
# 4. EVENT HANDLERS
# ==========================================

# ACTION: STOP BUTTON
$btnStop.Add_Click({
    # Stop Timers
    $timerJob.Stop()
    $timerSubnet.Stop()
    
    # Stop TShark Job
    if ($global:scanJob) { 
        Stop-Job $global:scanJob
        Remove-Job $global:scanJob 
    }
    
    # Stop Subnet Job
    if ($script:subnetJob) { 
        Stop-Job $script:subnetJob
        Remove-Job $script:subnetJob 
    }

    # Reset UI
    $progressBar.Value = 0
    $lblStatus.Text = "Process Stopped"
    $txtOutput.AppendText("`n`n==== Process Stopped ====")
    
    Toggle-Inputs $true
})

# ACTION: GET ARP TABLE
$btnArp.Add_Click({
    Toggle-Inputs $false
    $txtOutput.Clear()
    $lblStatus.Text = "Fetching ARP table..."
    $form.Refresh()

    Start-Sleep -Milliseconds 100 

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("=== HOST DISCOVERY (ARP TABLE) ===")
    [void]$sb.AppendLine("$(Get-Date -Format F)")
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
    Toggle-Inputs $true
})

# ACTION: START LINK SCAN (LLDP/CDP)
$btnScanLink.Add_Click({
    if ($comboAdapters.SelectedItem -eq $null) {
        [System.Windows.Forms.MessageBox]::Show("Please select an adapter first.", "Error", "OK", "Error")
        return
    }

    # Lock UI
    Toggle-Inputs $false
    $txtOutput.Clear()
    $txtOutput.Text = "Listening for LLDP/CDP packets.`nThis will take 60 seconds.`n`nPlease wait..."
    $lblStatus.Text = "Scanning..."
    $progressBar.Maximum = 60
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
            "-e", "lldp.mgn.addr.ip4",
            "-e", "lldp.port.desc", 
            "-e", "lldp.chassis.id.mac",
            "-e", "cdp.deviceid", 
            "-e", "cdp.portid", 
            "-e", "cdp.cluster.ip",
            "-e", "cdp.address" ,
            "-e", "cdp.platform"
        )
        return & $bin $args 2>$null
    }

    # Start Job
    $global:scanJob = Start-Job -ScriptBlock $jobScript -ArgumentList $global:tsharkBinary, $selectedIndex
    $progressBar.Value = 0
    $timerJob.Start()
})

# TIMER TICK: CHECK JOB STATUS
$timerJob.Add_Tick({
    if ($global:scanJob.State -eq 'Completed' -or $global:scanJob.State -eq 'Failed') {
        $timerJob.Stop()
        
        # Process Results
        $results = Receive-Job -Job $global:scanJob
        Remove-Job -Job $global:scanJob
        
        $sb = New-Object System.Text.StringBuilder
        [void]$sb.AppendLine("=== LINK DISCOVERY RESULTS ===")
        [void]$sb.AppendLine("$(Get-Date -Format F)")
        [void]$sb.AppendLine("")

        if ($results) {
            foreach ($line in $results) {
                if ([string]::IsNullOrWhiteSpace($line)) { continue }
                
                $fields = $line -split "\|"
                # Handle possible missing fields by padding array
                while ($fields.Count -lt 10) { $fields += "" }

                $lldpName = $fields[0]
                $lldpPort = $fields[1]
                $lldpIP   = $fields[2]
                $lldpDesc = $fields[3]
                $lldpMac  = $fields[4]
                $cdpName  = $fields[5]
                $cdpPort  = $fields[6]
                $cdpClIP  = $fields[7]
                $cdpIP    = $fields[8]
                $cdpPlat  = $fields[9]

                if ($lldpName -or $lldpPort) {
                    [void]$sb.AppendLine(">>> LLDP PACKET DETECTED")
                    [void]$sb.AppendLine("    Switch Name : $lldpName")
                    [void]$sb.AppendLine("    Port ID     : $lldpPort")
                    [void]$sb.AppendLine("    IP Address  : $lldpIP")
                    [void]$sb.AppendLine("    Description : $lldpDesc")
                    [void]$sb.AppendLine("    Chassis MAC : $lldpMac")
                    [void]$sb.AppendLine("----------------------------------")
                }
                
                if ($cdpName -or $cdpPort) {
                    [void]$sb.AppendLine(">>> CDP PACKET DETECTED")
                    [void]$sb.AppendLine("    Device ID   : $cdpName")
                    [void]$sb.AppendLine("    Port ID     : $cdpPort")
                    [void]$sb.AppendLine("    Cluster IP  : $cdpClIP")
                    [void]$sb.AppendLine("    Mgmt IP     : $cdpIP")
                    [void]$sb.AppendLine("    Platform    : $cdpPlat")
                    [void]$sb.AppendLine("----------------------------------")
                }
            }
        } 
        else {
             [void]$sb.AppendLine("No LLDP or CDP packets received.")
             [void]$sb.AppendLine("Verify the interface selected is correct and the cable is secure.")
        }

        $txtOutput.Text = $sb.ToString()
        $lblStatus.Text = "Scan Complete."
        Toggle-Inputs $true
    }
    else {
        if ($progressBar.Value -lt $progressBar.Maximum) {
        $progressBar.Value++
        }
    $lblStatus.Text = "Scanning network..."
    }
})

$btnScanSubnet.Add_Click({
    $inputText = $txtSubnet.Text.Trim()
    
    if ($inputText -eq "ex. 192.168.1." -or [string]::IsNullOrWhiteSpace($inputText)) {
        [System.Windows.Forms.MessageBox]::Show("Please enter a valid subnet (e.g. 192.168.50.)", "Input Error", "OK", "Warning")
        return
    }
    
    $baseIP = $txtSubnet.Text.Trim()
    
    # Validation: Ensure it ends with a dot
    if (-not $baseIP.EndsWith(".")) {
        $baseIP += "."
        $txtSubnet.Text = $baseIP
    }

    Toggle-Inputs $false
    $txtOutput.Clear()
    $txtOutput.Text = "Scanning subnet $baseIP`0/24.`nPlease wait..."
    $progressBar.Value = 0
    $progressBar.Maximum = 254
    
    # Start Background Job for Pinging
    $script:subnetJob = Start-Job -ScriptBlock {
        param($prefix)
        $results = @()
        $ping = New-Object System.Net.NetworkInformation.Ping
        
        # Loop 1 to 254
        1..254 | ForEach-Object {
            $currentIP = "$prefix$_"
            try {
                $status = $ping.Send($currentIP, 100).Status
            } 
            catch { $status = "Failed" 
            }
            
            # Output progress every IP
            Write-Output "Progress:$currentIP"
        }
    } -ArgumentList $baseIP
    
    $timerSubnet.Start()
})

# --- TIMER: SUBNET PROGRESS ---
$timerSubnet.Add_Tick({
    if ($script:subnetJob.State -eq 'Running') {
        # Check for new output from the job to update progress bar
        $msgs = Receive-Job -Job $script:subnetJob -Keep
        # Simple math to approximate progress based on output count
        $count = ($msgs | Where-Object { $_ -like "Progress:*" }).Count
        if ($count -gt $progressBar.Value -and $count -le 254) {
            $progressBar.Value = $count
            $lblStatus.Text = "Pinging host $count of 254..."
        }
    }
    elseif ($script:subnetJob.State -eq 'Completed' -or $script:subnetJob.State -eq 'Failed') {
        $timerSubnet.Stop()
        Stop-Job -Job $script:subnetJob
        Remove-Job -Job $script:subnetJob
        $progressBar.Value = 254
        
        $lblStatus.Text = "Scan Complete."
        
        # Retrieve ARP table
        $sb = New-Object System.Text.StringBuilder
        [void]$sb.AppendLine("=== HOST DISCOVERY ($($txtSubnet.Text)0/24) ===")
        [void]$sb.AppendLine("$(Get-Date -Format F)")
        [void]$sb.AppendLine("")
        [void]$sb.AppendLine(("{0,-18} {1,-20} {2}" -f "IP Address", "MAC Address", "State"))
        [void]$sb.AppendLine(("{0,-18} {1,-20} {2}" -f "----------", "-----------", "-----"))
        
        # Filter Get-NetNeighbor for the requested subnet
        $subnetPattern = $txtSubnet.Text.Replace(".", "\.")
        $neighbors = Get-NetNeighbor -AddressFamily IPv4 | Where-Object { $_.IPAddress -match "^$subnetPattern" -and $_.State -ne "Unreachable" } | Sort-Object { [Version]$_.IPAddress }
        
        if ($neighbors) {
            foreach ($n in $neighbors) {
                [void]$sb.AppendLine(("{0,-18} {1,-20} {2}" -f $n.IPAddress, $n.LinkLayerAddress, $n.State))
            }
        } 
        else {
            [void]$sb.AppendLine("No device response.")
        }
        $txtOutput.Text = $sb.ToString()
        
        Toggle-Inputs $true
    }
})

# ==========================================
# 5. RUN GUI
# ==========================================
[void]$form.ShowDialog()
