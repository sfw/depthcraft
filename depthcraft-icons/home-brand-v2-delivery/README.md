# v2 HomeMark opaque delivery (exact bytes)

Decode with `depthcraft-icons/home-brand-v2-delivery/decode-into-imageset.sh` or:

```bash
base64 -d < depthcraft-icons/home-brand-v2-delivery/HomeMark-28@1x-opaque.png.b64 > apps/DepthcraftReader/Assets.xcassets/HomeMark.imageset/HomeMark-28@1x-opaque.png
```

Expected sizes after decode: 1069 / 2046 / 2802 bytes; dims 28×28 / 56×56 / 84×84.
Prefer opaque on paper chrome. Skip ChromeLockup for this PR — keep Image+Text HStack.
