#include <stdio.h>

#include <libavcodec/avcodec.h>
#include <libavutil/avutil.h>

static int print_decoder_status(const char *name)
{
    const AVCodec *decoder = avcodec_find_decoder_by_name(name);
    printf("decoder.%s=%s\n", name, decoder ? "present" : "missing");
    return decoder ? 0 : 1;
}

int main(void)
{
    const char *version = av_version_info();
    const char *license = avutil_license();
    const char *configuration = avutil_configuration();
    int missing_decoders = 0;

    printf("version=%s\n", version ? version : "");
    printf("license=%s\n", license ? license : "");
    printf("configuration=%s\n", configuration ? configuration : "");

    missing_decoders += print_decoder_status("av1");
    missing_decoders += print_decoder_status("libdav1d");

    return missing_decoders == 0 ? 0 : 1;
}
