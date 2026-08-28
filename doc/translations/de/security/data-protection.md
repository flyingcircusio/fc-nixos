---
global_sync_id: "v1"
---

% last review: 2026-07-31

% review schedule: 1 year

% Customers need to be notified when substantial changes occur in this document!

# Datenschutzmaßnahmen { #data-protection }

Neben rein technischen Sicherheitsmaßnahmen implementieren wir
zusätzliche Maßnahmen, um eine sichere Umgebung für deine Daten und die
Daten deiner Kunden zu schaffen, basierend auf den folgenden Standards
und Vorschriften:

![](Zertlogo_Flying_Circus_bunt.png){ .off-glb }

- [Zertifiziertes](https://flyingcircus.io/iso-27001-de.pdf) Informationssicherheitsmanagementsystem (ISMS) basierend auf ISO/IEC 27001,
- Das [Bundesdatenschutzgesetz (BDSG)](http://de.wikipedia.org/wiki/Bundesdatenschutzgesetz), und
- die [Datenschutz-Grundverordnung (DS-GVO)](https://de.wikipedia.org/wiki/Datenschutz-Grundverordnung) der EU.

## Verantwortliche Stellen

**Informationssicherheitsbeauftragte:**

Christian Zagrodnick (CISO) \
<mailto:cz@flyingcircus.io>

Christian Schmidt (ISO) \
<mailto:cs@flyingcircus.io>

**Datenschutzbeauftragter:**

Prof. Dr. Andre Döring \
Robin Data GmbH \
Fritz-Haber-Straße 9 · 06217 Merseburg \
<https://www.robin-data.io> · <mailto:datenschutz@robin-data.io> \
[+49 3461 4798960](tel:+4934614798960)

## Allgemein

Dieses Dokument beschreibt unsere Sicherheitsmaßnahmen, gemäß GDPR Art. 32 (1). Basierend auf unserer ISO 27001-Zertifizierung betreiben wir ein risikobasiertes ISMS, aus dem sich umfangreiche Sicherheitsmaßnahmen und dazugehörige Dokumentation ableiten. Wir liefern
an dieser Stelle einen Überblick der wesentlichen Punkte.

Da einige der gesetzlichen Anforderungen von der spezifischen
(vertraglichen) Situation abhängen, möchten wir zunächst die allgemeine
Situation skizzieren, in die dich das Hosting im Flying Circus bringt:

Auftragsverarbeitung

: gilt im Rahmen der DS-GVO. Wir werden mit dir einen zur DS-GVO passenden
  Vertrag zur Datenverarbeitung umsetzen.

Auskunfsrecht

: Personen, die von der Datenverarbeitung betroffen sind, haben das Recht,
  Auskunft darüber zu verlangen, welche Daten über sie gespeichert sind und
  wie diese Daten gesichert werden.

Regelmäßige Überprüfung auf Einhaltung der Vorschriften:

: Es liegt in der Verantwortung des Auftraggebers, routinemäßig zu überprüfen, ob
  die geltenden Vorschriften von seinem Auftragnehmer eingehalten werden.
  Jährliche Kontrollen scheinen auch bei hochsensiblen Daten (z.B. Krankenakten)
  ausreichend zu sein. Das Ergebnis muss in schriftlicher Form dokumentiert
  werden. Die Prüfung muss in der Regel durch eine dritte Partei durchgeführt
  werden.


## Maßnahmen

### (1) Zugangskontrolle { #entry-control }

**Zweck: Verwehrung des Zugangs zu Verarbeitungsanlagen, mit denen die Verarbeitung
durchgeführt wird, für Unbefugte**

Die physischen Anlagen (Server, Switches, Festplatten, ...) befinden sich in
EU-Rechenzentren, die gegebenenfalls von Dritten betrieben werden. Das Eigentum an den
physischen Anlagen liegt beim Flying Circus, oder, in besonderen Fällen, bei unseren Kunden
[^customer-owned].

Für jedes von uns genutzte Rechenzentrum verlangen wir die
folgenden Maßnahmen:

- Videoüberwachung (Außenanlagen, Innenräume und Rack-Korridore)
- Ein zweiter Faktoren für die Zugangsgewährung mit
  Protokollierung
- der physische Zugang muss dokumentiert
  werden
- vorzugsweise 24 Stunden Wachdienst mit vernetztem
  Alarmsystem
- getrennte physische Sicherheitszonen für allgemeine Bereiche,
  Rechenzentrumsinfrastruktur und für Kunden zugängliche Bereiche
- separat abschließbare Racks mit der Möglichkeit eigene Schlösser und
  Schlüssel zu verwenden.


% ISMSControl: 7.1
% ISMSControl: 7.2
% ISMSControl: 7.3
% ISMSControl: 7.4

Wir unterhalten ein separates [List of data centers](../infrastructure/hardware/data-centers.md#data-centers).

Der physische Zugang zu Datenverarbeitungsanlagen darf nur von den Flying Circus Administratoren vorgenommen werden. Administratoren können den physischen Zugang an andere Personen (z.B.
Mitarbeiter des Rechenzentrums) delegieren.

#### Standorte mit niedriger Sicherheit

Der Flying Circus betreibt eine Zone mit geringerer Sicherheit, die `development`
(für die Entwicklung der Infrastruktur des Flying Circus) genannt wird.

Diese Standorte dürfen derzeit nicht für die Speicherung von Kundendaten
genutzt werden, da sie nicht ausreichend geschützt sind.

Aufgrund dieser Einschränkungen dürfen die Dienste in Hochsicherheitsbereichen nicht von den Diensten in Niedrigsicherheitsbereichen
abhängen.


### (2) Datenträgerkontrolle

**Zweck: Verhinderung des unbefugten Lesens, Kopierens, Veränderns oder Löschens von
Datenträgern**

Nur Flying Circus Administratoren dürfen physischen Zugriff auf Datenträger haben. Der Zugriff kann z.B. an Mitarbeiter des
Rechenzentrums delegiert werden.

Die Überführung von Datenträgern zwischen sicheren Standorten wird von Flying Circus Mitarbeitern oder
vertrauenswürdigen Versanddienstleistern abgewickelt.

Die Entsorgung gebrauchter Medien erfolgt über einen zertifizierten
Datenvernichtungsdienstleister.


### (3) Speicherkontrolle { #data-at-rest-encryption }

**Zweck: Verhinderung der unbefugten Eingabe von personenbezogenen Daten sowie der unbefugten Kenntnisnahme, Veränderung und Löschung von
gespeicherten personenbezogenen Daten**

Alle Daten in unseren [Speicherclustern](../infrastructure/storage.md#infrastructure-storage) werden verschlüsselt gespeichert. Dazu gehören der *Virtual Disk Block Storage*,
unser *S3-kompatibler Object Storage* und [alle automatisierten Backups](../infrastructure/backup.md#backup). Es gibt technische und organisatorische Maßnahmen zum Schutz der
entsprechenden Schlüssel.

Auf technischer Ebene verwenden wir den üblichen Linux [cryptsetup](https://gitlab.com/cryptsetup/cryptsetup) Software-Stack mit LUKS2-Metadaten und XTS-AES-512-Verschlüsselung. Wir
überprüfen regelmäßig die Empfehlungen in Standardrichtlinien und aus Arbeitsgruppen und sind in der Lage, die verwendeten
Verschlüsselungsparameter bei Bedarf zu aktualisieren.

Außerdem:

- Wir löschen Daten nach den steuer- oder handelsrechtlichen
  Aufbewahrungsfristen.
- Die Zugriffslogdateien werden
  anonymisiert.
- Wir löschen Kundendaten auf Wunsch des Kunden.


### (4) Benutzerkontrolle

**Zeck: Verhinderung der Nutzung automatisierter Verarbeitungssysteme mit Hilfe von Einrichtungen zur Datenübertragung
durch Unbefugte**


% ISMSControl: 5.16
% ISMSControl: 5.17
% ISMSControl: 8.5

Maschinen, die vom Flying Circus verwaltet werden, können über mehrere Wege zu
Verwaltungszwecken erreicht werden: SSH, Webschnittstellen und andere. Wir
verwenden dabei ein einheitliches Schema, um Benutzer innerhalb des Flying Circus
zu identifizieren und zu autorisieren. Der Zugriff zur Verwaltung der Systeme muss
über verschlüsselte Kommunikationskanäle erfolgen.

Die Identifizierung und Autorisierung durch Kundenanwendungen, die nicht von der Flying Circus Infrastruktur verwaltet werden, fallen nicht unter unsere
Sicherheitsverantwortung. Unsere Kunden sind verpflichtet, die Sicherheit ihrer Anwendungen selbst zu gewährleisten.

Die Benutzeridentifizierung muss mit *persönlichen* Zugangsdaten erfolgen,
damit Aktionen zu einem individuellen Urheber zurückverfolgt werden können.
Die Weitergabe der eigenen Zugangsdaten an andere Personen ist daher
verboten. Die Zugangsdaten können je nach Anwendbarkeit entweder aus einem
Benutzernamen und einem kryptografischen Verfahren (z. B. einem
privaten/öffentlichen Schlüssel) oder einem Passwort bestehen.

Nutzer mit einem Flying-Circus-Konto sind verpflichtet, ihr Passwort sicher zu verwalten: Passwörter dürfen nicht kompromittiert werden, wenn auf ein Gerät unbefugt zugegriffen wird (logisch oder physisch). Zu beachtende Dinge sind z.B.: Home-Verzeichnis auf einem Notebook, Schlüsselbund oder Passwortmanager-Software, Backups, USB-Sticks, Smartphones. Stark verschlüsselte Speicherung von Passwörtern ist erlaubt und sogar angeraten. Für Flying Circus Mitarbeiter gibt es eine separate *Richtlinie zum
Umgang mit geheimen Authentifizierungsinformationen*.

Alle Hardware-Maschinen haben Notfall-Root-Logins, die nur von Flying Circus
Administratoren verwendet werden dürfen, wenn die reguläre Benutzerauthentifizierung
nicht korrekt funktioniert. Solche Verwendungen werden überwacht und müssen dokumentiert
werden.

Alle privilegierten Aktionen müssen sicher protokolliert werden. Für Maschinen, die auf unserer aktuellen (NixOS) Plattform basieren, wird dies über ein lokales Logging-Journal erreicht, das von normalen Benutzern nicht manipuliert werden kann. Zusätzlich werden die Systemlogs an einen zentralen Logserver innerhalb des
gleichen Standorts versendet, wo die Logs analysiert und überwacht werden.

SSH-Logins müssen mit SSH-Schlüsseln durchgeführt werden. Passwortauthentifizierung ist nicht erlaubt und wird durch die Systemkonfiguration verhindert. Erfolgreiche SSH-Anmeldungen an Maschinen werden protokolliert, erfolglose SSH-Anmeldeversuche nicht [^log-unsuccessful-attempts]. Übermäßige fehlschlagende Login-Versuche per SSH werden automatisch per
Firewall unterbunden.

Passwörter für physische Maschinen, die Zugriff auf Root-Konten und
IPMI-Controller gewähren, werden als Kopien in einem stark verschlüsselten
Passwortmanager gespeichert.

### (5) Zugriffskontrolle { #access-control }

**Zweck: Gewährleistung, dass die zur Benutzung eines automatisierten Verarbeitungssystems Berechtigten ausschließlich zu den von ihrer Zugangsberechtigung
umfassten personenbezogenen Daten Zugang haben**

% ISMSControl: 5.15
% ISMSControl: 5.18
% ISMSControl: 8.3

Auf kundeneigene virtuelle Maschinen können alle Flying Circus Administratoren implizit zugreifen. In Projekten können weitere Mitarbeiter (z.B. Support-Mitarbeiter) expliziten Zugriff erhalten. Der Zugriff durch andere (z.B. Kundenpersonal, Dritte) muss durch einen
Kundenvertreter autorisiert werden.

% ISMSControl: 5.16

Benutzer werden zentral über <https://my.flyingcircus.io> verwaltet. Benutzer werden automatisch auf alle relevanten Systeme provisioniert, einschließlich der ordnungsgemäßen Entfernung von
Zugriffsrechten.

Flying Circus implementiert ein auf Berechtigungen basierendes Konzept, um
Aufgaben der Anwendungswartung von privilegierten administrativen Aufgaben zu
trennen: zum Beispiel Kundensoftware-Updates oder Datenbankzugriff versus
Betriebssystem-Updates oder Betriebssystemkonfiguration.

% ISMSControl: 8.2

Privilegierter administrativer Zugriff wird generell nicht an Kunden
gewährt. In Fällen, in denen eine andere Person, die kein Administrator
ist, benötigt wird, um ein Problem zu lösen, muss eine gemeinsame
Sitzung zwischen einem Administrator und der anderen Person
eingerichtet werden (z.B. mit `screen`).

Technisch gesehen gibt es drei Zugangsvarianten, um privilegierte
administrative Operationen durchzuführen:

1. Verwendung eines Benutzerkontos, dem die 'login' und 'wheel' [Berechtigungen](../platform/users/index.md#permissions) für ein bestimmtes Projekt
   erteilt wurden. Dies erfordert, dass der Benutzer sich mit seinem SSH-Schlüssel in einen
   regulären Account einloggt und zusätzlich sein Passwort angibt, um auf privilegierte
   Operationen zuzugreifen.
2. Die Verwendung eines Benutzerkontos, das Mitglied der
   globalen Gruppe der Administratoren ist, die Zugriff
   auf alle Maschinen innerhalb der Flying Circus
   Infrastruktur gewährt.
3. Notfall-Root-Logins (siehe oben in [(1) Zugangskontrolle](data-protection.md#entry-control)).

Autorisierte und unautorisierte Zugriffe auf privilegierte Operationen werden auf einem zentralen Loghost innerhalb desselben
Standorts protokolliert und analysiert. [^trace-tty]

Flying Circus pflegt eine Liste von Berechtigungen, die es den Nutzern
ermöglichen, Anwendungswartung und andere semi-privilegierte Aufgaben
durchzuführen, z.B. Zugriff auf Service-Benutzerkonten oder
Datenbank-Administrationsrechte. Die Berechtigungen werden den einzelnen Nutzern
durch den Kunden oder auf Kundenwunsch gewährt.

Alle Berechtigungsvergaben sind nachvollziehbar und explizit dokumentiert: ihre
Auswirkungen werden im Konfigurationscode und ihre Zuordnungen in der
Konfigurationsdatenbank dokumentiert. Eine umfassende Liste der Benutzer und
ihrer Berechtigungen kann auf Wunsch automatisch erstellt werden.

Gruppenkonten dürfen generell keine privilegierten administrativen
Operationen durchführen, um die Nachvollziehbarkeit von Aktionen zu
gewährleisten.

% ISMSControl: 8.11

Es gibt keine besonderen Regelungen zur Datenmaskierung[^data-masking].

### (6) Übertragungskontrolle

**Zweck: Gewährleistung, dass überprüft und festgestellt werden kann, an welche Stellen personenbezogene Daten mit Hilfe von Einrichtungen zur Datenübertragung übermittelt oder zur
Verfügung gestellt wurden oder werden können**

Die Übertragungskontrolle liegt in der Regel in der Verantwortung der Anwendung des
Kunden.

In das Flying Circus Portal eingegebene Daten werden nicht an Dritte
weitergegeben.


### (7) Eingabekontrolle

**Zweck: Gewährleistung, dass nachträglich überprüft und festgestellt werden kann, welche personenbezogenen Daten zu welcher Zeit und von wem in automatisierte Verarbeitungssysteme eingegeben oder
verändert worden sind**

Die Sicherheit der Dateneingabe, -änderung und -löschung ist generell Teil der
Anwendung des Kunden. Kunden müssen sicherstellen, dass die Dateneingabe,
-löschung und -entfernung entsprechend ihrer geltenden Datenschutzgesetze
angemessen gehandhabt wird.

Im Rahmen von Wartungsarbeiten kann es jedoch notwendig sein, dass
Administratoren Datensätze auf einer niedrigeren, technischen Ebene eingeben,
ändern oder löschen müssen, um den weiteren Betrieb des Gesamtsystems zu
gewährleisten. Dies wird nur geschehen, nachdem wir die betroffenen Kunden
informiert und dies in unserem Issue-Tracking-System dokumentiert haben.

Verwaltete Log-Dateien werden von der Flying Circus Infrastruktur automatisch
mit sinnvollen Aufbewahrungszeiten rotiert.

Änderungen im Flying Circus Benutzerverzeichnis (z.B. SSH-Schlüssel) können vom
Kunden selbst oder durch unseren Support durchgeführt werden. Erfolgt die
Änderung durch unseren Support, so muss diese vorher dokumentiert und nach der
Änderung durch den Kunden bestätigt werden.


### (8) Transportkontrolle

**Zweck: Gewährleistung, dass bei der Übermittlung personenbezogener Daten sowie beim Transport von Datenträgern die Vertraulichkeit und Integrität der Daten
geschützt werden**

% ISMSControl: 8.26


Alle privaten Daten, die über die Grenze einer Maschine hinaus übertragen
werden, müssen einen authentifizierten und verschlüsselten
Kommunikationskanal nutzen (Ausnahmen siehe unten). Zu den Datenpfaden,
auf denen sensible Informationen übertragen werden können, gehören:

- Anwendungsdaten (z.B. Datenbankinhalte) werden vom oder zum Kunden über die
  standardisierten verschlüsselten Protokolle, z.B. SCP/SFTP, https,
  übertragen.
- Persistente Daten werden auf Storage-Servern gespeichert. Der Datentransfer wird aus
  Performance-Gründen nicht verschlüsselt. Storage-Server sind mit Anwendungsservern über ein
  privates Netzwerk verbunden. Maschinen, auf denen Kunden administrative Privilegien gewährt
  werden, dürfen sich nicht direkt mit dem Speichernetzwerk verbinden (siehe auch [Network security](network.md#network-security)).
- Backups werden entweder über einen verschlüsselten Kommunikationskanal oder über das private Speichernetzwerk
  auf Backup-Server am selben Standort übertragen. Backup-Daten können auch auf externe Backup-Server übertragen
  werden, um die Desaster-Recovery-Fähigkeiten zu verbessern. Die Datenübertragung muss verschlüsselt erfolgen.
- Zusätzlich zu den Anwendungsdaten kann ein System zur Laufzeit Daten erzeugen, die sensible Informationen enthalten, zum Beispiel Log-Dateien. Log-Dateien verlassen in der Regel nicht den Rechner, auf dem sie erzeugt wurden, es sei denn,
  der Kunde betreibt einen Logging-Server. Log-Daten können auch über einen verschlüsselten Kanal an einen von Flying Circus betriebenen Log-Server am selben Standort übertragen werden. Nur Flying Circus-Administratoren dürfen Zugriff
  auf den zentralen Log-Server haben.


### (9) Wiederherstellbarkeit

**Zweck: Gewährleistung, dass eingesetzte Systeme im Störungsfall wiederhergestellt
werden können**

Wiederherstellungsszenarien sind unter [Disaster recovery](disaster-recovery.md#disaster-recovery) dokumentiert.

### (10) Zuverlässigkeit

**Zweck: Gewährleistung, dass alle Funktionen des Systems zur Verfügung stehen und auftretende Fehlfunktionen
gemeldet werden**

Alle Systeme werden kontinuierlich überwacht. Je nach Wichtigkeit des überwachten Systems wird unser Notfall-Support benachrichtigt, ein Support-Ticket automatisch erstellt, oder manuell ein Ticket während der
Monitoring-Review erstellt.

### (11) Datenintegrität

**Zweck: Gewährleistung, dass gespeicherte personenbezogene Daten nicht durch Fehlfunktionen des Systems
beschädigt werden können**

Integrität wird auf mehreren Ebenen
gewährleistet:

* Prüfsummen auf Dateisystemebene bei
  XFS-Dateisystemen
* Prüfsummen auf Blockebene bei Ceph bluestore
  OSDs
* Redundante Speicherung von Daten
* Datensicherungen mit Hash-basierten Integritätsprüfungen, siehe [Backup](../infrastructure/backup.md#backup).

Einzelheiten und Wiederherstellungszeiten finden Sie unter [Disaster recovery](disaster-recovery.md#disaster-recovery).


### (12) Auftragskontrolle

**Zweck: Gewährleistung, dass personenbezogene Daten, die im Auftrag verarbeitet werden, nur entsprechend den Weisungen des Auftraggebers
verarbeitet werden können**


Der Flying Circus stellt sicher, dass alle von Systemadministratoren
durchgeführten Aktionen durch einen Vertrag oder Auftrag mit den von der
Aktion betroffenen Kunden abgedeckt sind. Ein solcher Vertrag oder Auftrag
kann aufgrund von breit angelegten Wartungsverträgen oder aufgrund von
spezifischen Supportanfragen zustande kommen.

Einzelne Änderungsanfragen sollten ein zugehöriges Ticket im Flying Circus Request-Tracking-System haben. Andere Mittel der Dokumentation zur
Kontrolle von Änderungen sind möglich, z.B. erklärende Commit-Nachrichten in einem Versionskontrollsystem.

Spezifische durchgeführte Aktionen werden dem Kunden bei Bedarf
mitgeteilt.

### (13) Verfügbarkeitskontrolle

**Zweck: Gewährleistung, dass personenbezogene Daten gegen Zerstörung oder
Verlust geschützt sind**

% ISMSControl: 7.5
% ISMSControl: 8.14

Die Verfügbarkeit von Ressourcen, die von Rechenzentrumseinrichtungen abhängen, wird an den Betreiber des Rechenzentrums delegiert. Bereitgestellte
Service Level Agreements ermöglichen dem Flying Circus, die Erwartungen an die Verfügbarkeit explizit zu machen.

Hardware wird vom Flying Circus von professionellem Anbietern bezogen. Der
Flying Circus nutzt Standardverfahren zur Erhöhung der Verfügbarkeit einzelner
Komponenten (z.B. RAID-Speicher, redundante Netzteile, Ersatzkomponenten).

Die Kundendaten werden regelmäßig nach dem Flying Circus [Backup-Plan](../infrastructure/backup.md#backup) gesichert. Die Wiederherstellung vergangener Zustände
kann von Administratoren auf Anfrage durchgeführt werden. Zusätzlich gibt es einen [Desaster Recovery Plan](disaster-recovery.md#disaster-recovery), der Ausfallszenarien, unsere
Präventiv- und Wiederherstellungsmaßnahmen detailliert beschreibt.

### (14) Trennbarkeit

**Zweck: Gewährleistung, dass zu unterschiedlichen Zwecken erhobene personenbezogene Daten getrennt
verarbeitet werden können**


Um die Daten verschiedener Kunden zu trennen, nutzt der Flying Circus
Virtualisierung: Sowohl virtuelle Maschinen (zur Trennung des
Ausführungskontextes) als auch virtualisierte Festplatten (Ceph) sorgen
dafür, dass Kunden nur auf die ihnen gehörenden Daten zugreifen können.
Innerhalb einer einzelnen Maschine ist der Zugriff auf verschiedene
Dateien und Prozesse über Standard-UNIX-Berechtigungen möglich.

Maschinen (sowohl virtuelle als auch physische) leben in einem bestimmten
*Access Ring* (kurz: Ring):

- *Ring 0* Maschinen führen Infrastrukturaufgaben aus. Sie verarbeitenDaten, die
  zu mehreren Kunden gehören. Auf solchen Maschinen ist nur Administratoren der
  Zugriff erlaubt. Beispiele sind VM-Hosts und Storage-Server.
- *Ring 1* Maschinen verarbeiten Daten für einen bestimmten Kunden und sind für
  Benutzer zugänglich, die mit diesem Kunden verbunden sind. Beispiele sind
  Kunden-VMs.

Alle Ressourcen, die logisch zusammengehören (z.B. VMs, Storage Volumes), werden
in *Ressourcen-Gruppen* gebündelt. Innerhalb einer Ressourcen-Gruppe werden
dieselben Benutzerkonten und Berechtigungen verwendet.

Der Zugriff auf S3-kompatible Objektspeicher wird pro Ressourcengruppe mit
dedizierten Authentifizierungsdaten getrennt.


## Andere Maßnahmen

- Unser Supportprozess und die Maßnahmen zur Reaktion auf Vorfälle sind unter [Support-Details](../support/overview.md#support-details) dokumentiert.
- Wir haben einen Prozess für Notfall- und Krisenmanagement einschließlich Notfallplänen für kritische Geschäftsprozesse (Business Continuity). Siehe auch [Disaster recovery](disaster-recovery.md#disaster-recovery).

#### Fußnoten

[^customer-owned]:
    Wenn ein Kunde Equipment besitzt, das innerhalb des Flying Circus verwaltet
    wird, verlangen wir, dass dieser Kunde ein separates Rack mit separater
    Zugangskontrolle nutzt.

[^log-unsuccessful-attempts]:
    Wir halten es für akzeptabel, erfolglose Logins nicht zu protokollieren, da
    SSH-Logins nur mit kryptographischer Private/Public-Key-Authentifizierung
    gültig sind. Passwort-Logins werden immer abgelehnt. Mögliche
    Angriffsvektoren beschränken sich somit auf gestohlene oder geknackte private
    Schlüssel oder Schwachstellen in der SSH-Server-Software. Geknackte Schlüssel
    sind mit der aktuellen Technologie praktisch unmöglich. Bekannte geknackte
    Schlüsselformate werden regelmäßig widerrufen/zurückgewiesen. Gestohlene
    Schlüssel oder Fehler in der Serversoftware lassen sich auch nicht über
    erfolglose Login-Datensätze nachvollziehen. Im Gegenteil: Die Menge an
    Passwort-Login-Versuchen, die heutzutage durchgeführt werden (aufgrund von
    Bot-Netzen etc.), würde zu einem Spamming der Logging-Infrastruktur führen,
    was wiederum ein Vektor für DOS-Angriffe sein kann.

[^trace-tty]:
    Einzelne Aktionen, die mit administrativen Rechten durchgeführt
    werden, werden nur teilweise protokolliert.

[^data-masking]:
    Es findet Datenmaskierung wie in Linux üblich statt, z. B. werden Passwörter bei
    der Eingabe nicht angezeigt.
