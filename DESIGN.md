# Coolbx Ansible — ontwerp & architectuur

> Status: **ontwerp vastgelegd na brainstorm (29 jun 2026), nog niet gebouwd.** Dit document is de
> blauwdruk + handoff voor de implementatie. De repo bevat momenteel nog de oude POC-structuur
> (`local.yml` + `playbooks/`) die hierdoor vervangen wordt.

## Doel & visie
De **mutabele configuratielaag** van de Coolbx-vloot: per-groep/leerjaar-config die wijzigt **zonder
image-rebuild**. Mikt op "een betere Intune" voor scholen:
- **Git + PR + CI** i.p.v. een cloud-klik-GUI → alles reviewbaar, diff-baar, terugdraaibaar.
- **Pull-model**: elk toestel draait `ansible-pull` lokaal vanuit deze git-repo → geen cloud, geen
  agent, geen per-toestel-licentie, oneindig schaalbaar.
- **Idempotent + convergent**: ansible herstelt elk uur de gewenste staat → drift heelt zichzelf.
- **Transparant**: je leest exact wat elk toestel doet (geen black box).

## Kernprincipe: twee lagen
| Laag | Wat | Eigenschap |
|---|---|---|
| **Image** (bootc, coolbx-os) | OS, software-basis, security, branding-defaults, **wifi/eduroam-secrets** | onveranderlijk, gesigneerd, atomair, rollback |
| **Ansible** (deze repo, pull) | per-OU **deltas**: printers, per-groep-apps, dconf, netwerk-toggles | veranderbaar zonder rebuild, in git |

Strikte grens: ansible doet de **verschillen** per OU; het image de **universele basis**. Nooit
software-/kernconfig in ansible.

## Ontwerpbeslissingen (brainstorm 29 jun)
1. **Targeting = vrije OU-boom + kanaal.** Geen vaste `rol>graad>leerjaar`-niveaus, maar een
   school-gedefinieerde OU-boom (vrije namen/diepte), zoals Google Workspace OU's. Plus een **kanaal**
   (`test`/`stabiel`) voor gefaseerde uitrol (analoog aan de image-`:testing`/`:stable`).
2. **Scope = 4 rollen:** `printers`, `flatpaks` (per-groep software), `dconf-policy` (desktop),
   `network` (wifi-toggles + restricties per OU).
3. **Flatpak = hybride.** Ansible installeert beheerde apps **system-wide** (`--system`, overleven de
   gastsessie-reset); de gebruiker behoudt vrijheid om zelf **user-flatpaks** te installeren (verdwijnen
   bij reset op gast-toestellen = fris voor volgende leerling; blijven op niet-resettende toestellen).
   Mogelijke per-OU-toggle om user-installs te beperken (bv. 1e graad uit, 3e graad aan).
4. **Identiteit = lokaal `/etc/coolbx/fleet.yaml`** met `ou:` (vrij pad) + `kanaal:`. De puller leest
   dit; het maakt niet uit hóé het bestand er kwam (FOG/IT nu, registry/UI later). **Registry/UI-klaar.**
5. **Geheimen = ansible-vault** + vangrails: vault minimaal (alleen netwerk-secrets), sleutel in het
   gesigneerde image (fast-follow: **TPM-sealen**, ADR-0013-lijn), rotatie-runbook verplicht, géén
   per-gebruiker-eduroam-creds. Blast-radius = enkel netwerktoegang; herstel = roteren.
6. **CI = basis + dry-run.** Op elke PR: `yamllint` + `ansible-lint` + `ansible-playbook --syntax-check`
   + een `--check` (dry-run) tegen een Fedora-container per OU/rol.
7. **Observability = lokaal nu, UI-klaar.** Elke pull schrijft gestructureerde status (journald +
   statusbestand) die `coolbx-status` toont; formaat klaar voor latere centrale aggregatie.

## Architectuur

### OU-boom & laag-motor (data-gedreven rollen)
Een toestel draagt een **OU-pad** (bv. `leerkrachten/lagere-school` of `leerlingen/2egraad/3jaar`).
`local.yml` splitst dat pad en stapelt **vars** van algemeen naar specifiek:
```
common  →  <segment-1>  →  <segment-1>/<segment-2>  →  ...
```
Elke laag levert **data** (welke printers, welke flatpaks, welke dconf-keys). De **rollen zijn generiek
en data-gedreven**: ze draaien altijd en consumeren de samengevoegde vars. Zo bepaalt de school de boom
(namen/diepte) puur via data, zonder de rollen aan te raken.

### `/etc/coolbx/fleet.yaml` (identiteit, op het toestel)
```yaml
ou: leerlingen/2egraad/3jaar   # vrij pad; bepaalt de config-lagen
kanaal: stabiel                # of: test
```

### Kanaal → git-branch
De puller kiest de branch op basis van `kanaal`: `test` → `testing`-branch, `stabiel` → `main`.
Test-toestellen krijgen wijzigingen eerst; merge `testing`→`main` na verificatie.

## Repo-structuur (te bouwen)
```
coolbx-ansible/
  local.yml                     # entry: lees fleet.yaml → bouw OU-lagen → draai rollen
  requirements.yml              # collections (community.general)
  ansible.cfg
  roles/
    printers/                   # generiek, data-gedreven (vars: printers: [...])
    flatpaks/                   # system-flatpaks (vars: flatpaks: [...])
    dconf-policy/               # dconf-keys (vars: dconf: {...})
    network/                    # wifi-toggles/restricties (vars: ...)
  ou/                           # vars per OU-knoop — de SCHOOL vult deze vrij in
    common.yml
    leerlingen.yml
    leerlingen/2egraad.yml
    ...
  group_vars/ | vars/           # laag-overerving-glue
  vault/                        # ansible-vault secrets (netwerk)
  .github/workflows/ci.yml      # lint + syntax + dry-run
  README.md  DESIGN.md
```

## OS-kant (aanpassing in coolbx-os `fleet`-feature)
- `coolbx-ansible-pull` laten lezen uit **`/etc/coolbx/fleet.yaml`** (`ou` + `kanaal`) i.p.v. enkel
  `laptop-group`; `ou` + `kanaal` als extra-vars meegeven.
- **Kanaal → branch** kiezen in de `ansible-pull -C <branch>`-aanroep.
- Gestructureerde pull-status wegschrijven voor `coolbx-status`.
- Flathub-remote system-wide beschikbaar (image-basis of via de `flatpaks`-rol).

## Bewust uitgesteld
- **Beheer-UI / centrale registry** (OU's toewijzen à la Google Workspace, compliance-dashboard).
  Komt later; vermoedelijk een **aparte beheer-laag** (`coolbx-console`/`coolbx-fleet`) die infra deelt
  met Focus maar onafhankelijk blijft. Het datamodel hierboven is er klaar voor: de UI hoeft enkel
  `fleet.yaml` te zetten + de OU-vars te beheren.

## Volgende stap
Scaffold het repo-skelet (één voorbeeld-OU + één werkende rol), dan de OS-kant. Daarna de school de
OU-boom laten invullen.
