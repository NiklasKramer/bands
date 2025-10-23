# bands

**Version 0.6** - Snapshot independence & current state mode

A spectral processing instrument for norns, inspired by the Buchla 296e Spectral Processor.

## Installation

In maiden's command line, enter:

```
;install https://github.com/NiklasKramer/bands
```

## Overview

**bands** divides audio into 16 frequency bands, each with independent control over level, pan, threshold gating, and sample rate decimation. The script features a snapshot and matrix morphing system that allows you to blend between four different states (A, B, C, D) with smooth interpolation.

Think of it as a spectral workstation where you can sculpt sound by treating each frequency band as an individual voice, then morph between completely different sonic states using a 2D performance surface.

## Concept

The Buchla 296e Spectral Processor split incoming audio into 16 frequency bands, allowing independent processing of each. This norns script expands on that concept by adding:

- **Multiple input sources**: Live audio, oscillator, noise, dust, and file playback
- **Per-band processing**: Level, stereo panning, threshold gating, and bit-crushing
- **Snapshot morphing**: Store four complete states and blend between them
- **2D performance matrix**: Morph between snapshots using X/Y coordinates
- **Path recording**: Record and play back matrix movements
- **Output effects**: Delay and 3-band EQ affect the final mixed output

## Features

### Input Sources (Norns Screen Only)

- **I** - Audio Input: Live stereo input
- **~** - Oscillator: Complex Buchla-inspired oscillator with FM modulation (Level, Freq, Timbre, Morph, Mod Rate, Mod Depth)
- **.** - Dust: Random impulses with adjustable density
- **\*** - Noise: Pink noise with optional LFO modulation
- **>** - File: Audio file playback with level, speed, and play/stop control

### Band Processing (Grid + Norns)

16 frequency bands from 80 Hz to 12 kHz:

- **Levels**: -60 to +12 dB per band
- **Panning**: Stereo placement per band
- **Threshold**: Gate each band (only pass signals above threshold)
- **Decimate**: Sample rate reduction per band (100 Hz to 48 kHz)

### Output Effects (Norns Screen Only)

- **|..** - Delay: Stereo delay with time, feedback, mix, and width
- **=-=** - EQ: 3-band EQ with high/low cuts and gain controls

### Snapshot System

- **4 snapshots** (A, B, C, D): Store complete parameter states
- **Two viewing modes**:
  - **Snapshot Mode** (default): View and edit any snapshot independently from matrix position
  - **Current State Mode**: View live blended values from matrix position (editing disabled)
- **Matrix morphing**: Blend between all four snapshots using X/Y position
- **Path recording**: Record and loop matrix movements for automation
- **Glide**: Smooth parameter transitions when moving in the matrix
- **Copy/Paste**: Copy and paste snapshots with Shift + Key 2/3 for quick parameter duplication

#### Snapshot Mode vs Current State Mode

**Snapshot Mode** (default):

- Select any snapshot (A/B/C/D) to view and edit
- Selection is independent from matrix position
- Edit from anywhere - no restrictions
- Sound reflects matrix blend, display shows selected snapshot

**Current State Mode**:

- All snapshot indicators bright (viewing live blend)
- Display shows current blended values from matrix position
- Editing disabled (view-only)
- Perfect for monitoring what you're hearing

Toggle with:

- **Grid**: Shift + any snapshot key (A/B/C/D)
- **Norns**: Shift + Enc 2

## Controls

### Norns

**Encoder 1**: Switch between modes (synced with Grid keys 1-4)

- INPUTS → LEVELS → PANS → THRESHOLDS → DECIMATE → EFFECTS → MATRIX

**Encoder 1 + Shift**: Switch snapshots (A, B, C, D)

**Encoder 2**: Select parameter/band

- In INPUTS/EFFECTS: Select parameter
- In band modes: Select band (1-16)
- In MATRIX: Navigate X position

**Encoder 2 + Shift**: Toggle Current State Mode (view/edit toggle)

**Encoder 3**: Adjust value

- In INPUTS/EFFECTS: Change parameter value
- In band modes: Change selected band parameter
- In MATRIX: Navigate Y position
- In MATRIX + Shift: Adjust glide time
- In File input + Shift: Adjust pitch in semitones

**Key 1**: Shift modifier

- Hold to access alternate functions
- Release to return to normal mode
- Also activates LED on Grid key 16 when held

**Key 2**:

- In INPUTS/EFFECTS: Previous input/effect type
- In MATRIX: Go to selected position
- **Shift + Key 2**: Copy current snapshot to clipboard

**Key 3**:

- In INPUTS/EFFECTS: Next input/effect type
- In band modes: Randomize current parameter across all bands
- In MATRIX: Randomize matrix position
- **Shift + Key 3**: Paste clipboard to current snapshot

### Grid

**Row 16 (Bottom Control Row)**:

- **Keys 1-4**: Switch between band modes (LEVELS, PANS, THRESHOLDS, DECIMATE) - synced with Norns
- **Keys 7-10**: Snapshot buttons (A, B, C, D)
  - Press: Select snapshot for viewing/editing
  - Shift + Press: Toggle Current State Mode
  - Brightness in Snapshot Mode: Selected snapshot is bright, others dim
  - Brightness in Current State Mode: All bright (viewing live blend)
- **Key 14**: Switch to MATRIX mode (Grid-only, not synced)
- **Key 16**: Shift (hold for alternate functions)

**Band Modes (Modes 1-4)**:

- **Rows 1-16**: 16 frequency bands (80 Hz to 12 kHz)
- Brightness indicates current value
- Press to set value
- Shift + Press: Randomize band

**Matrix Mode**:

- **Grid 2,2 to 15,15**: 14x14 matrix for morphing between snapshots
  - Top-left (2,2) = Snapshot A
  - Top-right (15,2) = Snapshot B
  - Bottom-left (2,15) = Snapshot C
  - Bottom-right (15,15) = Snapshot D
  - Moving between positions blends all parameters
- **Key 1,1**: Start/stop path recording
- **Key 16,1**: Toggle path mode / Shift: Clear path
- **Path mode**: Add/remove points to create looping paths

## Parameters

All parameters are saved per-snapshot and can be morphed in the matrix:

### Global Settings

- **Q**: Filter resonance (1.0 - 2.0)
- **Glide**: Transition time for matrix movements (0.05 - 20s)
- **Decimate Smooth**: Smoothing amount for decimation (0 - 1)
- **Info Banner**: Toggle info banners on/off

### Input Sources

Each input has its own controls (see INPUTS screen):

- **File input**: Level, Speed (with semitone pitch control via Shift + Enc 3), Play/Stop, File selection

### Output Effects

- **Delay**: Time, Feedback, Mix, Width
- **EQ**: Low Cut, High Cut, Low/Mid/High Gain

### Snapshots A, B, C, D

Each snapshot stores:

- All input source settings
- All 16 band parameters (level, pan, threshold, decimate)
- All output effect settings

### Bands (Current State)

16 bands × 4 parameters = 64 parameters (automatically managed)

## Workflow Examples

### Basic Spectral Sculpting

1. Select **INPUTS** mode, choose an input source (e.g., **I** for live audio)
2. Switch to **LEVELS** mode (Enc 1 or Grid key 1)
3. Use Enc 2/3 or Grid to adjust individual band levels
4. Try **PANS** mode to spread bands across stereo field

### Snapshot Morphing

1. Select snapshot A (Grid key 7 or Shift + Enc 1)
2. Edit parameters in any mode - changes save to A automatically
3. Select snapshot B (Grid key 8)
4. Edit parameters - these save to B
5. Repeat for C and D to create four distinct sonic states
6. Switch to **MATRIX** mode (Grid key 14)
7. Move around the grid - hear all parameters morph!
8. Optional: Enable Current State Mode (Shift + Enc 2) to see live blended values

### Path Recording

1. In MATRIX mode, press Grid 16,1 to toggle path mode
2. Press Grid 1,1 to start recording
3. Touch positions on the matrix to add points
4. Press Grid 1,1 again to stop - path will loop
5. Adjust glide time for different transition speeds

### Creative Processing

1. Use **~** OSC with low frequency (5 Hz) as rhythmic source
2. Set different **THRESHOLDS** per band for spectral gating
3. Use **DECIMATE** on high bands for digital degradation
4. Add **|..** DELAY for spatial depth
5. Shape with **=-=** EQ to emphasize frequency ranges

## Tips

- **Start simple**: Use one input source, adjust levels, then experiment
- **Snapshot workflow**: Select a snapshot, edit freely, changes save automatically - no corner restrictions!
- **Current State Mode**: Perfect for monitoring what you're hearing while moving through the matrix
- **Use copy/paste**: Quickly duplicate snapshots and make variations (Shift + Key 2/3)
- **Try path recording**: Great for evolving textures and automation
- **Combine effects**: File playback + threshold gating + delay = glitch heaven
- **Watch the meters**: Visual feedback shows which bands are active
- **Grid/Norns sync**: Band modes stay in sync between Grid and Norns for seamless workflow

## Signal Flow

```
Input Sources → 16 Band-Pass Filters → Per-Band Processing →
Mix → Delay → EQ → Limiter → Output
```

Each band is independently processed before being mixed together and sent through the output effects chain.

## Requirements

- norns
- grid (required for band control, matrix, and path recording)

## Credits

Concept inspired by the Buchla 296e Spectral Processor.

Created with the assistance of Cursor IDE.
