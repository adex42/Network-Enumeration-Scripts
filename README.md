````markdown
#  Reconnaissance Scripts

This repository contains two Bash scripts designed to automate different types of network and host reconnaissance using **Nmap** (and optionally **enum4linux** for host enumeration).

---

##  `router.sh`

This is a simple, quick script designed to perform an aggressive scan focusing on a single target, typically a **router** or single host device, to gather service version and default script information.

###  Prerequisites

You must have **Nmap** installed on your system.

###  Usage Instructions

The script takes one required argument: the **target IP address** or **hostname**. You also need to set the environment variables `TARGET` and `OUTDIR` before running the script.

1.  **Set Variables:**
    * Set `TARGET` to the IP address or hostname of the router/target.
    * Set `OUTDIR` to the directory where you want to save the output file.

    ```bash
    TARGET="192.168.1.1" # Example target
    OUTDIR="scan-results" # Example output directory
    ```

2.  **Execute the script:**

    ```bash
    ./router.sh
    ```

###  Output

The script runs the following Nmap command:
`nmap -sC -sV -sS -sN -oN "$OUTDIR/router_recon.txt" "$TARGET" || echo "[!] router_recon completed with warnings"`

* The results will be saved to a file named **`router_recon.txt`** inside the specified `$OUTDIR`.
* The scan performs:
    * **`-sC`**: Default script scanning.
    * **`-sV`**: Version detection.
    * **`-sS`**: TCP SYN scan (fast stealth scan).
    * **`-sN`**: TCP Null scan.
    * **`-oN`**: Output the results to a normal text file.

---

##  `network.sh` (Corporate Discovery)

This is a comprehensive, multi-stage script intended for performing in-depth reconnaissance across an entire corporate network or subnet. It combines network-wide broadcast/UDP scans with targeted host enumeration against live hosts.

###  IMPORTANT: Root Privileges Required

This script performs network discovery and certain **UDP scans** that require **root** privileges to run correctly.

###  Prerequisites

* **Nmap**
* **enum4linux** (Optional, but highly recommended for thorough **SMB/Windows** host enumeration. If not found, the script will skip this part.)

###  Usage Instructions

The script requires **one** command-line argument: the **network in CIDR notation**.

1.  **Ensure you have root privileges** (use `sudo`).
2.  **Execute the script:**

    ```bash
    sudo ./network.sh <network/cidr>
    ```

    **Example:**

    ```bash
    sudo ./network.sh 192.168.1.0/24
    ```

###  Scan Stages and Output Structure

The script automatically creates a unique output directory named `scan-results-<network_cidr>-<timestamp>`.

**Example:** `scan-results-192.168.1.0_24-20251115-152404`

#### 1. Host Discovery
* Uses `nmap -sn` to find **live hosts** on the subnet.
* **Output:** `discovery.*` files in the main output directory.

#### 2. Network-Wide/Broadcast Scans
This stage runs resource-intensive UDP and broadcast scans against the entire network range to find common infrastructure services:
* **DNS** (UDP 53)
* **SNMP** (UDP 161)
* **mDNS** (UDP 5353)
* **DHCP** (UDP 67)
* **NTP** (UDP 123)
* **Printer** (TCP 631)
* **Output:** Files like `dns-*.xml`, `snmp-*.xml`, etc., in the main output directory.

#### 3. Per-Host Enumeration

For every live host discovered, the script creates a dedicated host directory (`$OUTDIR/hosts/<host_ip>`) and runs targeted, deeper enumeration scans based on open ports.

* **Scans include checks for:**
    * **SMTP** (25, 587)
    * **HTTP/HTTPS** (80, 443)
    * **SMB** (139, 445) - including `enum4linux` (if available)
    * **SNMP** (161)
    * **RDP** (3389)
    * **LDAP** (389, 636)
    * **Kerberos** (88)
    * **SSH** (22)
    * **IMAP** (143, 993)
    * **FTP** (21)
* **Output:** Host-specific Nmap XML/text files and `enum4linux.txt` files inside the respective host directories.

###  Next Steps

After the script completes, review the output directory. Start by examining the **Nmap XML (`.xml`)** and **grepable (`.gnmap`)** files for an overview of services, and then dive into the per-host directories for deep enumeration results.
````