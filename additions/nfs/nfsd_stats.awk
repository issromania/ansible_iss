#!/usr/bin/awk -f
# nfsd_stats.awk — parse /proc/net/rpc/nfsd -> InfluxDB line protocol
# Measurement: nfsd. Values are counters; derive rates in Grafana.
# The `host` tag is added by the Telegraf agent (global), so it is omitted here.
#
# LIMITATIONS (see server notes):
#   - io_*_bytes are 32-bit kernel counters and WRAP at 4 GiB. On fast servers
#     prefer NIC counters (inputs.net) for true throughput.
#   - th_fullcnt (thread-pool-exhausted count) is the only saturation proxy and
#     is zeroed on some newer kernels.
#   - Per-operation server latency is NOT exposed here (needs eBPF/nfsdist).
#
# Usage (via Telegraf inputs.exec):
#   awk -f /usr/local/bin/nfsd_stats.awk /proc/net/rpc/nfsd

$1 == "rc"  { rc_hits = $2; rc_miss = $3; rc_nocache = $4 }
$1 == "fh"  { fh_stale = $2 }
$1 == "io"  { io_read = $2; io_write = $3 }
$1 == "th"  { th_threads = $2; th_fullcnt = $3 }
$1 == "net" { net_cnt = $2; net_udp = $3; net_tcp = $4; net_tcpconn = $5 }
$1 == "rpc" { rpc_cnt = $2; rpc_bad = $3; rpc_badfmt = $4; rpc_badauth = $5; rpc_badclnt = $6 }

END {
    printf "nfsd "
    printf "rc_hits=%di,rc_miss=%di,rc_nocache=%di,", rc_hits, rc_miss, rc_nocache
    printf "fh_stale=%di,io_read_bytes=%di,io_write_bytes=%di,", fh_stale, io_read, io_write
    printf "th_threads=%di,th_fullcnt=%di,", th_threads, th_fullcnt
    printf "net_cnt=%di,net_udp=%di,net_tcp=%di,net_tcpconn=%di,", net_cnt, net_udp, net_tcp, net_tcpconn
    printf "rpc_cnt=%di,rpc_bad=%di,rpc_badfmt=%di,rpc_badauth=%di,rpc_badclnt=%di\n", \
           rpc_cnt, rpc_bad, rpc_badfmt, rpc_badauth, rpc_badclnt
}
