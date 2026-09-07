# Character assets

The public roster is Nara, Mochi, Pando, and Lumi. The character artwork was supplied by larrylabs; the workflow included Rodin-generated character models and subsequent rigging, animation, material, and face work in Blender and the native renderer.

This repository includes the runtime USDZ files, PNG textures, and portraits needed to run UselessPet. It does not include the original modeling projects or a complete reproducible art-generation pipeline. Screenshots in the README show these actual runtime characters.

All four companions use hybrid rigs with continuous eyelid, gaze, and smile controls. Mochi has softly weighted ears and a curled tail; Pando has restrained ear motion, and Lumi has gently swaying long ears. Their original bundled resources remain as neutral comparison baselines and fallbacks. Pando's refined geometry is derived from the distributed neutral USDZ because its original Rodin GLB is unavailable in the current art workspace. Keep neutral faces and identity consistent when editing animations.

Artwork is covered by [ASSET_LICENSE.md](../ASSET_LICENSE.md). Source code and localization text use [MIT](../LICENSE). `assets-manifest.json` records each distributed native resource and its SHA-256 checksum. After intentionally replacing a resource, run `make update-asset-manifest`, inspect the changed inventory, and then `make verify-assets`.

No external asset download is needed at runtime. Files are tracked in ordinary Git; Git LFS is not required.
