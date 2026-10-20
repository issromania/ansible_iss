#!/usr/bin/env bash
# Download the latest LibreOffice "stable" x86_64 RPM set from TDF and stage
# the RPMs for Ansible in $DEST (default ~/ansible/additions/libreoffice):
#   $DEST/rpms/*.rpm   - RPMs to install (exclusions already removed)
#   $DEST/meta.yml     - lo_version, lo_branch, lo_packages (published by
#                        issrepo_publish_libreoffice.sh, read by the task)
# Idempotent: exits 0 without downloading if the latest version is already staged.
set -euo pipefail

BASE=https://download.documentfoundation.org/libreoffice/stable
DEST=${DEST:-$HOME/ansible/additions/libreoffice/dist}
DEST=${DEST%/}   # a trailing slash would put the work dir inside $DEST and break the final swap
HELP_LANGS=(en-US ro)
LANG_PACKS=(en-GB ro)
EXCLUDE_RE='.*(mediawiki-publisher|onlineupdate|beanshell|dict-es).*'

die() { echo "ERROR: $*" >&2; exit 1; }

# Content identity of an RPM, ignoring build time and file mtimes: TDF ships the
# same package rebuilt minutes apart in several tarballs (e.g. dict-en).
rpmsig() {
    rpm -qp --qf '%{NEVRA}\n[R %{REQUIRENEVRS}\n][P %{PROVIDENEVRS}\n][C %{CONFLICTNEVRS}\n][O %{OBSOLETENEVRS}\n]' "$1" &&
    rpm -qp --scripts "$1" &&
    rpm -qp --dump "$1" | awk '{$3=""; print}'
}

ver=$(curl -fsSL "$BASE/" \
      | grep -oE 'href="[0-9]+(\.[0-9]+){2}/"' \
      | grep -oE '[0-9]+(\.[0-9]+){2}' \
      | sort -uV | tail -n1)
[[ -n $ver ]] || die "cannot determine latest version from $BASE/"

if [[ -f $DEST/meta.yml ]] && grep -qx "lo_version: \"$ver\"" "$DEST/meta.yml"; then
    echo "LibreOffice $ver already staged in $DEST"
    exit 0
fi

prefix="LibreOffice_${ver}_Linux_x86-64_rpm"
files=("${prefix}.tar.gz")
for l in "${HELP_LANGS[@]}"; do files+=("${prefix}_helppack_${l}.tar.gz"); done
for l in "${LANG_PACKS[@]}"; do files+=("${prefix}_langpack_${l}.tar.gz"); done

mkdir -p "$(dirname "$DEST")"
work=$(mktemp -d "$DEST.work.XXXXXX")   # same filesystem as $DEST -> atomic mv
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/extract" "$work/stage/rpms"

for f in "${files[@]}"; do
    url="$BASE/$ver/rpm/x86_64/$f"
    echo "Downloading $f"
    curl -fsSL --retry 3 -o "$work/$f" "$url"
    sum=$(curl -fsSL "$url.sha256" | awk '{print $1}' || true)
    [[ $sum =~ ^[0-9a-f]{64}$ ]] || die "no sha256 published for $f"
    echo "$sum  $work/$f" | sha256sum -c --quiet - || die "sha256 mismatch for $f"
    tar -xzf "$work/$f" -C "$work/extract"
    rm -f "$work/$f"
done

# The same RPM can ship in several tarballs (e.g. dict-en in main and en-GB langpack).
# Sorted order makes the main tarball's copy win; later copies must have identical
# content (rpmsig) or the run is refused.
while IFS= read -r -d '' r; do
    t=$work/stage/rpms/${r##*/}
    if [[ -e $t ]]; then
        sig_new=$(rpmsig "$r")
        sig_old=$(rpmsig "$t")
        [[ $sig_new == "$sig_old" ]] || die "different content in RPMs with the same name: ${r##*/}"
        echo "Duplicate (same content, kept first): ${r#"$work/extract/"}"
        continue
    fi
    mv "$r" "$t"
done < <(find "$work/extract" -type f -name '*.rpm' -print0 | LC_ALL=C sort -z)
echo "Excluded:"
find "$work/stage/rpms" -regextype posix-extended -regex "$EXCLUDE_RE" -print -delete

# Install list for Ansible. The branch must be part of the package names:
# the task removes other branches by name.
branch=${ver%.*}
mapfile -t names < <(rpm -qp --qf '%{NAME}\n' "$work"/stage/rpms/*.rpm 2>/dev/null | sort -u)
printf '%s\n' "${names[@]}" | grep -qxF "libobasis${branch}-core" \
    || die "libobasis${branch}-core not among staged RPMs; package naming assumption broken"

{
    echo "---"
    echo "lo_version: \"$ver\""
    echo "lo_branch: \"$branch\""
    echo "lo_packages:"
    printf '  - %s\n' "${names[@]}"
} >"$work/stage/meta.yml"

rm -rf "$DEST.old"
[[ -d $DEST ]] && mv "$DEST" "$DEST.old"
mv "$work/stage" "$DEST"
rm -rf "$DEST.old"

echo "Staged LibreOffice $ver: ${#names[@]} packages in $DEST"
echo "Next: sudo issrepo_publish_libreoffice.sh"
