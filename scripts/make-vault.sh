#!/usr/bin/env bash
# Coolbx OS — bouwt vault.yml (ansible-vault-versleuteld) uit lokale geheimen.
#
# Leest uit $SECRETS_DIR (default ~/.config/coolbx/secrets/):
#   ldap-client.crt           Google Secure LDAP-clientcertificaat (PEM)
#   ldap-client.key           bijhorende sleutel (PEM)
#   ldap-access.txt           regel 1 = LDAP-gebruikersnaam, regel 2 = wachtwoord
#   chrome-enrollment.txt     Chrome Enterprise Core-token
#   admin-password-hash.txt   optioneel: sha512-crypt-hash (`openssl passwd -6`) voor beheerder coolbx
#   vault-pass                vault-wachtwoord; wordt aangemaakt (openssl rand) als het ontbreekt
#
# Schrijft: <repo>/vault.yml. Print NOOIT geheimen. Het vault-wachtwoord hoort op elk toestel in
# /etc/coolbx/vault-pass (root-only, gezet door de installer) en NOOIT in git.
set -euo pipefail

SECRETS_DIR="${SECRETS_DIR:-$HOME/.config/coolbx/secrets}"
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO_DIR/vault.yml"
PASS_FILE="$SECRETS_DIR/vault-pass"

command -v ansible-vault >/dev/null || { echo "make-vault: ansible-vault niet gevonden (installeer ansible-core)" >&2; exit 1; }
[ -d "$SECRETS_DIR" ] || { echo "make-vault: map $SECRETS_DIR ontbreekt" >&2; exit 1; }
for f in ldap-client.crt ldap-client.key ldap-access.txt chrome-enrollment.txt; do
  [ -s "$SECRETS_DIR/$f" ] || { echo "make-vault: $SECRETS_DIR/$f ontbreekt of is leeg" >&2; exit 1; }
done
[ "$(wc -l < "$SECRETS_DIR/ldap-access.txt")" -ge 1 ] && [ "$(sed -n 2p "$SECRETS_DIR/ldap-access.txt")" != "" ] \
  || { echo "make-vault: ldap-access.txt verwacht 2 regels (gebruiker, wachtwoord)" >&2; exit 1; }

if [ ! -s "$PASS_FILE" ]; then
  umask 077
  openssl rand -base64 48 | tr -d '\n' > "$PASS_FILE"
  echo "make-vault: nieuw vault-wachtwoord aangemaakt in $PASS_FILE (bewaar dit veilig; zet het op de toestellen in /etc/coolbx/vault-pass)"
fi
chmod 0600 "$PASS_FILE"

# YAML met PEM-blokken als block-scalars; enkelregelige waarden als JSON-string (veilig gequote).
yaml_str() { python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()))'; }
yaml_block() { sed 's/^/  /'; }

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT
chmod 0600 "$TMP"
{
  echo "---"
  echo "# Gegenereerd door scripts/make-vault.sh — versleuteld met ansible-vault. Zie vault.example.yml."
  printf 'google_ldap_user: %s\n' "$(sed -n 1p "$SECRETS_DIR/ldap-access.txt" | yaml_str)"
  printf 'google_ldap_password: %s\n' "$(sed -n 2p "$SECRETS_DIR/ldap-access.txt" | yaml_str)"
  echo "google_ldap_cert: |"; yaml_block < "$SECRETS_DIR/ldap-client.crt"
  echo "google_ldap_key: |"; yaml_block < "$SECRETS_DIR/ldap-client.key"
  printf 'chrome_enrollment_token: %s\n' "$(yaml_str < "$SECRETS_DIR/chrome-enrollment.txt")"
  if [ -s "$SECRETS_DIR/admin-password-hash.txt" ]; then
    printf 'admin_password_hash: %s\n' "$(yaml_str < "$SECRETS_DIR/admin-password-hash.txt")"
  fi
} > "$TMP"

ansible-vault encrypt --vault-password-file "$PASS_FILE" --output "$OUT" "$TMP" >/dev/null
echo "make-vault: $OUT geschreven (versleuteld). Controleer met: ansible-vault view --vault-password-file $PASS_FILE $OUT | grep -o '^[a-z_]*:'"
