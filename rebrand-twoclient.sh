#!/usr/bin/env bash
# ============================================================
# rebrand-twoclient.sh
# Rebrand "OneClient" -> "Twoclient" (string yang tampil ke user saja).
#
# Kenapa script, bukan patch:
#   - gak butuh nomor baris / konteks persis  -> tahan beda versi repo
#   - file gak ada / pola gak ketemu          -> WARN, bukan gagal total
#   - dijalankan dua kali                     -> no-op (idempotent)
#
# Aman dijalankan di atas tree yang sudah ada patch offline-account.
# Enum internal (ClusterKind::OneClient dll), data-dir (~/.OneClient),
# IPC, URL Polyfrost, dan parsing export lama SEMUA GAK DISENTUH.
#
# Pemakaian:
#   bash rebrand-twoclient.sh                            # repo = folder sekarang
#   bash rebrand-twoclient.sh ~/Projects/mc/OneLauncher
#
# Revert kalau ada yang aneh:
#   git checkout -- packages                             # semua
#   git checkout -- packages/oneclient_core/src/relocate.rs   # per file
# ============================================================
set -uo pipefail

REPO="${1:-.}"
cd "$REPO" 2>/dev/null || { printf 'ERROR: gak bisa masuk direktori: %s\n' "$REPO"; exit 1; }

if [ ! -f packages/oneclient_app/Cargo.toml ]; then
  printf 'ERROR: packages/oneclient_app/Cargo.toml gak ada.\n'
  printf 'Jalankan script ini dari ROOT repo (folder yang punya packages/, Cargo.toml, distribution/, dll).\n'
  exit 1
fi

say()  { printf '\n\033[1;32m==>\033[0m %s\n' "$*"; }
okm()  { printf '  \033[32m[ok]\033[0m   %s\n' "$*"; }
skm()  { printf '  \033[36m[skip]\033[0m %s\n' "$*"; }
wnm()  { printf '  \033[33m[warn]\033[0m %s\n' "$*"; }

OK=0; SKIP=0; WARN=0

# repl <file> <sed-expr> <pola-lama> <penanda-sudah-direbrand> <label>
repl() {
  local f="$1" expr="$2" old="$3" donemark="$4" label="$5"
  if [ ! -f "$f" ]; then
    wnm "$label — FILE GAK ADA: $f (beda versi? dilewatin)"; WARN=$((WARN+1)); return
  fi
  if grep -qF -- "$old" "$f"; then
    if sed -i "$expr" "$f"; then
      okm "$label ($f)"; OK=$((OK+1))
    else
      wnm "$label — sed gagal di $f"; WARN=$((WARN+1))
    fi
  elif grep -qF -- "$donemark" "$f"; then
    skm "$label — udah direbrand ($f)"; SKIP=$((SKIP+1))
  else
    wnm "$label — pola gak ketemu di $f (beda versi? cek manual)"; WARN=$((WARN+1))
  fi
}

say "1/4 Blanket: semua 'OneClient' -> 'Twoclient' (file yang isinya murni string display/komentar)"
BLANKET=(
  packages/oneclient_app/lang/en_us.json
  packages/oneclient_auth/src/diagnostics.rs
  packages/oneclient_auth/src/msa.rs
  packages/oneclient_net/src/error.rs
  packages/oneclient_net/src/service.rs
  packages/oneclient_polyplus/src/session.rs
  packages/oneclient_content/src/modpacks/share.rs
  packages/oneclient_core/src/game/launch.rs
  packages/oneclient_mc/src/arguments.rs
  packages/oneclient_discord/src/lib.rs
  packages/oneclient_app/build.rs
  packages/oneclient_app/src/constants.rs
  packages/oneclient_app/src/view/onboarding/language.rs
  packages/oneclient_core/src/migration/launchers/import.rs
  packages/oneclient_core/src/migration/launchers/modrinth_app.rs
  packages/oneclient_java/src/install.rs
  packages/oneclient_content/src/packages/bad_mods.rs
  packages/oneclient_core/src/game/shared_dir.rs
  packages/oneclient_app/src/file_content.rs
)
for f in "${BLANKET[@]}"; do
  repl "$f" 's/OneClient/Twoclient/g' "OneClient" "Twoclient" "blanket"
done

say "2/4 Quoted-only: cuma \"OneClient\" yang di-quote (enum/identifier gak disentuh)"
QUOTED=(
  packages/oneclient_app/src/view/app/clusters/page.rs
  packages/oneclient_app/src/view/app/clusters/instance/steps.rs
  packages/oneclient_app/src/view/app/clusters/export_instance.rs
  packages/oneclient_app/src/view/app/clusters/instance/copy.rs
  packages/oneclient_app/src/view/app/clusters/instance/edit.rs
  packages/oneclient_app/src/view/app/clusters/instance/create.rs
  packages/oneclient_app/src/components/active_cluster_panel.rs
  packages/oneclient_core/src/migration/mod.rs
)
for f in "${QUOTED[@]}"; do
  repl "$f" 's/"OneClient"/"Twoclient"/g' '"OneClient"' '"Twoclient"' "quoted"
done

say "3/4 String khusus (mid-string / format / Cargo.toml / installer)"
repl packages/oneclient_app/src/view/app/clusters/instance/create.rs \
  's/format!("OneClient · {version}")/format!("Twoclient · {version}")/' \
  'format!("OneClient · {version}")' 'format!("Twoclient · {version}")' "judul versi cluster"
repl packages/oneclient_core/src/sharing/mod.rs \
  's/"it was shared from a newer OneClient (format {}). Update OneClient to import it."/"it was shared from a newer Twoclient (format {}). Update Twoclient to import it."/' \
  '"it was shared from a newer OneClient' '"it was shared from a newer Twoclient' "pesan sharing versi baru"
repl packages/oneclient_core/src/sharing/mod.rs \
  's/"the file is not a OneClient instance export"/"the file is not a Twoclient instance export"/' \
  '"the file is not a OneClient instance export"' '"the file is not a Twoclient instance export"' "pesan export salah format"
# catatan: "the cloud copy is not a OneClient instance" cuma ada di sync/mod.rs,
# bukan di sharing/mod.rs — makanya gak ada entrinya di sini.
repl packages/oneclient_core/src/sync/mod.rs \
  's/"the cloud copy is not a OneClient instance"/"the cloud copy is not a Twoclient instance"/' \
  '"the cloud copy is not a OneClient instance"' '"the cloud copy is not a Twoclient instance"' "pesan sync"
repl packages/oneclient_app/src/layout/settings_shell.rs \
  's/"OneClient v"/"Twoclient v"/' \
  '"OneClient v"' '"Twoclient v"' "label versi di settings (concat!)"
repl packages/oneclient_core/src/relocate.rs \
  's/OneClient keeps track of one old folder at a time./Twoclient keeps track of one old folder at a time./' \
  'OneClient keeps track of one old folder' 'Twoclient keeps track of one old folder' "pesan relocate (folder lama)"
repl packages/oneclient_core/src/relocate.rs \
  's/Restart OneClient to finish it./Restart Twoclient to finish it./' \
  'Restart OneClient to finish it.' 'Restart Twoclient to finish it.' "pesan relocate (restart)"
repl packages/oneclient_app/Cargo.toml \
  's/This build of OneClient needs/This build of Twoclient needs/' \
  'This build of OneClient needs' 'This build of Twoclient needs' "pesan installer NSIS (VC++ redist)"
repl packages/oneclient_app/Cargo.toml \
  's/^product-name = "OneClient"/product-name = "Twoclient"/' \
  'product-name = "OneClient"' 'product-name = "Twoclient"' "packager product-name"
# description crate: app & net diawali "OneClient", macro/events/discord
# OneClient-nya di tengah kalimat (masing2 cuma 1 kemunculan di file) ->
# makanya macro/events/discord pakai blanket per-file.
repl packages/oneclient_app/Cargo.toml \
  's/^description = "OneClient/description = "Twoclient/' \
  'description = "OneClient' 'description = "Twoclient' "crate description (app)"
repl packages/oneclient_net/Cargo.toml \
  's/^description = "OneClient/description = "Twoclient/' \
  'description = "OneClient' 'description = "Twoclient' "crate description (net)"
repl packages/oneclient_macro/Cargo.toml \
  's/OneClient/Twoclient/g' 'OneClient' 'Twoclient' "crate description (macro)"
repl packages/oneclient_events/Cargo.toml \
  's/OneClient/Twoclient/g' 'OneClient' 'Twoclient' "crate description (events)"
repl packages/oneclient_discord/Cargo.toml \
  's/OneClient/Twoclient/g' 'OneClient' 'Twoclient' "crate description (discord)"

say "4/4 Verifikasi"
LEFT=$(grep -rEn --include='*.rs' "ClusterKind::OneClient|TypeChoice::OneClient|ExportMode::OneClient|Filter::OneClient|MigrationSource::OneClientV1|OneClient = 0" packages | wc -l)
printf '  Identifier enum tersisa (HARUS > 0 biar compile aman): %s\n' "$LEFT"
if [ "$LEFT" -eq 0 ]; then
  wnm "BAHAYA: enum identifier hilang semua — kemungkinan salah replace. Revert: git checkout -- packages"
fi
BAD=$(grep -rEn --include='*.rs' "::Twoclient|TwoclientV1|enum Twoclient" packages | wc -l)
printf '  Kebocoran ke identifier (HARUS = 0): %s\n' "$BAD"
if [ "$BAD" -gt 0 ]; then
  wnm "ADA 'Twoclient' yang nyempluk ke identifier — cek baris di atas, revert file terkait"
fi
python3 -m json.tool packages/oneclient_app/lang/en_us.json > /dev/null 2>&1 \
  && okm "en_us.json masih JSON valid" \
  || wnm "en_us.json GAK valid sebagai JSON — cek!"
printf '  Sisa "OneClient" di packages (internal/IPC/URL/legacy/test — angka bebas, ini buat review): '
grep -rn --include='*.rs' --include='*.json' --include='*.toml' "OneClient" packages | wc -l

printf '\n'
printf '\033[1;32m==>\033[0m Ringkasan: %d ok, %d skip (udah direbrand), %d warn\n' "$OK" "$SKIP" "$WARN"
if [ "$WARN" -gt 0 ]; then
  printf '\033[33mSelesai dengan %d warning — baca baris [warn] di atas. Rebrand tetap jalan buat bagian yang match.\033[0m\n' "$WARN"
else
  printf '\033[32mRebrand beres semua. Review hasil: git diff --stat, lalu build ulang.\033[0m\n'
fi
