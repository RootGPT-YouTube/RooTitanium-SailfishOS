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
#include <QStandardPaths>
#include <QDir>
#include <QRegularExpression>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QVariantMap>
#include <QVariantList>
#include <QProcess>

// Helper nativo esposto al QML come "rtNative": cose che il QML Qt6 puro non
// sa fare (DBus, filesystem). Niente dipendenze Silica: solo Qt6DBus/Core.
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
};

int main(int argc, char **argv)
{
    QtWebEngineQuick::initialize();
    QGuiApplication app(argc, argv);
    // app_id Wayland = basename del .desktop (rootitanium.desktop): senza questo
    // lipstick non aggancia la finestra alla cover del launcher e mostra una
    // cover-segnaposto "in avvio" che va in timeout e si chiude da sola.
    app.setDesktopFileName(QStringLiteral("rootitanium"));

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
