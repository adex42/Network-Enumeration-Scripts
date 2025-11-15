#!/usr/bin/env bash
# corp_discovery.sh
# Usage: sudo ./corp_discovery.sh <network/cidr>
# Example: sudo ./corp_discovery.sh 192.168.1.0/24

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "This script performs network discovery and some UDP scans that require root."
  echo "Please run with sudo."
  exit 1
fi

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <network/cidr>   e.g. $0 192.168.1.0/24"
  exit 1
fi

NET="$1"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
OUTDIR="scan-results-${NET//\//_}-$TIMESTAMP"
mkdir -p "$OUTDIR"
echo "[*] Outputs will be stored in: $OUTDIR"

# helper for checking whether a port is open on a host (returns 0 if open)
port_open() {
  local host=$1
  local port=$2
  # quick grepable nmap to test a single port
  nmap -Pn -p "$port" --host-timeout 10s -oG - "$host" | awk '/Ports:/{print $0}' | grep -qE "${port}/open"
}

# Discover live hosts (ARP/ping)
echo "[*] Discovering alive hosts on $NET..."
nmap -sn "$NET" -oA "$OUTDIR/discovery" > /dev/null
LIVE_HOSTS=($(awk '/Up$/{print $2}' "$OUTDIR/discovery.gnmap"))
echo "[*] Found ${#LIVE_HOSTS[@]} host(s)."

# Run network-wide / broadcast-style scans (target the CIDR or broadcast-ish target)
echo "[*] Running network-wide UDP/service discovery scans (this may take a while)..."

# DNS related (UDP 53) -- check across the network
echo "[*] DNS recursion/AXFR/cache checks against $NET"
nmap -sU -p 53 --script=dns-recursion,dns-zone-transfer,dns-nsec-enum,dns-cache-snoop -oA "$OUTDIR/dns-$TIMESTAMP" "$NET"

# SNMP scan across the subnet (UDP 161) - info + brute (be careful: brute can be noisy)
echo "[*] SNMP info + snmp-brute across $NET"
nmap -sU -p 161 --script=snmp-info,snmp-brute -oA "$OUTDIR/snmp-$TIMESTAMP" "$NET"

# mDNS broadcast discovery (UDP 5353)
echo "[*] mDNS service discovery on $NET (UDP 5353)"
nmap -sU -p 5353 --script=broadcast-dns-service-discovery -oA "$OUTDIR/mdns-$TIMESTAMP" "$NET"

# DHCP discover (UDP 67) - targeting the network (uses broadcast)
echo "[*] DHCP discovery (udp/67) against $NET (may need specific interface)"
nmap -sU -p 67 --script=dhcp-discover -oA "$OUTDIR/dhcp-discover-$TIMESTAMP" "$NET"

# NTP (udp/123) and RADIUS (udp/1812) - run against entire subnet (these may be noisy)
echo "[*] NTP (udp/123) info scan on $NET"
nmap -sU -p 123 --script=ntp-info -oA "$OUTDIR/ntp-$TIMESTAMP" "$NET"

# Printer discovery (broadcast style) - check port 631 across the network
echo "[*] Printer broadcast info (tcp/631) across $NET"
nmap -sV -p 631 --script=broadcast-bjnp-discover -oA "$OUTDIR/printer-$TIMESTAMP" "$NET"

# Now run per-live-host scans (some scans gated by checking if the service/port is open first)
for host in "${LIVE_HOSTS[@]}"; do
  echo; echo "=============================="
  echo "[*] Enumerating host: $host"
  HOSTDIR="$OUTDIR/hosts/$host"
  mkdir -p "$HOSTDIR"

  # SMTP (25,587)
  if port_open "$host" 25 || port_open "$host" 587; then
    echo "[*] SMTP detected on $host - running smtp-enum & open-relay checks"
    nmap -sV -p 25,587 --script=smtp-enum-users,smtp-open-relay -oA "$HOSTDIR/smtp" "$host"
  else
    echo "[ ] SMTP (25/587) closed on $host"
  fi

  # HTTP (80,443) - run http-enum + http-vuln* (note: vuln scripts can be intrusive)
  if port_open "$host" 80 || port_open "$host" 443; then
    echo "[*] HTTP/HTTPS detected on $host - running http-enum and http-vuln*"
    nmap -sV -p 80,443 --script=http-enum,http-vuln* -oA "$HOSTDIR/http" "$host"
  else
    echo "[ ] HTTP/HTTPS (80/443) closed on $host"
  fi

  # SMB / enum4linux
  if port_open "$host" 445 || port_open "$host" 139; then
    echo "[*] SMB detected on $host - running nmap smb scripts and enum4linux"
    nmap -p 445 --script=smb-enum-shares,smb-enum-users,smb-os-discovery -oA "$HOSTDIR/smb-nmap" "$host"
    if command -v enum4linux >/dev/null 2>&1; then
      echo "[*] Running enum4linux -a $host"
      enum4linux -a "$host" > "$HOSTDIR/enum4linux.txt" 2>&1 || true
    else
      echo "[!] enum4linux not installed; skipping enum4linux for $host"
    fi
  else
    echo "[ ] SMB (445/139) closed on $host"
  fi

  # SNMP on host (udp/161) - lightweight info (brute already run network-wide)
  if nmap -Pn -sU -p 161 --host-timeout 10s "$host" -oG - | grep -q "161/udp\s*open"; then
    echo "[*] SNMP open on $host - running snmp-info"
    nmap -sU -p 161 --script=snmp-info -oA "$HOSTDIR/snmp" "$host"
  else
    echo "[ ] SNMP (161) closed on $host"
  fi

  # RDP (3389)
  if port_open "$host" 3389; then
    echo "[*] RDP detected on $host - running rdp scripts"
    nmap -p 3389 --script=rdp-enum-encryption,rdp-vuln-ms12-020 -oA "$HOSTDIR/rdp" "$host"
  else
    echo "[ ] RDP (3389) closed on $host"
  fi

  # LDAP (389,636)
  if port_open "$host" 389 || port_open "$host" 636; then
    echo "[*] LDAP detected on $host - running ldap-rootdse,ldap-search"
    nmap -sV -p 389,636 --script=ldap-rootdse,ldap-search -oA "$HOSTDIR/ldap" "$host"
    echo "[*] Attempt ldap-brute (if allowed in scope!)"
    nmap --script=ldap-brute -p 389 -oA "$HOSTDIR/ldap-brute" "$host"
  else
    echo "[ ] LDAP (389/636) closed on $host"
  fi

  # Kerberos (88)
  if port_open "$host" 88; then
    echo "[*] Kerberos (88) open - running krb5-enum-users"
    nmap -sU -p 88 --script=krb5-enum-users -oA "$HOSTDIR/kerberos" "$host"
  else
    echo "[ ] Kerberos (88) closed on $host"
  fi

  # SSH (22)
  if port_open "$host" 22; then
    echo "[*] SSH open - grabbing hostkey & auth methods"
    nmap -sV -p 22 --script=ssh-hostkey,ssh-auth-methods -oA "$HOSTDIR/ssh" "$host"
  else
    echo "[ ] SSH (22) closed on $host"
  fi

  # IMAP (143,993)
  if port_open "$host" 143 || port_open "$host" 993; then
    echo "[*] IMAP detected - running imap-capabilities"
    nmap -sV -p 143,993 --script=imap-capabilities -oA "$HOSTDIR/imap" "$host"
  else
    echo "[ ] IMAP (143/993) closed on $host"
  fi

  # FTP (21)
  if port_open "$host" 21; then
    echo "[*] FTP open - running ftp-anon & ftp-brute"
    nmap -sV -p 21 --script=ftp-anon,ftp-brute -oA "$HOSTDIR/ftp" "$host"
  else
    echo "[ ] FTP (21) closed on $host"
  fi

done

echo; echo "[*] All scans kicked off/completed. See $OUTDIR for results."
echo "[*] Recommended next steps: review *_nmap*.xml files, open pcap captures if you ran tcpdump, and triage hosts with interesting services."

exit 0
