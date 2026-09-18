// RooTitanium — decodifica video hardware su SailfishOS via droidmedia.
// Copyright (C) 2026 RootGPT. SPDX-License-Identifier: GPL-3.0-or-later

#include "media/filters/droid_video_decoder.h"

#include <dlfcn.h>

#include <algorithm>
#include <iterator>

#include "base/functional/bind.h"
#include "base/logging.h"
#include "base/task/bind_post_task.h"
#include "media/base/decoder_buffer.h"
#include "media/base/decoder_status.h"
#include "media/base/limits.h"
#include "media/base/video_frame.h"
#include "media/base/video_util.h"
#include "third_party/libyuv/include/libyuv.h"

extern "C" {
#include "droidmedia.h"
#include "droidmediacodec.h"
#include "droidmediaconstants.h"
}

namespace media {

namespace {

// Percorso della libreria ANDROID, non di una .so glibc: si carica solo con il
// linker di libhybris. Sta nel namespace hybris di ogni porting con droid-hal.
constexpr char kHybrisCommon[] = "libhybris-common.so.1";
constexpr char kDroidMedia[] = "libdroidmedia.so";

// L'unico valore OMX che siamo costretti a cablare: droidmedia non lo espone
// tra le sue costanti, ma e' standard AOSP e diversi vendor lo usano.
constexpr int kOmxYuv420PackedSemiPlanar = 0x27;

// ⭐ I numeri dei color format NON si cablano: cambiano tra vendor e versioni
// della HAL. Droidmedia li fa dire al device, ed e' l'unica fonte che non
// mente. Si interroga una volta per processo, e solo DOPO che
// PlatformSupported() ha dato l'ok (prima nessuna chiamata droidmedia e' lecita).
const DroidMediaColourFormatConstants& ColourConstants() {
  static const DroidMediaColourFormatConstants c = [] {
    DroidMediaColourFormatConstants tmp;
    memset(&tmp, 0, sizeof(tmp));
    droid_media_colour_format_constants_init(&tmp);
    return tmp;
  }();
  return c;
}

// Il campo che leggiamo si chiama hal_format e, a seconda del vendor, porta un
// OMX_COLOR_* oppure un HAL_PIXEL_FORMAT_*. Interroghiamo quindi anche questa
// seconda tabella: due dei suoi formati hanno i piani in ordine INVERTITO
// (NV21 = VU invece di UV, YV12 = V prima di U) e scambiarli darebbe un video
// con i colori ribaltati, non un errore visibile nei log.
const DroidMediaPixelFormatConstants& PixelConstants() {
  static const DroidMediaPixelFormatConstants c = [] {
    DroidMediaPixelFormatConstants tmp;
    memset(&tmp, 0, sizeof(tmp));
    droid_media_pixel_format_constants_init(&tmp);
    return tmp;
  }();
  return c;
}

// Come sono disposti in memoria i piani che il codec ci consegna.
enum class PlaneLayout {
  kUnsupported,  // formati tiled/proprietari: libyuv non li sa leggere
  kSemiPlanar,   // NV12: Y poi UV interlacciati
  kSemiPlanarVU, // NV21: come sopra ma V e U scambiati
  kPlanar,       // I420: Y poi U poi V
  kPlanarVU,     // YV12: Y poi V poi U
};

PlaneLayout LayoutFor(int color_format) {
  const DroidMediaColourFormatConstants& c = ColourConstants();
  // Il confronto con 0 va escluso: un campo che droidmedia non ha risolto resta
  // a zero, e senza questa guardia un color_format 0 combacerebbe con tutti.
  auto is = [color_format](int known) {
    return known != 0 && color_format == known;
  };
  if (is(c.OMX_COLOR_FormatYUV420SemiPlanar) ||
      is(c.QOMX_COLOR_FormatYUV420PackedSemiPlanar32m) ||
      color_format == kOmxYuv420PackedSemiPlanar) {
    return PlaneLayout::kSemiPlanar;
  }
  if (is(c.OMX_COLOR_FormatYUV420Planar) ||
      is(c.OMX_COLOR_FormatYUV420PackedPlanar)) {
    return PlaneLayout::kPlanar;
  }
  const DroidMediaPixelFormatConstants& p = PixelConstants();
  auto is_hal = [color_format](int known) {
    return known != 0 && color_format == known;
  };
  if (is_hal(p.HAL_PIXEL_FORMAT_YCrCb_420_SP)) {
    return PlaneLayout::kSemiPlanarVU;
  }
  if (is_hal(p.HAL_PIXEL_FORMAT_YV12)) {
    return PlaneLayout::kPlanarVU;
  }
  // Qui finiscono i tile proprietari (il 64x32Tile2m8ka di Qualcomm, i formati
  // MediaTek): libyuv non li tratta e un de-tiling scritto a mano sarebbe
  // codice non verificabile su hardware che non abbiamo. Meglio dire di no.
  return PlaneLayout::kUnsupported;
}

}  // namespace

// static
bool DroidVideoDecoder::PlatformSupported() {
  // Calcolata una volta per processo: se qui rispondiamo "no", nessuno tocchera'
  // mai una funzione droidmedia, e quindi il shim non potra' mai abortire.
  static const bool supported = [] {
    // Passo 1: libhybris c'e'? Su un porting nativo (senza HAL Android) no.
    void* hybris = dlopen(kHybrisCommon, RTLD_LAZY);
    if (!hybris) {
      DVLOG(1) << "droidmedia: " << kHybrisCommon << " assente, resto in software";
      return false;
    }
    // Passo 2: espone il linker Android?
    using AndroidDlopen = void* (*)(const char*, int);
    using AndroidDlsym = void* (*)(void*, const char*);
    auto android_dlopen =
        reinterpret_cast<AndroidDlopen>(dlsym(hybris, "android_dlopen"));
    auto android_dlsym =
        reinterpret_cast<AndroidDlsym>(dlsym(hybris, "android_dlsym"));
    if (!android_dlopen || !android_dlsym) {
      DVLOG(1) << "droidmedia: libhybris senza android_dlopen/dlsym";
      return false;
    }
    // Passo 3: la libreria Android si carica davvero?
    void* handle = android_dlopen(kDroidMedia, RTLD_NOW);
    if (!handle) {
      DVLOG(1) << "droidmedia: " << kDroidMedia << " non caricabile";
      return false;
    }
    // Passo 4: i simboli che useremo esistono in QUESTA versione di droidmedia.
    // I porting vecchi possono averne di meno, e il shim aborterebbe.
    static constexpr const char* kNeeded[] = {
        "droid_media_codec_is_supported", "droid_media_codec_create_decoder",
        "droid_media_codec_set_data_callbacks", "droid_media_codec_set_callbacks",
        "droid_media_codec_start", "droid_media_codec_stop",
        "droid_media_codec_destroy", "droid_media_codec_queue",
        "droid_media_codec_flush", "droid_media_codec_drain",
        "droid_media_codec_loop", "droid_media_codec_get_output_info",
        "droid_media_colour_format_constants_init",
        "droid_media_pixel_format_constants_init",
        "droid_media_codec_get_supported_color_formats",
    };
    for (const char* sym : kNeeded) {
      if (!android_dlsym(handle, sym)) {
        DVLOG(1) << "droidmedia: manca il simbolo " << sym << ", resto in software";
        return false;
      }
    }
    return true;
  }();
  return supported;
}

// static
const char* DroidVideoDecoder::AndroidMimeForCodec(VideoCodec codec) {
  switch (codec) {
    case VideoCodec::kH264:
      return "video/avc";
    case VideoCodec::kHEVC:
      return "video/hevc";
    case VideoCodec::kVP8:
      return "video/x-vnd.on2.vp8";
    case VideoCodec::kVP9:
      return "video/x-vnd.on2.vp9";
    case VideoCodec::kAV1:
      // Volutamente NON provato: sui device dove l'AV1 hardware non c'e'
      // (il POCO M4 Pro per esempio) is_supported risponderebbe no comunque,
      // e dove c'e' va verificato prima di prometterlo.
      return "";
    default:
      return "";
  }
}

DroidVideoDecoder::DroidVideoDecoder() = default;

DroidVideoDecoder::~DroidVideoDecoder() {
  Teardown();
}

VideoDecoderType DroidVideoDecoder::GetDecoderType() const {
  // Sotto c'e' davvero MediaCodec di Android: riusiamo il tipo esistente invece
  // di aggiungerne uno nuovo, cosi' non si tocca l'enum ne' gli istogrammi UKM.
  return VideoDecoderType::kMediaCodec;
}

bool DroidVideoDecoder::NeedsBitstreamConversion() const {
  // H.264/HEVC arrivano in formato AVCC dal demuxer MP4; MediaCodec vuole i
  // NAL in Annex-B. Chromium fa la conversione per noi se rispondiamo true.
  return needs_bitstream_conversion_;
}

bool DroidVideoDecoder::CanReadWithoutStalling() const {
  return true;
}

int DroidVideoDecoder::GetMaxDecodeRequests() const {
  // MediaCodec e' a pipeline: tenerlo alimentato serve, ma senza esagerare
  // perche' ogni buffer in volo e' memoria del vendor.
  return 4;
}

void DroidVideoDecoder::Initialize(const VideoDecoderConfig& config,
                                   bool low_delay,
                                   CdmContext* cdm_context,
                                   InitCB init_cb,
                                   const OutputCB& output_cb,
                                   const WaitingCB& waiting_cb) {
  task_runner_ = base::SequencedTaskRunner::GetCurrentDefault();

  auto fail = [&init_cb](DecoderStatus status) {
    // Rifiuto pulito: DecoderSelector passera' al decoder successivo, cioe' al
    // software. E' il nostro unico modo di degradare, e va usato sempre.
    std::move(init_cb).Run(status);
  };

  if (config.is_encrypted() || cdm_context) {
    fail(DecoderStatus::Codes::kUnsupportedEncryptionMode);
    return;
  }
  if (!PlatformSupported()) {
    fail(DecoderStatus::Codes::kUnsupportedConfig);
    return;
  }
  const char* mime = AndroidMimeForCodec(config.codec());
  if (!mime || !*mime) {
    fail(DecoderStatus::Codes::kUnsupportedCodec);
    return;
  }

  Teardown();  // reinizializzazione a caldo: MediaCodec non si riconfigura.

  DroidMediaCodecDecoderMetaData meta;
  memset(&meta, 0, sizeof(meta));
  meta.parent.type = mime;
  meta.parent.width = config.coded_size().width();
  meta.parent.height = config.coded_size().height();
  meta.parent.fps = 30;  // indicativo: il vendor lo usa solo per dimensionare
  meta.parent.flags = static_cast<DroidMediaCodecFlags>(
      DROID_MEDIA_CODEC_HW_ONLY | DROID_MEDIA_CODEC_NO_MEDIA_BUFFER);

  // extra_data = SPS/PPS per H.264, codec-private per VP9.
  if (!config.extra_data().empty()) {
    meta.codec_data.size = config.extra_data().size();
    meta.codec_data.data = const_cast<uint8_t*>(config.extra_data().data());
  }

  // ⭐ Il rifiuto che rende la cosa portabile: e' il DEVICE a dire se sa fare
  // questo codec. Niente elenchi cablati da noi.
  if (!droid_media_codec_is_supported(&meta.parent, /*encoder=*/false)) {
    fail(DecoderStatus::Codes::kUnsupportedConfig);
    return;
  }

  // ⭐ Rifiuto ANTICIPATO: chiediamo al device quali formati di uscita sa
  // produrre questo decoder e, se non ce n'e' nemmeno uno che sappiamo
  // convertire, ci togliamo di mezzo subito. Cosi' DecoderSelector scende sul
  // software prima ancora che il codec esista, invece di scoprirlo al primo
  // frame con un video gia' fermo (e' la lezione del 18/09). Se la lista
  // arrivasse vuota non concludiamo niente: decidera' il primo frame.
  uint32_t formats[32];
  const unsigned int n = droid_media_codec_get_supported_color_formats(
      &meta.parent, /*encoder=*/0, formats, std::size(formats));
  if (n > 0) {
    bool uno_buono = false;
    for (unsigned int i = 0; i < n && !uno_buono; ++i) {
      uno_buono = LayoutFor(static_cast<int>(formats[i])) != PlaneLayout::kUnsupported;
    }
    if (!uno_buono) {
      LOG(WARNING) << "droidmedia: nessuno dei " << n
                   << " formati di uscita e' convertibile, resto in software";
      fail(DecoderStatus::Codes::kUnsupportedConfig);
      return;
    }
  }

  codec_ = droid_media_codec_create_decoder(&meta);
  if (!codec_) {
    fail(DecoderStatus::Codes::kFailedToCreateDecoder);
    return;
  }

  DroidMediaCodecCallbacks cb;
  memset(&cb, 0, sizeof(cb));
  cb.signal_eos = &DroidVideoDecoder::OnSignalEos;
  cb.error = &DroidVideoDecoder::OnError;
  cb.size_changed = &DroidVideoDecoder::OnSizeChanged;
  droid_media_codec_set_callbacks(codec_, &cb, this);

  DroidMediaCodecDataCallbacks data_cb;
  memset(&data_cb, 0, sizeof(data_cb));
  // Lambda senza cattura: si converte nel puntatore a funzione con la firma
  // esatta che droidmedia pretende, e siccome e' scritta dentro un metodo
  // membro puo' chiamare il nostro statico privato.
  data_cb.data_available = [](void* user, DroidMediaCodecData* encoded) {
    DroidVideoDecoder::OnDataAvailable(user, encoded);
  };
  droid_media_codec_set_data_callbacks(codec_, &data_cb, this);

  if (!droid_media_codec_start(codec_)) {
    Teardown();
    fail(DecoderStatus::Codes::kFailedToCreateDecoder);
    return;
  }

  broken_.store(false, std::memory_order_relaxed);
  config_ = config;
  output_cb_ = output_cb;
  needs_bitstream_conversion_ =
      (config.codec() == VideoCodec::kH264 || config.codec() == VideoCodec::kHEVC);
  {
    base::AutoLock lock(size_lock_);
    coded_size_ = config.coded_size();
  }

  loop_thread_ = std::make_unique<base::Thread>("DroidMediaCodecLoop");
  loop_thread_->Start();
  loop_thread_->task_runner()->PostTask(
      FROM_HERE, base::BindOnce(&DroidVideoDecoder::LoopThreadMain,
                                base::Unretained(this)));

  std::move(init_cb).Run(DecoderStatus::Codes::kOk);
}

void DroidVideoDecoder::LoopThreadMain() {
  // droid_media_codec_loop() blocca finche' non ha lavoro: percio' sta su un
  // thread dedicato e non su una sequence di Chromium.
  while (codec_ &&
         droid_media_codec_loop(codec_) == DROID_MEDIA_CODEC_LOOP_OK) {
  }
}

void DroidVideoDecoder::Teardown() {
  if (loop_thread_) {
    loop_thread_->Stop();
    loop_thread_.reset();
  }
  if (codec_) {
    droid_media_codec_stop(codec_);
    droid_media_codec_destroy(codec_);
    codec_ = nullptr;
  }
}

void DroidVideoDecoder::Decode(scoped_refptr<DecoderBuffer> buffer,
                               DecodeCB decode_cb) {
  if (!codec_) {
    std::move(decode_cb).Run(DecoderStatus::Codes::kFailed);
    return;
  }
  // Il vendor ha segnalato un errore, o ci ha consegnato un formato che non
  // sappiamo convertire. Dichiararlo QUI e' cio' che permette alla pipeline di
  // scendere sul decoder software: se tacessimo, il video resterebbe fermo per
  // sempre su un decoder che non produce un fotogramma (incidente del 18/09).
  if (broken_.load(std::memory_order_relaxed)) {
    std::move(decode_cb).Run(DecoderStatus::Codes::kPlatformDecodeFailure);
    return;
  }

  if (buffer->end_of_stream()) {
    // drain() fa uscire dal decoder i frame ancora dentro: arriveranno per la
    // solita strada (data_available), e signal_eos chiudera' il giro.
    droid_media_codec_drain(codec_);
    std::move(decode_cb).Run(DecoderStatus::Codes::kOk);
    return;
  }

  DroidMediaCodecData data;
  memset(&data, 0, sizeof(data));
  data.data.size = buffer->data_size();
  data.data.data = const_cast<uint8_t*>(buffer->data());
  // droidmedia lavora in microsecondi come Chromium: nessuna conversione.
  data.ts = buffer->timestamp().InMicroseconds();
  data.decoding_ts = data.ts;
  data.sync = buffer->is_key_frame();

  // ⚠️ DA IRROBUSTIRE: il vendor puo' tenersi il buffer oltre la queue(), quindi
  // la memoria di `buffer` deve sopravvivere finche' non lo rilascia. Qui ci
  // appoggiamo alla copia che fa MediaCodec con NO_MEDIA_BUFFER; se il collaudo
  // mostrasse corruzione, va usato DroidMediaBufferCallbacks per tenere il ref
  // al DecoderBuffer e rilasciarlo nella unref.
  droid_media_codec_queue(codec_, &data, nullptr);
  std::move(decode_cb).Run(DecoderStatus::Codes::kOk);
}

void DroidVideoDecoder::Reset(base::OnceClosure closure) {
  if (codec_) {
    droid_media_codec_flush(codec_);
  }
  std::move(closure).Run();
}

// static — ATTENZIONE: gira sul thread del loop di droidmedia, non su una
// sequence di Chromium. Tutto quello che tocca Chromium va rimbalzato.
void DroidVideoDecoder::OnDataAvailable(void* data, void* encoded_raw) {
  auto* self = static_cast<DroidVideoDecoder*>(data);
  auto* encoded = static_cast<DroidMediaCodecData*>(encoded_raw);
  if (!self || !encoded || !encoded->data.data || encoded->data.size <= 0) {
    return;
  }

  DroidMediaCodecMetaData info;
  DroidMediaRect crop;
  memset(&info, 0, sizeof(info));
  memset(&crop, 0, sizeof(crop));
  droid_media_codec_get_output_info(self->codec_, &info, &crop);

  // info.width/height sono le dimensioni del BUFFER (gia' allineate dal
  // vendor): valgono quindi da stride e da altezza di slice. crop e' la parte
  // davvero visibile, che e' cio' che consegniamo a Chromium.
  const int stride = static_cast<int>(info.width);
  const int slice_height = static_cast<int>(info.height);
  const gfx::Size visible(crop.right - crop.left, crop.bottom - crop.top);
  if (stride <= 0 || slice_height <= 0 || visible.IsEmpty()) {
    return;
  }

  // Una riga sola, al primo frame: e' l'unico modo di sapere che cosa emette
  // davvero il decoder di QUESTO vendor. Senza il numero, diagnosticare da
  // remoto un device che non abbiamo in mano e' impossibile.
  static std::atomic<bool> gia_detto{false};
  if (!gia_detto.exchange(true)) {
    LOG(INFO) << "droidmedia: primo frame — hal_format=" << info.hal_format
              << " buffer=" << info.width << "x" << info.height
              << " crop=(" << crop.left << "," << crop.top << ")-(" << crop.right
              << "," << crop.bottom << ")";
  }

  const PlaneLayout layout = LayoutFor(info.hal_format);
  if (layout == PlaneLayout::kUnsupported) {
    // Una volta sola, ma col NUMERO: senza quello, su un device che non
    // abbiamo in mano non si puo' capire quale formato ci abbia mandato.
    LOG(ERROR) << "droidmedia: color format " << info.hal_format
               << " non convertibile con libyuv, ripiego sul software";
    self->broken_.store(true, std::memory_order_relaxed);
    return;
  }

  // Il vendor deve averci dato almeno un 4:2:0 intero: senza questo controllo
  // un buffer corto ci farebbe leggere fuori dalla sua memoria.
  const size_t attesa =
      static_cast<size_t>(stride) * slice_height * 3 / 2;
  if (static_cast<size_t>(encoded->data.size) < attesa) {
    LOG(ERROR) << "droidmedia: buffer di " << encoded->data.size
               << " byte, ne servono " << attesa << ": lo scarto";
    self->broken_.store(true, std::memory_order_relaxed);
    return;
  }

  scoped_refptr<VideoFrame> frame = VideoFrame::CreateFrame(
      PIXEL_FORMAT_I420, visible, gfx::Rect(visible), visible,
      base::Microseconds(encoded->ts));
  if (!frame) {
    return;
  }

  // ⭐ Niente buffer intermedio: libyuv scrive direttamente nei piani della
  // VideoFrame, con i loro stride. La "copia di troppo" che ci portavamo
  // dietro con droid_media_convert_to_i420 sparisce insieme alla dipendenza
  // dal vendor (libI420colorconvert.so), che su molti device non esiste.
  const auto* base_ptr = static_cast<const uint8_t*>(encoded->data.data);
  const uint8_t* src_y = base_ptr + crop.top * stride + crop.left;
  const uint8_t* chroma = base_ptr + static_cast<size_t>(stride) * slice_height;
  int rc = -1;

  if (layout == PlaneLayout::kSemiPlanar ||
      layout == PlaneLayout::kSemiPlanarVU) {
    // NV12: il piano UV e' interlacciato e ha meta' altezza. L'offset
    // orizzontale va portato a pari, altrimenti si scambiano U e V.
    const uint8_t* src_uv =
        chroma + (crop.top / 2) * stride + (crop.left & ~1);
    // NV21 differisce da NV12 solo per l'ordine dei due campioni di crominanza:
    // libyuv ha la funzione gemella, e usare quella giusta evita un video coi
    // colori invertiti che nessun log segnalerebbe.
    auto converti = (layout == PlaneLayout::kSemiPlanar) ? &libyuv::NV12ToI420
                                                         : &libyuv::NV21ToI420;
    rc = converti(
        src_y, stride, src_uv, stride,
        frame->writable_data(VideoFrame::kYPlane),
        frame->stride(VideoFrame::kYPlane),
        frame->writable_data(VideoFrame::kUPlane),
        frame->stride(VideoFrame::kUPlane),
        frame->writable_data(VideoFrame::kVPlane),
        frame->stride(VideoFrame::kVPlane),
        visible.width(), visible.height());
  } else {
    // I420 planare: U e V pieni, ciascuno con stride e altezza dimezzati.
    const int c_stride = stride / 2;
    const size_t piano_c = static_cast<size_t>(c_stride) * (slice_height / 2);
    const uint8_t* src_u =
        chroma + (crop.top / 2) * c_stride + crop.left / 2;
    const uint8_t* src_v = src_u + piano_c;
    // YV12 e' I420 con i due piani scambiati: si tratta passandoli al contrario.
    if (layout == PlaneLayout::kPlanarVU) {
      std::swap(src_u, src_v);
    }
    rc = libyuv::I420Copy(
        src_y, stride, src_u, c_stride, src_v, c_stride,
        frame->writable_data(VideoFrame::kYPlane),
        frame->stride(VideoFrame::kYPlane),
        frame->writable_data(VideoFrame::kUPlane),
        frame->stride(VideoFrame::kUPlane),
        frame->writable_data(VideoFrame::kVPlane),
        frame->stride(VideoFrame::kVPlane),
        visible.width(), visible.height());
  }

  if (rc != 0) {
    LOG(ERROR) << "droidmedia: conversione libyuv fallita (" << rc << ")";
    self->broken_.store(true, std::memory_order_relaxed);
    return;
  }

  self->task_runner_->PostTask(
      FROM_HERE, base::BindOnce(&DroidVideoDecoder::DeliverFrameOnSequence,
                                self->weak_factory_.GetWeakPtr(),
                                std::move(frame)));
}

void DroidVideoDecoder::DeliverFrameOnSequence(scoped_refptr<VideoFrame> frame) {
  if (output_cb_) {
    output_cb_.Run(std::move(frame));
  }
}

// static
void DroidVideoDecoder::OnSignalEos(void* data) {
  // Il flusso e' finito: non c'e' niente da consegnare, i frame sono gia'
  // passati da data_available.
}

// static
void DroidVideoDecoder::OnError(void* data, int err) {
  LOG(ERROR) << "droidmedia: errore del decoder vendor: " << err;
  // Gira sul thread del loop di droidmedia: si alza solo il flag, senza toccare
  // niente di Chromium. Il prossimo Decode() lo legge e fallisce, e la pipeline
  // ripiega sul software.
  if (auto* self = static_cast<DroidVideoDecoder*>(data)) {
    self->broken_.store(true, std::memory_order_relaxed);
  }
}

// static
int DroidVideoDecoder::OnSizeChanged(void* data, int32_t width, int32_t height) {
  auto* self = static_cast<DroidVideoDecoder*>(data);
  if (self) {
    base::AutoLock lock(self->size_lock_);
    self->coded_size_ = gfx::Size(width, height);
  }
  return 0;
}

}  // namespace media
