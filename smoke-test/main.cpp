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
#include <QDebug>
#include <sys/prctl.h>
// interceptor header (QtWebEngineCore) + profilo QML (QQuickWebEngineProfile
// espone setUrlRequestInterceptor come metodo C++ pubblico, verificato in 6.8.3)
#include <QtWebEngineCore/QWebEngineUrlRequestInterceptor>
#include <QtWebEngineCore/QWebEngineUrlRequestInfo>
#include <QtWebEngineQuick/qquickwebengineprofile.h>

// Interceptor header HTTP: riscrive il terzetto Sec-CH-UA low-entropy che Qt
// NON espone al QML (WebEngineClientHints tocca solo la parte high-entropy JS).
// Brand "Google Chrome" invece di "Chromium" (gli anti-bot diffidano di
// Chromium). Verificato via CDP: setHttpHeader sovrascrive davvero i Sec-CH-UA.
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
    }
};

// Ricezione link da ALTRE app (task 1.2 #1). Il .desktop dichiara i campi
// X-Maemo-Service/Object-Path/Method: libcontentaction (quello che sta dietro a
// Qt.openUrlExternally, al foglio «Apri con» e ai tap sui link in RooTelegram &
// co.) allora consegna l'URL con una chiamata DBus a questa interfaccia INVECE
// di rieseguire la riga Exec. Serve perche' l'Exec passa da
// «invoker --single-instance»: con l'app gia' viva il secondo processo non parte
// nemmeno, lipstick porta avanti la finestra esistente e l'URL va perso.
// L'interfaccia e' la standard org.freedesktop.Application (stesso schema di
// RooTheater); l'attivazione DBus quando l'app e' spenta la copre il .service
// generato da sailjaild dalla chiave X-Sailjail ExecDBus.
class OpenHandler : public QObject
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.freedesktop.Application")
    // URL arrivato PRIMA che il QML fosse pronto (caso attivazione DBus: il
    // processo parte per la chiamata stessa). test.qml lo legge all'avvio.
    Q_PROPERTY(QString pendingUrl READ pendingUrl NOTIFY openRequested)
public:
    using QObject::QObject;
    QString pendingUrl() const { return m_pendingUrl; }
    void setPendingUrl(const QString &u) { m_pendingUrl = u; }

public slots:
    // ── org.freedesktop.Application ──────────────────────────────────────────
    void Activate(const QVariantMap &) { emit activated(); }
    void Open(const QStringList &uris, const QVariantMap &)
    {
        if (uris.isEmpty()) { emit activated(); return; }
        handle(uris.first());
    }
    void ActivateAction(const QString &, const QVariantList &, const QVariantMap &) {}

    // libcontentaction invoca l'X-Maemo-Method passando gli URI come ARRAY di
    // stringhe (signature "as"): e' questo l'overload che scatta davvero.
    // La variante a stringa singola resta per i chiamanti che passano "s".
    void openUrl(const QStringList &uris) { if (!uris.isEmpty()) handle(uris.first()); }
    void openUrl(const QString &url) { handle(url); }

signals:
    void openRequested(const QString &url);   // → QML: apri in NUOVA scheda
    void activated();                         // attivazione nuda (nessun URL)

private:
    void handle(const QString &uri)
    {
        if (uri.isEmpty()) return;
        m_pendingUrl = uri;
        emit openRequested(uri);
    }
    QString m_pendingUrl;
};

// Helper nativo esposto al QML come "rtNative": cose che il QML Qt6 puro non
// sa fare (DBus, filesystem). Niente dipendenze Silica.
class NativeHelper : public QObject
{
    Q_OBJECT
public:
    using QObject::QObject;

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
    }
};

int main(int argc, char **argv)
{
    // comm del processo (/proc/PID/stat, /proc/PID/comm) = "harbour-rootita"
    // (troncato a 15 char): assicura che, oltre alla cmdline (argv[0] forgiato dal
    // launcher), anche il nome-processo che lipstick puo' leggere combaci col
    // launcher item. Insieme evitano la cover-segnaposto fantasma all'avvio.
    prctl(PR_SET_NAME, (unsigned long)"harbour-rootitanium", 0, 0, 0);

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
        // Nome gia' occupato = c'e' gia' un'istanza viva. Rete di sicurezza per
        // i percorsi che NON passano dal DBus (Exec ... %u lanciato a mano, o un
        // invoker senza --single-instance): inoltriamo l'URL a quella istanza e
        // usciamo, invece di aprire una seconda finestra.
        if (!openUrl.isEmpty()) {
            QDBusMessage fwd = QDBusMessage::createMethodCall(
                busName, objPath, QStringLiteral("org.freedesktop.Application"),
                QStringLiteral("openUrl"));
            fwd.setArguments({ QStringList{ openUrl } });
            bus.call(fwd, QDBus::NoBlock);
        }
        return 0;
    }
    // URL arrivato da argv: consegnalo al QML per la stessa strada del DBus.
    if (!openUrl.isEmpty())
        openHandler.setPendingUrl(openUrl);

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
