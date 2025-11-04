# bands

**Version 0.6** - Snapshot independence & current state mode

A spectral processing instrument for norns that divides audio into 16 frequency bands.

## Installation

In maiden's command line:

```
;install https://github.com/NiklasKramer/bands
```

## Overview

**bands** splits audio into 16 frequency bands (80 Hz to 12 kHz). Each band has independent level, pan, threshold gating, and sample rate decimation. Create four snapshots (A, B, C, D) and morph between them using a 2D matrix.

## Features

### Input Sources

- **I** - Audio Input
- **~** - Oscillator (FM modulation)
- **.** - Dust (random impulses)
- **\*** - Noise (with LFO)
- **>** - File playback

### Band Processing

16 bands with independent:

- **Levels**: -60 to +12 dB
- **Panning**: Stereo placement
- **Threshold**: Gate each band
- **Decimate**: Sample rate reduction (100 Hz to 48 kHz)

### Output Effects

- **|..** - Delay: Time (0.01-10s), Feedback (0-1), Mix, Width
- **=-=** - EQ: 3-band with cuts and gains

### Snapshot System

- **4 snapshots** (A, B, C, D): Store complete parameter states
- **Matrix morphing**: Blend between snapshots using X/Y position
- **Two modes**:
  - **Snapshot Mode** (default): View/edit any snapshot independently
  - **Current State Mode**: View live blended values (editing disabled)
- **Path recording**: Record and loop matrix movements
- **Copy/Paste**: Shift + Key 2/3

## Controls

### Norns

**Encoder 1**: Switch modes → INPUTS → LEVELS → PANS → THRESHOLDS → DECIMATE → EFFECTS → MATRIX  
**Encoder 1 + Shift**: Switch snapshots (A, B, C, D)  
**Encoder 2**: Select parameter/band  
**Encoder 2 + Shift**: Toggle Current State Mode  
**Encoder 3**: Adjust value  
**Encoder 3 + Shift** (in MATRIX): Adjust glide time  
**Encoder 3 + Shift** (in File input): Adjust pitch in semitones

**Key 1**: Shift modifier  
**Key 2**: Previous input/effect (or go to position in MATRIX)  
**Key 2 + Shift**: Copy snapshot  
**Key 3**: Next input/effect (or randomize in band modes)  
**Key 3 + Shift**: Paste snapshot

### Grid

**Row 16**:

- **Keys 1-4**: Band modes (LEVELS, PANS, THRESHOLDS, DECIMATE)
- **Keys 7-10**: Snapshots (A, B, C, D) - Press to select, Shift+Press to toggle Current State Mode
- **Key 14**: MATRIX mode
- **Key 16**: Shift

**Band Modes**: Press rows 1-16 to set values, Shift+Press to randomize

**Matrix Mode**:

- **Grid 2,2 to 15,15**: Morph between snapshots
- **Key 1,1**: Start/stop path recording
- **Key 16,1**: Toggle path mode (Shift: Clear path)

## Workflow

1. Select an input source (INPUTS mode)
2. Adjust band levels (LEVELS mode)
3. Create snapshots: Select A/B/C/D, edit parameters, changes save automatically
4. Morph: Switch to MATRIX mode, move around to blend snapshots
5. Record paths: Press 16,1 then 1,1 to start recording matrix movements

## Requirements

- norns
- grid (required)

## Credits

The 16 band frequencies (80, 150, 250, 350, 500, 630, 800, 1000, 1300, 1600, 2000, 2600, 3500, 5000, 8000, 12000 Hz) are taken from the Buchla 296e Spectral Processor.

Created with the assistance of Cursor IDE.
