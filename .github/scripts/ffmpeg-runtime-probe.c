#include <stdio.h>

#include <libavutil/avutil.h>

int main(void)
{
    const char *version = av_version_info();
    const char *license = avutil_license();
    const char *configuration = avutil_configuration();

    printf("version=%s\n", version ? version : "");
    printf("license=%s\n", license ? license : "");
    printf("configuration=%s\n", configuration ? configuration : "");

    return 0;
}
