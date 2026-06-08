# erl

This is a test project for Codex, Erlang, OpenBSD, and Raspberry Pi (RPi)
environments. The program controls detached-house heating based on outdoor
temperature and exchange electricity prices. The server is available at
https://jedi.ydns.eu.

## OTP release

Projektissa on `rebar3`/`relx`-release nimellä `quarter`. Release käynnistää
OTP-sovelluksen `quarter`, jonka callback-moduuli on `quarter_app`.

Kehitysbuild:

```sh
rebar3 release
```

Tuotantoprofiili:

```sh
rebar3 as prod release
```

Release löytyy buildin jälkeen esimerkiksi hakemistosta:

```text
_build/default/rel/quarter
```

tai tuotantoprofiililla:

```text
_build/prod/rel/quarter
```

Käynnistys foregroundissa:

```sh
_build/default/rel/quarter/bin/quarter foreground
```

Taustakäynnistys release-skriptillä:

```sh
_build/default/rel/quarter/bin/quarter start
_build/default/rel/quarter/bin/quarter stop
```

### Asetukset

* `config/sys.config` määrittää Erlang loggerin kirjoittamaan yhteiseen lokiin
  `/var/www/htdocs/jedi.ydns.eu/volatile/quarter.log`.
* `config/vm.args` määrittää paikallisen noden nimen ja kehityscookien.

Vaihda `config/vm.args`-tiedoston cookie ennen tuotantokäyttöä, jos distributed
Erlangia käytetään tai node on muuten saavutettavissa.

### Ajastus

* Erillistä `scheduler`-prosessia ei ole: `quarter_worker`, `hourly_worker` ja
  `daily_run_worker` ovat itsenäisiä gen_servereitä, jotka ajastavat omat työnsä
  omilla ajastimillaan.
* `quarter_worker` on vartin välein ajettava koordinaattori. Se kutsuu ensin
  `trig`-moduulia GPIO-ohjausta varten ja sen jälkeen `entso_quarter`-moduulia
  ENTSO-E:n `entso.xml`/`prices.txt`-tarkistusta varten.
* `entso_quarter` tarkistaa ENTSO-E:n vartin välein: jos päivän `entso.xml` on
  jo haettu ja kelvollinen, sitä käytetään; muuten se haetaan. Klo 15:00 jälkeen
  sama tarkistus tehdään myös seuraavalle päivälle.
* `hourly_worker` hakee FMI:n uusimmat havainnot ja ennusteen kerran tunnissa
  käynnistyshetkestä lasketulla jaksolla ilman erillistä cache/due-tarkistusta.
  Ennen FMI-hakua se lukee ENTSO-E:n
  päivän aikavälin `quarter_worker`in ylläpitämästä tilasta eikä käynnistä omaa
  ENTSO-E-hakua.
* `daily_run_worker` ajaa illan `run.txt`-suunnittelun klo 21:41 paikallista
  aikaa seuraavaa päivää varten.


### Varttikohtainen GPIO-ohjaus (`trig`)

`trig` korvaa vanhan tunnin välein ajetun shell-skriptin vartin välein ajettavalla
Erlang-tarkistuksella. Moduuli muodostaa nykyisen UTC-vartin ajan muodossa
`YYYY-MM-DDTHH:MM:00Z`. Sen jälkeen se koostaa kyseisen päivän ohjaustaulun
levyllä olevista `prices.txt`- ja `temps.txt`-tiedostoista `entso_run`-moduulin
kautta. Ohjaustaulu on Erlangin `map`, jossa avain on vartin kellonaika ja arvo
on `discharge`. Jos avainta ei löydy, toiminto on `normal`.
`run.txt` kirjoitetaan samalla uudestaan vain ihmisen luettavaksi lokiksi.
`trig` ajaa OpenBSD:n `gpioctl`-komennot:

* ei riviä: pumppu päälle ja normaali säätö päälle (`gpioctl gpio0 26 1`,
  `gpioctl gpio0 20 1`)
* rivillä `P`: purku päälle, pumppu pois ja normaali säätö päälle
  (`gpioctl gpio0 26 0`, `gpioctl gpio0 20 1`)

Erillistä `run.plan`-tiedostoa tai muuta pysyvää ohjaustaulua ei kirjoiteta,
koska suunnitelma voidaan aina muodostaa uudestaan levyllä olevista sää- ja
hintatiedoista. GPIO-ohjaus käyttää kiinteästi OpenBSD:n `gpioctl`-komentoa,
`gpio0`-laitetta sekä pinnejä 26 ja 20.


## OpenBSD/RPi4 daemonina

OpenBSD:ssä oikea tapa käynnistää `quarter` bootissa on tehdä sille oma
`rc.d`-skripti ja ohjata sitä `rcctl`-komennolla. Repo sisältää valmiin
mallin tiedostossa `rc.d/quarter`. Skripti käynnistää ja pysäyttää palvelun
`rebar3`/`relx`-releasen omalla `bin/quarter start|stop` -rajapinnalla ja
odottaa, että Erlang VM:n `beam.smp`-prosessi oikeasti ilmestyy tai poistuu.
Tarkistus tehdään prosessista eikä `bin/quarter ping` -komennolla, koska
remote ping voi epäonnistua liian aikaisin, vaikka daemonisoitu VM olisi jo
käynnistymässä.

Yksi suositeltu asennustapa OpenBSD/RPi4-koneella:

```sh
# Luo ajokäyttäjä, jolla ei ole kirjautumiskuorta.
doas groupadd _quarter
doas useradd -g _quarter -s /sbin/nologin -d /var/empty -L daemon _quarter

# Rakenna release OpenBSD-koneella tai kopioi OpenBSD:ssä rakennettu release.
rebar3 release

# Asenna tai päivitä release vakaaseen polkuun.
doas ./update-quarter-release.escript

# Varmista, että ohjelman käyttämät data- ja lokihakemistot ovat olemassa
# ja että _quarter saa kirjoittaa niihin.
doas mkdir -p /var/www/htdocs/jedi.ydns.eu/var \
             /var/www/htdocs/jedi.ydns.eu/volatile
doas chown -R _quarter:_quarter /var/www/htdocs/jedi.ydns.eu/var \
                                 /var/www/htdocs/jedi.ydns.eu/volatile

# Asenna rc.d-skripti.
doas install -o root -g wheel -m 555 rc.d/quarter /etc/rc.d/quarter

# Testaa käsin ja ota boot-käynnistys käyttöön.
doas rcctl start quarter
doas rcctl check quarter
doas rcctl enable quarter
```

Hyödylliset ylläpitokomennot:

```sh
doas rcctl stop quarter
doas rcctl restart quarter
doas tail -f /var/www/htdocs/jedi.ydns.eu/volatile/quarter.log
```

Ennen tuotantokäyttöä vaihda `config/vm.args`-tiedoston cookie tai pidä cookie
konekohtaisessa, versionhallinnan ulkopuolisessa release-konfiguraatiossa.
Jos node halutaan pitää vain paikallisena, nykyinen `-sname quarter` riittää;
älä avaa Erlangin EPMD-/distributed Erlang -portteja ulkoverkkoon.

## ENTSO/FMI run.txt -suunnittelu

Seuraava vaihe vanhan cron-ajon (`/rc/trilogy.rc`) korvaamisessa on mukana
Erlangissa. `xml_parse` muodostaa ENTSO-E:n `entso.xml`-tiedostosta täytetyn
`prices.txt`-hintasarjan päivän hakemistoon. Kun `quarter_worker` on hakenut
ENTSO-E:n hintajakson ja FMI:n lämpötilat, `entso_run` laskee saman ohjausidean
kuin vanha awk-putki valmiista `prices.txt`- ja `temps.txt`-tiedostoista.
Varsinainen ohjaustaulu pidetään vain laskennan tuloksena muistissa, ja `run.txt`
kirjoitetaan siitä lokiksi:

1. `prices.txt` antaa varttihinnat ja `temps.txt` antaa vastaavat ulkolämpötilat.
2. Menoveden pyynti lasketaan normal-tilassa säätökäyrällä
   `-0.0067*T*T - 0.9*T + 42.7` (rajattu välille 25..60 °C).
3. `P` ja `COP` lasketaan menoveden ja ulkolämpötilan funktiona moduulissa
   `entso_tables` (55 °C taulukoista johdettu yleistys).
4. Jokaiselle vartille lasketaan:
   * suhteellinen hinta: `((hinta + 63.3) * 1.24) / COP(T, Tmeno)`
   * tehontarve: `-0.2 * T + 6`
   * varastoon jäävä teho: `P(T, Tmeno) - tehontarve`
   * varaajan energiakynnys: `(55 - Tmeno) * 2 * 1.17`
5. Ohjaussuunnitelma muodostetaan Erlangin `map`-taulukoksi, jossa avain on
   vartin UTC-aika ja arvo on `discharge` (puuttuva avain = `normal`):
   * päivän tehontarve lasketaan summana `(-0.2 * T + 6) * 0.25` kaikille
     varttiriveille
   * halvimmat vartit valitaan nousevan suhteellisen hinnan järjestyksessä
     `normal`-tilaan, kunnes päivän tehontarve on katettu
   * muut vartit merkitään arvolla `discharge`
   * `run.txt` kirjoitetaan tästä taulusta lokiksi (`P`)

`xml_parse` täyttää puuttuvat hintapositiot edellisellä hinnalla ennen
`prices.txt`-kirjoitusta, kuten vanha `do_entso`-vaihe. `run.txt`-suunnittelu
ei ole FMI:n tuntipäivityksen tai ENTSO:n 15 minuutin hakusilmukan osa, vaan se ajetaan
kerran illassa klo 21:41 paikallista aikaa seuraavaa päivää varten vanhan
crontab-esimerkin mukaisesti. Päiväkohtaisen datan polku on aina
`/var/www/htdocs/jedi.ydns.eu/var`. `P`/`COP`-mallia päivitetään
muokkaamalla `entso_tables`-moduulia.

`plan_day/1` palauttaa lisäksi metadatan, jossa:
* `actions` ja `discharge_quarters` ovat sama asia (kuinka moni vartti on
  `discharge`/`P`-tilassa).
* `normal_quarters` kertoo normal-tilaan valittujen varttien määrän.
* `daily_heat_need_kwh` on lämpöenergian tarve (kWh_th) mallin
  `(-0.2 * T + 6)` perusteella.
* `daily_electric_need_kwh` on arvioitu sähköenergiantarve (kWh_el), jossa
  huomioidaan COP: varttitarve lasketaan kaavalla
  `((-0.2 * T + 6) / COP(T, Tmeno)) * 0.25`.
