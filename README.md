# SoundsBrowse

A browser/previewer for audio sample libraries: a folder tree, a file list and a waveform with playback.
Built with Delphi 13 (VCL) and [BASS](https://www.un4seen.com/) (free for non-commercial use).

## Build

Open `SoundsBrowse.dproj` in Delphi and build the **Win64** target. The exe is written to `bin\Win64\`.
A post-build step copies `bass.dll` and its add-ons from `lib\bass\x64\`, and the soundfont from `lib\soundfont\`, next to it.
To run it elsewhere, copy the whole `bin\Win64` folder.

## Formats

- **BASS itself:** WAV/BWF, AIFF, MP3/MP2/MP1 and Ogg Vorbis. It also plays M4A/AAC/WMA through Windows Media Foundation.
- **Add-ons**, loaded automatically from `bass*.dll` next to the exe:
  - FLAC, Opus, WavPack, APE, DSD, ALAC, Musepack, TTA, Speex and AC3.
  - MIDI (`.mid`, `.midi`, `.rmi`, `.kar`) through BASSMIDI, rendered with a soundfont (see below).
  - To add more, drop in another BASS add-on DLL.

### MIDI soundfont

MIDI files are played with the Aspirin Stereo V1.2 soundfont (`005.6mg_Aspirin_Stereo_V1.2_Bank.sf2`), which ships next to the exe.
To use a different `.sf2` or `.sf3` soundfont, choose *Options > Choose MIDI soundfont...*. *Options > Use bundled MIDI soundfont* switches back.

The choice is saved in `SoundsBrowse.ini`, where you can also edit it by hand (a relative path is relative to the exe; empty means the bundled one):

```ini
[MIDI]
SoundFont=C:\SoundFonts\MyFont.sf2
```

## Controls

| | |
|---|---|
| Select a file (click / arrow keys) | Loads it; plays it if *Auto-play* is on |
| Click a file that is already loaded | Replays it |
| Space | Play / stop |
| Enter, double-click file | Play from the start |
| Left / Right | Skip 2 s (Shift: 10 s) |
| Click waveform | Play from that point |
| Drag on waveform | Select a region and play it (loops if *Loop* is on) |
| Mouse wheel over waveform | Zoom; Shift+wheel scrolls |
| Right-drag waveform | Pan |
| Double-click waveform | Zoom to fit |
| Ctrl+F | Filter box (space-separated words must all match; Esc clears) |
| Drag files from the list | Copy them into Explorer, a DAW, a sampler, ... |

## Explorer integration

*Options > Show in Explorer context menu* toggles an "Open in SoundsBrowse" right-click entry on:

- folders
- drives
- the empty area inside an open folder

It's stored per user under `HKCU\Software\Classes`, so it needs no installer or admin rights. On Windows 11 the entry is under *Show more options*.

If you move the exe, click the option again and the entry will point to the new location.

Only one copy of SoundsBrowse runs at a time. Opening a folder from Explorer, or starting the exe with a folder path as its argument, switches the running window to that folder.

Settings (window layout, last folder, volume, ...) are saved in `SoundsBrowse.ini` next to the exe.

## Licence

SoundsBrowse is released under the [MIT License](LICENSE).

The MIT License covers only SoundsBrowse's own code. These bundled third-party files keep their own terms:

- **BASS** and its add-ons (`lib\bass\`) are by [Un4seen Developments](https://www.un4seen.com/). They are free for non-commercial use only; see `lib\bass\bass.txt`. If you use this code in a commercial product, you need your own BASS licence.
- **The Aspirin Stereo V1.2 soundfont** (`lib\soundfont\`) is in the public domain, as stated in the file's own copyright field.
- **The Windows10 Dark VCL style** (`res\Windows10Dark.vsf`) comes with Delphi and is redistributed under Embarcadero's terms for redistributable style files.
