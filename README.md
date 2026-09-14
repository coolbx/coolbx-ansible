# coolbx-ansible — toestelconfig voor Coolbx OS

> **Deze repo is publiek.** Alles wat geheim is (LDAP-certificaat, wachtwoorden, Chrome-token,
> beheerderswachtwoord) hoort **uitsluitend** in de versleutelde `vault.yml`. Nooit ergens anders.

## Wat is dit?

Coolbx OS maakt van een gewone laptop een beheerd schooltoestel (zoals een Chromebook). Het
besturingssysteem zelf komt als kant-en-klaar *image*. Deze repo is de **instellingenlaag**
erbovenop: welke kiosk-apps een toestel krijgt, welk browserbeleid, welke bureaubladinstellingen,
welke extra programma's, welke printers, en wie mag aanmelden. Elk toestel haalt deze instellingen
regelmatig zelf op uit git (`ansible-pull`) en past ze toe. Geen server, geen agent, geen licentie.

## De drie lagen

| Laag | Waar | Wat |
|---|---|---|
| **Image** | coolbx-os (bootc) | software, beveiliging, rol-standaard (leerling / leerkracht / gedeeld) |
| **Toestel** | *deze repo* + `/etc/coolbx/device.yaml` op het toestel | kiosk-apps, browserbeleid, dconf, flatpaks, printers, Google-login, geheimen |
| **Gebruiker** | Google Admin-console | bladwijzers, extensies, instellingen per gebruiker/groep |

## Hoe weet een toestel wat het moet doen?

Het toestel geeft bij elke pull door: zijn **rol** (uit `device.yaml`), een eventueel **profiel**,
zijn **kanaal**, zijn **serienummer** (BIOS) en zijn **hostnaam**. De rol `device-identity` bepaalt dan:

1. staat het toestel in `devices.yml` (op serienummer, anders op hostnaam)? → dat profiel;
2. anders: staat er een `profile:` in `/etc/coolbx/device.yaml`? → dat profiel;
3. anders: `<rol>-standaard` (bv. `leerling-standaard`).

Het profiel wordt bovenop `profiles/basis.yml` gelegd (dicts samengevoegd, lijsten aangevuld).

## Een toestel toevoegen

Voeg een regel toe aan `devices.yml`:

```yaml
devices:
  - serial: "5CD1234ABC"          # BIOS-serienummer: cat /sys/class/dmi/id/product_serial
    name: lln-3a-07
    profile: leerling-standaard
    channel: stabiel
    powerwash: false
```

Het serienummer vind je ook via `coolbx-status` op het toestel. Een toestel dat **niet** in de lijst
staat werkt gewoon: het krijgt het standaardprofiel van zijn rol. De lijst is dus alleen nodig voor
afwijkingen (ander profiel, powerwash op afstand).

`powerwash: true` laat het toestel zichzelf wissen bij de volgende herstart zonder aangemelde
gebruiker. Zet de vlag daarna terug op `false`.

## Een profiel maken

Kopieer een bestaand profiel in `profiles/` (bv. `leerling-standaard.yml` → `leerling-3degraad.yml`)
en pas aan. Beschikbare sleutels (zie `profiles/basis.yml` voor voorbeelden):

| Sleutel | Doet |
|---|---|
| `kiosk_apps` | vergrendelde web-apps (launcher "Toetsmodus"-stijl); `allow_domains` beperkt het surfen |
| `chrome_policies` | Chrome/Chromium-beleid van het toestel (JSON in `/etc/chromium/policies/managed/`) |
| `dconf`, `dconf_locks` | GNOME-instellingen (systeemwaarden) en welke de gebruiker niet mag wijzigen |
| `flatpaks` | extra programma's uit Flathub (systeembreed; nooit automatisch verwijderd) |
| `printers` | CUPS-printers (`name`, `uri`, `model` of `ppd`, `default`) |
| `google_login` | wie mag aanmelden: domein, LDAP-zoekbases, Google-groepen (weglaten = geen Google-login) |

Wijs het profiel toe via `devices.yml` of via `profile:` in `device.yaml` op het toestel.

## Kanalen: eerst testen, dan uitrollen

- Toestellen met kanaal **`test`** volgen de branch **`testing`**.
- Toestellen met kanaal **`stabiel`** volgen **`main`**.

Werkwijze: wijziging → pull request naar `testing` → controleren op een testtoestel → mergen naar `main`.

## Geheimen (vault)

Alle geheimen staan in `vault.yml`, versleuteld met [ansible-vault](https://docs.ansible.com/ansible/latest/vault_guide/index.html).
Het plaintext-sjabloon is `vault.example.yml`.

1. Zet de bronbestanden in `~/.config/coolbx/secrets/` (zie de kop van `scripts/make-vault.sh`).
2. Draai `scripts/make-vault.sh`. Dit maakt (eenmalig) een vault-wachtwoord aan in
   `~/.config/coolbx/secrets/vault-pass` en schrijft `vault.yml`.
3. Commit **alleen** `vault.yml`. Het wachtwoord komt op elk toestel in `/etc/coolbx/vault-pass`
   (root-only; de installer zet het) en staat **nooit** in git.

Zonder vault-wachtwoord draait de playbook nog steeds; rollen die geheimen nodig hebben (Chrome-
inschrijving, Google-login, beheerderswachtwoord) slaan dan over met een melding.

## Testen

Vereist `ansible-core` (bv. `pip install ansible-core` of `dnf install ansible-core`).

```bash
# Syntax
ansible-playbook --syntax-check local.yml

# Dry-run als leerling-toestel (verandert niets, toont wat er zou gebeuren)
sudo ansible-playbook local.yml --check --diff \
  -e coolbx_role=leerling -e coolbx_profile= -e coolbx_channel=stabiel \
  -e coolbx_serial= -e coolbx_hostname="$(hostname -s)" \
  --vault-password-file ~/.config/coolbx/secrets/vault-pass   # optioneel

# Lint (zoals de CI)
yamllint --strict . && ansible-lint
```

Op een toestel: `sudo /usr/libexec/coolbx-ansible-pull` (of wacht op de timer). De status staat in
`/var/lib/coolbx/ansible-status.json` en in `coolbx-status`.

## Structuur

```
local.yml            entry voor ansible-pull (ansible.cfg + inventory.yml: alleen localhost)
devices.yml          platte toestellijst (serienummer → profiel)
profiles/            basis.yml + één bestand per profiel
roles/               device-identity, kiosk-apps, dconf, chrome, google-login,
                     flatpaks, printers, admin-user, powerwash
vault.yml            geheimen (versleuteld) — vault.example.yml is het sjabloon
scripts/make-vault.sh
```

Ontwerp en het waarom: `DESIGN.md` en de ADRs in de coolbx-os-repo (`docs/adr/0029` t/m `0034`).
