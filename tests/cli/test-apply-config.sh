#!/bin/sh
# apply-config تنها نویسنده‌ی کانفیگ است، پس تنها جایی است که می‌تواند جلوی
# مقدار خراب را بگیرد — موتور اجرا حالت اعتبارسنجی ندارد.
set -u
. "$(dirname -- "$0")/../lib.sh"

srv=$(fixture server)
cli=$(fixture client)
trap 'rm -rf "$srv" "$cli"' EXIT
S="$srv/conf/server.toml"
C="$cli/conf/client.toml"

# --- پذیرش مقدار درست ---------------------------------------------------
run_stdin '{"transport":"wssmux","keepalive_period":90}' \
  env FARSHUB_CONF_DIR="$srv/conf" sh "$FARSHUB" apply-config server
assert_rc 'JSON درست پذیرفته شد' 0
assert_contains 'transport عوض شد' "$OUT" 'changed transport'
assert_contains 'keepalive عوض شد' "$OUT" 'changed keepalive_period'
assert_contains 'مقدار نوشته شد' "$(cat "$S")" 'transport = "wssmux"'
assert_contains 'عدد بدون گیومه' "$(cat "$S")" 'keepalive_period = 90'
assert_file 'پشتیبان ساخته شد' "$S.bak"

# مقدار تکراری = unchanged، نه changed
run_stdin '{"transport":"wssmux"}' \
  env FARSHUB_CONF_DIR="$srv/conf" sh "$FARSHUB" apply-config server
assert_contains 'مقدار یکسان unchanged است' "$OUT" 'unchanged transport'

# --- خطوط key=value، برای اسکریپت‌نویسی بدون python ---------------------
run_stdin 'log_level=debug
nodelay=false
' env FARSHUB_CONF_DIR="$srv/conf" sh "$FARSHUB" apply-config server
assert_rc 'خطوط key=value' 0
assert_contains 'رشته با گیومه' "$(cat "$S")" 'log_level = "debug"'
assert_contains 'بولین بدون گیومه' "$(cat "$S")" 'nodelay = false'

# --- رد کردن ------------------------------------------------------------
before=$(cat "$S")

run_stdin '{"transport":"quic"}' \
  env FARSHUB_CONF_DIR="$srv/conf" sh "$FARSHUB" apply-config server
assert_rc 'transport ناشناس رد شد' 1
assert_contains 'پیام transport' "$OUT" 'transport'

run_stdin '{"bogus_key":1}' \
  env FARSHUB_CONF_DIR="$srv/conf" sh "$FARSHUB" apply-config server
assert_rc 'کلید ناشناس رد شد' 1

run_stdin '{"heartbeat":0}' \
  env FARSHUB_CONF_DIR="$srv/conf" sh "$FARSHUB" apply-config server
assert_rc 'عدد بیرون بازه رد شد' 1

run_stdin '{"nodelay":"yes"}' \
  env FARSHUB_CONF_DIR="$srv/conf" sh "$FARSHUB" apply-config server
assert_rc 'بولین غیر true/false رد شد' 1

run_stdin '{"token":"short"}' \
  env FARSHUB_CONF_DIR="$srv/conf" sh "$FARSHUB" apply-config server
assert_rc 'توکن کوتاه رد شد' 1

run_stdin '{"bind_addr":"0.0.0.0:99999"}' \
  env FARSHUB_CONF_DIR="$srv/conf" sh "$FARSHUB" apply-config server
assert_rc 'پورت بیرون بازه رد شد' 1

run_stdin '{"bind_addr":"0.0.0.0:3080\"; rm -rf /"}' \
  env FARSHUB_CONF_DIR="$srv/conf" sh "$FARSHUB" apply-config server
assert_rc 'نویسه‌ی خطرناک رد شد' 1

run_stdin '{"remote_addr":"1.2.3.4:3080"}' \
  env FARSHUB_CONF_DIR="$srv/conf" sh "$FARSHUB" apply-config server
assert_rc 'کلید سمت مقابل رد شد' 1

# هیچ‌کدام از ردها نباید فایل را دست زده باشند
assert_eq 'فایل پس از ردها دست‌نخورده' "$(cat "$S")" "$before"

# توکن با طول و نویسه‌ی مجاز — بعد از سنجش «دست‌نخورده» می‌آید، چون این یکی
# عمداً می‌نویسد.
run_stdin '{"token":"CHANGE_ME_CHANGE_ME_CHANGE_ME_1234"}' \
  env FARSHUB_CONF_DIR="$srv/conf" sh "$FARSHUB" apply-config server
assert_rc 'توکن با نویسه‌ی مجاز پذیرفته شد' 0

# --- ports --------------------------------------------------------------
run_stdin 'ports+=443
ports+=8443=443
ports+=2000-2100
ports+=127.0.0.2:443=1.1.1.1:5201
' env FARSHUB_CONF_DIR="$srv/conf" sh "$FARSHUB" apply-config server
assert_rc 'ردیف‌های معتبر ports' 0
body=$(cat "$S")
assert_contains 'ردیف ساده' "$body" '"443",'
assert_contains 'ردیف نگاشت' "$body" '"8443=443",'
assert_contains 'ردیف بازه' "$body" '"2000-2100",'
assert_contains 'ردیف کامل' "$body" '"127.0.0.2:443=1.1.1.1:5201",'

run_stdin 'ports+=99999' \
  env FARSHUB_CONF_DIR="$srv/conf" sh "$FARSHUB" apply-config server
assert_rc 'پورت بیرون بازه در ردیف' 1

run_stdin 'ports+=2100-2000' \
  env FARSHUB_CONF_DIR="$srv/conf" sh "$FARSHUB" apply-config server
assert_rc 'بازه‌ی برعکس' 1

run_stdin 'ports=' \
  env FARSHUB_CONF_DIR="$srv/conf" sh "$FARSHUB" apply-config server
assert_rc 'خالی کردن ports' 0
assert_contains 'ports خالی شد' "$(cat "$S")" 'ports = ['

# --- سمت کلاینت ---------------------------------------------------------
run_stdin '{"remote_addr":"1.2.3.4:3080","connection_pool":16}' \
  env FARSHUB_CONF_DIR="$cli/conf" sh "$FARSHUB" apply-config client
assert_rc 'کلاینت پذیرفت' 0
assert_contains 'remote_addr نوشته شد' "$(cat "$C")" 'remote_addr = "1.2.3.4:3080"'

run_stdin 'ports+=443' \
  env FARSHUB_CONF_DIR="$cli/conf" sh "$FARSHUB" apply-config client
assert_rc 'کلاینت ports ندارد' 1

run_stdin '{"remote_addr":"SERVER_IP:3080"}' \
  env FARSHUB_CONF_DIR="$cli/conf" sh "$FARSHUB" apply-config client
assert_rc 'جای‌نگهدار remote_addr رد شد' 1

# --- استفاده ------------------------------------------------------------
run_stdin '{}' env FARSHUB_CONF_DIR="$srv/conf" sh "$FARSHUB" apply-config
assert_rc 'بدون سمت' 2

summary
