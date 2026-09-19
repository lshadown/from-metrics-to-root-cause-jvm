# Skrypt demo: od metryk do przyczyny

## Historia w trzech zdaniach

Klient zgłasza, że nasze API czasem odpowiada bardzo wolno (2–3 sekundy), choć zwykle odpowiada w ułamku sekundy.
Winnym wydaje się zewnętrzny serwis, bo on faktycznie jest wolny.
Prawdziwa przyczyna jest jednak w naszym własnym kodzie: żądania czekają na blokadę (lock) w cache'u.

## Co robią serwisy

**api-service** (`https://demo-a.gruzewski.dev`)

- Ma jeden endpoint: `GET /orders?userId=X&details=true`.
- Zwraca listę zamówień użytkownika plus dodatkowe dane o użytkowniku ("enrichment": segment i risk score).
- Te dodatkowe dane pobiera z external-service i zapisuje w cache'u w pamięci, osobno dla każdego userId.
- Cache ma czas ważności (TTL): 5 sekund dla użytkownika premium, 10 sekund dla zwykłego.
- Kiedy wpis w cache'u wygaśnie, api-service zakłada blokadę (lock) na tego userId. Tylko jeden wątek idzie po świeże dane. Pozostałe wątki czekają na blokadzie, a gdy dane wrócą, biorą je z cache'a.

**external-service** (`https://demo-b.gruzewski.dev`)

- Ma jeden endpoint: `GET /enrichment?userId=X`.
- Udaje wolną bazę danych.
- Dla użytkownika premium (userId podzielne przez 20, np. 40) odpowiada po 2,5 sekundy.
- Dla zwykłego użytkownika odpowiada po 80 milisekund.

## Ruch podczas demo

- `scripts/baseline-traffic.sh` – ciągły ruch zwykłych użytkowników. Wszystkie te żądania są szybkie.
- `scripts/demo.sh` – co 30 sekund wysyła 15 żądań naraz o użytkownika premium `userId=40`.

## Co dokładnie się dzieje przy każdej serii 15 żądań

1. Wpada 15 żądań o userId=40 w tej samej chwili. Cache dla tego użytkownika dawno wygasł (ważny był 5 sekund, ostatnia seria była 30 sekund temu).
2. Wszystkie 15 żądań widzi pusty cache i staje w kolejce do jednej blokady.
3. Pierwsze żądanie dostaje blokadę i pyta external-service. To trwa 2,5 sekundy.
4. Pozostałe 14 żądań przez te 2,5 sekundy nic nie robi. Czekają na blokadzie.
5. Pierwsze żądanie wraca, zapisuje dane w cache'u i zwalnia blokadę.
6. Pozostałe 14 żądań budzi się po kolei, bierze dane z cache'a i odpowiada. Każde z nich trwało ~2,5 sekundy, choć żadne nie pytało external-service.

Wynik: 15 wolnych odpowiedzi, ale tylko jedno wolne wywołanie external-service.
Te pozostałe 14 razy po 2,5 sekundy to czas stracony u nas, na czekaniu.

## Dlaczego to trudne do znalezienia

- Nie ma żadnych błędów. Wszystko odpowiada 200, tylko wolno.
- External-service jest wolny zawsze tak samo (2,5 s dla premium). Nie zmienia się w czasie, więc nie wyjaśnia, dlaczego wolne odpowiedzi pojawiają się seriami.
- Kod cache'a wygląda poprawnie. Blokada na jeden userId to normalny wzorzec ochrony przed zalaniem zewnętrznego serwisu.

---

## Skrypt prezentacji krok po kroku

### Przed prezentacją

1. Uruchom w dwóch terminalach:
   - `./scripts/baseline-traffic.sh`
   - `WAIT_FOR_TTL=90 ./scripts/demo.sh` (co 90 s zamiast 30 s, żeby skoki p99 były osobne, a nie ciągłe)
2. Odczekaj co najmniej 3–5 minut, żeby na wykresach było kilka serii.
3. Otwórz `https://grafana.gruzewski.dev`, dashboard "From Metrics to Root Cause", zakres "Last 15 minutes".
4. Upewnij się, że wiersz "api-service internals (enrichment)" na dole jest zwinięty.

### Krok 1 – Dashboard: pokaż objaw

Co pokazujesz: panel **/orders latency (api-service)**.

Co mówisz:

- Klient ma rację. p50 jest niskie (ok. 100 ms), ale p99 co pół minuty skacze do 2,5–3 sekund.
- Dzieje się to regularnie, więc to nie przypadek.

### Krok 2 – Dashboard: pierwszy podejrzany

Co pokazujesz: panel **/enrichment latency (external-service)**.

Co mówisz:

- Pierwsza myśl: to zewnętrzny serwis, bo od niego zależymy.
- Ale on wygląda na zdrowy: p95 i p99 to ok. 90 ms, płasko, bez skoków. Nic tu nie pasuje do skoków p99 na /orders.
- Czyli dashboard nie daje żadnego podejrzanego. Gdzie te 2,5 sekundy?

(Wyjaśnienie dla Ciebie, nie na głos: wolne wywołanie premium do external-service to jedno żądanie na serię wśród setek szybkich, więc nie wchodzi nawet w p99. Zobaczysz je dopiero w logach jako `refreshMs=2502`.)

### Krok 3 – Dashboard: odrzuć fałszywe tropy

Co pokazujesz: panele **JVM heap used**, **5xx responses**, **Tomcat busy threads**.

Co mówisz:

- Heap wygląda jak piła, ale to normalny cykl garbage collectora. Nie to.
- Błędów 5xx nie ma. Nic się nie wywala, tylko zwalnia.
- Zajęte wątki Tomcata skaczą do ~15 dokładnie wtedy, gdy skacze p99. Czyli wątki na coś czekają. Metryka nie powie na co.
- Wniosek: metryki mówią **że** i **kiedy** jest problem. Nie mówią **dlaczego**. Idziemy do logów.

### Krok 4 – Logi: znajdź wolne żądania

Co pokazujesz: Grafana → Drilldown → Logs → datasource Loki.

Co robisz:

1. Wybierz serwis api-service (`service_name = observability-api-service-1`).
2. W polu "Filter by fields" dodaj: `durationMs > 2000`.

Co mówisz:

- Wszystkie wolne żądania mają ten sam `userId=40` i wypadają w tej samej sekundzie.
- Każde ma pole `traceId`. Weźmy jedno z nich.

### Krok 5 – Logi: zobacz, co robiło jedno żądanie

Co robisz:

1. Rozwiń jeden wpis, kliknij lupkę przy `traceId` (filtruj po tym traceId).
2. Zostają 3 linie tego jednego żądania.

Co mówisz:

- Linia `http_in`: żądanie trwało `durationMs=2366`.
- Linia `lock acquired`: `lockWaitMs=2366`. Całe 2,3 sekundy to czekanie na blokadę.
- Linia `cache hit after lock`: `cache_hit=true`, `after_lock=true`. Po zwolnieniu blokady dane były już w cache'u.
- To żądanie **nigdzie nie dzwoniło**. Cały czas spędziło u nas, czekając.
- Alternatywnie, zamiast po traceId, możesz pokazać wszystkich czekających naraz filtrem pola `lockWaitMs > 2000`: 14 linii na serię, wszystkie `userType=premium`.

### Krok 6 – Logi: znajdź to jedno żądanie, które faktycznie dzwoniło

Co robisz:

1. Zostaw filtr `durationMs > 2000` i dodaj drugi filtr pola: `logger_name = com.gruzewskidev.api_service.ExternalEnrichmentClient`
   (albo prościej: zamień filtry na `cache_refresh = true`).
2. Zostaje jedna linia na serię: `Downstream enrichment call` z `userId=40`, `durationMs=2502`.
3. Kliknij lupkę przy jej `traceId`. Widzisz 4 linie tego żądania: `lock acquired` (`lockWaitMs=0`), `Downstream enrichment call` (`durationMs=2502`), `cache refreshed` (`refreshMs=2502`, `ttl=PT5S`), `http_in` (`durationMs=2502`).
4. (Opcjonalnie) Zmień label na external-service i zostaw filtr po tym samym traceId: jest tam linia `db query` z `db_query_duration_ms=2500`, `segment=premium`. Dla czekających żądań w external-service nie ma nic.

Co mówisz:

- Tylko jedno żądanie z piętnastu poszło do external-service. To ono ma `lockWaitMs=0` i `refreshMs=2502`.
- Pozostałe czternaście mają `lockWaitMs` ok. 2400 i nie mają linii "Downstream". Nie dzwoniły nigdzie.
- Widać też `ttl=PT5S`: dane premium są ważne tylko 5 sekund. Po tym czasie następna seria znów trafia w pusty cache.

### Krok 7 – Trace: potwierdź w Tempo

Co robisz:

1. Z wpisu logu kliknij link do trace'a (przycisk Tempo przy `traceId`) albo Explore → Tempo → wklej traceId.
2. Pokaż dwa trace'y obok siebie:
   - trace żądania, które czekało (z kroku 5),
   - trace żądania, które odświeżało cache (z kroku 6).

Co mówisz:

- Trace żądania, które czekało: jeden długi span `/orders`, 2,4 sekundy, i **żadnego** spanu do external-service. Czas zniknął wewnątrz api-service.
- Trace żądania, które odświeżało: trzy spany: api-service → klient HTTP → external-service, gdzie 2,5 sekundy wisi na external-service.
- Jedno żądanie zapłaciło prawdziwą cenę. Czternaście zapłaciło ją drugi raz, czekając.

### Krok 8 – Dashboard: potwierdź metrykami, które ktoś dodał wcześniej

Co robisz: wróć na dashboard, rozwiń wiersz **api-service internals (enrichment)**.

Co mówisz:

- **Enrichment cache hit/miss**: co 30 sekund 15 missów dla premium.
- **Enrichment lock wait**: max ok. 2,4 sekundy, tylko dla premium. Dla zwykłych użytkowników prawie zero.
- **Enrichment refresh duration**: ok. 2,5 sekundy dla premium.
- Wszystko, co wydedukowaliśmy z logów i trace'ów, było w metrykach. Ale tylko dlatego, że ktoś je wcześniej dodał do kodu.

### Krok 9 – Wnioski (slajd)

- Metryki zawężają obszar: gdzie i kiedy.
- Logi dają hipotezę: żądania czekają na blokadę.
- Trace ją potwierdza: czas ginie wewnątrz serwisu, nie w zależności.
- Metryki domenowe (cache hit/miss, lock wait) zamykają pętlę i pozwalają postawić alert na przyszłość.
- Naprawa (opcjonalnie): dłuższy TTL z losowym rozrzutem, odświeżanie w tle przed wygaśnięciem, albo serwowanie starych danych podczas odświeżania.
