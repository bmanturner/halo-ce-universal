# extract-xiso

An Xbox disc image (xdvdfs) extraction and creation tool by in
<in@fishtank.com>, under a modified BSD license (see `LICENSE.TXT`, copied
unchanged from upstream).

Upstream: https://github.com/XboxDev/extract-xiso, commit
3f5b62cfe68f000b0e3c8a30104973f3a297948e.

None of its code is built as it is: `port/runtime/xiso.c`, which copies the
maps folder out of a disc image when the iPhone and iPad app imports one,
reads the format as `extract-xiso.c` does and carries its notice. The Apple
apps include `LICENSE.TXT` as `Licenses/extract-xiso.txt`. OpenCE's own
desktop reader (`port/linux/src/xiso.c`) no longer uses it: OpenCE wrote it
again from a description of the format when it moved to the AGPL 3.0, with
which this license's advertising clause is incompatible.

This product includes software developed by in <in@fishtank.com>.
