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
    QQmlApplicationEngine engine;
    NativeHelper native;
    engine.rootContext()->setContextProperty(QStringLiteral("rtNative"), &native);
    engine.load(QUrl::fromLocalFile(base + "/test.qml"));
    if (engine.rootObjects().isEmpty())
        return -1;
    return app.exec();
}

#include "main.moc"
