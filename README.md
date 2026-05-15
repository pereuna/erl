# erl

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

### Devuan -> OpenBSD/RPI4 huomio

`rebar.config` käyttää asetusta `{include_erts, false}`, koska Devuan/Linuxissa
rakennettu ERTS ei ole siirrettävissä OpenBSD/RPI4-koneelle. Tuotantokoneelle
pitää asentaa Erlang/OTP erikseen, tai release pitää rakentaa suoraan
OpenBSD/RPI4-koneella.

Jos rakennat releasen suoraan samalla OpenBSD/RPI4-koneella, jolla se ajetaan,
voit halutessasi vaihtaa `include_erts`-asetukseksi `true`, jolloin release
pakkaa mukaan kyseisen koneen Erlang-runtimen.

### Asetukset

* `config/sys.config` määrittää Erlang loggerin kirjoittamaan standard outputiin.
* `config/vm.args` määrittää paikallisen noden nimen ja kehityscookien.

Vaihda `config/vm.args`-tiedoston cookie ennen tuotantokäyttöä, jos distributed
Erlangia käytetään tai node on muuten saavutettavissa.

### Ajastus

* Erillistä `scheduler`-prosessia ei ole: `quarter_worker`, `hourly_worker` ja
  `daily_run_worker` ovat itsenäisiä gen_servereitä, jotka ajastavat omat työnsä
  yhteisillä `eutils`-viivelaskureilla.
* `quarter_worker` on vartin välein ajettava koordinaattori. Se kutsuu ensin
  `trig`-moduulia GPIO-ohjausta varten ja sen jälkeen `entso_quarter`-moduulia
  ENTSO-E:n `entso.xml`/`prices.txt`-tarkistusta varten.
* `entso_quarter` tarkistaa ENTSO-E:n vartin välein: jos päivän `entso.xml` on
  jo haettu ja kelvollinen, sitä käytetään; muuten se haetaan. Klo 15:00 jälkeen
  sama tarkistus tehdään myös seuraavalle päivälle.
* `hourly_worker` hakee FMI:n uusimmat havainnot ja ennusteen kerran tunnissa
  ilman erillistä cache/due-tarkistusta. Ennen FMI-hakua se varmistaa ENTSO-E:n
  päivän aikavälin samalla `kurl:fetch_day/1`-tarkistuksella.
* `daily_run_worker` ajaa illan `run.txt`-suunnittelun klo 21:41 paikallista
  aikaa seuraavaa päivää varten.


### Varttikohtainen GPIO-ohjaus (`trig`)

`trig` korvaa vanhan tunnin välein ajetun shell-skriptin vartin välein ajettavalla
Erlang-tarkistuksella. Moduuli muodostaa nykyisen UTC-vartin ajan muodossa
`YYYY-MM-DDTHH:MM:00Z`. Sen jälkeen se koostaa kyseisen päivän ohjaustaulun
levyllä olevista `prices.txt`- ja `temps.txt`-tiedostoista `entso_run`-moduulin
kautta. Ohjaustaulu on Erlangin `map`, jossa avain on vartin kellonaika ja arvo
on `charge` tai `discharge`. Jos avainta ei löydy, toiminto on `normal`.
`run.txt` kirjoitetaan samalla uudestaan vain ihmisen luettavaksi lokiksi.
`trig` ajaa OpenBSD:n `gpioctl`-komennot:

* ei riviä: pumppu päälle ja normaali säätö päälle (`gpioctl gpio0 26 1`,
  `gpioctl gpio0 20 1`)
* rivillä `L`: varaajan lataus päälle, pumppu päälle ja pyynti 55 °C
  (`gpioctl gpio0 26 1`, `gpioctl gpio0 20 0`)
* rivillä `P`: purku päälle, pumppu pois ja normaali säätö päälle
  (`gpioctl gpio0 26 0`, `gpioctl gpio0 20 1`)

Erillistä `run.plan`-tiedostoa tai muuta pysyvää ohjaustaulua ei kirjoiteta,
koska suunnitelma voidaan aina muodostaa uudestaan levyllä olevista sää- ja
hintatiedoista. GPIO-asetukset voi muuttaa muuttujilla `TRIG_GPIO_COMMAND`,
`TRIG_GPIO_DEVICE`, `TRIG_PUMP_PIN` ja `TRIG_CONTROL_PIN`.

## ENTSO/FMI run.txt -suunnittelu

Seuraava vaihe vanhan cron-ajon (`/rc/trilogy.rc`) korvaamisessa on mukana
Erlangissa. `xml_parse` muodostaa ENTSO-E:n `entso.xml`-tiedostosta täytetyn
`prices.txt`-hintasarjan päivän hakemistoon. Kun `quarter_worker` on hakenut
ENTSO-E:n hintajakson ja FMI:n lämpötilat, `entso_run` laskee saman ohjausidean
kuin vanha awk-putki valmiista `prices.txt`- ja `temps.txt`-tiedostoista.
Varsinainen ohjaustaulu pidetään vain laskennan tuloksena muistissa, ja `run.txt`
kirjoitetaan siitä lokiksi:

1. `prices.txt` antaa varttihinnat ja `temps.txt` antaa vastaavat ulkolämpötilat.
2. `P55` ja `COP55` haetaan Erlangin sisäisistä vektoreista moduulista
   `entso_tables`; vektorin elementti 1 vastaa lämpötilaa -20 °C, eli vanhan
   `FNR-21`-indeksoinnin.
3. Jokaiselle vartille lasketaan:
   * suhteellinen hinta: `((hinta + 63.3) * 1.24) / COP55[T]`
   * tehontarve: `-0.2 * T + 6`
   * varastoon jäävä teho: `P55[T] - tehontarve`
   * varaajan energiakynnys: `(55 - (-0.0067*T - 0.9*T + 42.7)) * 2 * 1.17`
4. Ohjaussuunnitelma muodostetaan Erlangin `map`-taulukoksi, jossa avain on
   vartin UTC-aika ja arvo on `charge` tai `discharge`:
   * halvimmat vartit nousevan suhteellisen hinnan järjestyksessä merkitään
     arvolla `charge`, kunnes kumulatiivinen varastoteho ylittää kyseisen rivin
     energiakynnyksen
   * kalleimmat vartit laskevan suhteellisen hinnan järjestyksessä merkitään
     arvolla `discharge`, kunnes kumulatiivinen tehontarve ylittää kyseisen rivin
     energiakynnyksen
   * `run.txt` kirjoitetaan tästä taulusta lokiksi (`L`/`P`)

`xml_parse` täyttää puuttuvat hintapositiot edellisellä hinnalla ennen
`prices.txt`-kirjoitusta, kuten vanha `do_entso`-vaihe. `run.txt`-suunnittelu
ei ole FMI:n tuntipäivityksen tai ENTSO:n 15 minuutin hakusilmukan osa, vaan se ajetaan
kerran illassa klo 21:41 paikallista aikaa seuraavaa päivää varten vanhan
crontab-esimerkin mukaisesti. Päiväkohtaisen datan polku on aina
`/var/www/htdocs/jedi.ydns.eu/var`. `P55`/`COP55`-arvoja ei enää lueta
`const`-hakemistosta, vaan niitä muutetaan päivittämällä `entso_tables`-moduulin
vektorit.
