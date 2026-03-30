#ifndef OPENMEOW_BRIDGING_HEADER_H_
#define OPENMEOW_BRIDGING_HEADER_H_

#if __has_include("sherpa-onnx/c-api/c-api.h")
#include "sherpa-onnx/c-api/c-api.h"
#define SHERPA_ONNX_AVAILABLE 1
#endif

#if __has_include("opus/opus.h")
#include "opus/opus.h"
#define OPUS_AVAILABLE 1

// Non-variadic wrappers for opus_encoder_ctl (Swift can't call variadic C functions)
static inline int opus_encoder_set_bitrate(OpusEncoder *enc, opus_int32 bitrate) {
    return opus_encoder_ctl(enc, OPUS_SET_BITRATE(bitrate));
}
static inline int opus_encoder_get_lookahead(OpusEncoder *enc, opus_int32 *lookahead) {
    return opus_encoder_ctl(enc, OPUS_GET_LOOKAHEAD(lookahead));
}

// Non-variadic wrapper for opus_decoder_ctl (RFC 7845 output gain)
static inline int opus_decoder_set_gain(OpusDecoder *dec, opus_int32 gain) {
    return opus_decoder_ctl(dec, OPUS_SET_GAIN(gain));
}
#endif

#if __has_include("ogg/ogg.h")
#include "ogg/ogg.h"
#endif

#if __has_include("lame/lame.h")
#include "lame/lame.h"
#define LAME_AVAILABLE 1
#endif

#endif
