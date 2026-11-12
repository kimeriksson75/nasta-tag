# Nästa tåg hem

En webbapp som gör en sak: visar när du måste gå för att hinna med den snabbaste resan hem
eller till jobbet, med tunnelbana, buss, pendeltåg, spårvagn eller båt. SL:s reseplanerare
räknar ut resan, med gångtiden till första hållplatsen och eventuella byten. Färgen visar hur mycket marginal du har:
grön från 5 minuter, gul från 2 minuter och röd under 2 minuter.

Hemadressen anges under kugghjulet: förslag visas medan du skriver, och ett tryck sparar.

Köra lokalt:

    python3 -m http.server 5180

Testa logiken:

    npm test

Tunnelbanans stationer (`data/metro.json`) används bara för äldre sparade destinationer,
för klockans genväg och för att välja start när platsen saknas. Uppdatera med `node scripts/build-stations.mjs`.

Tjänster, ingen kräver API-nyckel:

- Resor med uppdaterade tider: SL:s reseplanerare (trips), högst tre resor per fråga
- Adressökning: SL:s reseplanerare (stop-finder)
- Gångvägen i kartvyn: routing.openstreetmap.de, kartbilder från OpenFreeMap

Platsen kräver https på telefonen, så appen måste ligga på en https-adress för att fungera där.
