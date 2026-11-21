# Det som inte får försvinna

Appen är byggd för att man ska kunna lita på den på väg ut genom dörren. Knapparna och beteendena
nedan är det användarna räknar med. De får inte tas bort, gömmas eller ändra betydelse av misstag.
En ändring av något här beslutas med Kim först och skrivs in här i samma commit.

## Huvudskärmen, när det finns en resa

| Vad | När det syns | Vaktas av |
|---|---|---|
| Rubriken och ringen med minuter | Alltid | `StateTests`, `VoiceTests` |
| "HH:MM-tåget hem" och raden under, med "hemma HH:MM" | Alltid | `TimesTests` |
| Snooze N min | När det finns en senare avgång och du inte står vid hållplatsen | `MustStayTests` |
| Ångra snooze | Efter Snooze, tills avgången du hoppade över har gått (sedan grå) | `MustStayTests` |
| Strunta i resan idag | Alltid, utom vid hållplatsen (då osynlig men på plats) | `MustStayTests` |
| Kortet med gångvägen, som öppnar kartan | Alltid, utom när avgången är missad | – (kolla i simulatorn) |
| Följ på låsskärmen | Alltid, utom när avgången är missad | – (kolla i simulatorn) |
| Uppdaterad HH:MM | Har alltid sin plats, syns efter första hämtningen | – (kolla i simulatorn) |

## Beteenden

- Snabbast fram vinner. Appen väljer aldrig ett långsammare färdmedel för att du råkar stå nära
  dess hållplats: hemma är hemma, även granne med en busshållplats (`MustStayTests`).
- Tiderna kommer alltid i ordning: gå före avgång, avgång före framme (`TimesTests`).
- En resa vars byte inte går att hinna visas inte (`TimesTests`).
- Ingenting på skärmen flyttar sig när text eller resa byts.

## Före varje bygge till TestFlight

1. `ios/release.sh` kör alla tester och avbryter om något är rött. Ladda aldrig upp förbi det.
2. Starta appen i simulatorn och se att allt i tabellen ovan finns där det ska.
3. Ett test som går sönder rättas i appen, inte genom att testet ändras.
