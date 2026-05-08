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
