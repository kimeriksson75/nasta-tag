# Nästa tåg hem

En webbapp som gör en sak: visar nästa tunnelbanetåg hem som du faktiskt hinner med.
Den tar med gångtiden till närmaste station. Färgen visar hur mycket marginal du har:
grön från 5 minuter, gul från 2 minuter och röd under 2 minuter.

Hemadressen anges under kugghjulet: förslag visas medan du skriver, och ett tryck sparar.

Köra lokalt:

    python3 -m http.server 5180

Testa logiken:

    node --test

Uppdatera stationsdata: `node scripts/build-stations.mjs`. Linjesträckningarna står i skriptet.
Lägg till Barkarby och Gula linjen där när de får trafik.

Tjänster, ingen kräver API-nyckel:

- Avgångar och stationer: SL Transport via Trafiklab
- Gångtid: routing.openstreetmap.de. Vid fel används en uppskattning, som visas med "ca".
- Adressökning: SL:s reseplanerare (stop-finder), ingen nyckel

Platsen kräver https på telefonen, så appen måste ligga på en https-adress för att fungera där.
