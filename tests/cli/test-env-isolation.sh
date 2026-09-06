#!/bin/sh
# نام سایت nginx و نام یونیت systemd هم باید مثل بقیه‌ی FARSHUB_* قابل
# override باشند. بدون این، اجرای تست روی سرور زنده سایت و سرویس زنده را
# بازنویسی می‌کند — همان چیزی که بخش ۶ اسپک باید جلویش را بگیرد.
set -u
. "$(dirname -- "$0")/../lib.sh"

d=$(fixture)
trap 'rm -rf "$d"' EXIT

# ۱) paths پیش‌فرض
fh paths server
assert_rc 'paths بدون خطا' 0
assert_contains 'یونیت پیش‌فرض' "$OUT" 'unit=farshub-server.service'
assert_contains 'نام سایت پیش‌فرض' "$OUT" 'site_name=farshub-panel'

# ۲) paths با override — هیچ نامی نباید به نصب زنده اشاره کند
envrun "$d" paths server
assert_rc 'paths با override' 0
assert_contains 'یونیت جدا' "$OUT" 'unit=farshub-test-server.service'
assert_contains 'سایت جدا' "$OUT" 'site_name=farshub-test'
assert_contains 'کانفیگ جدا' "$OUT" "conf=$d/conf/server.toml"
assert_missing 'اشاره‌ای به یونیت زنده نیست' "$OUT" 'unit=farshub-server.service'
assert_missing 'اشاره‌ای به سایت زنده نیست' "$OUT" 'site_name=farshub-panel'

# ۳) install با override: فایل یونیت باید با نام prefix نوشته شود، و drop-in
#    محیطی داشته باشد وگرنه _exec سرویس کانفیگ اشتباه را برمی‌دارد.
envrun "$d" install server
assert_rc 'install با override' 0
assert_file 'یونیت با نام جدا نوشته شد' "$d/units/farshub-test-server.service"
assert_file 'drop-in محیطی نوشته شد' "$d/units/farshub-test-server.service.d/10-farshub-env.conf"
dropin=$(cat "$d/units/farshub-test-server.service.d/10-farshub-env.conf" 2>/dev/null || true)
assert_contains 'drop-in مسیر کانفیگ را می‌دهد' "$dropin" "Environment=FARSHUB_CONF_DIR=$d/conf"
assert_contains 'drop-in ExecStart را بازنویسی می‌کند' "$dropin" "ExecStart=$d/bin/farshub _exec server"

# ۴) payload: نصب سمت دوم باید بدون مخزن هم کار کند — API از /usr/local/bin
#    صدا می‌زند و آنجا مخزنی نیست.
assert_file 'payload کانفیگ‌ها' "$d/state/payload/configs/client.toml"
assert_file 'payload یونیت‌ها' "$d/state/payload/systemd/farshub-client.service"
rm -rf "$d/second"
mkdir -p "$d/second"
cp "$d/bin/farshub" "$d/second/farshub"     # نسخه‌ی نصب‌شده، بدون مخزن کنارش
run env \
  FARSHUB_CONF_DIR="$d/conf" FARSHUB_LIBEXEC="$d/libexec" \
  FARSHUB_BIN_DIR="$d/bin" FARSHUB_UNIT_DIR="$d/units" \
  FARSHUB_LOG_DIR="$d/log" FARSHUB_STATE_DIR="$d/state" \
  FARSHUB_UNIT_PREFIX=farshub-test \
  sh "$d/second/farshub" install client
assert_rc 'install سمت دوم بدون مخزن' 0
assert_file 'کانفیگ سمت دوم' "$d/conf/client.toml"

summary
