#!/usr/bin/env bash
# Publish the LibreOffice RPMs staged by libreoffice_prepare.sh into the ISS dnf
# repository served by monitor. Run with sudo.
#
# Layout (one repo per EL major; other components can later sit next to libreoffice/):
#   /var/www/html/issrepo/el9/x86_64/{repodata,libreoffice/*.rpm}
#   /var/www/html/issrepo/el10/x86_64/{repodata,libreoffice/*.rpm}
#   /var/www/html/issrepo/meta/libreoffice.yml   - read by the Ansible task
set -euo pipefail

die() { echo "ERROR: $*" >&2; exit 1; }
[[ $EUID -eq 0 ]] || die "run as root (sudo)"

SRC=${1:-$(getent passwd "${SUDO_USER:?pass the staging dir as argument}" | cut -d: -f6)/ansible/additions/libreoffice/dist}
SRC=${SRC%/}
REPO=/var/www/html/issrepo
ELS=(9 10)
ARCH=x86_64

for c in createrepo_c rsync restorecon; do
    command -v "$c" >/dev/null || die "$c not installed"
done
[[ -f $SRC/meta.yml && -d $SRC/rpms ]] || die "$SRC is not a staging directory"
compgen -G "$SRC/rpms/*.rpm" >/dev/null || die "no RPMs in $SRC/rpms"

# Repo-wide lock: anything that runs createrepo_c on issrepo must take it.
exec 9>/run/lock/issrepo.lock
flock -w 600 9 || die "issrepo is locked by another publisher"

for el in "${ELS[@]}"; do
    dir=$REPO/el$el/$ARCH
    install -d -m 0755 "$dir/libreoffice"
    # Add new RPMs and refresh metadata first, then drop the old ones and refresh
    # again: clients holding the previous metadata never hit a missing file.
    rsync -rt --chmod=F644 "$SRC/rpms/" "$dir/libreoffice/"
    createrepo_c --update -q "$dir"
    rsync -rt --chmod=F644 --delete "$SRC/rpms/" "$dir/libreoffice/"
    createrepo_c --update -q "$dir"
    echo "el$el: $(find "$dir/libreoffice" -name '*.rpm' | wc -l) LibreOffice RPMs"
done

restorecon -RF "$REPO"
# Metadata last: the Ansible task only asks for what is already in the repo.
install -D -m 0644 "$SRC/meta.yml" "$REPO/meta/libreoffice.yml"
restorecon -F "$REPO/meta/libreoffice.yml"
grep -E '^lo_version' "$REPO/meta/libreoffice.yml"
