#!/bin/sh
# ==========================================================================
#  FarsHub Tunnel — ساخت بسته‌ی انتشار
#
#  یک tar.gz تمیز می‌سازد که روی سرور با «tar -xzf» باز شود و بلافاصله
#  «farshub install» رویش کار کند. قبل از ساخت دو چیز را گارد می‌کند:
#  MD5 موتور اجرا و خط‌پایان LF.
#
#  استفاده:  sh scripts/release.sh [پوشه‌ی خروجی]
#            پیش‌فرض خروجی: پوشه‌ی والد مخزن.
#
#  POSIX sh — به bash نیاز ندارد. روی ویندوز (Git Bash) هم اجرا می‌شود.
# ==========================================================================
set -eu

PKG='farshub-tunnel'          # نام پوشه‌ی داخل آرشیو (کوتاه و lowercase)

die() { printf 'release: %s\n' "$1" >&2; exit 1; }
say() { printf '%s\n' "$*"; }

self_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
root=$(CDPATH= cd -- "$self_dir/.." && pwd)
name=$(basename -- "$root")
out_dir=${1:-$(CDPATH= cd -- "$root/.." && pwd)}

[ -f "$root/bin/farshub" ]      || die 'bin/farshub پیدا نشد.'
[ -f "$root/bin/farshub-core" ] || die 'bin/farshub-core پیدا نشد.'
[ -d "$out_dir" ]               || die "پوشه‌ی خروجی وجود ندارد: $out_dir"

ver=$(sed -n "s/^CLI_VERSION='\([^']*\)'.*/\1/p" "$root/bin/farshub")
[ -n "$ver" ] || die 'CLI_VERSION از bin/farshub خوانده نشد.'

# --- گارد ۱: موتور اجرا باید byte-identical باشد -------------------------
# مقدار مرجع از ORIGIN.md خوانده می‌شود تا یک منبع حقیقت داشته باشیم.
want=$(sed -n 's/^| MD5 | `\([0-9a-f]\{32\}\)` |.*$/\1/p' "$root/docs/ORIGIN.md")
[ -n "$want" ] || die 'MD5 مرجع در docs/ORIGIN.md پیدا نشد.'
have=$(md5sum "$root/bin/farshub-core" | cut -d' ' -f1)
[ "$have" = "$want" ] || die "MD5 موتور اجرا با ORIGIN.md نمی‌خواند.
  انتظار: $want
  واقعی : $have
باینری patch‌شده نباید عوض شود — انتشار متوقف شد."

# --- گارد ۲: خط‌پایان LF --------------------------------------------------
# یک CR در bin/farshub روی لینوکس «bad interpreter» می‌دهد.
for f in "$root/bin/farshub" "$root/configs/"*.toml \
         "$root/systemd/"*.service; do
  tr -d '\r' <"$f" | cmp -s - "$f" ||
    die "خط‌پایان CRLF در $(basename -- "$f") — به LF تبدیلش کنید."
done

# --- ساخت آرشیو ----------------------------------------------------------
# در دو پاس، چون مود اجرایی bin/ را باید خود tar تحمیل کند: روی ویندوز
# `chmod +x` بر یک ELF لینوکسی بی‌اثر است (MSYS بیت اجرا را از شبیانگ حدس
# می‌زند و ELF را نمی‌شناسد)، پس farshub-core همیشه 644 دیده می‌شود.
#   پاس ۱: bin/ با --mode=755
#   پاس ۲: بقیه با مود طبیعی خودشان
# --owner/--group=0 لازم است چون tar وگرنه مالک ویندوزی (uid 197121) را ثبت
#   می‌کند و tar سمت سرور با root پیش‌فرضش --same-owner است.
# --transform: پوشه‌ی داخل آرشیو کوتاه و lowercase شود.
# devserver.py: خود PANEL.md می‌گوید هرگز deploy نشود.
# نام فایل عمداً بدون نسخه است تا لینک
# releases/latest/download/farshub-tunnel.tar.gz همیشه معتبر بماند؛ نسخه در
# tag و عنوان ریلیز ثبت می‌شود.
tarball="$out_dir/$PKG.tar.gz"
work=$(mktemp -d) || die 'ساخت پوشه‌ی موقت ناموفق بود.'
trap 'rm -rf "$work"' EXIT HUP INT TERM

tar -cf "$work/a.tar" -C "$root/.." \
    --owner=0 --group=0 --numeric-owner \
    --transform="s,^$name,$PKG," \
    --mode=755 \
    "$name/bin"

tar -cf "$work/b.tar" -C "$root/.." \
    --owner=0 --group=0 --numeric-owner \
    --transform="s,^$name,$PKG," \
    --exclude="$name/bin" \
    --exclude='.claude' \
    --exclude='web/devserver.py' \
    --exclude='__pycache__' \
    --exclude='*.pyc' \
    --exclude='.DS_Store' \
    --exclude='Thumbs.db' \
    --exclude='*.tar.gz' \
    "$name"

tar -Af "$work/a.tar" "$work/b.tar"
gzip -9c "$work/a.tar" >"$tarball"

files=$(tar -tzf "$tarball" | grep -vc '/$')
size=$(wc -c <"$tarball")
sum=$(sha256sum "$tarball" | cut -d' ' -f1)

say "بسته ساخته شد: $tarball"
say "  نسخه   : $ver"
say "  حجم    : $((size / 1024)) KB  ($files فایل)"
say "  sha256 : $sum"
say ''
say 'انتشار روی گیت‌هاب:'
say "  gh release create v$ver \"$tarball\" -t \"FarsHub Tunnel $ver\""
say ''
say 'روی سرور:'
say "  tar -xzf $PKG.tar.gz"
say "  md5sum $PKG/bin/farshub-core        # باید $want باشد"
say "  sudo $PKG/bin/farshub install server"
