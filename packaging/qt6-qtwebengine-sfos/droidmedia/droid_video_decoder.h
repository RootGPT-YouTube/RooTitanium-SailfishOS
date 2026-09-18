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

#include "base/memory/weak_ptr.h"
#include "base/synchronization/lock.h"
#include "base/task/sequenced_task_runner.h"
#include "base/threading/thread.h"
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
  // Il ciclo di droidmedia gira su un thread suo: droid_media_codec_loop()
  // blocca finche' non c'e' lavoro, quindi non puo' stare su una sequence di
  // Chromium.
  void LoopThreadMain();
  void Teardown();

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
  std::unique_ptr<base::Thread> loop_thread_;

  VideoDecoderConfig config_;
  OutputCB output_cb_;
  bool needs_bitstream_conversion_ = false;

  // Protegge le dimensioni, che il decoder puo' cambiare a meta' flusso
  // (size_changed arriva dal thread del loop).
  base::Lock size_lock_;
  gfx::Size coded_size_;

  base::WeakPtrFactory<DroidVideoDecoder> weak_factory_{this};
};

}  // namespace media

#endif  // MEDIA_FILTERS_DROID_VIDEO_DECODER_H_
