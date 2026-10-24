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
#include <QDBusServer>
#include <QDBusAbstractAdaptor>
#include <QThread>
#include <unistd.h>
#include <QSemaphore>
#include <QVariantMap>
#include <QVariantList>
#include <QProcess>
#include <QStringList>
#include <QTimer>
#include <QDebug>
#include <atomic>
#include <thread>
#include <chrono>
#include <signal.h>
#include <limits.h>
#include <sys/prctl.h>
#include <QDBusConnectionInterface>
#include <QWindow>
#include <QHash>
#include <QJsonDocument>
#include <QJsonObject>
#include <qpa/qplatformnativeinterface.h>
#include <wayland-client.h>
// interceptor header (QtWebEngineCore) + profilo QML (QQuickWebEngineProfile
// espone setUrlRequestInterceptor come metodo C++ pubblico, verificato in 6.8.3)
#include <QtWebEngineCore/QWebEngineUrlRequestInterceptor>
#include <QtWebEngineCore/QWebEngineUrlRequestInfo>
#include <QtWebEngineCore/qtwebenginecoreglobal.h>
#include <QtWebEngineCore/QWebEngineCookieStore>
#include <QtWebEngineQuick/qquickwebengineprofile.h>
#include <QtWebEngineCore/QWebEngineNotification>
#include <QLocale>
#include <QQmlEngine>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDataStream>
#include <QImage>
#include <QPointer>
#include <QDBusArgument>
#include <QDBusMetaType>
#include <dlfcn.h>
#include <QDateTime>

// ⚠️ Link visitati (cancellazione selettiva della cronologia, 12 ott 2026).
// Chromium tiene la sua lista dei link visitati (il colore :visited) e Qt la
// espone SOLO su QWebEngineProfile C++ (clearVisitedLinks); il profilo QML non
// ha nulla di equivalente (verificato nei qmltypes e negli header 6.140).
// Ci arriviamo dagli interni: QQuickWebEngineProfile::d_ptr ->
// QQuickWebEngineProfilePrivate::m_profileAdapter -> ProfileAdapter::
// visitedLinksManager(). Le due classi del core sono esportate dalla libreria,
// solo i due membri sono privati: li leggiamo con il trucco standard e legale
// dell'istanza esplicita di template (l'accesso non viene controllato negli
// argomenti di un'istanza esplicita), senza toccare la memoria a mano.
// E' accettabile SOLO perche' portiamo con noi questo Qt esatto: la struttura
// non puo' cambiare sotto i piedi. Senza gli header (es. Qt 6.8) il blocco non
// si compila e le funzioni rispondono false: il QML resta com'era.
#if __has_include(<QtWebEngineQuick/private/qquickwebengineprofile_p.h>) && __has_include("profile_adapter.h") && __has_include("visited_links_manager_qt.h")
#define RT_VISITED_LINKS 1
#include <QtWebEngineQuick/private/qquickwebengineprofile_p.h>
#include "profile_adapter.h"
#include "visited_links_manager_qt.h"
namespace rtpriv {
template <typename Tag, typename Tag::type M>
struct Ruba { friend typename Tag::type prendi(Tag) { return M; } };
struct ProfiloD { using type = QScopedPointer<QQuickWebEngineProfilePrivate> QQuickWebEngineProfile::*; friend type prendi(ProfiloD); };
struct ProfiloAdapter { using type = QPointer<QtWebEngineCore::ProfileAdapter> QQuickWebEngineProfilePrivate::*; friend type prendi(ProfiloAdapter); };
template struct Ruba<ProfiloD, &QQuickWebEngineProfile::d_ptr>;
template struct Ruba<ProfiloAdapter, &QQuickWebEngineProfilePrivate::m_profileAdapter>;
static QtWebEngineCore::VisitedLinksManagerQt *visitati(QQuickWebEngineProfile *p)
{
    if (!p) return nullptr;
    QQuickWebEngineProfilePrivate *d = (p->*prendi(ProfiloD())).data();
    if (!d) return nullptr;
    QtWebEngineCore::ProfileAdapter *a = (d->*prendi(ProfiloAdapter())).data();
    return a ? a->visitedLinksManager() : nullptr;
}
} // namespace rtpriv
#endif

// Interceptor header HTTP: riscrive il terzetto Sec-CH-UA low-entropy che Qt
// NON espone al QML (WebEngineClientHints tocca solo la parte high-entropy JS).
// Brand "Google Chrome" invece di "Chromium" (gli anti-bot diffidano di
// Chromium). Verificato via CDP: setHttpHeader sovrascrive davvero i Sec-CH-UA.
// Stato dei toggle privacy (task 1.3 §E), condiviso fra QML, interceptor e
// cookie filter. atomic perché l'interceptor e il filtro cookie possono essere
// invocati da thread diversi da quello del QML.
// I valori iniziali rispecchiano i default del QML (loadCfg li sovrascrive con
// la kv prima che parta qualunque richiesta): tenerli allineati, altrimenti
// "default" vuol dire due cose diverse nei due file.
struct PrivacyFlags {
    std::atomic<bool> dnt{true};           // DNT: 1 + Sec-GPC: 1
    std::atomic<bool> noReferrer{false};   // niente Referer verso terze parti
    std::atomic<bool> block3pCookies{true};
};
static PrivacyFlags g_privacy;

class HeaderInterceptor : public QWebEngineUrlRequestInterceptor
{
    Q_OBJECT
public:
    using QWebEngineUrlRequestInterceptor::QWebEngineUrlRequestInterceptor;
    void interceptRequest(QWebEngineUrlRequestInfo &info) override
    {
        // versione letta dal motore (task 2.6 #3): con la 122 scritta a mano
        // il passaggio a Chromium 140 lasciava l'header indietro
        static const QByteArray secChUa = [] {
            const QByteArray major = QByteArray(qWebEngineChromiumVersion()).split('.').value(0);
            return QByteArray("\"Google Chrome\";v=\"") + major + "\", \"Chromium\";v=\"" + major
                   + "\", \"Not:A-Brand\";v=\"24\"";
        }();
        info.setHttpHeader("sec-ch-ua", secChUa);
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

// ===================== primo piano su richiesta (task 2.5 #3) =====================
// Un link in arrivo deve portare avanti l'app anche se e' in cover. Il client
// Qt6 parla xdg-shell, che non ha alcuna richiesta di raise; lipstick pero'
// espone ancora qt_surface_extension, il protocollo con cui le app Qt5/Silica
// fanno QWindow::raise(): la sua richiesta `raise` finisce in
// LipstickCompositor::windowRaised, cioe' nel primo piano. Qt6 non lo usa
// piu', quindi lo parliamo a mano: interfacce scritte qui (niente scanner), con
// l'ordine dei messaggi letto dai metadati di libQt5Compositor sul device:
// richieste update_generic_property, set_content_orientation_mask,
// set_window_flags, raise, lower; eventi onscreen_visibility,
// set_generic_property, close.
extern "C" {
static const struct wl_interface *rt_null_types[] = { nullptr, nullptr };
static const struct wl_message rt_ext_requests[] = {
    { "update_generic_property", "sa", rt_null_types },
    { "set_content_orientation_mask", "i", rt_null_types },
    { "set_window_flags", "i", rt_null_types },
    { "raise", "", rt_null_types },
    { "lower", "", rt_null_types },
};
static const struct wl_message rt_ext_events[] = {
    { "onscreen_visibility", "i", rt_null_types },
    { "set_generic_property", "sa", rt_null_types },
    { "close", "", rt_null_types },
};
static const struct wl_interface rt_qt_extended_surface_interface = {
    "qt_extended_surface", 1, 5, rt_ext_requests, 3, rt_ext_events };
static const struct wl_interface *rt_getext_types[] = {
    &rt_qt_extended_surface_interface, &wl_surface_interface };
static const struct wl_message rt_surfext_requests[] = {
    { "get_extended_surface", "no", rt_getext_types },
};
static const struct wl_interface rt_qt_surface_extension_interface = {
    "qt_surface_extension", 1, 1, rt_surfext_requests, 0, nullptr };
}

class RtWindowRaiser
{
public:
    // true se la richiesta e' partita (non che lipstick l'abbia onorata)
    static bool raise()
    {
        QWindow *w = nullptr;
        for (QWindow *c : QGuiApplication::topLevelWindows())
            if (c->isVisible()) { w = c; break; }
        if (!w) return false;
        if (!ensure(w)) return false;
        wl_proxy_marshal(s_ext, 3 /* raise */);
        wl_display_flush(s_display);
        return true;
    }

private:
    static bool ensure(QWindow *w)
    {
        if (s_ext && s_window == w) return true;
        auto *wa = qGuiApp->nativeInterface<QNativeInterface::QWaylandApplication>();
        QPlatformNativeInterface *ni = QGuiApplication::platformNativeInterface();
        if (!wa || !ni) return false;
        s_display = wa->display();
        auto *surface = static_cast<wl_surface *>(
            ni->nativeResourceForWindow(QByteArrayLiteral("surface"), w));
        if (!s_display || !surface) return false;
        if (!s_surfext && !bindExtension()) {
            qWarning("[rt] qt_surface_extension assente: niente primo piano automatico");
            return false;
        }
        if (s_ext) wl_proxy_destroy(s_ext);
        s_ext = wl_proxy_marshal_constructor(s_surfext, 0, &rt_qt_extended_surface_interface,
                                             nullptr, surface);
        if (!s_ext) return false;
        // la coda privata serviva solo al registry: gli eventi della superficie
        // (close compreso) li consegna il ciclo di Qt sul main thread
        wl_proxy_set_queue(s_ext, nullptr);
        wl_proxy_add_listener(s_ext, reinterpret_cast<void (**)(void)>(const_cast<Listener *>(&s_listener)), nullptr);
        s_window = w;
        return true;
    }

    // registry su una coda PRIVATA: un roundtrip sulla coda di Qt
    // consegnerebbe fuori tempo i suoi eventi
    static bool bindExtension()
    {
        wl_event_queue *q = wl_display_create_queue(s_display);
        auto *wrapped = static_cast<wl_display *>(wl_proxy_create_wrapper(s_display));
        wl_proxy_set_queue(reinterpret_cast<wl_proxy *>(wrapped), q);
        wl_registry *reg = wl_display_get_registry(wrapped);
        static const wl_registry_listener rl = {
            [](void *, wl_registry *r, uint32_t name, const char *iface, uint32_t) {
                if (!s_surfext && strcmp(iface, "qt_surface_extension") == 0)
                    s_surfext = static_cast<wl_proxy *>(
                        wl_registry_bind(r, name, &rt_qt_surface_extension_interface, 1));
            },
            [](void *, wl_registry *, uint32_t) {}
        };
        wl_registry_add_listener(reg, &rl, nullptr);
        wl_display_roundtrip_queue(s_display, q);
        wl_registry_destroy(reg);
        wl_proxy_wrapper_destroy(wrapped);
        if (s_surfext) wl_proxy_set_queue(s_surfext, nullptr);
        wl_event_queue_destroy(q);
        return s_surfext != nullptr;
    }

    static inline wl_display *s_display = nullptr;
    static inline wl_proxy *s_surfext = nullptr;
    static inline wl_proxy *s_ext = nullptr;
    static inline QWindow *s_window = nullptr;

    // Eventi della superficie estesa. `close` va onorato: e' il gesto di
    // chiusura dalla cover, che con la superficie estesa lipstick potrebbe
    // mandare da qui invece che da xdg_toplevel.
    struct Listener {
        void (*onscreen_visibility)(void *, wl_proxy *, int32_t);
        void (*set_generic_property)(void *, wl_proxy *, const char *, wl_array *);
        void (*close)(void *, wl_proxy *);
    };
    static inline const Listener s_listener = {
        [](void *, wl_proxy *, int32_t) {},
        [](void *, wl_proxy *, const char *, wl_array *) {},
        [](void *, wl_proxy *) {
            qInfo("[rt] chiusura richiesta da lipstick (qt_extended_surface.close)");
            if (s_window) s_window->close();
        },
    };

};

// Link aperti da ALTRE app (task 1.2 #1, rivisto in 2.5 #3). Dalla 2.5 il
// .desktop dichiara X-Maemo-Service/Object-Path/Method: lipstick e
// libcontentaction chiamano openUrl QUI, sull'istanza viva, invece di eseguire
// la riga Exec; ad app chiusa la avvia il .service di attivazione DBus. Resta
// anche il vecchio inoltro: un secondo processo lanciato con un URL trova il
// nome occupato e lo passa qui prima di uscire (main()). Interfaccia standard
// org.freedesktop.Application, come in RooTheater.
// Sveglia da Foghorn ad app chiusa (task 2.8 #0): il processo parte nascosto,
// recapita la push al motore (che sveglia il service worker del sito, e la
// notifica esce da RtNotifier) e si richiude da solo se nessuno lo apre.
// g_wakeHidden = siamo una sveglia e la finestra non e' ancora stata mostrata.
static std::atomic<bool> g_wakeHidden{false};
static std::atomic<qint64> g_wakeActivity{0};   // ms dell'ultima push o notifica
static std::atomic<qint64> g_wakePush{0};       // ms dell'ultima push arrivata
static std::atomic<qint64> g_wakeNotif{0};      // ms dell'ultima notifica mostrata
static void wakeTouch() { g_wakeActivity = QDateTime::currentMSecsSinceEpoch(); }

// ===================== notifiche dei siti (task 2.7 #1) =====================
// Senza un ricevitore di presentNotification il permesso «Notifiche» si
// concedeva ma non compariva nulla. Qui ogni notifica del motore diventa una
// notifica di sistema (org.freedesktop.Notifications di lipstick).
// Tocco sulla notifica: lipstick chiama il nostro rtNotificationClicked (hint
// x-nemo-remote-action-default) → click() verso il sito + primo piano. Con
// l'app chiusa il .service di attivazione DBus la riavvia e si apre l'origine.
class RtNotifier : public QObject
{
    Q_OBJECT
public:
    RtNotifier(const QString &busName, const QString &objPath)
        : m_busName(busName), m_objPath(objPath)
    {
        QDBusConnection::sessionBus().connect(
            QString(), QStringLiteral("/org/freedesktop/Notifications"),
            QStringLiteral("org.freedesktop.Notifications"), QStringLiteral("NotificationClosed"),
            this, SLOT(onSystemClosed(uint,uint)));
    }

    std::atomic<bool> enabled{true};   // interruttore «Permessi App › Notifiche»

    void attach(QQuickWebEngineProfile *p)
    {
        connect(p, &QQuickWebEngineProfile::presentNotification, this, &RtNotifier::present);
    }

    // Tocco su una notifica di un processo precedente (patch 0310 del motore):
    // il motore consegna il click al service worker del sito, che apre la sua
    // pagina come ad app aperta. false = motore senza la patch.
    bool clickPersistent(const QString &id, const QString &origin)
    {
        if (!m_click || id.isEmpty()) return false;
        m_click(id.toUtf8().constData(), origin.toUtf8().constData());
        return true;
    }

    // true = notifica ancora nostra: click() inoltrato al sito
    bool activate(const QString &key)
    {
        auto it = m_items.find(key);
        const bool ours = it != m_items.end() && it->n;
        qWarning("[rt] notifica %s toccata: %s", qPrintable(key), ours ? "click al sito" : "non piu' nostra");
        if (!ours) return false;
        it->n->click();
        return true;
    }

    // Push arrivata per un sito (richiesta utenti #3, avito). Se entro 10 s il
    // sito non mostra niente, una notifica nostra: Chrome fa lo stesso (dopo un
    // piccolo budget) con «sito aggiornato in background», QtWebEngine invece
    // tace (silent_push_allowed sempre vero). Casi misurati: service worker
    // senza gestore «push» (m.avito.ru) e payload aesgcm, che UnifiedPush non
    // puo' decifrare perche' Foghorn passa solo il corpo.
    void pushArrived(const QString &origin)
    {
        if (origin.isEmpty() || !enabled.load()) return;
        const QString o = bareOrigin(origin);
        const qint64 t = QDateTime::currentMSecsSinceEpoch();
        QTimer::singleShot(10000, this, [this, o, t]() {
            if (m_lastShown.value(o) >= t) return;
            qWarning("[rt] push di %s senza notifica del sito: mostro quella generica", qPrintable(o));
            presentGeneric(o);
        });
    }

private slots:
    void present(QWebEngineNotification *n)
    {
        if (!n) return;
        // il profilo QML la consegna con proprieta' JavaScript: nessun handler
        // QML la tiene, quindi la gestiamo noi (la cancelliamo noi alla chiusura)
        QQmlEngine::setObjectOwnership(n, QQmlEngine::CppOwnership);
        // incognito: niente notifiche (il QML nega gia' il permesso, come
        // Chrome; questo e' il paracadute). Si guarda qui e non all'attach
        // perche' il profilo normale nasce off-the-record e cambia dopo
        auto *prof = qobject_cast<QQuickWebEngineProfile *>(sender());
        if (!enabled.load() || (prof && prof->isOffTheRecord())) { n->deleteLater(); return; }
        wakeTouch();
        g_wakeNotif = QDateTime::currentMSecsSinceEpoch();

        // stesso tag dello stesso sito = sostituisce la precedente (come Chrome).
        // Senza tag mai: matches() confronta solo tag e origine, e due notifiche
        // senza tag dello stesso sito si sarebbero cancellate a vicenda
        uint replaces = 0;
        for (auto it = m_items.begin(); !n->tag().isEmpty() && it != m_items.end(); ++it) {
            if (it->n && it->n->matches(n)) {
                replaces = it->id;
                it->n->deleteLater();
                m_items.erase(it);
                break;
            }
        }
        // il pid nella chiave: dopo un riavvio la chiave di una notifica
        // vecchia non deve combaciare con una nuova del processo nuovo
        const QString key = QString::number(QCoreApplication::applicationPid()) + '-' + QString::number(++m_seq);
        const QString origin = n->origin().toString();
        const QString host = n->origin().host();
        // id persistente (notifica di un service worker): vale solo qui dentro,
        // il motore emette presentNotification in modo sincrono (patch 0310)
        const QString pid = m_currentId ? QString::fromUtf8(m_currentId()) : QString();

        QVariantMap hints;
        hints.insert(QStringLiteral("x-nemo-preview-summary"), n->title());
        hints.insert(QStringLiteral("x-nemo-preview-body"), n->message());
        hints.insert(QStringLiteral("x-nemo-feedback"), QStringLiteral("chat_exists"));
        hints.insert(QStringLiteral("x-nemo-priority"), 120);
        hints.insert(QStringLiteral("urgency"), QVariant::fromValue<uchar>(1));
        // con l'id persistente il tocco arriva al sito anche ad app riavviata
        hints.insert(QStringLiteral("x-nemo-remote-action-default"),
                     pid.isEmpty()
                     ? m_busName + ' ' + m_objPath + QStringLiteral(" org.freedesktop.Application rtNotificationClicked ")
                       + arg(key) + ' ' + arg(origin)
                     : m_busName + ' ' + m_objPath + QStringLiteral(" org.freedesktop.Application rtPersistentClicked ")
                       + arg(key) + ' ' + arg(origin) + ' ' + arg(pid));
        // «Elimina» (richiesta utenti): con la sola azione default lipstick
        // non offre la freccia per espandere, quindi nemmeno un modo di
        // togliere una singola notifica fuori dalla modalita' riordino. Il
        // remote action va al bus stesso (GetId, sempre presente, senza
        // argomenti): non sveglia l'app chiusa, e lipstick dopo l'azione
        // rimuove la notifica non residente, che ci torna come NotificationClosed
        hints.insert(QStringLiteral("x-nemo-remote-action-delete"),
                     QStringLiteral("org.freedesktop.DBus / org.freedesktop.DBus GetId"));
        const QString icon = saveIcon(n->icon(), host);
        if (!icon.isEmpty()) hints.insert(QStringLiteral("image-path"), icon);

        // il corpo dice anche DA DOVE arriva: titolo e testo li sceglie il sito
        QString body = n->message();
        if (!host.isEmpty()) body = body.isEmpty() ? host : body + QStringLiteral("\n") + host;

        QDBusMessage m = QDBusMessage::createMethodCall(
            QStringLiteral("org.freedesktop.Notifications"), QStringLiteral("/org/freedesktop/Notifications"),
            QStringLiteral("org.freedesktop.Notifications"), QStringLiteral("Notify"));
        m.setArguments({ QStringLiteral("RooTitanium"), replaces, appIcon(), n->title(), body,
                         QStringList{ QStringLiteral("default"), QString(),
                                      QStringLiteral("delete"), deleteLabel() }, hints, -1 });

        m_lastShown.insert(bareOrigin(origin), QDateTime::currentMSecsSinceEpoch());
        Item item; item.n = n; item.origin = origin;
        m_items.insert(key, item);
        connect(n, &QWebEngineNotification::closed, this, [this, key]() { closedBySite(key); });

        auto *w = new QDBusPendingCallWatcher(QDBusConnection::sessionBus().asyncCall(m), this);
        connect(w, &QDBusPendingCallWatcher::finished, this, [this, key](QDBusPendingCallWatcher *w) {
            QDBusPendingReply<uint> r = *w;
            w->deleteLater();
            auto it = m_items.find(key);
            if (r.isError()) {
                qWarning() << "[rt] notifica non consegnata:" << r.error().message();
                if (it != m_items.end()) { if (it->n) it->n->deleteLater(); m_items.erase(it); }
                return;
            }
            if (it == m_items.end()) {          // il sito l'ha gia' chiusa
                closeSystem(r.value());
                return;
            }
            it->id = r.value();
            qWarning("[rt] notifica %s mostrata (id %u)", qPrintable(key), it->id);
            if (it->n) it->n->show();           // evento «show» verso il sito
        });
    }

    // chiusa da lipstick (scorrimento, «cancella tutto» o dopo il tocco)
    void onSystemClosed(uint id, uint reason)
    {
        for (auto it = m_items.begin(); it != m_items.end(); ++it) {
            if (it->id != id) continue;
            const QString key = it.key();
            qWarning("[rt] notifica %s chiusa dal sistema (motivo %u)", qPrintable(key), reason);
            // dopo un tocco lipstick chiude la notifica e chiama il remote
            // action quasi insieme, in ordine non garantito: si aspetta un
            // attimo prima di dimenticarla, o il click arriverebbe a vuoto
            QTimer::singleShot(3000, this, [this, key]() {
                auto it = m_items.find(key);
                if (it == m_items.end()) return;
                QPointer<QWebEngineNotification> n = it->n;
                m_items.erase(it);
                if (n) { n->close(); n->deleteLater(); }
            });
            return;
        }
    }

private:
    struct Item { QPointer<QWebEngineNotification> n; QString origin; uint id = 0; };

    static QString bareOrigin(QString o)
    {
        while (o.endsWith(QLatin1Char('/'))) o.chop(1);
        return o;
    }

    // tocco: la chiave non e' di nessuna notifica viva, quindi il sito si apre
    // sulla sua origine (stessa strada delle notifiche di un processo morto)
    void presentGeneric(const QString &origin)
    {
        g_wakeNotif = QDateTime::currentMSecsSinceEpoch();
        m_lastShown.insert(origin, g_wakeNotif);
        const QString host = QUrl(origin).host().remove(QRegularExpression(QStringLiteral("^www\\.")));
        const bool it = QLocale().language() == QLocale::Italian;
        const QString body = it ? QStringLiteral("Nuova notifica dal sito (senza testo): toccala per aprirlo")
                                : QStringLiteral("New notification from the site (no text): tap to open it");
        QVariantMap hints;
        hints.insert(QStringLiteral("x-nemo-preview-summary"), host);
        hints.insert(QStringLiteral("x-nemo-preview-body"), body);
        hints.insert(QStringLiteral("x-nemo-feedback"), QStringLiteral("chat_exists"));
        hints.insert(QStringLiteral("x-nemo-priority"), 120);
        hints.insert(QStringLiteral("urgency"), QVariant::fromValue<uchar>(1));
        hints.insert(QStringLiteral("x-nemo-remote-action-default"),
                     m_busName + ' ' + m_objPath + QStringLiteral(" org.freedesktop.Application rtNotificationClicked ")
                     + arg(QStringLiteral("generic")) + ' ' + arg(origin));
        hints.insert(QStringLiteral("x-nemo-remote-action-delete"),
                     QStringLiteral("org.freedesktop.DBus / org.freedesktop.DBus GetId"));
        QDBusMessage m = QDBusMessage::createMethodCall(
            QStringLiteral("org.freedesktop.Notifications"), QStringLiteral("/org/freedesktop/Notifications"),
            QStringLiteral("org.freedesktop.Notifications"), QStringLiteral("Notify"));
        m.setArguments({ QStringLiteral("RooTitanium"), uint(0), appIcon(), host, body,
                         QStringList{ QStringLiteral("default"), QString(),
                                      QStringLiteral("delete"), deleteLabel() }, hints, -1 });
        QDBusConnection::sessionBus().send(m);
    }

    void closedBySite(const QString &key)
    {
        auto it = m_items.find(key);
        if (it == m_items.end()) return;
        const uint id = it->id;
        if (it->n) it->n->deleteLater();
        m_items.erase(it);
        if (id) closeSystem(id);
    }

    static void closeSystem(uint id)
    {
        QDBusMessage m = QDBusMessage::createMethodCall(
            QStringLiteral("org.freedesktop.Notifications"), QStringLiteral("/org/freedesktop/Notifications"),
            QStringLiteral("org.freedesktop.Notifications"), QStringLiteral("CloseNotification"));
        m.setArguments({ id });
        QDBusConnection::sessionBus().send(m);
    }

    // stessa scelta di lingua del QML (win.t): italiano o inglese
    static QString deleteLabel()
    {
        return QLocale().language() == QLocale::Italian ? QStringLiteral("Elimina") : QStringLiteral("Delete");
    }

    // argomento del remote action: QVariant serializzato e in base64, come lo
    // decodifica lipstick (Qt 5) → formato di stream fissato a Qt 5
    static QString arg(const QString &v)
    {
        QByteArray ba;
        QDataStream s(&ba, QIODevice::WriteOnly);
        s.setVersion(QDataStream::Qt_5_6);
        s << QVariant(v);
        return QString::fromLatin1(ba.toBase64());
    }

    static QString appIcon()
    {
        for (const char *sz : { "172x172", "128x128", "108x108", "86x86" }) {
            const QString p = QStringLiteral("/usr/share/icons/hicolor/%1/apps/harbour-rootitanium.png")
                                  .arg(QLatin1String(sz));
            if (QFileInfo::exists(p)) return p;
        }
        return QStringLiteral("harbour-rootitanium");
    }

    // icona del sito: un file per host nella cache (lipstick vuole un percorso)
    static QString saveIcon(const QImage &img, const QString &host)
    {
        if (img.isNull() || host.isEmpty()) return QString();
        const QString dir = QStandardPaths::writableLocation(QStandardPaths::CacheLocation)
                            + QStringLiteral("/notifiche");
        QDir().mkpath(dir);
        QString safe = host;
        safe.replace(QRegularExpression(QStringLiteral("[^A-Za-z0-9.-]")), QStringLiteral("_"));
        const QString path = dir + '/' + safe + QStringLiteral(".png");
        const QImage scaled = img.width() > 128 || img.height() > 128
            ? img.scaled(128, 128, Qt::KeepAspectRatio, Qt::SmoothTransformation) : img;
        return scaled.save(path, "PNG") ? path : QString();
    }

    QString m_busName, m_objPath;
    QHash<QString, Item> m_items;
    QHash<QString, qint64> m_lastShown;   // origine (senza / finale) → ms dell'ultima notifica
    quint64 m_seq = 0;
    const char *(*m_currentId)() = (const char *(*)())dlsym(RTLD_DEFAULT, "rtpush_notification_current_id");
    void (*m_click)(const char *, const char *) =
        (void (*)(const char *, const char *))dlsym(RTLD_DEFAULT, "rtpush_notification_click");
};
static RtNotifier *g_notifier = nullptr;

// ===================== Web Push via UnifiedPush (task 2.8 #0) =====================
// Il motore (patch rt_push_driver.cpp in QtWebEngineCore) ha il Web Push di
// Chromium al completo, ma al posto dei server Google chiede A NOI di registrare
// un token presso il distributore UnifiedPush del telefono (Foghorn) e riceve da
// noi endpoint e messaggi. Decifratura e recapito al service worker del sito li
// fa Chromium; la notifica che il sito mostra passa poi da RtNotifier.
// Protocollo: UnifiedPush D-Bus v2 (Distributor2/Connector2), come RooTelegram.
// I simboli rtpush_* si cercano con dlsym: con un motore senza la patch l'app
// parte uguale e il Web Push resta spento (mai verso Google).
extern "C" {
typedef void (*RtPushRegisterCb)(const char *, const char *, const char *);
typedef void (*RtPushUnregisterCb)(const char *);
typedef void (*RtOpenUrlCb)(const char *);
}
class RtUnifiedPush;
class RtPushConnector : public QDBusAbstractAdaptor
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.unifiedpush.Connector2")
public:
    explicit RtPushConnector(RtUnifiedPush *up);
public slots:
    QVariantMap NewEndpoint(const QVariantMap &args);
    QVariantMap Message(const QVariantMap &args);
    QVariantMap Unregistered(const QVariantMap &args);
private:
    RtUnifiedPush *m_up;
};

class RtUnifiedPush : public QObject
{
    Q_OBJECT
public:
    static constexpr const char *SERVICE = "org.unifiedpush.Connector.rootitanium";
    static constexpr const char *PATH = "/org/unifiedpush/Connector";

    RtUnifiedPush()
    {
        s_self = this;
        m_setHandlers = (void (*)(RtPushRegisterCb, RtPushUnregisterCb))dlsym(RTLD_DEFAULT, "rtpush_set_handlers");
        m_endpoint = (void (*)(const char *, const char *))dlsym(RTLD_DEFAULT, "rtpush_endpoint");
        m_failed = (void (*)(const char *))dlsym(RTLD_DEFAULT, "rtpush_failed");
        m_message = (void (*)(const char *, const char *, int))dlsym(RTLD_DEFAULT, "rtpush_message");
        // 0311: con le intestazioni aesgcm; un motore piu' vecchio non lo ha
        m_messageEx = (void (*)(const char *, const char *, int, const char *, const char *, const char *))
                dlsym(RTLD_DEFAULT, "rtpush_message_ex");
        m_unregistered = (void (*)(const char *))dlsym(RTLD_DEFAULT, "rtpush_unregistered");
        m_setOpen = (void (*)(RtOpenUrlCb))dlsym(RTLD_DEFAULT, "rtpush_set_open_handler");
        new RtPushConnector(this);
    }

    // Interruttore «Notifiche push dei siti», SPENTO di default (decisione
    // utente 18 ott). Sta in un file e non nella kv del QML perche' lo deve
    // leggere anche la sveglia, prima del QML. Spento: i siti non si iscrivono,
    // le push in arrivo si scartano, la sveglia esce subito. Le iscrizioni
    // restano: riaccendendo tornano buone.
    static QString onMarker()
    {
        return QDir::homePath() + QStringLiteral("/.local/share/harbour-rootitanium/push-on");
    }
    static QString goneFile()
    {
        return QDir::homePath() + QStringLiteral("/.local/share/harbour-rootitanium/push-gone");
    }
    Q_INVOKABLE bool isEnabled() const { return QFile::exists(onMarker()); }
    // deregistrazioni arrivate a interruttore spento → al motore, che le tiene in
    // coda finche' il suo driver non esiste (nasce con il servizio Push acceso)
    void replayGone()
    {
        if (!m_started || !isEnabled()) return;
        QFile f(goneFile());
        if (!f.open(QIODevice::ReadOnly)) return;
        const QList<QByteArray> tokens = f.readAll().split('\n');
        f.close();
        f.remove();
        for (const QByteArray &t : tokens)
            if (!t.trimmed().isEmpty()) {
                qInfo("[rtpush] deregistrazione rimasta in sospeso: %s", t.constData());
                m_unregistered(t.trimmed().constData());
            }
    }
    Q_INVOKABLE void setEnabled(bool on)
    {
        if (!on) {
            QFile::remove(onMarker());
        } else {
            QDir().mkpath(QFileInfo(onMarker()).absolutePath());
            QFile f(onMarker());
            if (f.open(QIODevice::WriteOnly)) f.write("1\n");
        }
        qInfo("[rtpush] notifiche push dei siti: %s", on ? "accese" : "spente");
        if (on) replayGone();
    }
    // per la riga di stato in Impostazioni: noengine | noname | nodistributor | ready:<nome>
    Q_INVOKABLE QString status() const
    {
        if (!engineSupport()) return QStringLiteral("noengine");
        if (!m_started) return QStringLiteral("noname");
        const QString d = findDistributor();
        if (d.isEmpty()) return QStringLiteral("nodistributor");
        return QStringLiteral("ready:") + d.mid(int(qstrlen("org.unifiedpush.Distributor.")));
    }

    // il motore ha la patch: si puo' accendere il servizio Push del profilo
    bool engineSupport() const
    {
        return m_setHandlers && m_endpoint && m_failed && m_message && m_unregistered;
    }

    // Prende il nome del connettore (Foghorn ci chiama li') e si offre al motore.
    bool start()
    {
        // openWindow dei siti e click delle notifiche (0310) anche a Push spento
        if (m_setOpen) m_setOpen(&RtUnifiedPush::onOpenUrl);
        if (!engineSupport()) {
            qWarning("[rtpush] motore senza ponte UnifiedPush: Web Push spento");
            return false;
        }
        QDBusConnection bus = QDBusConnection::sessionBus();
        if (!bus.registerObject(QLatin1String(PATH), this, QDBusConnection::ExportAdaptors)
            || !bus.registerService(QLatin1String(SERVICE))) {
            qWarning("[rtpush] nome %s non disponibile: %s", SERVICE, qPrintable(bus.lastError().message()));
            bus.unregisterObject(QLatin1String(PATH));
            return false;
        }
        m_setHandlers(&RtUnifiedPush::onRegister, &RtUnifiedPush::onUnregister);
        m_started = true;
        replayGone();
        const QString d = findDistributor();
        qInfo("[rtpush] connettore %s pronto (distributore: %s)", SERVICE,
              d.isEmpty() ? "nessuno" : qPrintable(d));
        return true;
    }

    void newEndpoint(const QString &token, const QString &endpoint)
    {
        qInfo("[rtpush] endpoint per %s: %s", qPrintable(token), qPrintable(QUrl(endpoint).host()));
        m_endpoint(token.toUtf8().constData(), endpoint.toUtf8().constData());
    }
    void message(const QString &token, const QByteArray &body, const QString &encoding = QString(),
                 const QString &encryption = QString(), const QString &cryptoKey = QString())
    {
        if (!isEnabled()) {
            qInfo("[rtpush] push per %s scartata: interruttore spento", qPrintable(token));
            return;
        }
        qInfo("[rtpush] push di %d byte per %s%s", int(body.size()), qPrintable(token),
              encoding.isEmpty() ? "" : qPrintable(QStringLiteral(" (") + encoding + QLatin1Char(')')));
        emit activity();
        if (m_messageEx && !encoding.isEmpty())
            m_messageEx(token.toUtf8().constData(), body.constData(), int(body.size()),
                        encoding.toUtf8().constData(), encryption.toUtf8().constData(),
                        cryptoKey.toUtf8().constData());
        else
            m_message(token.toUtf8().constData(), body.constData(), int(body.size()));
        if (g_notifier) g_notifier->pushArrived(originOf(token));
    }
    // sito di una registrazione: il motore tiene token → app_id in rtpush.json,
    // e l'app_id di Chromium e' «wp:<origine>#<guid>»
    static QString originOf(const QString &token)
    {
        QFile f(QDir::homePath() + QStringLiteral("/.rootitanium/GCM Store/rtpush.json"));
        if (!f.open(QIODevice::ReadOnly)) return QString();
        const QString app = QJsonDocument::fromJson(f.readAll()).object()
            .value(QLatin1String("registrations")).toObject()
            .value(token).toObject().value(QLatin1String("app_id")).toString();
        if (!app.startsWith(QLatin1String("wp:"))) return QString();
        return app.mid(3).section(QLatin1Char('#'), 0, 0);
    }

    void unregistered(const QString &token)
    {
        qInfo("[rtpush] il distributore ha tolto %s", qPrintable(token));
        if (!isEnabled()) {
            // a interruttore spento il motore non ha il driver attivo e la
            // notizia andrebbe persa (misurato 19 ott): la si tiene da parte
            // e la si consegna alla riaccensione, altrimenti il sito si
            // crederebbe ancora iscritto senza ricevere piu' nulla
            QDir().mkpath(QFileInfo(goneFile()).absolutePath());
            QFile f(goneFile());
            if (f.open(QIODevice::Append)) f.write(token.toUtf8() + '\n');
            return;
        }
        m_unregistered(token.toUtf8().constData());
    }

signals:
    void noDistributor();   // → QML: avviso «installa Foghorn»
    void activity();        // push arrivata: la sveglia resta viva ancora un po'
    void openUrlRequested(const QString &url);   // clients.openWindow() del sito

private:
    static void onRegister(const char *token, const char *vapid, const char *description)
    {
        if (s_self) s_self->doRegister(QString::fromUtf8(token), QString::fromUtf8(vapid), QString::fromUtf8(description));
    }
    static void onUnregister(const char *token)
    {
        if (s_self) s_self->doUnregister(QString::fromUtf8(token));
    }
    static void onOpenUrl(const char *url)
    {
        qInfo("[rtpush] il sito apre %s", url);
        if (s_self) emit s_self->openUrlRequested(QString::fromUtf8(url));
    }

    void doRegister(const QString &token, const QString &vapid, const QString &description, int attempt = 1)
    {
        if (!isEnabled()) {
            qInfo("[rtpush] iscrizione %s rifiutata: interruttore spento", qPrintable(token));
            m_failed(token.toUtf8().constData());
            return;
        }
        const QString distributor = findDistributor();
        if (distributor.isEmpty()) {
            qWarning("[rtpush] nessun distributore UnifiedPush installato");
            m_failed(token.toUtf8().constData());
            emit noDistributor();
            return;
        }
        QVariantMap args;
        args.insert(QStringLiteral("service"), QLatin1String(SERVICE));
        args.insert(QStringLiteral("token"), token);
        args.insert(QStringLiteral("description"), description);
        // la chiave VAPID del sito: con Mozilla l'endpoint accetta solo lui
        if (!vapid.isEmpty()) args.insert(QStringLiteral("vapid"), vapid);
        QDBusMessage call = QDBusMessage::createMethodCall(distributor, QStringLiteral("/org/unifiedpush/Distributor"),
                                                           QStringLiteral("org.unifiedpush.Distributor2"),
                                                           QStringLiteral("Register"));
        call << args;
        // asincrona: prima di rispondere il distributore ci chiama NewEndpoint
        // 0311: 30 s e non 20, cioe' piu' dei 20 che Foghorn concede al server:
        // con lo stesso valore la nostra attesa scadeva un attimo prima della
        // sua risposta
        auto *w = new QDBusPendingCallWatcher(QDBusConnection::sessionBus().asyncCall(call, 30000), this);
        connect(w, &QDBusPendingCallWatcher::finished, this,
                [this, token, vapid, description, attempt](QDBusPendingCallWatcher *w) {
            w->deleteLater();
            const QDBusMessage r = w->reply();
            // a{sv} arriva come QDBusArgument: toMap() darebbe una mappa vuota
            const QVariantMap res = qdbus_cast<QVariantMap>(r.arguments().value(0));
            if (r.type() == QDBusMessage::ReplyMessage
                && res.value(QStringLiteral("success")).toString() == QLatin1String("REGISTRATION_SUCCEEDED")) {
                qInfo("[rtpush] registrazione %s accettata", qPrintable(token));
                return;
            }
            const QString reason = res.value(QStringLiteral("reason")).toString();
            qWarning("[rtpush] registrazione %s rifiutata (tentativo %d): %s %s", qPrintable(token), attempt,
                     qPrintable(r.errorMessage()), qPrintable(reason));
            // 0311: INTERNAL_ERROR (o nessuna risposta) = Foghorn non collegato
            // al server in quel momento, misurato il 24 ott: si ricollega da
            // solo pochi secondi dopo. Si riprova invece di rinunciare
            const bool transient = r.type() != QDBusMessage::ReplyMessage || reason == QLatin1String("INTERNAL_ERROR");
            if (transient && attempt < 3) {
                QTimer::singleShot(8000, this, [this, token, vapid, description, attempt]() {
                    doRegister(token, vapid, description, attempt + 1);
                });
                return;
            }
            m_failed(token.toUtf8().constData());
        });
    }

    void doUnregister(const QString &token)
    {
        const QString distributor = findDistributor();
        if (distributor.isEmpty()) return;
        QVariantMap args;
        args.insert(QStringLiteral("token"), token);
        QDBusMessage call = QDBusMessage::createMethodCall(distributor, QStringLiteral("/org/unifiedpush/Distributor"),
                                                           QStringLiteral("org.unifiedpush.Distributor2"),
                                                           QStringLiteral("Unregister"));
        call << args;
        QDBusConnection::sessionBus().send(call);
        qInfo("[rtpush] deregistrato %s", qPrintable(token));
    }

    // primo org.unifiedpush.Distributor.* attivo o attivabile (Foghorn)
    static QString findDistributor()
    {
        QDBusConnectionInterface *iface = QDBusConnection::sessionBus().interface();
        if (!iface) return QString();
        QStringList names = iface->registeredServiceNames().value();
        QDBusMessage la = QDBusMessage::createMethodCall(QStringLiteral("org.freedesktop.DBus"), QStringLiteral("/org/freedesktop/DBus"),
                                                         QStringLiteral("org.freedesktop.DBus"), QStringLiteral("ListActivatableNames"));
        const QDBusMessage r = QDBusConnection::sessionBus().call(la, QDBus::Block, 3000);
        if (r.type() == QDBusMessage::ReplyMessage) names += r.arguments().value(0).toStringList();
        for (const QString &n : names)
            if (n.startsWith(QLatin1String("org.unifiedpush.Distributor."))) return n;
        return QString();
    }

    static RtUnifiedPush *s_self;
    void (*m_setHandlers)(RtPushRegisterCb, RtPushUnregisterCb) = nullptr;
    void (*m_endpoint)(const char *, const char *) = nullptr;
    void (*m_failed)(const char *) = nullptr;
    void (*m_message)(const char *, const char *, int) = nullptr;
    void (*m_messageEx)(const char *, const char *, int, const char *, const char *, const char *) = nullptr;
    void (*m_unregistered)(const char *) = nullptr;
    void (*m_setOpen)(RtOpenUrlCb) = nullptr;
    bool m_started = false;
};
RtUnifiedPush *RtUnifiedPush::s_self = nullptr;

RtPushConnector::RtPushConnector(RtUnifiedPush *up) : QDBusAbstractAdaptor(up), m_up(up) {}

QVariantMap RtPushConnector::NewEndpoint(const QVariantMap &args)
{
    m_up->newEndpoint(args.value(QStringLiteral("token")).toString(), args.value(QStringLiteral("endpoint")).toString());
    return QVariantMap();
}

QVariantMap RtPushConnector::Message(const QVariantMap &args)
{
    const QVariant v = args.value(QStringLiteral("message"));
    const QByteArray body = v.canConvert<QDBusArgument>() ? qdbus_cast<QByteArray>(v) : v.toByteArray();
    // 0311: intestazioni di cifratura, se il distributore le inoltra (oggi
    // Foghorn no: richiesta all'autore). Accettati sia un dizionario «headers»
    // con i nomi di autopush, sia le chiavi piatte; trattino o trattino basso
    QVariantMap h = args;
    const QVariant hv = args.value(QStringLiteral("headers"));
    if (hv.canConvert<QDBusArgument>()) {
        // a{ss} oppure a{sv}: convertire un a{ss} in QVariantMap fa cadere
        // l'app (SIGSEGV, misurato 24 ott), quindi si guarda la firma
        const QDBusArgument a = hv.value<QDBusArgument>();
        if (a.currentSignature() == QLatin1String("a{ss}")) {
            QMap<QString, QString> m;
            a >> m;
            for (auto it = m.cbegin(); it != m.cend(); ++it) h.insert(it.key(), it.value());
        } else if (a.currentSignature() == QLatin1String("a{sv}")) {
            QVariantMap m;
            a >> m;
            h.insert(m);
        }
    } else if (hv.isValid()) {
        h.insert(hv.toMap());
    }
    auto pick = [&h](std::initializer_list<const char *> names) {
        for (const char *n : names) {
            const QString v = h.value(QLatin1String(n)).toString();
            if (!v.isEmpty()) return v;
        }
        return QString();
    };
    m_up->message(args.value(QStringLiteral("token")).toString(), body,
                  pick({ "encoding", "content-encoding", "content_encoding" }),
                  pick({ "encryption" }), pick({ "crypto_key", "crypto-key" }));
    // l'id conferma la consegna al distributore
    QVariantMap reply;
    reply.insert(QStringLiteral("id"), args.value(QStringLiteral("id")).toString());
    return reply;
}

QVariantMap RtPushConnector::Unregistered(const QVariantMap &args)
{
    m_up->unregistered(args.value(QStringLiteral("token")).toString());
    return QVariantMap();
}

class OpenHandler : public QObject
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.freedesktop.Application")
public slots:
    // due overload: "as" e' quello che usa libcontentaction, "s" i chiamanti
    // che passano un URI solo (la nostra riga di inoltro in main()).
    void openUrl(const QStringList &uris) { if (!uris.isEmpty()) handle(uris.first()); }
    void openUrl(const QString &url) { handle(url); }

    // «Sei viva?» chiesto dal processo nato da un nuovo lancio (task 2.5 #7).
    // Gli slot girano nel MAIN thread: un'istanza col ciclo eventi piantato non
    // risponde, ed e' proprio quello che si vuole scoprire (il Ping standard di
    // org.freedesktop.DBus.Peer no: lo serve il thread DBus anche a main thread
    // fermo). Valore = finestre visibili; 0 = istanza viva ma senza finestra.
    int rtAlive()
    {
        // sveglia nascosta: chi chiede e' un lancio dall'icona → ci mostriamo noi,
        // altrimenti ci chiuderebbe come fantasma (0 finestre) e ripartirebbe
        if (g_wakeHidden.exchange(false)) { emit wakeShow(); return 1; }
        int n = 0;
        for (QWindow *w : QGuiApplication::allWindows())
            if (w->isVisible()) ++n;
        return n;
    }

    // tocco su una notifica di un service worker (patch 0310): se la notifica
    // e' di un processo precedente il click va al sito tramite il suo id
    void rtPersistentClicked(const QString &key, const QString &origin, const QString &id)
    {
        if (g_wakeHidden.exchange(false)) emit wakeShow();
        if (g_notifier && g_notifier->activate(key)) emit notificationClicked(origin);
        else if (g_notifier && g_notifier->clickPersistent(id, origin)) emit persistentClicked(origin);
        else if (!origin.isEmpty()) emit openRequested(origin);
        if (!RtWindowRaiser::raise())
            qWarning("[rt] primo piano non richiesto: finestra o protocollo assenti");
    }

    // tocco su una notifica di un sito (remote action di lipstick, task 2.7 #1)
    void rtNotificationClicked(const QString &key, const QString &origin)
    {
        if (g_wakeHidden.exchange(false)) emit wakeShow();
        if (g_notifier && g_notifier->activate(key)) emit notificationClicked(origin);
        else if (!origin.isEmpty()) emit openRequested(origin);   // app riavviata: la notifica non e' piu' nostra
        if (!RtWindowRaiser::raise())
            qWarning("[rt] primo piano non richiesto: finestra o protocollo assenti");
    }

signals:
    void openRequested(const QString &url);   // → QML: apri in NUOVA scheda
    void notificationClicked(const QString &origin);   // → QML: vai alla scheda del sito
    void persistentClicked(const QString &origin);     // → QML: idem, ma il sito parte da freddo
    void wakeShow();   // → QML: la sveglia diventa l'app vera (finestra + sessione)

private:
    void handle(const QString &uri)
    {
        if (uri.isEmpty()) return;
        if (g_wakeHidden.exchange(false)) emit wakeShow();
        emit openRequested(uri);
        // in cover l'utente non vedrebbe la scheda nuova (task 2.5 #3)
        if (!RtWindowRaiser::raise())
            qWarning("[rt] primo piano non richiesto: finestra o protocollo assenti");
    }
};

// Helper nativo esposto al QML come "rtNative": cose che il QML Qt6 puro non
// sa fare (DBus, filesystem). Niente dipendenze Silica.
// ===================== tastiera di sistema: orientamento =====================
// Il plugin input-context di Maliit NON manda piu' al server l'orientamento
// dell'app: la connessione a contentOrientationChanged e' COMMENTATA nel
// sorgente del pacchetto (righe 348/354 di minputcontext.cpp, dal commit di
// Rinigus del 2020 "follow Flatpak container window orientation"). Al suo posto
// il plugin interroga un "container" D-Bus, ma solo se trova il suo indirizzo in
// FLATPAK_MALIIT_CONTAINER_DBUS — pensato per le app Flatpak, dove il container
// e' il compositore annidato. Senza quella variabile l'angolo resta 0 per sempre
// e la tastiera non ruota mai: e' il motivo per cui in orizzontale esce dritta.
//
// Qui facciamo noi da container per il NOSTRO plugin: un server D-Bus
// peer-to-peer privato del processo (nessun bus di sessione, nessun servizio
// pubblicato) che espone org.container con le due proprieta' che il plugin
// legge — `orientation` (gradi) e `activeState` — e i due segnali che ascolta.
// Vedi Documentation/TASK-tastiera-sistema.md.
class RtMaliitContainer : public QDBusAbstractAdaptor
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.container")
    Q_PROPERTY(int orientation READ orientation)
    Q_PROPERTY(bool activeState READ activeState)
public:
    explicit RtMaliitContainer(QObject *parent) : QDBusAbstractAdaptor(parent) {}
    int orientation() const { return m_angle; }
    // sempre attivo: il plugin inoltra l'angolo solo se il container si dichiara
    // tale (updateContainerOrientation: `if (containerActive && active)`)
    bool activeState() const { return true; }
public slots:
    // invocato dal main thread via QueuedConnection: l'oggetto vive nel thread
    // del container e il segnale deve partire da li'
    void setOrientation(int angle)
    {
        if (angle == m_angle) return;
        m_angle = angle;
        emit orientationChanged(angle);
    }
    // Ripete l'angolo ANCHE se non e' cambiato. Serve all'apertura della
    // tastiera: il plugin inoltra al server solo con un campo a fuoco
    // (`containerActive && active`), quindi la prima volta l'angolo arriva
    // insieme alla tastiera e lipstick puo' aver gia' calcolato l'area riservata
    // su una tastiera verticale (finestra alta 194 px invece di 480: i due esiti
    // alternati visti sul POCO). Ripetendolo, il calcolo viene rifatto.
    void reassertOrientation() { emit orientationChanged(m_angle); }
signals:
    void orientationChanged(int angle);
    void activeStateChanged(bool active);
private:
    int m_angle = 0;
};

// Il container DEVE vivere in un thread suo. Il plugin maliit si costruisce
// dentro l'init di QGuiApplication, sul MAIN thread, e li' legge le nostre
// proprieta' con una chiamata D-Bus SINCRONA: se a servirla fosse il main
// thread — fermo ad aspettare quella stessa risposta — l'app si pianta prima di
// mostrare la finestra. Successo verificato: senza thread il log si ferma su
// "Successfully created platform theme", con il thread l'app parte.
class RtMaliitContainerThread : public QThread
{
    Q_OBJECT
public:
    explicit RtMaliitContainerThread(const QString &address)
        : m_address(address) {}

    // indirizzo REALE del server (con guid), valido dopo waitReady()
    QString serverAddress() const { return m_realAddress; }
    RtMaliitContainer *adaptor() const { return m_adaptor; }
    bool waitReady(int ms) { return m_ready.tryAcquire(1, ms); }

protected:
    void run() override
    {
        QDBusServer server(m_address);
        QObject obj;
        m_adaptor = new RtMaliitContainer(&obj);
        if (server.isConnected()) {
            m_realAddress = server.address();
            QObject::connect(&server, &QDBusServer::newConnection, &obj,
                             [&obj](const QDBusConnection &c) {
                QDBusConnection conn(c);
                conn.registerObject(QStringLiteral("/"), &obj,
                                    QDBusConnection::ExportAdaptors);
            });
        }
        m_ready.release();
        if (!server.isConnected()) return;
        exec();
    }

private:
    QString m_address;
    QString m_realAddress;
    QSemaphore m_ready;
    RtMaliitContainer *m_adaptor = nullptr;
};

static void killTree(pid_t root);   // sotto, con gli helper /proc (task 2.5 #7)

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

    // --- orientamento della tastiera di sistema (vedi RtMaliitContainer) ---
    void setMaliitContainer(RtMaliitContainer *c) { m_maliit = c; }
    // Chiamata dal QML a ogni cambio di orientamento della UI. L'angolo e' quello
    // di cui e' ruotato il CONTENUTO (0 o 90), non il telefono.
    Q_INVOKABLE void setKeyboardOrientation(int angle)
    {
        if (!m_maliit) return;
        QMetaObject::invokeMethod(m_maliit, "setOrientation", Qt::QueuedConnection,
                                  Q_ARG(int, angle));
    }
    // da chiamare quando la tastiera compare (vedi reassertOrientation)
    Q_INVOKABLE void reassertKeyboardOrientation()
    {
        if (!m_maliit) return;
        QMetaObject::invokeMethod(m_maliit, "reassertOrientation", Qt::QueuedConnection);
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
    // versione completa del Chromium del motore (es. "140.0.7339.264"):
    // UA e Client Hints la prendono da qui (task 2.6 #3)
    Q_INVOKABLE QString chromiumVersion() { return QString::fromLatin1(qWebEngineChromiumVersion()); }

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

    // «Apri con…» (richiesta utenti): le app che libcontentaction associa al
    // tipo del file, nell'ordine di lca-tool. Ogni voce: id = nome del .desktop
    // (quello che vuole --trigger), name = nome localizzato, def = predefinita
    Q_INVOKABLE QVariantList openWithActions(const QString &path)
    {
        QVariantList out;
        if (!QFileInfo::exists(path))
            return out;
        const QString url = QUrl::fromLocalFile(path).toString();
        auto run = [](const QStringList &args) {
            QProcess p;
            p.start(QStringLiteral("/usr/bin/lca-tool"), args);
            if (!p.waitForFinished(4000)) { p.kill(); p.waitForFinished(500); return QStringList(); }
            return QString::fromUtf8(p.readAllStandardOutput()).split(QLatin1Char('\n'), Qt::SkipEmptyParts);
        };
        const QStringList ids = run({ QStringLiteral("--file"), QStringLiteral("--print"), url });
        const QStringList names = run({ QStringLiteral("--l10n"), QStringLiteral("--file"), QStringLiteral("--print"), url });
        const QStringList def = run({ QStringLiteral("--file"), QStringLiteral("--printdefault"), url });
        for (int i = 0; i < ids.size(); ++i) {
            const QString id = ids.at(i).trimmed();
            if (id.isEmpty())
                continue;
            out.append(QVariantMap{
                { QStringLiteral("id"), id },
                { QStringLiteral("name"), names.size() == ids.size() ? names.at(i).trimmed() : id },
                { QStringLiteral("def"), !def.isEmpty() && def.first().trimmed() == id },
            });
        }
        return out;
    }
    Q_INVOKABLE bool openFileWith(const QString &path, const QString &action)
    {
        if (!QFileInfo::exists(path) || action.isEmpty())
            return false;
        return QProcess::startDetached(QStringLiteral("/usr/bin/lca-tool"),
            { QStringLiteral("--file"), QStringLiteral("--trigger"), action, QUrl::fromLocalFile(path).toString() });
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
        // notifiche dei siti (task 2.7 #1). L'incognito lo scarta present()
        if (g_notifier) g_notifier->attach(p);

        // task 1.3 §C — cookie di terze parti. Il filtro resta installato per
        // sempre e consulta il toggle a ogni richiesta: così accenderlo o
        // spegnerlo ha effetto subito, senza reinstallare nulla (QWebEngineCookieStore
        // ::FilterRequest::thirdParty, verificato in qwebenginecookiestore.h 6.8.3).
        p->cookieStore()->setCookieFilter([](const QWebEngineCookieStore::FilterRequest &r) {
            return !(g_privacy.block3pCookies.load(std::memory_order_relaxed) && r.thirdParty);
        });
    }

    // Link visitati di Chromium: vedi il blocco RT_VISITED_LINKS in cima.
    // urls vuota = tutti. Ritorna false se qui non si puo' (header assenti al
    // build): il QML tratta false come «niente da fare», non come errore.
    Q_INVOKABLE bool clearVisitedLinks(QObject *profileObj, const QStringList &urls)
    {
#ifdef RT_VISITED_LINKS
        auto *m = rtpriv::visitati(qobject_cast<QQuickWebEngineProfile *>(profileObj));
        if (!m) return false;
        if (urls.isEmpty()) { m->deleteAllVisitedLinkData(); return true; }
        QList<QUrl> l;
        for (const QString &u : urls) l.append(QUrl(u));
        m->deleteVisitedLinkDataForUrls(l);
        return true;
#else
        Q_UNUSED(profileObj); Q_UNUSED(urls);
        return false;
#endif
    }
    // Solo per il collaudo (il colore :visited non e' leggibile da JS, per scelta
    // di Chromium): dice se Chromium ricorda l'URL come visitato.
    Q_INVOKABLE bool visitedLinkKnown(QObject *profileObj, const QString &url)
    {
#ifdef RT_VISITED_LINKS
        auto *m = rtpriv::visitati(qobject_cast<QQuickWebEngineProfile *>(profileObj));
        return m && m->containsUrl(QUrl(url));
#else
        Q_UNUSED(profileObj); Q_UNUSED(url);
        return false;
#endif
    }

    // --- task 1.3 §E: i tre toggle, letti da interceptor e cookie filter ---
    // Chiamata dal QML a ogni cambio e una volta all'avvio dopo loadCfg().
    // interruttore «Permessi App › Notifiche»: spento, anche i siti gia'
    // autorizzati tacciono (il permesso salvato per sito resta com'e')
    Q_INVOKABLE void setNotificationsEnabled(bool on) { if (g_notifier) g_notifier->enabled = on; }

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

    // Voce «Esci» del menu' (task 2.5 #7). Chiusura ordinata, con una rete di
    // sicurezza: se lo spegnimento di Chromium si pianta, fra 5 s il processo
    // chiude comunque se stesso e i suoi figli. Su SFOS chiudere la cover non
    // basta a sapere che l'app e' morta davvero: qui lo e'.
    Q_INVOKABLE void quitApp()
    {
        std::thread([] {
            std::this_thread::sleep_for(std::chrono::seconds(5));
            killTree(getpid());
            _exit(0);
        }).detach();
        QCoreApplication::quit();
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
    RtMaliitContainer *m_maliit = nullptr;
    bool m_keepDisplayOn = false;
};

// ===================== istanze fantasma (task 2.5 #7) =====================
// Caso reale (Moto Edge 30 Neo, port non ufficiale): un lancio rimasto vivo
// senza finestra tiene il nome DBus, e da li' ogni tocco sull'icona trova il
// nome occupato, crede di parlare con l'istanza buona ed esce muto. L'utente
// vede solo «l'app non parte». Questi helper leggono /proc per decidere se il
// proprietario del nome e' davvero un fantasma e, solo allora, chiuderlo con
// tutti i suoi processi Chromium.

static QString procExe(pid_t pid)
{
    char buf[PATH_MAX];
    const QByteArray link = QStringLiteral("/proc/%1/exe").arg(pid).toLatin1();
    const ssize_t n = readlink(link.constData(), buf, sizeof(buf) - 1);
    if (n <= 0) return QString();
    buf[n] = '\0';
    return QString::fromLocal8Bit(buf);
}

// campi di /proc/PID/stat DOPO il nome tra parentesi (che puo' contenere spazi):
// [0] = stato, [1] = ppid, [19] = starttime in tick
static QList<QByteArray> procStat(pid_t pid)
{
    QFile f(QStringLiteral("/proc/%1/stat").arg(pid));
    if (!f.open(QIODevice::ReadOnly)) return {};
    const QByteArray all = f.readAll();
    const int close = all.lastIndexOf(')');
    if (close < 0) return {};
    return all.mid(close + 2).split(' ');
}

// secondi da quando il processo e' nato (-1 se non si sa)
static double procAgeSec(pid_t pid)
{
    const QList<QByteArray> st = procStat(pid);
    QFile up(QStringLiteral("/proc/uptime"));
    if (st.size() < 20 || !up.open(QIODevice::ReadOnly)) return -1;
    const double uptime = up.readAll().split(' ').value(0).toDouble();
    return uptime - st.at(19).toDouble() / sysconf(_SC_CLK_TCK);
}

// tutti i discendenti (zygote e renderer di Chromium sono nipoti, non figli)
static QList<pid_t> procDescendants(pid_t root)
{
    QHash<pid_t, QList<pid_t>> children;
    const QStringList dirs = QDir(QStringLiteral("/proc")).entryList(QDir::Dirs | QDir::NoDotAndDotDot);
    for (const QString &d : dirs) {
        bool ok = false;
        const pid_t pid = d.toInt(&ok);
        if (!ok) continue;
        const QList<QByteArray> st = procStat(pid);
        if (st.size() > 1) children[(pid_t)st.at(1).toInt()].append(pid);
    }
    QList<pid_t> out, todo{root};
    while (!todo.isEmpty()) {
        const pid_t p = todo.takeFirst();
        for (pid_t c : children.value(p)) { out.append(c); todo.append(c); }
    }
    return out;
}

static void killTree(pid_t root)
{
    for (pid_t p : procDescendants(root)) kill(p, SIGKILL);
    if (root != getpid()) kill(root, SIGKILL);
}

// Il proprietario del nome e' un fantasma? Nel dubbio NO: chiudere un'istanza
// buona costa le schede aperte, lasciare un fantasma costa un altro tocco.
static bool ownerIsGhost(QDBusConnection &bus, const QString &busName,
                         const QString &objPath, pid_t pid)
{
    if (pid <= 0) return false;
    // mai uccidere un processo che non e' RooTitanium
    if (!procExe(pid).endsWith(QLatin1String("/webengine-smoke"))) return false;
    // ancora in avvio (QML in caricamento = main thread occupato): non e' un
    // fantasma, e' il doppio tocco sull'icona
    const double age = procAgeSec(pid);
    if (age >= 0 && age < 20) return false;
    for (int attempt = 0; attempt < 2; ++attempt) {
        QDBusMessage m = QDBusMessage::createMethodCall(
            busName, objPath, QStringLiteral("org.freedesktop.Application"),
            QStringLiteral("rtAlive"));
        const QDBusMessage r = bus.call(m, QDBus::Block, 5000);
        if (r.type() == QDBusMessage::ReplyMessage) {
            const int windows = r.arguments().value(0).toInt();
            if (windows > 0) return false;
            qWarning("[rt] istanza %d viva ma senza finestre", (int)pid);
            return true;
        }
        // versione vecchia senza rtAlive: ha risposto, quindi il ciclo eventi gira
        if (r.errorName() == QLatin1String("org.freedesktop.DBus.Error.UnknownMethod"))
            return false;
        qWarning("[rt] istanza %d non risponde (tentativo %d): %s", (int)pid,
                 attempt + 1, qPrintable(r.errorName()));
    }
    return true;
}

int main(int argc, char **argv)
{
    // comm del processo (/proc/PID/stat, /proc/PID/comm) = "harbour-rootita"
    // (troncato a 15 char): assicura che, oltre alla cmdline (argv[0] forgiato dal
    // launcher), anche il nome-processo che lipstick puo' leggere combaci col
    // launcher item. Insieme evitano la cover-segnaposto fantasma all'avvio.
    prctl(PR_SET_NAME, (unsigned long)"harbour-rootitanium", 0, 0, 0);

    // avvio da attivazione D-Bus di Foghorn (org.unifiedpush.Connector.rootitanium
    // .service): la variabile si toglie subito, non deve arrivare ai figli
    const bool pushWake = qgetenv("RT_PUSH_WAKE") == "1";
    qunsetenv("RT_PUSH_WAKE");
    g_wakeHidden = pushWake;
    wakeTouch();

    // Ripiego rendering software: se accanto al binario esiste il file NOGPU,
    // Chromium non usa la GPU. Serve col motore 6.140 sui driver senza
    // EGL_EXT_image_dma_buf_import (Mali/libhybris): la pagina via GPU esce
    // nera finche' il passaggio texture Chromium->Qt non e' risolto.
    if (QFile::exists(QFileInfo(QStringLiteral("/proc/self/exe")).canonicalPath()
                      + QStringLiteral("/NOGPU"))) {
        QByteArray flags = qgetenv("QTWEBENGINE_CHROMIUM_FLAGS");
        flags += " --disable-gpu --disable-gpu-compositing";
        qputenv("QTWEBENGINE_CHROMIUM_FLAGS", flags);
        qInfo("[rt] NOGPU presente: rendering software");
    }

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

    // Container Maliit (vedi RtMaliitContainer): il server dev'essere gia' in
    // ascolto e l'indirizzo gia' nell'ambiente PRIMA che nasca QGuiApplication,
    // perche' il plugin input-context si costruisce li' dentro e legge la
    // variabile una volta sola. Socket privato in XDG_RUNTIME_DIR, un nome per
    // processo: niente bus di sessione, nessun servizio visibile ad altri.
    RtMaliitContainerThread *maliitContainer = nullptr;
    {
        const QByteArray xrd = qgetenv("XDG_RUNTIME_DIR");
        if (!xrd.isEmpty()) {
            const QString sock = QStringLiteral("%1/rt-maliit-%2")
                                     .arg(QString::fromLocal8Bit(xrd))
                                     .arg((int)getpid());
            QFile::remove(sock);   // socket orfano di un'istanza morta male
            maliitContainer = new RtMaliitContainerThread(
                QStringLiteral("unix:path=%1").arg(sock));
            maliitContainer->start();
            // se il thread non e' pronto in fretta si prosegue SENZA container:
            // si perde la rotazione della tastiera, non l'avvio dell'app
            if (maliitContainer->waitReady(3000)
                && !maliitContainer->serverAddress().isEmpty()) {
                qputenv("FLATPAK_MALIIT_CONTAINER_DBUS",
                        maliitContainer->serverAddress().toLatin1());
                qInfo("[rt] container Maliit in ascolto su %s",
                      qPrintable(maliitContainer->serverAddress()));
            } else {
                qWarning("[rt] container Maliit non avviato: la tastiera di sistema"
                         " non ruotera' in orizzontale");
            }
        }
    }

    // Da Qt 6.12 initialize() e' vuota (deprecata): non accende piu' i contesti
    // GL condivisi. Senza, la texture che Chromium disegna non e' visibile dal
    // contesto di Qt e la pagina esce NERA (Mali senza dma_buf import, POCO).
    QCoreApplication::setAttribute(Qt::AA_ShareOpenGLContexts);
    QtWebEngineQuick::initialize();
    QGuiApplication app(argc, argv);
    // app_id Wayland = basename del .desktop INSTALLATO (harbour-rootitanium.desktop):
    // deve combaciare col nome del .desktop da cui lipstick lancia, altrimenti non
    // aggancia la finestra alla cover del launcher e mostra una cover-segnaposto
    // "in avvio" che va in timeout e si chiude da sola (doppia cover all'avvio).
    app.setDesktopFileName(QStringLiteral("harbour-rootitanium"));

    // carica test.qml dalla stessa cartella dell'eseguibile. Dal VERO percorso
    // (/proc/self/exe), non da argv[0]: il launcher forgia argv[0] per farsi
    // riconoscere da lipstick, e cosi' il suo valore resta libero (task 2.5 #3).
    const QString base = QCoreApplication::applicationDirPath();

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
        // Nome gia' occupato = l'istanza viva e' un'altra. Prima pero' si
        // controlla che sia viva davvero (task 2.5 #7): se e' un fantasma la si
        // chiude e si parte noi, altrimenti l'app non si aprirebbe piu'.
        const pid_t owner = (pid_t)bus.interface()->servicePid(busName).value();
        if (!ownerIsGhost(bus, busName, objPath, owner)) {
            // Istanza buona: le passiamo l'URL (che aprira' in una scheda
            // nuova) e usciamo senza mai creare una seconda finestra. Senza URL
            // non c'e' niente da dire: il foreground lo fa lipstick.
            qInfo("[rt] istanza gia' attiva (pid %d): %s", (int)owner,
                  openUrl.isEmpty() ? "esco" : "le passo il link ed esco");
            if (!openUrl.isEmpty()) {
                QDBusMessage fwd = QDBusMessage::createMethodCall(
                    busName, objPath, QStringLiteral("org.freedesktop.Application"),
                    QStringLiteral("openUrl"));
                fwd.setArguments({ openUrl });
                bus.call(fwd, QDBus::Block);   // Block: il processo esce subito dopo
            }
            return 0;
        }
        qWarning("[rt] istanza fantasma (pid %d): la chiudo e parto io", (int)owner);
        killTree(owner);
        bool registered = false;
        for (int i = 0; i < 50 && !(registered = bus.registerService(busName)); ++i)
            QThread::msleep(100);   // il bus libera il nome appena muore il socket
        if (!registered) {
            qWarning("[rt] nome DBus ancora occupato dopo la chiusura del fantasma: esco");
            return 1;
        }
    }

    RtNotifier notifier(busName, objPath);
    g_notifier = &notifier;
    RtUnifiedPush unifiedPush;
    const bool pushReady = unifiedPush.start();
    QQmlApplicationEngine engine;
    // il QML accende il servizio Push del profilo SOLO se c'e' il ponte: con un
    // motore senza patch Chromium userebbe i server Google
    engine.rootContext()->setContextProperty(QStringLiteral("rtPushReady"), pushReady);
    engine.rootContext()->setContextProperty(QStringLiteral("rtPush"), &unifiedPush);
    engine.rootContext()->setContextProperty(QStringLiteral("rtWakeMode"), pushWake);
    QObject::connect(&unifiedPush, &RtUnifiedPush::activity, &app, []() {
        wakeTouch();
        g_wakePush = QDateTime::currentMSecsSinceEpoch();
    });
    // clients.openWindow() di un sito (tocco su una sua notifica): come un link
    QObject::connect(&unifiedPush, &RtUnifiedPush::openUrlRequested, &openHandler,
                     [&openHandler](const QString &url) { openHandler.openUrl(url); });
    NativeHelper native;
    engine.rootContext()->setContextProperty(QStringLiteral("rtNative"), &native);
    engine.rootContext()->setContextProperty(QStringLiteral("rtOpen"), &openHandler);
    engine.rootContext()->setContextProperty(QStringLiteral("rtOpenUrl"), openUrl);
    // Quale tastiera e' in uso: la sceglie il launcher (che sa se il plugin
    // maliit e' nel bundle e se il device ha maliit-server) e la comunica via
    // QT_IM_MODULE; il QML deve saperlo per NON istanziare anche l'InputPanel
    // di QtVirtualKeyboard, che altrimenti si affianca a quella di sistema.
    const bool useMaliit = (qgetenv("QT_IM_MODULE") == "maliit");
    engine.rootContext()->setContextProperty(QStringLiteral("rtMaliit"), useMaliit);
    native.setMaliitContainer(maliitContainer ? maliitContainer->adaptor() : nullptr);
    engine.load(QUrl::fromLocalFile(base + "/test.qml"));
    if (engine.rootObjects().isEmpty())
        return -1;
    // Il primo piano su un link lo chiede OpenHandler (RtWindowRaiser): lipstick
    // consegna l'URL via DBus (X-Maemo-* del .desktop) ma non porta avanti da
    // solo una finestra Qt6 in cover — misurato il 10 ott (task 2.5 #3).
    // La sveglia esce 3 s dopo la notifica della push (misurato 20 ott sul
    // POCO: ~200 MB di PSS, motore + renderer del service worker; tenerli 20 s
    // per niente era il lamento di un tester). Se la notifica non arriva vale
    // la regola di prima: almeno 20 s di vita e 10 s senza push ne' notifiche.
    // Mostrare la finestra spegne la sveglia per sempre (g_wakeHidden = latch:
    // in cover isVisible() torna false, misurato da RooTelegram). RooTelegram ha
    // misurato che quit() a finestra nascosta puo' restare appeso: paracadute.
    QTimer wakeExit;
    if (pushWake) {
        qInfo("[rtpush] avvio da sveglia: finestra nascosta");
        const qint64 born = QDateTime::currentMSecsSinceEpoch();
        // interruttore spento: la push si scarta, inutile restare 20 s
        const qint64 minLife = unifiedPush.isEnabled() ? 20000 : 2000;
        QObject::connect(&wakeExit, &QTimer::timeout, &app, [&wakeExit, born, minLife]() {
            bool shown = false;
            for (QWindow *w : QGuiApplication::allWindows())
                if (w->isVisible()) shown = true;
            if (shown || !g_wakeHidden) {
                g_wakeHidden = false;
                wakeExit.stop();
                qInfo("[rtpush] la sveglia ora e' l'app vera");
                return;
            }
            const qint64 now = QDateTime::currentMSecsSinceEpoch();
            const qint64 push = g_wakePush, notif = g_wakeNotif;
            const bool delivered = push > 0 && notif >= push && now - notif >= 3000;
            if (!delivered
                && (now - born < minLife || (minLife > 2000 && now - g_wakeActivity < 10000))) return;
            qInfo("[rtpush] sveglia %s dopo %lld ms: esco", delivered ? "consegnata" : "inattiva",
                  (long long)(now - born));
            wakeExit.stop();
            QTimer::singleShot(8000, []() { killTree(getpid()); _exit(0); });
            QCoreApplication::quit();
        });
        wakeExit.start(500);
    }
    const int rc = app.exec();
    // Esci dal menu' (task 2.5 #7): niente processi Chromium orfani dopo di noi
    killTree(getpid());
    return rc;
}

#include "main.moc"
