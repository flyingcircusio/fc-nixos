---
global_sync_id: "v1"
search:
  exclude: true
---

# DevOps-Leitfaden

% This document is being linked to from dead media
% with printed URLs and QR codes. Do not change its name
% and do not change the manual anchor names!

Die folgenden Abschnitte enthalten Ticket-Vorlagen im MarkDown-Format um sie in
gängigen Ticketsystemen wie Github, Gitlab, Youtrack oder Jira zu verwenden.

Einfach den jeweiligen Abschnitt kopieren, ein neues Ticket anlegen, den Titel
eintragen und die kopierte Vorlage einfügen. 

## Das Projekt { #projekt }

```
(Titel des Tickets) Das Projekt

_Um digitale Projekte erfolgreich zu starten und weiterzuentwickeln braucht es heutzutage ein übergreifendes Verständnis bei allen Beteiligten. Um unsere Erfahrung möglichst gut einbringen zu können ist es wichtig, dass wir Projekte nicht nur aus der Perspektive betrachten ob sie viel oder wenig Technik brauchen. Am meisten Wirkung entfaltet unser Team in den Projekten, in denen wir den weiteren Kontext kennen und wissen welche Bedeutung das Projekt für unsere Kund*innen und die Nutzer*innen hat._

* [ ] **Wie heißt das Projekt?**

* [ ] **Worum geht es in diesem Projekt?**

* [ ] **Wer sind die Nutzer*innen?**

* [ ] **Welche Funktionen bietet das Projekt seinen Nutzer*innen?**

* [ ] **Wie sieht der bestmögliche Erfolg für dieses Projekt aus?**
```

## Kund\*in und Team { #team }


```
(Titel des Tickets) Kund*in und Team

_Neben dem Verständnis für das Projekt selbst müssen viele Absprachen getroffen werden und Beziehungen aufgebaut werden. Insbesondere ist es uns wichtig Zugang zu unterschiedlichen Perspektiven zu haben um Bedürfnisse aus unternehmerischen und technischen Perspektiven berücksichtigen zu können. Offenheit und Transparenz heißt auch möglichst “Stille Post”-Situationen zu vermeiden, die häufig zu Missverständnissen und Verzögerungen führen._

* [ ] **Wie lauten die Kundendaten einschließlich Firmierung und Anschrift?**


* [ ] **Projektverantwortliche Person:**


| Name | Organisation | Kontaktdaten (E-Mail, Telefon) | Funktion oder Rolle |
| -- | -- | -- | -- |
|  | | | |

* [ ] **Verantwortliche Person aus der Software-Entwicklung:**

| Name | Organisation | Kontaktdaten (E-Mail, Telefon) | Funktion oder Rolle |
| -- | -- | -- | -- |
|  | | | |


* [ ] **Weitere im Projekt relevante Personen:**

| Name | Organisation | Kontaktdaten (E-Mail, Telefon) | Funktion oder Rolle |
| -- | -- | -- | -- |
|  | | | |
|  | | | |
|  | | | |
|  | | | |

* [ ] **Welche bisher mit dem Betrieb vertrauten Personen sind unterstützend für die Migration ansprechbar?**

| Name | Organisation | Kontaktdaten (E-Mail, Telefon) | Funktion oder Rolle |
| -- | -- | -- | -- |
|  | | | |
|  | | | |


```

## Zeitplan und Roadmap { #zeitplan }


```
(Titel des Tickets) Zeitplan und Roadmap

_Unterschiedliche Projekte können eine ganz unterschiedliche Dynamik entwickeln - häufig gibt es viele Unbekannte. Um möglichst proaktiv Entscheidungen treffen zu können und sinnvolle Optionen vorschlagen zu können hilft es wenn wir die Situation des Projektes gut einschätzen können, wissen welche Termine unserer Kund*innen relevant sind und wo die Reise in Zukunft hingehen soll._


* [ ] **Welchen Charakter hat das Projekt?**

_Im groben unterscheiden wir zwischen Neuentwicklungen und Migrationen. Weitere Unterschiede ergeben sich wenn es sich um ein “Minimal Viable Product” handelt, wenn bestehende Systeme weiterentwickelt werden oder es sich um einen vollständigen Relaunch handelt._

* [ ] **In welchem Stadium befindet sich das Projekt zur Zeit?**

_Unabhängig ob das Projekt neu entwickelt wird oder bereits existiert: in welchem Entwicklungszustand befindet sich das Projekt zur Zeit? Wird noch das grundlegende Konzept besprochen? Gibt es bereits funktionierenden Code? Ist die Entwicklung bereits abgeschlossen und es soll “nur noch” Live gehen?_


* [ ] **Zeitplan:**

| Was | Bis wann | 
| -- | -- |
| Entwicklungsumgebung | | 
| Staging-Umgebung | |
| Produktionsumgebung | | 
| Ready-to-launch | |
| Livegang (Migration) | |
| | |
| | | 

* [ ] **Weitere Termine:**

_Deadlines, festgelegte Termine und andere relevante Ereignisse im weiteren Kontext: Produkt-Launches, Werbemaßnahmen, Versammlungen, Kunden-Events, …_

| Was | Wann |
| -- | -- |
| | | 
| | | 
| | | 

* [ ] **Welche Weiterentwicklungen sind in den nächsten 24 Monaten vorgesehen?**

* [ ] **Welches Wachstum wird in den nächsten 24 Monaten erwartet?**
```

## Datenschutz, Sicherheit, Compliance { #sicherheit }

```
(Titel des Tickets) Datenschutz, Sicherheit, Compliance

_Wir haben uns beim Flying Circus entschieden alle Aspekte rund um das Sicherheit umfassend aber auch pragmatisch zu behandeln. Der Flying Circus ist selbst vollständig nach ISO-27001 zertifiziert und wir begleiten unsere Kund*innen dabei das notwendige Sicherheitsniveau auch im Betrieb der eigenen Anwendung zu erreichen._

* [ ] **Welche personenbezogenen Daten werden verarbeitet oder gespeichert?**

_Welche sensiblen personenbezogene Daten mit erhöhtem Schutzbedarf werden verarbeitet? Die Verarbeitung von personenbezogenen Daten mit erhöhtem Schutzbedarf bedarf neben der üblichen Regelung einer AV eine Datenschutzfolgeabschätzung._

* [ ] **Welche Maßnahmen zur IT- und Datensicherheit sind implementiert?**

_Im allgemeinen sind die technischen und organisatorischen Maßnahmen aus den Anforderungen an die Sicherheit der Datenverarbeitung der EU-DSGVG, bzw. dem BDSG zu berücksichtigen._

_Einige dieser Anforderungen setzt der Flying Circus durch Maßnahmen der Infrastruktur und Plattform vollumfänglich um – die übrigen Themen sind von uns weitestgehend vorbereitet, benötigen aber anwendungs- und kundenspezifische Betrachtungen um sie vollständig zu erfüllen._

| Vom Flying Circus vollständig umgesetzte Anforderungen | Anforderungen, die weitestgehend umgesetzt sind aber anwendungsspezifisch ergänzt werden müssen |
| -- | -- |
| Zugangskontrolle, Transportkontrolle, Datenträgerkontrolle | Speicherkontrolle, Benutzerkontrolle, Zugriffskontrolle, Übertragungskontrolle, Eingabekontrolle, Wiederherstellbarkeit, Auftragskontrolle, Verfügbarkeitskontrolle Trennbarkeit, Datenintegrität |

* [ ] **Gibt es besondere Anforderungen an Backups?**

_Unser Standardschema sieht tägliche Backups aller virtuellen Festplatten vor. Dabei halten wir jeweils die Backups der letzten 7 Tage, 4 Wochen und 3 Monate vor. Optional können Backups auch stündlich angefertigt werden (und werden 24h aufbewahrt). Für individuelle Varianten können wir miteinander sprechen. Die konkrete Uhrzeit, zu der Backups angefertigt werden, kann nicht festgelegt werden, ist aber gleichbleibend._

* [ ] **Werden Offsite-Backups benötigt?**

_Unsere Backups werden primär zur schnellen Wiederherstellung innerhalb des RZs aufbewahrt. Optional können Backups an unseren Backup-Standort in Halle gespiegelt werden._

* [ ] **Gibt es besondere Anforderungen an SSL-Zertifikate?**

_Standardmäßig werden Let’s-Encrypt-Zertifikate mit automatischer aktualisierung eingesetzt. Falls andere Zertifikate eingesetzt werden sollen oder Zertifikats-Pinning eine Rolle spielt sollten wir dies wissen._

* [ ] **Welche Standards sind zu berücksichtigen oder welche Zertifikate sind zu erbringen?**

_Der Flying Circus ist umfassend nach ISO 27001 zur IT-Sicherheit zertifiziert. Wir evaluieren laufend auch ob weitere Standards oder Zertifizierungen in Projekten relevant sind, benötigen hier aber gegebenenfalls entsprechende Vorlaufzeiten und Projektvolumina um diese zu realisieren._

* [ ] **Gibt es spezifische, weitergehende Sicherheitsanforderungen, die berücksichtigt werden müssen?**

```

## Architektur und Handwerkliches { #architektur }

```
(Titel des Tickets) Architektur und Handwerkliches

_Viele Anwendungen folgen ähnlichen architekturellen Ansätzen und verwenden Bibliotheken und Frameworks die bestimmte Themen einheitlich regeln. In Web-orientierten Projekten gibt es typischerweise eine Kombination von Webserver, Frontend, Backend, Datenbank und weiteren Diensten wie Message-Queues oder API-Anbindungen. Daten-fokussierte Anwendungen erfordern meist eine Cluster-Technologie zur Koordination von Jobs, sowie unterschiedliche Datenbanken. Die folgenden Fragen sollen uns helfen einen Überblick zu bekommen welche spezifischen Aspekte in diesem Projekt eine Rolle spielen und geben Denkanstöße um typische Fallen zu vermeiden._


* [ ] **Aus welchen Software-Komponenten besteht die Anwendung, welche begleitenden Dienste werden benötigt und wie kommunizieren diese untereinander?**

_Wünschenswert wäre ein Diagramm der wichtigsten Komponenten und eine möglichst vollständige Liste der konkreten Software._


* [ ] **Welche Bibliotheken, Programme oder Funktionen, sind einen zweiten Blick wert, da diese im Betrieb besondere Anforderungen haben könnten?**

_Hier denken wir an Themen wie PDF-Generierung, exotische oder ggfs. veraltete Biblioteken wie beispielsweise wkhtmltopdf, Bilderkennung (OCR), Kryptografie oder der Bedarf an speziellen CPU-Flags wie aes, sse oder Vektor-Operationen._


* [ ] **Werden große oder viele Dateien beim Upload, beim Download und in der Speicherung verarbeitet?**

_Wir empfehlen in diesem Kontext die Speicherung in unserem S3-kompatiblen Object Storage und raten dringend von der Verwendung von lokalen oder Netzwerk-Dateisystemen ab._

_Um beim Einsatz von S3 spätere Probleme zu reduzieren haben wir einen separaten [Guide für Entwickler](https://doc.flyingcircus.io/platform/infrastructure/storage.html#application-implementation-guidance) zur Strukturierung von Bucket-Namen und den Key-Namensräumen innerhalb der Buckets entwickelt._

* [ ] **Gibt es Eigenschaften der Anwendung, die eine horizontale Skalierung über mehrere Server verhindern? Wird NFS benötigt?**

_Typischerweise ist dies der Fall, wenn die Anwendung das Dateisystem für bewegliche Daten Sessions, Bilder, Caches o.ä. verwenden. Wenn dies der Fall ist und keine Möglichkeit besteht die Anwendung durch den Einsatz von S3, Redis, memcache und anderen Diensten in eine “Shared-Nothing”-Architektur zu überführen muss ein erhöhtes Augenmerk auf die möglichen Strategien zur Skalierbarkeit gelegt werden._

_Häufig werden Sessions lokal gespeichert. Diese sollten in Redis oder einer bereits genutzten Datenbank gespeichert werden. memcached sollte nicht für Sessions genutzt werden, da das Eviction-Verhalten für diesen Zweck nicht gut kontrollierbar ist._

* [ ] **Gibt es aufwändige Funktionen, die synchron bearbeitet werden und dadurch Threads oder Worker blockieren können?**

* [ ] **Welche asynchrone Job-Qeues kommen zum Einsatz und für welche Jobs werden diese genutzt?**

_Wir empfehlen den Einsatz spezialisierter Werkzeuge (z.B. Celery, RabbitMQ, oder ähnliches) um Job-Queues zu implementieren, da diese generell schon umfassende Möglichkeiten zum Monitoring und Management bei problematischen Jobs bieten. Allgemein sollte davon abgesehen werden generische Datenbanken wie MySQL zur Implementation von Job-Queues zu verwenden, hier wäre als Ersatz Redis zu empfehlen._


* [ ] **Wie werden regelmäßige Tasks verwaltet?**

_Regelmäßige Tasks sollten mindestens davor geschützt werden parallel zu laufen (Locking), sollten mit Timeouts versehen werden und müssen erlauben Fehler zu erkennen (Monitoring) und zu diagnostizieren (Logging). Bei fehlenden Alternativen wandeln wir Cron-Jobs in systemd-Timer um, sodass diese Anforderungen zumindest grundlegend erfüllt werden._

* [ ] **Gibt es Anforderungen an Plattform und Infrastruktur um Mandantenfähigkeit zu realisieren?**


* [ ] **Gibt es Gründe die Anwendung in unterschiedliche Produktiv-Umgebungen aufzutrennen?**

_Die Umgebungen im Flying Circus bilden Einheiten um Anforderungen an Sicherheit und Verfügbarkeit einheitlich zu verwalten. In komplexen Anwendungen, die mehrere Dutzend VMs verwenden, kann es sinnvoll sein, diese in unterschiedliche Einheiten aufzutrennen um separate Zugriffsrechte zu pflegen oder unterschiedliche SLA-Level vorzusehen._
```

## Deployment und Konfiguration     { #deployment }

```
(Titel des Tickets) Deployment und Konfiguration

_Einer der wichtigsten Aspekte mit denen wir ein Projekt erfolgreich machen können ist die Etablierung eines automatisierten Deployments. Dabei ist es wichtig, dass die Anwendung dies auch gut unterstützt: neue Funktionen und Fehlerbehebungen können dann äußerst schnell und zuverlässig den Nutzer*innen zur Verfügung gestellt werden. Wenn hier gut gemeinsam gearbeitet wird, dann stellen auch mehrere Releases pro Tag keine Herausforderung für Entwickler*innen und SREs im DevOps-Ansatz dar. Im Gegenzug ist versteckt sich hier aber auch eins der größten Risiken: lässt sich die Anwendung nicht zuverlässig vollständig automatisiert deployen, dann kann schnell eine Kette von negativen Auswirkungen das Projekt gefährden: wichtige Änderungen können nicht zeitnah ausgerollt werden, es entstehen Fehler und Downtimes, Arbeitszeit von Projektleiter*innen, Entwickler*innen und SREs werden in komplizierten Abstimmungen, Bürokratie und Fehlerbehebungen verschwendet - statt das Projekt gemeinsam voran zu bringen. Mit den folgenden Fragen wollen wir den Blick schärfen um das Projekt rechtzeitig auf einen erfolgversprechenden Pfad zu lenken._

* [ ] **Welche Release-Artefakte gibt es und wie werden diese versioniert?**

_Alle Abhängigkeiten müssen umfassend definiert und gepinnt sein, sodass Builds und Deployments zuverlässig wiederholbar und auch zurückrollbar sind._

_Bei Containern sollten die Versionsnummern alle auf konkrete Versionen gepinnt sein. Der Einsatz von “latest” ist nicht zulässig._

* [ ] **Wie werden die Abhängigkeiten der Anwendung oder die Container-Images aktuell gehalten?**

_Der Flying Circus liefert Security-Updates für die Plattform automatisch aus. Beim Aktualisieren von Container-Images oder Anwendungsdependencies ist die Build- und Test-Chain, sowie die Kompetenz der Entwickler gefragt und wir müssen uns abstimmen wie dieser Aspekt gemeinsam gehandhabt wird._

* [ ] **Werden dauerhafte oder temporäre Umgebungen abweichend von “Staging” und “Production” benötigt?**

_Wir gehen von mindestens zwei getrennten Umgebungen aus: Staging und Production. Staging dient sowohl dazu Änderungen in der Anwendung als auch regelmäßige Updates unserer Plattform zu testen. In einigen Situationen haben wir die Erfahrung gemacht, dass es eine einzelne Staging-Umgebung nicht ausreicht, weil Entwickler*innen, SREs, Kund*innen, und externe Tester*innen gleichzeitig darauf zugreifen müssen. Wir können je nach Bedarf weitere Umgebungen für Integrationstests, Abnahmen oder auch Entwickler bereitstellen._

* [ ] **Gibt es derzeit Abläufe, die ein vollautomatiertes Deployment verhindern und regelmäßig manuelle Eingriffe notwendig machen?**

_Unser Ziel ist es, dass wir gemeinsam Änderungen schneller und häufiger in Produktion nehmen, ohne dass bei jedem Release manuelle Arbeit notwendig ist. Dazu investieren wir gern in die Automatisierung der Pipeline sind aber auch darauf angewiesen, dass nicht jedes Release manuelle Änderungen an Umgebungsvariablen, Secrets, Versionsnummern etc. benötigt, sondern, dass sich dies auch geeignet automatisieren lässt._

* [ ] **Sind alle Konfigurationsparameter über Konfigurationsdateien oder Umgebungsvariablen steuerbar?**

_“Hard coded” Konfiguration gilt es zu vermeiden, da sonst Verwechslungen zwischen Staging und Production entsthen können oder uns im Notfall schnelle Eingriffsmöglichkeiten fehlen. Beispiele für Konfigurationsparameter sind: Verbindungen zu Datenbanken oder externen Diensten, IP-Adressen und Ports, Benutzernamen, Datenbanknamen, Passwörter,  API-Verbindungsdaten, API-Endpunkte, Domains, URLs, S3-Bucket-Namen, Keys, Listen-Adressen und Ports, …_

_Ein weiteres mögliches Anti-Pattern ist auch, dass Konfigurationsparameter in Datenbanken gespeichert werden. Dies kann im speziellen auch Content-Management-Systeme betreffen, bei denen Links zu internen Dokumenten mit absoluter URL/Domain gespeichert werden, sodass bei der Replikation von Daten aus der Produktiv- in die Staging-Umgebung Verwirrung für die Anwender entstehen kann, der zu unbeabsichtigen Schäden in der Produktivumgebung führen kann._

_Beim Einsatz von Docker ist zu beachten, dass die Konfiguration vollständig von außerhalb des Containers parametrisierbar sein muss und es keine abweichenden Images je nach Umgebung (Staging, Production) geben darf._

* [ ] **Wie werden Datenbank-Schemata migriert?**

_Automatisierte Deployments benötigen auch automatisierte, wiederholbare und kontinuierliche Migrationsskripte für Schema-Migrationen. Hier ist auch zu beachten, ob Migrationen online laufen können und ob die Anwendung einen kontinuierlichen Roll-Out verträgt._

* [ ] **Welche Interaktionen für System Reliability Engineers (SREs) sind vorgesehen?**

_Auf Systemebene kann es Skripte geben, die von SREs regelmäßig oder in besonderen Situationen benötigt werden. Hier wünschen wir uns eine Übersicht an Skripten oder Anleitungen, die bereits bekannt sind._

_Aber: ein regelmäßiges Eingreifen durch SREs um Standard-Geschäftsfälle zu behandeln ist nicht zulässig. Der flexible DevOps-Ansatz ersetzt nicht die Investition in Basis-Funktionalität._

* [ ] (Spezifisch für PHP-Anwendungen) **Kann die Anwendung mit einem “Eternal Opcache” umgehen?**

_Eine Eigenart von PHP besteht darin, dass der Quelltext bei potentiell jedem Request vollständig neu geparst wird. Das kostet wertvolle Zeit und Ressourcen und macht Anwendungen potentiell sehr langsam - zumal sich der Quelltext ohne Deployment nicht ändert. Wie setzen standardmäßig hier den sogenannten “Opcache” ein, der den Quelltext nur einmal parst und dann für folgende Requests cached. Dieser Cache wird von uns standardmäßig nur bei Neustarts des Servers oder einem Deployment gelöscht. Manche Anwendungen können damit Schwierigkeiten haben, speziell wenn dynamisch Code generiert wird._

```

## Last- und Kapazitätsplanung  { #kapazitaetsplanung }

```
(Titel des Tickets) Last- und Kapazitätsplanung

_Wir wollen die für das Projekt notwendige Infrastruktur bereits im ersten Schritt möglichst passend dimensionieren: zu große bedeutet unnötige Kosten; zu klein bedeutet das Risiko von schlechter Performance oder sogar Downtimes. Unsere Infrastruktur lässt sich zeitnah skalieren, aber bestimmte strukturelle Aspekte müssen wir rechtzeitig berücksichtigen um dann angemessen flexibel reagieren zu können. Im gemeinsamen Austausch bestimmen wir gern aufgrund unserer Erfahrung anhand der vorhandenen Daten das konkrete Setup. Wenn ein Projekt bereits eine Historie hat, dann ist es sehr hilfreich Daten aus verfügbaren Abrechnungen, Zugriffsstatistiken und Systemkonfigurationen einzubeziehen._

* [ ] **Für wie viele Nutzer*innen ist die Anwendung ausgelegt?**

_Je nach Anwendungsart kann es - zum Beispiel im Umfeld IoT - auch technische Clients geben, die ähnlich wie Nutzer*innen eingeplant werden sollten._


* [ ] **Mit wie vielen gleichzeitigen Nutzer*innen wird gerechnet?**

_Gleichzeitige Nutzung kann unterschiedliche Auswirkung haben: viele offene Verbindungen, hohe Zugriffszahlen, höherer Speicherverbrauch oder andere Ressourcen (Job-Queues), die zum Flaschenhals werden. Je genauer wir hier die Anforderungen und die reale Situation der Implementation kennen, desto besser können wir einschätzen ob ein einfacheres Setup (das nicht spontan skalieren muss) oder ein anspruchsvolleres Setup (das sehr plötzlich sehr viel skalieren muss) benötigt wird. Gleichzeitig sollte das auch den Entwickler*innen entsprechend helfen zu planen welche Funktionen und Code-Pfade hier möglicherweise ein gutes Skalieren begünstigen oder erschweren könnte._


* [ ] **Mit wie vielen Zugriffen wird im Monat gerechnet?**

_Um die Last zu planen helfen uns sowohl Zugriffszahlen, die einzelne URLs wiederspiegeln (wie man sie aus Webserver-Logs erhält) oder auch gröbere Zahlen zu Seitenabrufen (wie man sie aus Analyse-Tools erhält). Auch unique vs. wiederholte Besuche und Abrufe sind interessant._


* [ ] **Welche Datenmengen werden gespeichert und wie sieht das Wachstum bei konstanter und steigender Nutzung aus?**

_Hier wäre wissenswert in welcher Größenordnung (wenige Megabyte, einige Gigabyte, dutzende oder hunderte Gigabyte oder mehr) welche Arten von Daten in welchen Funktionen oder Teilsystemen anfallen. Auch ob die Daten im Verlauf der Nutzung wieder gelöscht werden und sich dadurch ein Sättigungspunkt einstellen sollte oder ob die Daten potentiell unendlich lange aufbewahrt werden und dadurch mit potentiell unendlichem Speicherbedarf zu rechnen ist._

_Insbesondere wenn es sich um besonders große oder zahlreiche Bilder, Videos, Dokumente, Archive handelt sollten wir gemeinsam schauen wie diese gehandhabt werden._


* [ ] **Welche Datenmengen werden durchschnittlich pro Monat aus dem oder in das Internet übertragen?**

_Um die Kosten gut abzuschätzen benötigen wir eine grobe Zahl in Gigabytes (GiB) oder Terabytes (TiB) welche Daten in Summe übertragen werden. 100 GiB stehen jedem Projekt monatlich ohne zusätzliche Kosten zur Verfügung._

_Daten, die zwischen VMs innerhalb eines Rechenzentrums übertragen werden, werden sind immer inklusive._


* [ ] **Welche Spitzenauslastung im Traffic zum Internet werden erwartet?**

_Traffic im Internet wird in MBit/s oder GBit/s angegeben. Hilfreich sind Erfahrungswerte um mögliche Engstellen frühzeitig abschätzen zu können._


* [ ] **Welche spezifischen Anforderungen oder Erfahrungen in Bezug auf CPU, RAM und Storage liegen vor?**

_Bei Projekten, die bereits produktiv betrieben werden oder die bereits während der Entwicklungs- oder in der Testphase entsprechende Erfahrungen gemacht haben._

_Neben der Menge an CPUs und Arbeitsspeicher ist hier auch die größe und die Art der Storages relevant. Sind normale schnelle Disks (250 IOPS) oder schnellere Disks (10.000 IOPS) angemessen?_

* [ ] **Welche regelmäßigen, saisonalen Lastprofile und Lastprognosen spielen eine Rolle?**

_Lastprofile unterscheiden sich häufig je nach Tageszeit, aber auch über Wochen oder Monate hinweg können starke Unterschiede bestehen, zum Beispiel durch die Aussendung von Newslettern, Pushnachrichten, Live-Events oder Werbung._

```

## Performance und Skalierbarkeit   { #skalierung }

```
(Titel des Tickets) Performance und Skalierbarkeit

_Neben einer passenden Auslegung der Infrastruktur gibt es unterschiedliche Detailaspekte von Anwendungen, die beeinflussen wie wir im Fall von steigender Last reagieren können. Bestimmte Funktionen und Komponenten müssen bei Überschreiten von kritischen Grenzen neu ausgelegt und anders aufgebaut werden. Horizontale Skalierung liefert auf Anwendungsebene hier häufig die besten Hebel - gleichzeitig hilft es nur wenig eine Funktion, die aufgrund ungünstiger Algorithmen oder Datenbankstrukturen auf mehr Server zu verteilen._

* [ ] **Welche Performance-Probleme sind bekannt?**

_Wir können hier proaktiv tätig werden, wenn wir grob wissen bei welchen Funktionen oder Komponenten und in welchen Situationen es zu Performance-Problemen kommt._

* [ ] **Welche langlaufenden Requests oder Jobs gibt es?**

_Langlaufende Requests können zu Verfügbarkeitsschwierigkeiten führen, wenn diese Worker-Prozesse blockieren. Hier können wir zum einen darauf achten diese Schwierigkeiten durch geschicktes Load-Balancing nicht eskalieren zu lassen._

_Gleichzeitig können wir, wenn diese Langläufer in Summe zu Problemen führen, gemeinsam diagnostisch Vorgehen und beispielsweise Profiling und Datenbank-Query-Analysen anwenden um fehlende Indices oder ungünstige Datenstrukturen und Algorithmen zu erkennen und mögliche Lösungsstrategien aufzeigen._

* [ ] **Welche Caching-Konzepte werden benötigt?**

_Für Anwendungen die weitestgehend Lese-Zugriffe statt Schreibzugriffe verzeichnen empfehlen wir den Einsatz entsprechender Caching-Werkzeuge. In den meisten Fällen ist hier varnish das Werkzeug der Wahl. Gleichzeitig gibt es gegebenenfalls weitere Caching-Anforderungen von Teilkomponenten der Anwendung, diese sollten wir ebenfalls klären._

* [ ] **Wie verhält sich die Anwendung unter Last und einem Cold-Cache-Szenario, also bei spontanem Verlust der Caches?**

* [ ] **Wie werden vorhandene Caches invalidiert?**

* [ ] **Welche Integration mit spezifischen Caching-Regeln muss berücksichtigt werden?**

_Varnish kann in einigen Situationen mit sehr allgemeinen Cache-Regeln verwendet werden, wenn die Anwendung entsprechende Header ausliefert und (siehe oben) entsprechende Invalidierungs-Nachrichten schickt._

_Gleichzeitig können wir spezielle Regeln vorsehen um komplexere Caching-Strategien zu implementieren, beispielsweise um korrektes Caching auch für angemeldete Benutzer sicherzustellen._

```

## Netzwerk, Internet, externe Dienste und APIs     { #netzwerk }

```
(Titel des Tickets) Netzwerk, Internet, externe Dienste und APIs

_Das Netzwerk im Flying Circus entworfen worden um unterschiedlichste Anwendungen sicher und performant zu betreiben, sodass Entwickler sich darüber weitestgehend keine Gedanken machen müssen. Gleichzeitig gibt es aus unserer Erfahrung eine Reihe von neuralgischen Punkten, die frühzeitig geklärt werden sollten um böse Überraschungen zu vermeiden._

* [ ] **Welche Anforderungen bestehen hinsichtlich der Netzwerkarchitektur?**

_Die Netzwerk-Architektur im Flying Circus sieht eine Trennung zwischen externem und internem Traffic vor und beinhaltet Firewalls an der RZ-Grenze und auf jeder einzelnen virtuellen Maschine._

_Gleichzeitig gibt es manchmal relevante Anforderungen in Bezug auf externe Firewalls, NAT-Traversal oder öffentliche IP-Adressen._

* [ ] **Spricht etwas gegen die Verwendung von IPv6?**

_Wir bieten alle Kundendienste standardmäßig per Dual-Stack (IPv4 + IPv6) an. Zwar ist in Deutschland die Nutzung von IPv4 bisher uneingeschränkt für Endkunden möglich, so bietet IPv6 jedoch inzwischen, speziell bei mobilen Nutzer*innen deutliche Vorteile in Bezug auf Geschwindigkeit und Zuverlässigkeit._

* [ ] **Welche VPN-Verbindungen werden benötigt?**

_Um Nutzer\*innen, Standorte oder APIs anzubinden können unterschiedliche Technologien zum Einsatz kommen. Wir empfehlen grundsätzlich je nach Einsatzzweck Wireguard und OpenVPN. Wenn keine anderen Optionen zur Verfügung stehen unterstützen wir auch IPsec - allerdings ist dies häufig mit Schwierigkeiten bei der Einrichtung und teilweise auch - je nach Unterstützung durch die Gegenstelle - Herausforderungen bei eventuell notwendiger Problembehebung im Fehlerfall verbunden._

* [ ] **Wer betreibt den relevanten DNS-Server?**

_DNS-Betrieb bieten wir vom Flying Circus als Inklusiv-Service mit umfassendem Self-Service-UI an. Allgemein sind unsere SLAs umfassender abgedeckt, wenn wir im Fehlerfall auch bei DNS-Themen 24/7 handlungsfähig sind und nicht auf externe Hilfe angewiesen sind, die gegebenenfalls nicht passend zum gewählten SLA reaktionsfähig ist._

_Falls Domains nicht komplett von uns verwaltet werden sollen können wir auch anbieten eine delegierte Sub-Zone zu verwalten und das Thema dadurch etwas zu entschärfen._

* [ ] **Welche Arten von E-Mails werden versendet oder emfangen?**

_E-Mail ist ein in sich breites Thema und kann hier nur angerissen werden. Wir unterscheiden grundsätzlich den Versand von Massenmails und Transaktionsmails oder den Bedarf an “Enduser-Mailservern”._

* [ ] **Welcher Typ Mailserver soll eingesetzt werden?**

_Wir können externe Mailserver anbinden, APIs von Dienstleistern verwenden oder ein Mailserver beim Flying Circus betrieben werden. Dies hat auch jeweils Auswirkungen wie die Anbindung von den Entwicklern realisiert ist (SMTP, IMAP, API) und welches Monitoring und welche Handlungsmöglichkeiten im Fehlerfall dem SRE-Team zur Verfügung stehen._

* [ ] **Werden dynamische oder statische Mail-Accounts verwendet?**

* [ ] **Wer ist für die korrekte Konfiguration von E-Mail-Domains im DNS zuständig?**

_Um eine gute Zustellrate für versendete E-Mails zu erzielen müssen eine Reihe spezifischer Domain-Authentifierungsprotokolle (DMARC, DKIM, SPF) gesetzt werden. Dies geschieht im DNS-Server. Wenn der Flying Circus den DNS für die relevanten Domains verwaltet übernehmen wir dies._

* [ ] **Welche dritten Parteien werden direkt oder indirekt in die Anwendung eingebunden?**

_Abseits von den Nutzer*innen der Anwendung kann es sein, dass eingehende oder ausgehende API-Calls eine Rolle spielen, die besonders betrachtet werden sollten. Speziell wenn diese synchron oder im Kontext von Nutzeranfragen stattfinden._


```

## Monitoring, Zuverlässigkeit, Business Continuity     { #monitoring }

```
(Titel des Tickets) Monitoring, Zuverlässigkeit, Business Continuity

_Grundsätzlich sollen Systeme im Idealfall natürlich keine Fehler aufweisen. Gleichzeitig ist die Erkenntnis aus dem Betrieb komplexer Systeme: Fehler passieren. Man kann deshalb nur zu einem Teil Fehler verhindern und muss sich auf der anderen Seite darauf vorbereiten mit Fehlern umzugehen. Wir wägen zwischen diesen beiden Maßnahmen ständig ab um Stabilität und Flexibilität in Einklang zu bringen. Um für Fehlerfälle vorbereitet zu sein klären wir die an das System gestellten Erwartungen, stellen sicher dass wir im Ernstfall handlungsfähig sind, wollen dass kleinere Fehler möglichst keine größeren Fehler nach sich ziehen und geben Anregungen wie auch Entwickler*innen dazu beitragen können._

* [ ] **Welche Fehler haben in der Vergangenheit zu Problemen, Downtimes oder Störungen geführt?**

* [ ] **Welche drei Aspekte haben im laufenden Betrieb bisher am meisten Herausforderungen bereitet?**

* [ ] **Welche potenziellen Probleme würden am meisten Sorgen bereiten?**

* [ ] **Reagiert die Anwendung bei kurzen Störungen oder unklaren Fehlern korrekt und erholt sich selbständig oder “stürzt sauber ab”?**

_Manche Frameworks neigen dazu, beispielsweise bei kurzen Verbindungsverlusten zur Datenbank, ohne externen Eingriff in einen teilweise schlecht erkennbaren inkonsistenten Zustand zu geraten._

_Unser grundsätzlicher Ansatz zur Optimierung der “Mean Time To Recovery” sieht vor, dass es in komplexen Systemen immer zu kurzzeitigen Fehlern kommen kann und die Anwendung als ganzes solche Zustände ohne manuellen Eingriff überstehen kann._

* [ ] **Wie wir mit Vorgängen umgegangen, die nicht durch Transaktionen geschützt sind, und in inkonsistente Zustände geraten können?**

_Speziell bei geplanten oder ungeplanten Reboots oder spontanen Crashes von Anwendung oder Betriebssystem sollte es nicht generell notwendig sein manuell einzugreifen um das System wieder in einen betriebsfähigen Zustand zu versetzen._

* [ ] **Wie kann die Kommunikation mit externen Diensten beobachtet werden?**

_Anfragen an externe Dienste und APIs müssen in den Logs ersichtlich sein und Request-Beginn und Request-Ende mit eindeutigen IDs und Zeitstempeln ausweisen. Gleichzeitig sollte es eine Option geben die Nutzdaten von Requests an externe Dienste bei Bedarf zu loggen._

* [ ] **Wie reagiert die Anwendung, wenn externe Dienste down sind oder undefiniert nicht reagieren?**

_Ein sauberes Verhalten der Anwendung wäre gegeben, wenn “graceful degradation” dazu führt, dass sich zum einen keine Requests unendlich lang aufstauen und dadurch andere Teile der Anwendung blockieren und zum anderen, dass Nutzer zeitnah eine Antwort mit entsprechendem Hinweis, dass bestimmte Funktionen nicht zur Verfügungs stehen erhalten. Gleichzeitig sollten Nutzerdaten in diesem Fall nicht verloren gehen._

* [ ] **Welche Endpunkte für Metriken und Monitoring stehen in der Anwendung zur Verfügung?**

_Idealerweise stellt die Anwendung einen Prometheus-kompatiblen Endpunkt per HTTP zur Verfügung von dem wir Metriken rund um das Anwendungsverhalten in unsere Telemetrie-Infrastruktur integrieren können._

_Außerdem benötigen wir einen Endpunkt, der per HTTP angesprochen werden kann und beispielsweise mit JSON-Output antwortet und maschinen- und menschenlesbare Statusinformationen bereitstellt. Es sollten spezifische Diagnosen, wie beispielsweise “Datenbank nicht erreichbar - Fehlermeldung: [Details]” enthalten sein._

* [ ] **Wie kann die Readiness der Anwendungsprozesse nach Start abgefragt werden?**

_Readiness-Probes dienen dazu um Prozessmanagern die Unterscheidung korrekter oder fehlerhafter Starts zu ermöglichen und um zu verhindern, dass Load-Balancer Anfragen an Ports weiterleiten, die noch nicht antwortbereit sind._

* [ ] **Welcher Support-Level und Reaktionszeiten sind erwünscht?**

_Der Flying Circus bietet zwei Service-Level an: Guided und Managed._

_Im Rahmen des Guided-Service-Levels unterstützen wir bei der Migration, Konfiguration und Wartung auf unserer Plattform, entwickeln gemeinsam einen Migrationsplan und definieren den Projektablauf. Die Umsetzung übernehmen Sie._

_Im Managed-Service-Level übernehmen wir die vollständige Betriebsverantwortung, entwickeln ein voll-automatisiertes Deployment Ihrer Anwendung auf unserer Plattform und betreiben Ihre Anwendung dauerhaft stabil und sicher._

_In beiden Varianten legen Sie fest, welche maximalen ungeplanten Downtimes monatlich zulässig sind und ob wir bei anwendungsspezifischen Fehlern während der normalen Geschäftszeiten (Mo-Fr, 8-16 Uhr, 3h Reaktionszeit), zu erweiterten Zeiten (Mo-So, 7-21 Uhr, 1h Reaktionszeit) oder 24/7 (1h, oder 15 Min) reagieren._

* [ ] **In welchem Zeitfenster dürfen automatisierte Wartungsarbeiten durchgeführt werden?**

_Unser Standardzeitfenster liegt zwischen 22 Uhr und 5 Uhr nachts und meldet notwendige Wartungsarbeiten mindestens 12 Stunden vorher per E-Mail an die technischen Ansprechpartner. Das Zeitfenster kann frei nach den eigenen Bedürfnissen bestimmt werden, darf aber nicht zu kurz gefasst werden, da Wartungsarbeiten über mehrere Maschinen hinweg nacheinander eingeplant werden. Außerdem sollte die Vorankündigungszeit nicht mehr als wenige Tage betragen, da sonst Sicherheitsupdates nicht zeitnah eingespielt werden können._

* [ ] **Welche Schritte sind zur Vor- und Nachbereitung von Wartungsfenstern notwendig?**

_Es kann erforderlich sein bestimmte Prozesse vor Unterbrechungen zu schützen oder die Anwendung sauber in einen Wartungszustand zu versetzen oder wieder zu aktivieren. Unser Wartungsmanagement erlaubt hier eine Automatisierung. Manuelle Eingriffe sind für regelmäßige Wartungsfenster nicht zulässig._
```
