#!/bin/sh
set -e

if [ -f .env ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in \#*|'') continue ;; esac
    key="${line%%=*}"
    value="${line#*=}"
    export "$key=$value"
  done < .env
fi

SABNZBD_DIR="${SABNZBD_PATH_CONFIG:-./sabnzbd/config}"
mkdir -p "${SABNZBD_DIR}/sabnzbd"

INI="${SABNZBD_DIR}/sabnzbd.ini"

echo "[pre-deploy] generating sabnzbd.ini from environment"

cat > "$INI" <<EOF
__version__ = 19
__encoding__ = utf-8
[misc]
config_conversion_version = 5
helpful_warnings = 0
queue_complete = ${SABNZBD_QUEUE_COMPLETE:-}
queue_complete_pers = 0
bandwidth_perc = ${SABNZBD_BANDWIDTH_PERC:-100}
refresh_rate = ${SABNZBD_REFRESH_RATE:-1}
interface_settings = ${SABNZBD_INTERFACE_SETTINGS:-'{"dateFormat":"fromNow","extraQueueColumns":["processing"],"extraHistoryColumns":["size"],"displayCompact":false,"displayFullWidth":true,"displayTabbed":false,"confirmDeleteQueue":true,"confirmDeleteHistory":true,"keyboardShortcuts":true}'}
queue_limit = ${SABNZBD_QUEUE_LIMIT:-20}
config_lock = 0
fixed_ports = 1
notified_new_skin = 2
direct_unpack_tested = 1
sorters_converted = 1
check_new_rel = 0
auto_browser = 0
language = ${SABNZBD_LANGUAGE:-en}
enable_https_verification = 1
host = ::
port = 8080
https_port =
username =
password =
bandwidth_max = ${SABNZBD_BANDWIDTH_MAX:-}
cache_limit = ${SABNZBD_CACHE_LIMIT:-512M}
web_dir = ${SABNZBD_WEB_DIR:-Glitter}
web_color = ${SABNZBD_WEB_COLOR:-Auto}
https_cert = server.cert
https_key = server.key
https_chain =
enable_https = 0
inet_exposure = 0
api_key = placeholder
nzb_key = placeholder
socks5_proxy_url =
permissions =
download_dir = /data/incomplete
download_free = ${SABNZBD_DOWNLOAD_FREE:-50G}
complete_dir = /data/downloads
complete_free = ${SABNZBD_COMPLETE_FREE:-100G}
fulldisk_autoresume = 1
script_dir = ${SABNZBD_SCRIPT_DIR:-}
nzb_backup_dir = nzb-backup
admin_dir = admin
backup_dir = backup
dirscan_dir = ${SABNZBD_DIRSCAN_DIR:-}
dirscan_speed = ${SABNZBD_DIRSCAN_SPEED:-5}
password_file =
log_dir = logs
max_art_tries = ${SABNZBD_MAX_ART_TRIES:-5}
top_only = ${SABNZBD_TOP_ONLY:-1}
sfv_check = 0
script_can_fail = 0
enable_recursive = 1
flat_unpack = ${SABNZBD_FLAT_UNPACK:-1}
par_option = ${SABNZBD_PAR_OPTION:-}
pre_check = ${SABNZBD_PRE_CHECK:-1}
nice =
win_process_prio = 3
ionice =
fail_hopeless_jobs = 1
fast_fail = 1
auto_disconnect = 1
pre_script = ${SABNZBD_PRE_SCRIPT:-None}
end_queue_script = ${SABNZBD_END_QUEUE_SCRIPT:-None}
no_dupes = ${SABNZBD_NO_DUPES:-0}
no_series_dupes = ${SABNZBD_NO_SERIES_DUPES:-0}
no_smart_dupes = ${SABNZBD_NO_SMART_DUPES:-0}
dupes_propercheck = 1
pause_on_pwrar = ${SABNZBD_PAUSE_ON_PWRAR:-1}
ignore_samples = 1
deobfuscate_final_filenames = 1
auto_sort = ${SABNZBD_AUTO_SORT:-}
direct_unpack = ${SABNZBD_DIRECT_UNPACK:-1}
propagation_delay = ${SABNZBD_PROPAGATION_DELAY:-0}
folder_rename = 1
replace_spaces = 0
replace_underscores = 0
replace_dots = 0
safe_postproc = 1
pause_on_post_processing = 0
enable_all_par = 0
sanitize_safe = 1
cleanup_list = ${SABNZBD_CLEANUP_LIST:-}
unwanted_extensions = ${SABNZBD_UNWANTED_EXTENSIONS:-ade, adp, app, application, appref-ms, asp, aspx, asx, bas, bat, bgi, cab, cer, chm, cmd, cnt, com, cpl, crt, csh, der, diagcab, exe, fxp, gadget, grp, hlp, hpj, hta, htc, inf, ins, iso, isp, its, jar, jnlp, js, jse, ksh, lnk, mad, maf, mag, mam, maq, mar, mas, mat, mau, mav, maw, mcf, mda, mdb, mde, mdt, mdw, mdz, msc, msh, msh1, msh2, mshxml, msh1xml, msh2xml, msi, msp, mst, msu, ops, osd, pcd, pif, pl, plg, prf, prg, printerexport, ps1, ps1xml, ps2, ps2xml, psc1, psc2, psd1, psdm1, pst, py, pyc, pyo, pyw, pyz, pyzw, reg, scf, scr, sct, shb, shs, theme, tmp, url, vb, vbe, vbp, vbs, vhd, vhdx, vsmacros, vsw, webpnp, website, ws, wsc, wsf, wsh, xbap, xll, xnk}
action_on_unwanted_extensions = ${SABNZBD_ACTION_ON_UNWANTED_EXT:-2}
unwanted_extensions_mode = 0
new_nzb_on_failure = 0
history_retention = ${SABNZBD_HISTORY_RETENTION:-30}
history_retention_option = ${SABNZBD_HISTORY_RETENTION_OPTION:-all}
history_retention_number = 1
quota_size = ${SABNZBD_QUOTA_SIZE:-}
quota_day = ${SABNZBD_QUOTA_DAY:-}
quota_resume = 0
quota_period = ${SABNZBD_QUOTA_PERIOD:-m}
enable_tv_sorting = 0
tv_sort_string =
tv_categories = tv,
enable_movie_sorting = 0
movie_sort_string =
movie_sort_extra = -cd%1
movie_categories = movies,
enable_date_sorting = 0
date_sort_string =
date_categories = tv,
schedlines = ${SABNZBD_SCHEDLINES:-}
rss_rate = ${SABNZBD_RSS_RATE:-0}
ampm = 0
start_paused = 0
preserve_paused_state = 0
enable_par_cleanup = 1
process_unpacked_par2 = 1
enable_unrar = 1
enable_7zip = 1
enable_filejoin = 1
enable_tsjoin = 1
overwrite_files = 0
ignore_unrar_dates = 0
backup_for_duplicates = 0
empty_postproc = 0
wait_for_dfolder = 0
rss_filenames = 0
api_logging = 0
html_login = 1
disable_archive = 0
warn_dupl_jobs = 0
keep_awake = 0
tray_icon = 0
allow_incomplete_nzb = 0
enable_broadcast = 0
ipv6_hosting = 0
ipv6_staging = 0
api_warnings = 1
no_penalties = 0
x_frame_options = 1
allow_old_ssl_tls = 0
enable_season_sorting = ${SABNZBD_ENABLE_SEASON_SORTING:-0}
verify_xff_header = 0
rss_odd_titles = nzbindex.nl/, nzbindex.com/, nzbclub.com/
quick_check_ext_ignore = nfo, sfv, srr
req_completion_rate = ${SABNZBD_REQ_COMPLETION_RATE:-100.5}
selftest_host = self-test.sabnzbd.org
movie_rename_limit = 100M
episode_rename_limit = 20M
size_limit = ${SABNZBD_SIZE_LIMIT:-0}
direct_unpack_threads = ${SABNZBD_DIRECT_UNPACK_THREADS:-3}
history_limit = ${SABNZBD_HISTORY_LIMIT:-10}
wait_ext_drive = 5
max_foldername_length = 246
nomedia_marker =
ipv6_servers = 0
url_base =
host_whitelist = ${SABNZBD_HOST_WHITELIST:-sabnzbd, gluetun, localhost}
local_ranges = ${SABNZBD_LOCAL_RANGES:-}
max_url_retries = 10
downloader_sleep_time = 10
receive_threads = 2
switchinterval = 0.005
ssdp_broadcast_interval = 15
ext_rename_ignore =
unrar_parameters =

[logging]
log_level = ${SABNZBD_LOG_LEVEL:-1}
max_log_size = ${SABNZBD_MAX_LOG_SIZE:-5242880}
log_backups = ${SABNZBD_LOG_BACKUPS:-5}

[servers]
    [[${SABNZBD_SERVER1_NAME:-newsserver}]]
    displayname = ${SABNZBD_SERVER1_NAME:-newsserver}
    host = ${SABNZBD_SERVER1_HOST}
    port = ${SABNZBD_SERVER1_PORT:-563}
    timeout = 60
    username = ${SABNZBD_SERVER1_USERNAME}
    password = ${SABNZBD_SERVER1_PASSWORD}
    connections = ${SABNZBD_SERVER1_CONNECTIONS:-20}
    ssl = ${SABNZBD_SERVER1_SSL:-1}
    ssl_verify = 2
    ssl_ciphers =
    enable = 1
    required = 0
    optional = 0
    retention = 0
    expire_date =
    quota =
    priority = 0
    notes =

[categories]
    [[*]]
    name = *
    order = 0
    pp = 3
    script = Default
    dir =
    newzbin =
    priority = -100
EOF

ORDER=1
IDX=1
while true; do
  eval "CAT_NAME=\${SABNZBD_CAT_${IDX}_NAME:-}"
  [ -z "$CAT_NAME" ] && break
  eval "CAT_DIR=\${SABNZBD_CAT_${IDX}_DIR:-${CAT_NAME}}"
  eval "CAT_PP=\${SABNZBD_CAT_${IDX}_PP:-3}"
  eval "CAT_SCRIPT=\${SABNZBD_CAT_${IDX}_SCRIPT:-Default}"
  eval "CAT_PRIORITY=\${SABNZBD_CAT_${IDX}_PRIORITY:--100}"
  cat >> "$INI" <<EOF

    [[${CAT_NAME}]]
    name = ${CAT_NAME}
    order = ${ORDER}
    pp = ${CAT_PP}
    script = ${CAT_SCRIPT}
    dir = ${CAT_DIR}
    newzbin =
    priority = ${CAT_PRIORITY}
EOF
  ORDER=$((ORDER + 1))
  IDX=$((IDX + 1))
done

chown -R "${PUID:-1000}:${PGID:-1000}" "${SABNZBD_DIR}"

echo "[pre-deploy] sabnzbd.ini created"
