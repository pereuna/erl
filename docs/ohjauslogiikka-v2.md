# Ohjauslogiikka v2 (skeleton)

## Tavoite
- Erottaa nykyinen ohjauslogiikka selkeisiin vaiheisiin (data, päätös, toimeenpano).
- Mahdollistaa suuret logiikkamuutokset ilman tuotantopolun rikkoutumista.

## Nykytila (v1) lyhyesti
- `quarter_worker` koordinoi varttiajon.
- `trig` muodostaa vartin avaimella toimivan ohjauspäätöksen.
- `entso_run` rakentaa suunnitelman hintojen ja lämpötilojen perusteella.

## V2-suunnitelma

### 1) Rajapinnat ja datamalli
- [ ] Määritä yhteinen päätösrakenne (`charge` / `discharge` / `normal` + metatiedot).
- [ ] Määritä syötedatan validoinnit (prices/temps puuttuvat arvot).

### 2) Päätöksentekokerros
- [ ] Irrota päätöksenteko omaksi moduuliksi (`control_logic_v2`).
- [ ] Lisää mahdollisuus useille strategioille (esim. konservatiivinen/aggressiivinen).

### 3) Toimeenpano (GPIO)
- [ ] Rajaa GPIO-komennot adapteriin, jotta päätöslogiikka on testattava ilman laitetta.
- [ ] Lisää dry-run-tila kehitystä varten.

### 4) Käyttöönotto
- [ ] Feature flag (v1/v2 valinta konfiguraatiolla).
- [ ] Turvallinen fallback v1-logiikkaan virhetilanteissa.

## Testausrunko
- [ ] Yksikkötestit päätöksentekokerrokselle.
- [ ] Integraatiotesti: päivän `prices.txt` + `temps.txt` -> päätöstaulu.
- [ ] Smoke-testi: release käyntiin ja varttikierros ilman poikkeuksia.

## Muutosloki
- 2026-05-19: Skeleton-dokumentti luotu haaralle `feat/ohjauslogiikka-v2`.
