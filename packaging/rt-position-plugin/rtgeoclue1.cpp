// Plugin di posizione Qt6 per SailfishOS: GeoClue 1 via DBus (task 2.5 #4).
//
// Perche' esiste: QtWebEngine chiede la posizione a QtPositioning
// (QGeoPositionInfoSource::createDefaultSource), ma Qt6 parla solo GeoClue 2,
// mentre SailfishOS ha GeoClue 1 (geoclue-provider-hybris per il GPS,
// -mlsdb per le celle). Senza un plugin nel bundle ogni sito riceveva
// POSITION_UNAVAILABLE anche col permesso concesso (misurato il 10 ott).
//
// Parla direttamente con i due provider, senza il «master» di GeoClue 1: sul
// POCO il master rispondeva «no usable Position providers» anche con i
// provider vivi. Finche' la sorgente e' attiva tiene un riferimento
// (AddReference) a entrambi; ogni posizione utile viene inoltrata, e il GPS
// vince sulle celle quando ha un fix.
#include <QtPositioning/QGeoPositionInfoSource>
#include <QtPositioning/QGeoPositionInfoSourceFactory>
#include <QtDBus/QDBusConnection>
#include <QtDBus/QDBusMessage>
#include <QtDBus/QDBusArgument>
#include <QtDBus/QDBusPendingCallWatcher>
#include <QtDBus/QDBusPendingReply>
#include <QDateTime>
#include <QTimeZone>
#include <QTimer>
#include <QtMath>

namespace {
struct Provider { const char *service; const char *path; bool gps; };
const Provider kProviders[] = {
    { "org.freedesktop.Geoclue.Providers.Hybris", "/org/freedesktop/Geoclue/Providers/Hybris", true },
    { "org.freedesktop.Geoclue.Providers.Mlsdb",  "/org/freedesktop/Geoclue/Providers/Mlsdb",  false },
};
const char *kGeoclue  = "org.freedesktop.Geoclue";
const char *kPosition = "org.freedesktop.Geoclue.Position";
enum { FieldLat = 1, FieldLon = 2, FieldAlt = 4 };
}

class RtGeoclueSource : public QGeoPositionInfoSource
{
    Q_OBJECT
public:
    explicit RtGeoclueSource(QObject *parent) : QGeoPositionInfoSource(parent)
    {
        m_timeout.setSingleShot(true);
        connect(&m_timeout, &QTimer::timeout, this, [this] {
            releaseIfIdle();
            setError(QGeoPositionInfoSource::UpdateTimeoutError);
        });
        QDBusConnection bus = QDBusConnection::sessionBus();
        for (const Provider &p : kProviders)
            bus.connect(QLatin1String(p.service), QLatin1String(p.path), QLatin1String(kPosition),
                        QStringLiteral("PositionChanged"), this, SLOT(onPositionChanged(QDBusMessage)));
    }
    ~RtGeoclueSource() override { release(); }

    QGeoPositionInfo lastKnownPosition(bool fromSatellitePositioningMethodsOnly = false) const override
    {
        if (fromSatellitePositioningMethodsOnly && !m_lastFromGps) return QGeoPositionInfo();
        return m_last;
    }
    PositioningMethods supportedPositioningMethods() const override { return AllPositioningMethods; }
    int minimumUpdateInterval() const override { return 1000; }
    Error error() const override { return m_error; }

    void startUpdates() override
    {
        m_running = true;
        m_error = NoError;
        acquire();
        queryAll();
    }
    void stopUpdates() override
    {
        m_running = false;
        releaseIfIdle();
    }
    void requestUpdate(int timeout = 0) override
    {
        m_error = NoError;
        m_single = true;
        m_timeout.start(timeout > 0 ? timeout : 30000);
        acquire();
        queryAll();
    }

private slots:
    void onPositionChanged(const QDBusMessage &msg)
    {
        handle(msg.arguments(), msg.path() == QLatin1String(kProviders[0].path));
    }

private:
    void setError(Error e) { m_error = e; emit errorOccurred(e); }

    void acquire()
    {
        if (m_referenced) return;
        m_referenced = true;
        // AddReference accende il provider (il GPS parte solo con un cliente)
        for (const Provider &p : kProviders)
            QDBusConnection::sessionBus().asyncCall(QDBusMessage::createMethodCall(
                QLatin1String(p.service), QLatin1String(p.path), QLatin1String(kGeoclue),
                QStringLiteral("AddReference")));
    }
    void release()
    {
        if (!m_referenced) return;
        m_referenced = false;
        for (const Provider &p : kProviders)
            QDBusConnection::sessionBus().asyncCall(QDBusMessage::createMethodCall(
                QLatin1String(p.service), QLatin1String(p.path), QLatin1String(kGeoclue),
                QStringLiteral("RemoveReference")));
    }
    void releaseIfIdle() { m_single = false; if (!m_running) release(); }

    void queryAll()
    {
        for (const Provider &p : kProviders) {
            auto *w = new QDBusPendingCallWatcher(QDBusConnection::sessionBus().asyncCall(
                QDBusMessage::createMethodCall(QLatin1String(p.service), QLatin1String(p.path),
                                               QLatin1String(kPosition), QStringLiteral("GetPosition"))), this);
            const bool gps = p.gps;
            connect(w, &QDBusPendingCallWatcher::finished, this, [this, w, gps] {
                const QDBusMessage r = w->reply();
                if (r.type() == QDBusMessage::ReplyMessage) handle(r.arguments(), gps);
                w->deleteLater();
            });
        }
    }

    // (fields, timestamp, lat, lon, alt, (level, horizontal, vertical))
    void handle(const QList<QVariant> &a, bool gps)
    {
        if (a.size() < 6) return;
        const int fields = a.at(0).toInt();
        if ((fields & (FieldLat | FieldLon)) != (FieldLat | FieldLon)) return;
        const double lat = a.at(2).toDouble(), lon = a.at(3).toDouble();
        if (qIsNaN(lat) || qIsNaN(lon)) return;
        // una posizione da celle non scavalca un fix GPS recente (< 30 s)
        if (!gps && m_lastFromGps && m_last.timestamp().secsTo(QDateTime::currentDateTimeUtc()) < 30)
            return;
        QGeoCoordinate c(lat, lon);
        if ((fields & FieldAlt) && !qIsNaN(a.at(4).toDouble())) c.setAltitude(a.at(4).toDouble());
        const qint64 ts = a.at(1).toLongLong();
        QGeoPositionInfo info(c, ts > 0 ? QDateTime::fromSecsSinceEpoch(ts, QTimeZone::UTC)
                                        : QDateTime::currentDateTimeUtc());
        const QDBusArgument acc = a.at(5).value<QDBusArgument>();
        int level = 0; double h = qQNaN(), v = qQNaN();
        acc.beginStructure(); acc >> level >> h >> v; acc.endStructure();
        if (!qIsNaN(h) && h > 0) info.setAttribute(QGeoPositionInfo::HorizontalAccuracy, h);
        if (!qIsNaN(v) && v > 0) info.setAttribute(QGeoPositionInfo::VerticalAccuracy, v);
        m_last = info;
        m_lastFromGps = gps;
        if (!m_running && !m_single) return;
        if (m_single) { m_timeout.stop(); releaseIfIdle(); }
        emit positionUpdated(info);
    }

    QGeoPositionInfo m_last;
    bool m_lastFromGps = false;
    bool m_running = false;
    bool m_single = false;
    bool m_referenced = false;
    Error m_error = NoError;
    QTimer m_timeout;
};

class RtGeoclueFactory : public QObject, public QGeoPositionInfoSourceFactory
{
    Q_OBJECT
    Q_PLUGIN_METADATA(IID "org.qt-project.qt.position.sourcefactory/6.0" FILE "rtgeoclue1.json")
    Q_INTERFACES(QGeoPositionInfoSourceFactory)
public:
    QGeoPositionInfoSource *positionInfoSource(QObject *parent, const QVariantMap &) override
    { return new RtGeoclueSource(parent); }
    QGeoSatelliteInfoSource *satelliteInfoSource(QObject *, const QVariantMap &) override { return nullptr; }
    QGeoAreaMonitorSource *areaMonitor(QObject *, const QVariantMap &) override { return nullptr; }
};

#include "rtgeoclue1.moc"
