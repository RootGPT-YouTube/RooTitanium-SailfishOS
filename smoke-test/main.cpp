// RooTitanium smoke test: mini launcher WebEngineView per verificare che
// qt6-qtwebengine 6.8.3 (build nativa) renderizzi sul device via GPU/hybris.
#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QtWebEngineQuick/qtwebenginequickglobal.h>
#include <QUrl>
#include <QFileInfo>
#include <QFile>
#include <QString>
#include <QByteArray>
#include <QStandardPaths>
#include <QDir>
#include <QRegularExpression>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QVariantMap>
#include <QVariantList>
#include <QProcess>
#include <QStringList>
#include <QTimer>
#include <QDebug>
#include <atomic>
#include <sys/prctl.h>
// interceptor header (QtWebEngineCore) + profilo QML (QQuickWebEngineProfile
// espone setUrlRequestInterceptor come metodo C++ pubblico, verificato in 6.8.3)
#include <QtWebEngineCore/QWebEngineUrlRequestInterceptor>
#include <QtWebEngineCore/QWebEngineUrlRequestInfo>
#include <QtWebEngineCore/QWebEngineCookieStore>
#include <QtWebEngineQuick/qquickwebengineprofile.h>

// Interceptor header HTTP: riscrive il terzetto Sec-CH-UA low-entropy che Qt
// NON espone al QML (WebEngineClientHints tocca solo la parte high-entropy JS).
// Brand "Google Chrome" invece di "Chromium" (gli anti-bot diffidano di
// Chromium). Verificato via CDP: setHttpHeader sovrascrive davvero i Sec-CH-UA.
// Stato dei toggle privacy (task 1.3 §E), condiviso fra QML, interceptor e
// cookie filter. atomic perché l'interceptor e il filtro cookie possono essere
// invocati da thread diversi da quello del QML.
struct PrivacyFlags {
    std::atomic<bool> dnt{false};          // DNT: 1 + Sec-GPC: 1
    std::atomic<bool> noReferrer{false};   // niente Referer verso terze parti
    std::atomic<bool> block3pCookies{false};
};
static PrivacyFlags g_privacy;

class HeaderInterceptor : public QWebEngineUrlRequestInterceptor
{
    Q_OBJECT
public:
    using QWebEngineUrlRequestInterceptor::QWebEngineUrlRequestInterceptor;
    void interceptRequest(QWebEngineUrlRequestInfo &info) override
    {
        // engine reale = Chromium 122 (Qt 6.8.3): versione coerente
        info.setHttpHeader("sec-ch-ua",
            "\"Google Chrome\";v=\"122\", \"Chromium\";v=\"122\", \"Not:A-Brand\";v=\"24\"");
        info.setHttpHeader("sec-ch-ua-mobile", "?1");
        info.setHttpHeader("sec-ch-ua-platform", "\"Android\"");

        // --- task 1.3 §B: segnali di preferenza, solo col toggle acceso ---
        // Finora "Non tenere traccia" era SOLO JS (navigator.doNotTrack): nessun
        // header partiva davvero. Ora è un segnale vero sul filo.
        if (g_privacy.dnt.load(std::memory_order_relaxed)) {
            info.setHttpHeader("DNT", "1");
            info.setHttpHeader("Sec-GPC", "1");
        }

        // --- task 1.3 §B: Referer e Authorization cross-origin ---
        // Il valore non è nascondere quale pagina si stava leggendo (lo copre già
        // strict-origin-when-cross-origin): è che ogni terza parte incorporata
        // riceve "Referer: https://quel-sito/" a ogni pixel, font o script, e
        // impara che stai su quel sito ANCHE con i cookie di terze parti bloccati.
        // Verificato il 20 lug: setHttpHeader("Referer", "") azzera davvero
        // l'header, Chromium non lo reimposta a valle (4 casi di test in
        // Documentation/TASK-1.3-hardening.md).
        if (g_privacy.noReferrer.load(std::memory_order_relaxed) && isCrossSite(info)) {
            info.setHttpHeader("Referer", QByteArray());
            // credenziali che non devono seguire un redirect verso un altro sito
            info.setHttpHeader("Authorization", QByteArray());
        }
    }

private:
    // "Cross-site" approssimato per confronto di suffisso: Qt non espone il
    // registrable domain (eTLD+1). Il confronto host-contro-host puro, usato nel
    // test del 20 lug, tratta www.sito.it → cdn.sito.it come cross e toglie il
    // Referer anche ai CDN dello stesso proprietario: rompe siti veri. Qui si
    // confrontano le ultime due etichette (sito.it), che copre il caso comune;
    // resta impreciso sui suffissi a due livelli (.co.uk → "co.uk"), dove al
    // massimo si è più permissivi, mai più aggressivi. Scelta fra le due
    // lasciate aperte dal piano §B, presa in implementazione.
    static QString sameSiteKey(const QString &host)
    {
        const QStringList parts = host.split(QLatin1Char('.'), Qt::SkipEmptyParts);
        if (parts.size() <= 2) return host;
        return parts.mid(parts.size() - 2).join(QLatin1Char('.'));
    }

    static bool isCrossSite(const QWebEngineUrlRequestInfo &info)
    {
        const QString first = info.firstPartyUrl().host();
        const QString req   = info.requestUrl().host();
        if (first.isEmpty() || req.isEmpty()) return false;   // dato mancante: non si tocca
        return sameSiteKey(first).compare(sameSiteKey(req), Qt::CaseInsensitive) != 0;
    }
};

// Link aperti da ALTRE app quando RooTitanium e' GIA' in esecuzione (task 1.2 #1).
// Lipstick consegna l'URL eseguendo la riga Exec del .desktop con %u, quindi il
// secondo processo nasce comunque (l'Exec e' scritto per esteso senza
// «invoker --single-instance», che altrimenti lo farebbe uscire subito). Quel
// processo trova il nome di sessione gia' occupato, chiama qui via DBus e muore:
// e' questo l'unico canale verso l'istanza viva. Interfaccia standard
// org.freedesktop.Application, come in RooTheater.
class OpenHandler : public QObject
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.freedesktop.Application")
public slots:
    // due overload: "as" e' quello che usa libcontentaction, "s" i chiamanti
    // che passano un URI solo (la nostra riga di inoltro in main()).
    void openUrl(const QStringList &uris) { if (!uris.isEmpty()) handle(uris.first()); }
    void openUrl(const QString &url) { handle(url); }

signals:
    void openRequested(const QString &url);   // → QML: apri in NUOVA scheda

private:
    void handle(const QString &uri) { if (!uri.isEmpty()) emit openRequested(uri); }
};

// Helper nativo esposto al QML come "rtNative": cose che il QML Qt6 puro non
// sa fare (DBus, filesystem). Niente dipendenze Silica.
class NativeHelper : public QObject
{
    Q_OBJECT
public:
    explicit NativeHelper(QObject *parent = nullptr) : QObject(parent)
    {
        // Rinnovo della pausa di blanking (task #3). MCE la fa scadere da sola
        // dopo ~60 s: 30 s di intervallo tengono il margine e, soprattutto, se
        // l'app muore o si blocca il display torna normale da solo entro un
        // minuto. Nessun rischio di lasciare il telefono acceso all'infinito.
        m_blankTimer.setInterval(30 * 1000);
        connect(&m_blankTimer, &QTimer::timeout, this, [this] { pauseBlanking(); });
    }

    // Condivisione DI SISTEMA SailfishOS: apre il dialogo sailfish-share via
    // DBus session (org.sailfishos.share / share(a{sv})) — stesso protocollo
    // del ShareAction Qt5 di Sailfish.Share, ricostruito perché il plugin
    // Silica non esiste in Qt6. Formato risorsa URL come i browser SFOS:
    // { type: "text/x-url", status: url, linkTitle: titolo }.
    Q_INVOKABLE bool shareUrl(const QString &url, const QString &title)
    {
        QVariantMap resource{
            { QStringLiteral("type"),   QStringLiteral("text/x-url") },
            { QStringLiteral("status"), url },
        };
        if (!title.isEmpty())
            resource.insert(QStringLiteral("linkTitle"), title);
        QVariantMap config{
            { QStringLiteral("resources"), QVariantList{ resource } },
            { QStringLiteral("mimeType"),  QStringLiteral("text/x-url") },
        };
        QDBusMessage msg = QDBusMessage::createMethodCall(
            QStringLiteral("org.sailfishos.share"), QStringLiteral("/"),
            QStringLiteral("org.sailfishos.share"), QStringLiteral("share"));
        msg.setArguments({ config });
        return QDBusConnection::sessionBus().send(msg);
    }

    // Percorso per "Salva pagina come PDF": ~/Documents (o versione localizzata,
    // via xdg-user-dirs come QStandardPaths), nome file dal titolo pagina
    // sanificato; se esiste già aggiunge " (2)", " (3)", ...
    Q_INVOKABLE QString pdfPathForTitle(const QString &title)
    {
        QString dir = QStandardPaths::writableLocation(QStandardPaths::DocumentsLocation);
        if (dir.isEmpty())
            dir = QDir::homePath() + QStringLiteral("/Documents");
        QDir().mkpath(dir);
        QString base = title;
        base.replace(QRegularExpression(QStringLiteral("[\\\\/:*?\"<>|\\x00-\\x1f]")), QStringLiteral(" "));
        base = base.simplified();
        base.truncate(80);
        if (base.isEmpty())
            base = QStringLiteral("pagina");
        QString path = dir + QStringLiteral("/") + base + QStringLiteral(".pdf");
        for (int i = 2; QFileInfo::exists(path); ++i)
            path = dir + QStringLiteral("/") + base + QStringLiteral(" (%1).pdf").arg(i);
        return path;
    }

    // Cartella download: ~/Downloads (o localizzata, xdg-user-dirs), creata
    // se manca — così ogni download PARTE già con destinazione valida
    Q_INVOKABLE QString downloadsPath()
    {
        QString dir = QStandardPaths::writableLocation(QStandardPaths::DownloadLocation);
        if (dir.isEmpty())
            dir = QDir::homePath() + QStringLiteral("/Downloads");
        QDir().mkpath(dir);
        return dir;
    }

    // rimuovi un file parziale di un download annullato/fallito (il .download
    // di Chromium resta su disco: verificato, cancel() non lo pulisce qui)
    Q_INVOKABLE void removeFile(const QString &path) { QFile::remove(path); }

    // Apri file scaricato con l'app di sistema (libcontentaction: lca-tool
    // sceglie l'handler dal mime type, come il tap in Transfer/Impostazioni)
    Q_INVOKABLE bool openFile(const QString &path)
    {
        if (!QFileInfo::exists(path))
            return false;
        return QProcess::startDetached(QStringLiteral("/usr/bin/lca-tool"),
            { QStringLiteral("--triggerfile"), QUrl::fromLocalFile(path).toString() });
    }

    // Installa l'interceptor header sul profilo QML. I due WebEngineProfile sono
    // dichiarati in QML; QQuickWebEngineProfile espone setUrlRequestInterceptor
    // come metodo C++ pubblico (non Q_INVOKABLE) → lo chiamiamo qui passando
    // l'oggetto profilo da QML (Component.onCompleted: rtNative.setupProfile(this)).
    Q_INVOKABLE void setupProfile(QObject *profileObj)
    {
        auto *p = qobject_cast<QQuickWebEngineProfile *>(profileObj);
        if (!p) { qWarning() << "rtNative.setupProfile: non è un WebEngineProfile"; return; }
        p->setUrlRequestInterceptor(new HeaderInterceptor(p));

        // task 1.3 §C — cookie di terze parti. Il filtro resta installato per
        // sempre e consulta il toggle a ogni richiesta: così accenderlo o
        // spegnerlo ha effetto subito, senza reinstallare nulla (QWebEngineCookieStore
        // ::FilterRequest::thirdParty, verificato in qwebenginecookiestore.h 6.8.3).
        p->cookieStore()->setCookieFilter([](const QWebEngineCookieStore::FilterRequest &r) {
            return !(g_privacy.block3pCookies.load(std::memory_order_relaxed) && r.thirdParty);
        });
    }

    // --- task 1.3 §E: i tre toggle, letti da interceptor e cookie filter ---
    // Chiamata dal QML a ogni cambio e una volta all'avvio dopo loadCfg().
    Q_INVOKABLE void setPrivacyFlags(bool dnt, bool noReferrer, bool block3pCookies)
    {
        g_privacy.dnt.store(dnt, std::memory_order_relaxed);
        g_privacy.noReferrer.store(noReferrer, std::memory_order_relaxed);
        g_privacy.block3pCookies.store(block3pCookies, std::memory_order_relaxed);
    }

    // Terzo toggle (isolamento storage di terze parti): è un FLAG di Chromium,
    // e i flag si leggono solo all'avvio del processo. Il QML salva qui la
    // preferenza; main() la rilegge al lancio successivo e la fonde nei flag
    // prima di QtWebEngineQuick::initialize(). La UI deve dire "al prossimo
    // avvio", altrimenti sembra rotto. File di testo di una riga invece della
    // kv SQLite: main() dovrebbe altrimenti aprire il DB QML LocalStorage, il
    // cui nome file è un hash — sproporzionato per un booleano.
    Q_INVOKABLE void setStartupStoragePartitioning(bool on)
    {
        const QString path = startupFlagsPath();
        QDir().mkpath(QFileInfo(path).absolutePath());
        QFile f(path);
        if (!f.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
            qWarning() << "rtNative: non riesco a scrivere" << path;
            return;
        }
        f.write(on ? "storage-partitioning=1\n" : "storage-partitioning=0\n");
    }

    // Path ESPLICITO, non QStandardPaths::AppDataLocation: quello dipende da
    // applicationName, che deriva da basename(argv[0]) e quindi vale
    // "harbour-rootitanium" dal launcher ma "run.sh" dai lanci di sviluppo.
    // Fissare applicationName in main() sposterebbe anche il DB QML LocalStorage,
    // cioè segnalibri e cronologia degli utenti già installati: mai.
    static QString startupFlagsPath()
    {
        return QDir::homePath()
               + QStringLiteral("/.local/share/harbour-rootitanium/startup-flags.conf");
    }

    static bool startupStoragePartitioning()
    {
        QFile f(startupFlagsPath());
        if (!f.open(QIODevice::ReadOnly)) return false;
        return QString::fromLatin1(f.readAll()).contains(QLatin1String("storage-partitioning=1"));
    }

    // --- task #3: il display non si spegne mentre un video è in play ---
    // Nemo.KeepAlive (DisplayBlanking) è Qt5/Silica e per noi non esiste, ma
    // sotto non fa che chiamare MCE: lo chiamiamo diretti sul SYSTEM bus. Il
    // .desktop ha Sandboxing=Disabled, quindi il bus è raggiungibile.
    Q_INVOKABLE void setKeepDisplayOn(bool on)
    {
        if (on == m_keepDisplayOn) return;
        m_keepDisplayOn = on;
        if (on) {
            pauseBlanking();          // subito, poi ogni 30 s
            m_blankTimer.start();
        } else {
            m_blankTimer.stop();
            mceCall(QStringLiteral("req_display_cancel_blanking_pause"));
        }
    }

private:
    void pauseBlanking() { mceCall(QStringLiteral("req_display_blanking_pause")); }

    static void mceCall(const QString &method)
    {
        QDBusMessage msg = QDBusMessage::createMethodCall(
            QStringLiteral("com.nokia.mce"),
            QStringLiteral("/com/nokia/mce/request"),
            QStringLiteral("com.nokia.mce.request"), method);
        QDBusConnection::systemBus().send(msg);   // fire-and-forget: nessuna risposta attesa
    }

    QTimer m_blankTimer;
    bool m_keepDisplayOn = false;
};

int main(int argc, char **argv)
{
    // comm del processo (/proc/PID/stat, /proc/PID/comm) = "harbour-rootita"
    // (troncato a 15 char): assicura che, oltre alla cmdline (argv[0] forgiato dal
    // launcher), anche il nome-processo che lipstick puo' leggere combaci col
    // launcher item. Insieme evitano la cover-segnaposto fantasma all'avvio.
    prctl(PR_SET_NAME, (unsigned long)"harbour-rootitanium", 0, 0, 0);

    // task 1.3 §E, terzo toggle: "Isola lo storage di terze parti" è un flag di
    // Chromium e i flag si leggono solo all'avvio. Qui si fonde nella variabile
    // che il launcher ha già composto, PRIMA di initialize(). Fusione e non
    // semplice append: due "--enable-features" separati sulla stessa riga di
    // comando non si sommano, l'ultimo vince e il primo si perderebbe.
    if (NativeHelper::startupStoragePartitioning()) {
        QString flags = QString::fromLocal8Bit(qgetenv("QTWEBENGINE_CHROMIUM_FLAGS"));
        const QRegularExpression re(QStringLiteral("--enable-features=([^\\s]*)"));
        const QRegularExpressionMatch m = re.match(flags);
        if (m.hasMatch())
            flags.replace(m.capturedStart(0), m.capturedLength(0),
                          QStringLiteral("--enable-features=%1,ThirdPartyStoragePartitioning")
                              .arg(m.captured(1)));
        else
            flags += QStringLiteral(" --enable-features=ThirdPartyStoragePartitioning");
        qputenv("QTWEBENGINE_CHROMIUM_FLAGS", flags.toLocal8Bit());
    }

    QtWebEngineQuick::initialize();
    QGuiApplication app(argc, argv);
    // app_id Wayland = basename del .desktop INSTALLATO (harbour-rootitanium.desktop):
    // deve combaciare col nome del .desktop da cui lipstick lancia, altrimenti non
    // aggancia la finestra alla cover del launcher e mostra una cover-segnaposto
    // "in avvio" che va in timeout e si chiude da sola (doppia cover all'avvio).
    app.setDesktopFileName(QStringLiteral("harbour-rootitanium"));

    // carica test.qml dalla stessa cartella dell'eseguibile
    const QString base = QFileInfo(QString::fromLocal8Bit(argv[0])).absolutePath();

    // URL da aprire passato dal chooser di sistema (.desktop: Exec=... %u): il
    // primo argomento http(s)/file — lipstick/libcontentaction lancia l'app con
    // l'URL del link. Esposto al QML come rtOpenUrl; test.qml lo apre all'avvio.
    QString openUrl;
    for (int i = 1; i < argc; ++i) {
        const QString a = QString::fromLocal8Bit(argv[i]);
        if (a.startsWith(QLatin1String("http://"))  ||
            a.startsWith(QLatin1String("https://")) ||
            a.startsWith(QLatin1String("file://"))) { openUrl = a; break; }
    }

    // Servizio DBus per i link in arrivo da altre app (vedi OpenHandler).
    // Nome/oggetto derivati dall'identita' X-Sailjail del .desktop
    // (OrganizationName.ApplicationName), come per RooTheater.
    const QString busName  = QStringLiteral("com.github.RootGPT_YouTube.rootitanium");
    const QString objPath  = QStringLiteral("/com/github/RootGPT_YouTube/rootitanium");
    OpenHandler openHandler;
    QDBusConnection bus = QDBusConnection::sessionBus();
    bus.registerObject(objPath, &openHandler, QDBusConnection::ExportAllSlots);
    if (!bus.registerService(busName)) {
        // Nome gia' occupato = l'istanza viva e' un'altra. Le passiamo l'URL
        // (che aprira' in una scheda nuova) e usciamo senza mai creare una
        // seconda finestra. Senza URL non c'e' niente da dire: usciamo e basta,
        // il foreground della finestra esistente lo fa lipstick.
        if (!openUrl.isEmpty()) {
            QDBusMessage fwd = QDBusMessage::createMethodCall(
                busName, objPath, QStringLiteral("org.freedesktop.Application"),
                QStringLiteral("openUrl"));
            fwd.setArguments({ openUrl });
            bus.call(fwd, QDBus::Block);   // Block: il processo esce subito dopo
        }
        return 0;
    }

    QQmlApplicationEngine engine;
    NativeHelper native;
    engine.rootContext()->setContextProperty(QStringLiteral("rtNative"), &native);
    engine.rootContext()->setContextProperty(QStringLiteral("rtOpen"), &openHandler);
    engine.rootContext()->setContextProperty(QStringLiteral("rtOpenUrl"), openUrl);
    engine.load(QUrl::fromLocalFile(base + "/test.qml"));
    if (engine.rootObjects().isEmpty())
        return -1;
    // NB: qui NON serve portare avanti la finestra da soli. Il foreground lo fa
    // lipstick, che e' il vero mittente (le app chiamano
    // org.sailfishos.fileservice.openUrl su com.jolla.lipstick, e lipstick
    // attiva l'handler oltre a consegnargli l'URL). Verificato sul device:
    // app in background + link → scheda nuova E app in primo piano.
    // QWindow::raise()/requestActivate() sarebbero comunque inutili: il client
    // Qt6 parla xdg-shell, che non ha alcuna richiesta di raise.
    return app.exec();
}

#include "main.moc"
