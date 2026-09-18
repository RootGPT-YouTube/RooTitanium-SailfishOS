// RooTitanium — decodifica video hardware su SailfishOS via droidmedia.
// Copyright (C) 2026 RootGPT. SPDX-License-Identifier: GPL-3.0-or-later
//
// Si inserisce in DefaultDecoderFactory::CreateVideoDecoders() PRIMA dei tre
// decoder software (libvpx / dav1d / ffmpeg): DecoderSelector li prova in
// ordine, quindi se il nostro Initialize() rifiuta si ripiega da solo sul
// software, senza che noi si debba scrivere nessuna logica di fallback.
//
// Sotto c'e' MediaCodec di Android, raggiunto via droidmedia, che a sua volta
// passa da libhybris. Vedi Documentation/TASK-decodifica-video.md.

#ifndef MEDIA_FILTERS_DROID_VIDEO_DECODER_H_
#define MEDIA_FILTERS_DROID_VIDEO_DECODER_H_

#include <atomic>
#include <memory>

#include "base/memory/ref_counted.h"
#include "base/memory/weak_ptr.h"
#include "base/synchronization/lock.h"
#include "base/task/sequenced_task_runner.h"
#include "media/base/media_export.h"
#include "media/base/video_decoder.h"
#include "media/base/video_decoder_config.h"

// Solo i tipi OPACHI di droidmedia sono forward-dichiarabili: il suo header
// li definisce come `typedef struct _DroidMediaCodec DroidMediaCodec;`.
// DroidMediaCodecData e DroidMediaData NO: sono `typedef struct { ... } X;`,
// cioe' struct ANONIME, che non hanno un nome da dichiarare in anticipo. Per
// quelle il tipo resta confinato nel .cc (errore preso al primo build, 17/09).
struct _DroidMediaCodec;

namespace media {

class MEDIA_EXPORT DroidVideoDecoder : public VideoDecoder {
 public:
  // 🔴 REQUISITO DI PORTABILITA'. Il shim hybris.c di droidmedia NON degrada:
  // __resolve_sym fa assert()+abort() e __load_library aborta se manca
  // libhybris o se libdroidmedia.so non si carica. Su un porting SFOS nativo
  // (senza HAL Android) la prima chiamata ammazzerebbe il browser invece di
  // ripiegare sul software. Quindi PRIMA di toccare qualunque funzione
  // droidmedia si passa da qui, che usa solo dlopen() normale e non aborta mai.
  // Il risultato e' calcolato una volta sola per processo.
  static bool PlatformSupported();

  DroidVideoDecoder();
  DroidVideoDecoder(const DroidVideoDecoder&) = delete;
  DroidVideoDecoder& operator=(const DroidVideoDecoder&) = delete;
  ~DroidVideoDecoder() override;

  // VideoDecoder
  void Initialize(const VideoDecoderConfig& config,
                  bool low_delay,
                  CdmContext* cdm_context,
                  InitCB init_cb,
                  const OutputCB& output_cb,
                  const WaitingCB& waiting_cb) override;
  void Decode(scoped_refptr<DecoderBuffer> buffer, DecodeCB decode_cb) override;
  void Reset(base::OnceClosure closure) override;
  bool NeedsBitstreamConversion() const override;
  bool CanReadWithoutStalling() const override;
  int GetMaxDecodeRequests() const override;
  VideoDecoderType GetDecoderType() const override;

 private:
  // ⭐ Ponte fra il thread del vendor e noi. I callback di droidmedia arrivano
  // su un thread suo, che non sa niente del ciclo di vita degli oggetti di
  // Chromium: senza questo, un fotogramma in volo puo' trovare il decoder gia'
  // distrutto. Il Ponte tiene un lock e un puntatore che azzeriamo PRIMA di
  // chiudere il codec, cosi' un callback o arriva mentre siamo vivi, o non
  // tocca niente. (Il fullscreen falliva proprio qui: la transizione distrugge
  // il decoder mentre sta decodificando — 18/09.)
  class Ponte : public base::RefCountedThreadSafe<Ponte> {
   public:
    explicit Ponte(DroidVideoDecoder* decoder) : decoder_(decoder) {}
    Ponte(const Ponte&) = delete;
    Ponte& operator=(const Ponte&) = delete;

    // Da chiamare sulla sequence del decoder, PRIMA di fermare il codec: se un
    // callback e' dentro, aspetta che finisca; quelli dopo non faranno nulla.
    void Scollega() {
      base::AutoLock lock(lock_);
      decoder_ = nullptr;
    }

    template <typename F>
    void Con(F funzione) {
      base::AutoLock lock(lock_);
      if (decoder_) {
        funzione(decoder_);
      }
    }

   private:
    friend class base::RefCountedThreadSafe<Ponte>;
    ~Ponte() = default;
    base::Lock lock_;
    DroidVideoDecoder* decoder_ GUARDED_BY(lock_);
  };

  // ⚠️ NIENTE thread del loop, ed e' deliberato: senza il flag
  // USE_EXTERNAL_LOOP droidmedia avvia GIA' un thread suo che chiama
  // droid_media_codec_loop(). Farne partire un secondo nostro voleva dire due
  // consumatori sullo stesso codec, e il renderer moriva in silenzio (18/09).
  // gmp-droid, per la stessa ragione, non ha nessun loop proprio.
  void Teardown();

  // Crea, configura e avvia il codec del vendor secondo `config`. Sta a parte
  // perche' serve in due punti: alla prima inizializzazione e alla ripartenza
  // dopo un drain, dove ricreare il codec e' l'UNICO modo di farlo tornare vivo.
  bool AvviaCodec(const VideoDecoderConfig& config);

  // Chiamate DAL thread del loop: rimbalzano sulla sequence del chiamante.
  // `encoded` e' un DroidMediaCodecData*, ma quel tipo non si puo' nominare
  // qui (vedi sopra) e non vogliamo l'header droidmedia dentro un header di
  // media/: in build jumbo finirebbe fuso con mezzo media/renderers. Il
  // callback C vero e' una lambda senza cattura dentro Initialize(), che si
  // converte nel puntatore a funzione con la firma esatta e ci passa questo.
  static void OnDataAvailable(void* data, void* encoded);
  static void OnSignalEos(void* data);
  static void OnError(void* data, int err);
  static int OnSizeChanged(void* data, int32_t width, int32_t height);

  void DeliverFrameOnSequence(scoped_refptr<VideoFrame> frame);

  // Traduce il codec di Chromium nel MIME Android ("video/avc",
  // "video/x-vnd.on2.vp9", ...). Stringa vuota = codec che non proviamo.
  static const char* AndroidMimeForCodec(VideoCodec codec);

  scoped_refptr<base::SequencedTaskRunner> task_runner_;
  _DroidMediaCodec* codec_ = nullptr;

  // Si alza quando il vendor segnala un errore o quando il codec ci consegna un
  // formato di pixel che non sappiamo convertire. Da quel momento ogni Decode()
  // fallisce, cosi' la pipeline puo' ripiegare sul software invece di restare
  // ferma su un video che non parte (incidente del 18/09). Lo scrive il thread
  // del loop di droidmedia e lo legge la sequence di Chromium: atomico.
  std::atomic<bool> broken_{false};

  // Quanti fotogrammi abbiamo davvero consegnato: serve a leggere il ciclo di
  // vita nei log (quando si blocca, e dopo quanti frame).
  std::atomic<int> consegnati_{0};

  // Abbiamo mandato un end-of-stream al codec: da quel momento e' esaurito e il
  // prossimo Reset deve ricrearlo, non limitarsi al flush.
  std::atomic<bool> drained_{false};

  VideoDecoderConfig config_;
  OutputCB output_cb_;
  bool needs_bitstream_conversion_ = false;

  // Protegge le dimensioni, che il decoder puo' cambiare a meta' flusso
  // (size_changed arriva dal thread del loop).
  base::Lock size_lock_;
  gfx::Size coded_size_;

  scoped_refptr<Ponte> ponte_;

  // ⚠️ Preso UNA VOLTA sulla sequence di Chromium, in Initialize: chiamare
  // GetWeakPtr() dal thread del vendor non e' lecito, e finora lo facevamo.
  base::WeakPtr<DroidVideoDecoder> weak_self_;

  base::WeakPtrFactory<DroidVideoDecoder> weak_factory_{this};
};

}  // namespace media

#endif  // MEDIA_FILTERS_DROID_VIDEO_DECODER_H_
