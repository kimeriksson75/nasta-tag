# Nästa tåg

- iOS-appen ligger i `ios/`, logiken och testerna i `ios/NastaTagCore` (`swift test`).
- Läs `ios/MUST_STAY.md` innan du ändrar något på skärmen eller i hur resor väljs. Det som står där
  får inte tas bort eller ändras utan att Kim har bestämt det.
- Ett rött test rättas i appen. Ändra eller ta inte bort ett test för att få det grönt, utom när
  beteendet det vaktar har ändrats med flit och `MUST_STAY.md` uppdateras i samma commit.
- Ny logik för vad som syns läggs i NastaTagCore med ett test, inte direkt i vyn.
- Bygg till TestFlight med `ios/release.sh`, som avbryter om något test är rött.
- Lägg aldrig API-nycklar eller andra hemligheter i koden eller i git.
