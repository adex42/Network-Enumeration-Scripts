#!/usr/bin/env bash
# router_snmp_oneip.sh
# Usage: sudo ./router_snmp_oneip.sh <target-ip>
# Runs:
#  - nmap -sC -sV -sS -sN -o router_recon.txt <IP>
#  - nmap -sS -sV -O -A --script "default,vuln,discovery" -p- <IP> -oA host-detail
#  - nmap -sU -p161 --script=snmp-info,snmp-brute <IP>
#  - nmap -sU -p161 --script=snmp-ios-config --script-args creds.snmp=public <IP>
#  - nmap -sU -p161 --script=snmp-ios-config --script-args creds.snmp=private <IP>

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "[!] This script requires root privileges (sudo)."
  exit 1
fi

if [[ $# -ne 1 ]]; then
  echo "Usage: sudo $0 <target-ip>"
  exit 1
fi

TARGET="$1"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
OUTDIR="oneip_recon_${TARGET//./_}_$TIMESTAMP"
mkdir -p "$OUTDIR"

echo "[*] Output directory: $OUTDIR"
echo "[*] Target: $TARGET"
echo

# 1) Basic router recon
echo "[1/5] Running basic router recon: nmap -sC -sV -sS -sN ..."
nmap -sC -sV -sS -sN -oN "$OUTDIR/router_recon.txt" "$TARGET" || echo "[!] router_recon completed with warnings"

# 2) Full host-detail (all ports) with default,vuln,discovery scripts
echo "[2/5] Running full host-detail (all ports) with scripts -> $OUTDIR/host-detail.*"
nmap -sS -sV -O -A --script "default,vuln,discovery" -p- -oA "$OUTDIR/host-detail" "$TARGET" || echo "[!] host-detail completed with warnings"

# 3) SNMP info + snmp-brute against the single IP
echo "[3/5] Running SNMP info + snmp-brute on $TARGET (udp/161) -> $OUTDIR/snmp-info-brute"
nmap -sU -p 161 --script=snmp-info,snmp-brute -oA "$OUTDIR/snmp-info-brute" "$TARGET" || echo "[!] snmp-info/snmp-brute completed with warnings"

# 4) snmp-ios-config with community 'public'
echo "[4/5] Running snmp-ios-config with community 'public' -> $OUTDIR/snmp-ios-config-public.nmap"
nmap -sU -p 161 --script=snmp-ios-config --script-args 'creds.snmp=public' -oN "$OUTDIR/snmp-ios-config-public.nmap" "$TARGET" || echo "[!] snmp-ios-config(public) completed with warnings"

# 5) snmp-ios-config with community 'private'
echo "[5/5] Running snmp-ios-config with community 'private' -> $OUTDIR/snmp-ios-config-private.nmap"
nmap -sU -p 161 --script=snmp-ios-config --script-args 'creds.snmp=private' -oN "$OUTDIR/snmp-ios-config-private.nmap" "$TARGET" || echo "[!] snmp-ios-config(private) completed with warnings"

# Quick summary file
SUMMARY="$OUTDIR/quick-summary.txt"
echo "Quick summary for $TARGET" > "$SUMMARY"
echo "Timestamp: $TIMESTAMP" >> "$SUMMARY"
echo >> "$SUMMARY"

if [[ -f "$OUTDIR/router_recon.txt" ]]; then
  echo "=== Router Recon (first 80 lines) ===" >> "$SUMMARY"
  sed -n '1,80p' "$OUTDIR/router_recon.txt" >> "$SUMMARY" || true
  echo >> "$SUMMARY"
fi

if [[ -f "$OUTDIR/host-detail.nmap" ]]; then
  echo "=== Host Detail (first 120 lines) ===" >> "$SUMMARY"
  sed -n '1,120p' "$OUTDIR/host-detail.nmap" >> "$SUMMARY" || true
  echo >> "$SUMMARY"
fi

echo "[*] All scans completed. Outputs: $OUTDIR"
echo "[*] Quick summary: $SUMMARY"
echo
echo "IMPORTANT NOTES:"
echo "- 'snmp-brute' and '--script=vuln' can be noisy. Only run when explicitly authorized."
echo "- Review the .nmap/.xml/.gnmap files in $OUTDIR for full details."

exit 0
