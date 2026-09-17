// RooTitanium — decodifica video hardware su SailfishOS via droidmedia.
// Copyright (C) 2026 RootGPT. SPDX-License-Identifier: GPL-3.0-or-later

#include "media/filters/droid_video_decoder.h"

#include <dlfcn.h>

#include "base/functional/bind.h"
#include "base/logging.h"
#include "base/task/bind_post_task.h"
#include "media/base/decoder_buffer.h"
#include "media/base/decoder_status.h"
#include "media/base/limits.h"
#include "media/base/video_frame.h"
#include "media/base/video_util.h"

extern "C" {
#include "droidmedia.h"
#include "droidmediaconvert.h"
#include "droidmediacodec.h"
}

namespace media {

namespace {

// Percorso della libreria ANDROID, non di una .so glibc: si carica solo con il
// linker di libhybris. Sta nel namespace hybris di ogni porting con droid-hal.
constexpr char kHybrisCommon[] = "libhybris-common.so.1";
constexpr char kDroidMedia[] = "libdroidmedia.so";

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
        "droid_media_convert_create", "droid_media_convert_destroy",
        "droid_media_convert_to_i420",
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
  data_cb.data_available = &DroidVideoDecoder::OnDataAvailable;
  droid_media_codec_set_data_callbacks(codec_, &data_cb, this);

  if (!droid_media_codec_start(codec_)) {
    Teardown();
    fail(DecoderStatus::Codes::kFailedToCreateDecoder);
    return;
  }

  convert_ = droid_media_convert_create();
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
  if (convert_) {
    droid_media_convert_destroy(convert_);
    convert_ = nullptr;
  }
}

void DroidVideoDecoder::Decode(scoped_refptr<DecoderBuffer> buffer,
                               DecodeCB decode_cb) {
  if (!codec_) {
    std::move(decode_cb).Run(DecoderStatus::Codes::kFailed);
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
void DroidVideoDecoder::OnDataAvailable(void* data,
                                        _DroidMediaCodecData* encoded) {
  auto* self = static_cast<DroidVideoDecoder*>(data);
  if (!self || !self->convert_ || !encoded) {
    return;
  }

  DroidMediaCodecMetaData info;
  DroidMediaRect crop;
  memset(&info, 0, sizeof(info));
  memset(&crop, 0, sizeof(crop));
  droid_media_codec_get_output_info(self->codec_, &info, &crop);
  droid_media_convert_set_crop_rect(self->convert_, crop, info.width, info.height);

  const gfx::Size visible(crop.right - crop.left, crop.bottom - crop.top);
  if (visible.IsEmpty()) {
    return;
  }

  // ⚠️ UNA COPIA DI TROPPO, e lo sappiamo: convert_to_i420 scrive un I420
  // contiguo, mentre i piani di VideoFrame possono avere allineamenti loro.
  // Per il primo giro passiamo da un buffer temporaneo; se il profilo dira'
  // che pesa, si alloca la VideoFrame con stride compatibili e si converte
  // direttamente dentro. Nemmeno gmp-droid di Gecko e' zero-copy, quindi
  // partiamo alla pari e semmai miglioriamo dopo.
  const size_t y = static_cast<size_t>(visible.width()) * visible.height();
  const size_t uv = ((visible.width() + 1) / 2) * ((visible.height() + 1) / 2);
  std::vector<uint8_t> i420(y + 2 * uv);
  if (!droid_media_convert_to_i420(self->convert_, &encoded->data, i420.data())) {
    return;
  }

  scoped_refptr<VideoFrame> frame = VideoFrame::CreateFrame(
      PIXEL_FORMAT_I420, visible, gfx::Rect(visible), visible,
      base::Microseconds(encoded->ts));
  if (!frame) {
    return;
  }
  const uint8_t* src_y = i420.data();
  const uint8_t* src_u = src_y + y;
  const uint8_t* src_v = src_u + uv;
  const int half_w = (visible.width() + 1) / 2;
  const int half_h = (visible.height() + 1) / 2;
  for (int r = 0; r < visible.height(); ++r) {
    memcpy(frame->writable_data(VideoFrame::kYPlane) +
               r * frame->stride(VideoFrame::kYPlane),
           src_y + r * visible.width(), visible.width());
  }
  for (int r = 0; r < half_h; ++r) {
    memcpy(frame->writable_data(VideoFrame::kUPlane) +
               r * frame->stride(VideoFrame::kUPlane),
           src_u + r * half_w, half_w);
    memcpy(frame->writable_data(VideoFrame::kVPlane) +
               r * frame->stride(VideoFrame::kVPlane),
           src_v + r * half_w, half_w);
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
  // ⚠️ DA COMPLETARE: qui va segnalato l'errore alla pipeline e, meglio
  // ancora, chiesto un ripiego sul software per il resto della sessione.
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
