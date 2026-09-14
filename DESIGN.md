# Ontwerp v3 — config-repo van Coolbx OS

> Vervangt het OU-boom-ontwerp van 29 juni 2026. De beslissingen en het waarom staan in de
> coolbx-os-repo: `docs/ROADMAP.md` §3 en ADR-0029 (kiosk-apps), 0031 (accountmodel),
> 0032 (config-naad), 0033 (Chrome Enterprise Core), 0034 (powerwash).

## Principe

Drie lagen, elk met één bron:

1. **Image** (bootc, coolbx-os): software, hardening, rol-standaard. Onveranderlijk, gesigneerd.
2. **Toestel** (deze repo): *runtime*-config die zonder image-rebuild mag wijzigen. Het toestel
   trekt ze zelf (`ansible-pull`), idempotent, elke run convergeert naar de gewenste staat.
3. **Gebruiker** (Google Admin-console): browserbeleid per gebruiker/groep.

Strikte grens: hier **nooit** software- of kernconfig (dat is het image).

## Identiteit: geen OU-boom, wel een platte lijst

- Het toestel kent zijn **rol** (`leerling` | `leerkracht` | `gedeeld`), optioneel **profiel** en
  **kanaal** uit `/etc/coolbx/device.yaml` (default uit het image, ingevuld door de installer).
- `devices.yml` is een platte lijst: serienummer → naam, profiel, kanaal, powerwash-vlag.
  Hostnaam is de fallback-sleutel (VM's zonder bruikbaar BIOS-serienummer).
- Resolutie (`roles/device-identity`): `devices.yml`-match > `device.yaml`-profiel > `<rol>-standaard`.
- Kanaal → git-branch (`test` → `testing`, `stabiel` → `main`) kiest het toestel zelf, vóór de pull.

## Profielen: data, geen code

`profiles/basis.yml` + `profiles/<naam>.yml` → één `cfg`-dict (`combine(recursive=True,
list_merge='append')`). De rollen zijn generiek en lezen alleen `cfg`:

| Rol | Leest | Schrijft / doet |
|---|---|---|
| kiosk-apps | `cfg.kiosk_apps` | `/etc/coolbx/kiosk-apps.d/<id>.yaml`, dan `coolbx-kiosk-apps apply` |
| dconf | `cfg.dconf`, `cfg.dconf_locks` | `/etc/dconf/db/local.d/50-coolbx-profile` (+locks), `dconf update` |
| chrome | vault `chrome_enrollment_token`, `cfg.chrome_policies` | enrollment-token, `coolbx-profile.json` |
| google-login | `cfg.google_login`, vault LDAP-geheimen | config.yaml + access + cert/key, dan `coolbx-google-login-apply` |
| flatpaks | `cfg.flatpaks` | system-flatpaks uit Flathub (alleen installeren) |
| printers | `cfg.printers` | `lpadmin` |
| admin-user | vault `admin_password_hash` | wachtwoord van beheerder `coolbx` |
| powerwash | `coolbx_device.powerwash` | `coolbx-powerwash request --reboot-if-idle` |

Elke rol is idempotent (tweede run: `changed=0`), werkt in `--check`, en slaat netjes over als
het bijhorende OS-commando ontbreekt (dev-machine, CI-container).

## Geheimen

De repo is publiek. Alles geheims zit in `vault.yml` (ansible-vault). Het vault-wachtwoord staat
enkel op de toestellen (`/etc/coolbx/vault-pass`, root-only, door de installer) en bij de beheerder
(`~/.config/coolbx/secrets/vault-pass`). `scripts/make-vault.sh` bouwt de vault; `vault.example.yml`
documenteert de sleutels. Zonder wachtwoord draait de playbook door en slaan geheim-afhankelijke
rollen over. Advies uit ADR-0032 blijft: overweeg de repo privé te zetten.

## Afhankelijkheden

Alleen `ansible.builtin` — het image heeft enkel `ansible-core`, geen collections.
`requirements.yml` (community.general) is optioneel, voor lint en toekomstige rollen.

## Bewust uitgesteld

Beheer-UI / centrale registry (schrijft later gewoon `devices.yml`), centrale status-aggregatie,
OU-boom (de platte lijst dekt de behoefte; Google levert de groepen).
