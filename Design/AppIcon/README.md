# App icon sources

- `ShipNotesAppIcon-source.png` is the original design source and is retained for future edits.
- The canonical 1024-pixel export is [AppIcon-1024.png](../../Sources/ShipNotes/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png).
  The former `ShipNotesAppIcon-master-1024.png` was byte-identical to that file and has been removed.
- The asset catalog contains the runtime icon sizes. `scripts/build-app.sh` builds
  the `.icns` from those files; it does not read the design source directory.
