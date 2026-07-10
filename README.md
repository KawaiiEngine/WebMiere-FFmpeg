# WebMiere FFmpeg

This repository contains the repeatable pinned-source FFmpeg build factory used to produce Windows x64 shared FFmpeg libraries for WebMiere. It does not contain WebMiere source code or prebuilt third-party FFmpeg binaries.

Notice: FFmpeg libraries built by KawaiiEngine for WebMiere - licensed under LGPL v3 or later.

## Build Method

The build runs on GitHub Actions with a GitHub-hosted `windows-2022` runner. It uses MSYS2 build tools together with the Visual Studio 2022 MSVC x64 toolchain.

The workflow builds FFmpeg 8.1.2 from tag `n8.1.2`, resolved to commit `38b88335f99e76ed89ff3c93f877fdefce736c13`. It pins `nv-codec-headers` to commit `e844e5b26f46bb77479f063029595293aa8f812d`.

The planned dav1d-enabled build also builds dav1d 1.5.1 from pinned upstream commit `42b2b24fb8819f1ed3643aa9cf2a62f03868e3aa`. dav1d is BSD 2-Clause licensed. Its static library is linked into the generated shared `avcodec-62.dll`; no separate `dav1d.dll` or `libdav1d.dll` is distributed.

The source revisions and build metadata are pinned and recorded for auditability. Identical output hashes are not guaranteed across GitHub runner-image, MSVC, or MSYS2 package updates.

The FFmpeg configuration remains LGPL v3-or-later oriented:

- `--enable-version3`
- `--disable-gpl`
- `--disable-nonfree`
- `--enable-shared`
- `--disable-static`
- `--extra-version=kawaiiengine-webmiere`

The dav1d-enabled migration must additionally record these options in the generated configure records:

- `--pkg-config-flags=--static`
- `--enable-libdav1d`
- `--enable-decoder=libdav1d`

Here, `--disable-static` disables FFmpeg static-library outputs. It does not prevent the separately built static dav1d library from being linked into FFmpeg's shared `avcodec` library. `--pkg-config-flags=--static` supplies the link metadata required for that static dav1d dependency.

The build disables programs, documentation, networking, avdevice, and avfilter, and enables only the WebMiere-required demuxer, protocol, decoders, parsers, libraries, and VP9/AV1 NVDEC support.

The planned dav1d-enabled WebMiere video decode components are distinct:

- FFmpeg's native VP9 software decoder
- FFmpeg's native AV1 decoder, used with AV1 NVDEC
- the libdav1d AV1 software decoder
- FFmpeg VP9 and AV1 parsers
- FFmpeg VP9 and AV1 NVDEC hardware-acceleration support

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

In the dav1d-enabled package, dav1d code is contained in `avcodec-62.dll`; it does not add a sixth runtime DLL.

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

For the dav1d-enabled build, each runtime and development package must include generated compliance and verification files:

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
- `COPYING.dav1d`, copied from the exact pinned upstream dav1d `COPYING`
- exact corresponding FFmpeg source archive
- exact corresponding `nv-codec-headers` source archive
- exact corresponding dav1d source archive

The records must identify the pinned FFmpeg, nv-codec-headers, and dav1d versions and commits. Together they preserve build information, the complete configure command and output, FFmpeg source-change verification, runtime dependency and component probes, and SHA-256 manifests for package contents and final ZIP files. Generated records and source archives are produced by the build; they are not placeholders in this repository.

`ffmpeg-changes.diff` is generated and must be empty. The workflow fails if the checked-out FFmpeg source differs from the pinned commit.

`ffmpeg-runtime-probe.txt` is produced by a small MSVC-built probe that links the generated headers/import library and calls the freshly built FFmpeg DLLs for version, license, configuration, and required WebMiere component checks. The dav1d-enabled probe must cover the native VP9 and AV1 decoders, the libdav1d decoder, VP9/AV1 parsers, and VP9/AV1 NVDEC availability.

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

For the dav1d-enabled build, the FFmpeg portions of the generated libraries remain licensed under LGPL v3 or later, while the statically linked dav1d portions are BSD 2-Clause licensed. `nv-codec-headers` retains its upstream license and copyright notices. NVIDIA, Microsoft, and all other third-party rights and trademarks remain with their respective owners.
