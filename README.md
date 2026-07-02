# WebMiere FFmpeg

This repository contains the repeatable pinned-source FFmpeg build factory used to produce Windows x64 shared FFmpeg libraries for WebMiere. It does not contain WebMiere source code or prebuilt third-party FFmpeg binaries.

Notice: FFmpeg libraries built by KawaiiEngine for WebMiere - licensed under LGPL v3 or later.

## Build Method

The build runs on GitHub Actions with a GitHub-hosted `windows-2022` runner. It uses MSYS2 build tools together with the Visual Studio 2022 MSVC x64 toolchain.

The workflow builds FFmpeg 8.1.2 from tag `n8.1.2`, resolved to commit `38b88335f99e76ed89ff3c93f877fdefce736c13`. It pins `nv-codec-headers` to commit `e844e5b26f46bb77479f063029595293aa8f812d`.

The source revisions and build metadata are pinned and recorded for auditability. Identical output hashes are not guaranteed across GitHub runner-image, MSVC, or MSYS2 package updates.

The FFmpeg configuration is LGPL v3-or-later oriented:

- `--enable-version3`
- `--disable-gpl`
- `--disable-nonfree`
- `--enable-shared`
- `--disable-static`
- `--extra-version=kawaiiengine-webmiere`

The build disables programs, documentation, networking, avdevice, and avfilter, and enables only the WebMiere-required demuxer, protocol, decoders, parsers, libraries, and VP9 NVDEC support.

## Run The Workflow

Open **Actions**, select **Build FFmpeg WebMiere Windows x64**, then choose **Run workflow**.

The workflow also runs for pull requests targeting `main`. A tag matching `ffmpeg-webmiere-*` triggers the release job.

## Artifacts

Successful runs upload the two package artifacts:

- `ffmpeg-webmiere-windows-x64-runtime`
- `ffmpeg-webmiere-windows-x64-dev`

The workflow also uploads `ffmpeg-webmiere-windows-x64-sha256sums`, which contains the final ZIP checksum manifest used by the tag release job.

The runtime artifact contains exactly these FFmpeg DLLs under `bin/`:

- `avcodec-62.dll`
- `avformat-62.dll`
- `avutil-60.dll`
- `swscale-9.dll`
- `swresample-6.dll`

Deploy those five runtime DLLs into the WebMiere plug-in's `ffmpeg` subdirectory:

```text
WebMiere\ffmpeg\
```

The development artifact contains matching FFmpeg headers, these MSVC import libraries, and the same compliance/source metadata files as the runtime package. It does not include pkg-config `.pc` files.

- `avcodec.lib`
- `avformat.lib`
- `avutil.lib`
- `swscale.lib`
- `swresample.lib`

## Verification Records

Each package includes generated compliance and verification files:

- `FFmpeg-BUILD-INFO.txt`
- `FFmpeg-SOURCE.txt`
- `ffmpeg-configure.txt`
- `ffmpeg-configure-output.txt`
- `ffmpeg-changes.diff`
- `ffmpeg-runtime-report.txt`
- `ffmpeg-runtime-probe.txt`
- `SHA256SUMS.txt`
- `COPYING.LGPLv3`
- `COPYING.GPLv3`
- exact corresponding FFmpeg source archive
- exact corresponding `nv-codec-headers` source archive

`ffmpeg-changes.diff` is generated and must be empty. The workflow fails if the checked-out FFmpeg source differs from the pinned commit.

`ffmpeg-runtime-probe.txt` is produced by a small MSVC-built probe that links the generated headers/import library and calls the freshly built FFmpeg DLLs for version, license, and configuration checks.

Verify package checksums from the extracted package root with:

```sh
sha256sum -c SHA256SUMS.txt
```

The workflow also validates `artifacts/SHA256SUMS.txt` for the final runtime and development ZIP files before upload. For tag builds, the release assets are:

- `ffmpeg-webmiere-windows-x64-runtime.zip`
- `ffmpeg-webmiere-windows-x64-dev.zip`
- `SHA256SUMS.txt`

When GitHub Artifact Attestations are supported for the repository/account, verify provenance with GitHub CLI:

```sh
gh attestation verify ffmpeg-webmiere-windows-x64-runtime.zip -R KawaiiEngine/WebMiere-FFmpeg
gh attestation verify ffmpeg-webmiere-windows-x64-dev.zip -R KawaiiEngine/WebMiere-FFmpeg
```

## Use With Visual Studio

Extract `ffmpeg-webmiere-windows-x64-dev` and add its `include` directory to **C/C++ > General > Additional Include Directories**.

Add its `lib` directory to **Linker > General > Additional Library Directories**, then link:

- `avcodec.lib`
- `avformat.lib`
- `avutil.lib`
- `swscale.lib`
- `swresample.lib`

Ship the five runtime DLLs in the WebMiere plug-in's `ffmpeg` subdirectory.

## License

The original factory materials in this repository, including the GitHub Actions workflow, PowerShell build and packaging script, runtime probe source, and repository documentation, are MIT licensed.

FFmpeg remains licensed under LGPL v3 or later for this build. `nv-codec-headers` retains its own upstream license. NVIDIA, Microsoft, and other third-party components retain their respective licenses and trademarks.
