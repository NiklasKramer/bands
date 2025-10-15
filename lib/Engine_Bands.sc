Engine_Bands : CroneEngine {
    
    *new { arg context, doneCallback; ^super.new(context, doneCallback); }
    
    // ---- Boot / Alloc --------------------------------------------------------
    alloc {
        var freqs;
        
        // Audio input source - live audio in
        SynthDef(\audioInSource, { |outBus = 0, level = 0.0|
            var sig;
            sig = SoundIn.ar([0, 1]);  // Stereo audio input
            Out.ar(outBus, sig * level);
        }).add;
        
        // Noise source - pink noise with optional LFO modulation
        SynthDef(\noiseSource, { |outBus = 0, level = 0.1, lfoRate = 0, lfoDepth = 1.0|
            var sig, noiseLfo, lfoMin;
            
            // Depth controls how deep the LFO goes (0.0 = no modulation, 1.0 = full range)
            lfoMin = 1.0 - lfoDepth;  // Calculate minimum level based on depth
            noiseLfo = Select.kr(lfoRate > 0, [
                1.0,  // No LFO when rate is 0
                LFTri.kr(lfoRate).range(lfoMin, 1.0)  // LFO with variable depth
            ]);
            
            sig = PinkNoise.ar([level * 0.5 * noiseLfo, level * noiseLfo]);
            
            // Smooth level changes to avoid clicks
            Out.ar(outBus, sig * Lag.kr(level > 0, 0.5));
        }).add;
        
        // Dust source - random impulses
        SynthDef(\dustSource, { |outBus = 0, level = 0.0, density = 10|
            var sig;
            
            // Bipolar impulses (more dynamic)
            sig = Dust2.ar([density, density]);
            sig = sig * 0.3;  // Scale down
            
            // Smooth level changes to avoid clicks
            Out.ar(outBus, sig * level * Lag.kr(level > 0, 0.5));
        }).add;
        
        // File playback source - stereo file player with speed control
        SynthDef(\fileSource, { |outBus = 0, level = 0.0, bufnum = 0, speed = 1.0, gate = 1|
            var sig, env;
            
            // Envelope for smooth start/stop
            env = EnvGen.kr(Env.asr(0.01, 1, 0.1), gate, doneAction: 0);
            
            // PlayBuf with speed control (allows negative speeds for reverse playback)
            sig = PlayBuf.ar(2, bufnum, BufRateScale.kr(bufnum) * speed, loop: 1);
            
            // Smooth level changes to avoid clicks
            Out.ar(outBus, sig * level * env * Lag.kr(level > 0, 0.5));
        }).add;
        
        // Complex oscillator source - inspired by Buchla 259e "Twisted Waveform Generator"
        SynthDef(\oscSource, { |outBus = 0, level = 0.0, freq = 220, timbre = 0.5, warp = 0.5, modRate = 5.0, modDepth = 0.0|
            var sig, phase, sine, triangle, square, modulator, modulatedFreq;
            var shaped1, shaped2, shaped3, morphed, warped;
            var harmonic1, harmonic2, harmonic3;
            
            // Frequency with smooth lag for glide
            freq = Lag.kr(freq, 0.05);
            
            // Internal modulation oscillator (259e's modulation oscillator)
            // Through-zero linear FM capability
            modulator = SinOsc.ar(modRate) * modDepth * freq;
            modulatedFreq = freq + modulator;
            
            // Generate multiple waveforms simultaneously (like 259e's multiple outputs)
            phase = Phasor.ar(0, modulatedFreq / SampleRate.ir, 0, 1);
            sine = SinOsc.ar(modulatedFreq);
            triangle = LFTri.ar(modulatedFreq);
            square = LFPulse.ar(modulatedFreq, 0, 0.5) * 2 - 1;
            
            // Multiple waveshaping tables (259e's selectable wavetables)
            // Table 1: Classic wavefolder (Serge-style)
            shaped1 = (sine * (1 + (timbre * 5))).fold2(1.0);
            
            // Table 2: Chebyshev waveshaping (adds specific harmonics)
            shaped2 = sine + (sine.squared * 0.5 * timbre) + (sine.cubed * 0.33 * timbre);
            shaped2 = shaped2.tanh;  // Soft clipping
            
            // Table 3: West Coast wavefolding with asymmetry
            shaped3 = (sine * (1 + (timbre * 4))).wrap2(1.0).fold2(0.8);
            
            // Morph parameter: blend between waveshaping tables
            // warp controls which tables are blended
            morphed = Select.ar(warp.clip(0, 0.999) * 2.999, [
                shaped1,  // 0.0 - 0.33: Table 1
                shaped2,  // 0.33 - 0.66: Table 2  
                shaped3   // 0.66 - 1.0: Table 3
            ]);
            
            // Add blend between adjacent tables for smooth morphing
            morphed = SelectX.ar(warp.clip(0, 0.999) * 2.999, [shaped1, shaped2, shaped3]);
            
            // Mix in raw waveforms for additional harmonic content
            // Lower timbre = more pure waveforms, higher = more waveshaped
            harmonic1 = (triangle * (1 - timbre)) + (morphed * timbre);
            
            // Add subtle harmonics from modulation interaction
            harmonic2 = SinOsc.ar(modulatedFreq * 2, harmonic1 * timbre) * 0.2;
            harmonic3 = SinOsc.ar(modulatedFreq * 3, harmonic1 * timbre * 0.5) * 0.1;
            
            // Combine for rich harmonic content
            sig = harmonic1 + harmonic2 + harmonic3;
            
            // Add subtle pulse width modulation for movement
            sig = sig + (square * LFTri.kr(0.1).range(0, 0.15) * timbre * 0.3);
            
            // Final waveshaping stage (259e's output stage)
            warped = (sig * (1 + warp)).tanh * 0.8;
            
            // Stereo imaging with phase offset (259e's stereo outputs)
            sig = [warped, DelayN.ar(warped, 0.01, SinOsc.kr(0.23).range(0.0005, 0.002))];
            
            // Add subtle stereo width modulation
            sig = sig * [1.0, 1.0 + (LFNoise1.kr(0.5) * 0.05)];
            
            // Output with level control and smooth fading
            Out.ar(outBus, sig * level * Lag.kr(level > 0, 0.5) * 0.6);
        }).add;
        
        // Stereo delay with width control
        SynthDef(\delayFx, { |inBus = 0, outBus = 0, time = 0.5, feedback = 0.5, mix = 0.0, width = 0.5|
            var sig, delayedL, delayedR, maxTime, wet;
            sig = In.ar(inBus, 2);
            
            maxTime = 2.0;
            time = Lag.kr(time.clip(0.01, maxTime), 0.1);
            feedback = Lag.kr(feedback.clip(0.0, 1.5), 0.1);  // Allow extreme feedback up to 1.5
            mix = Lag.kr(mix.clip(0.0, 1.0), 0.1);
            width = Lag.kr(width.clip(0.0, 1.0), 0.1);
            
            // Dual delay lines with different times for width
            delayedL = LocalIn.ar(1);
            delayedR = LocalIn.ar(1);
            
            delayedL = DelayC.ar(delayedL + sig[0], maxTime, time * (1 - (width * 0.3)));
            delayedR = DelayC.ar(delayedR + sig[1], maxTime, time * (1 + (width * 0.3)));
            
            LocalOut.ar([delayedL * feedback, delayedR * feedback]);
            
            wet = [delayedL, delayedR];
            sig = (sig * (1 - mix)) + (wet * mix);
            
            Out.ar(outBus, sig);
        }).add;
        
        // 3-band EQ with high/low cuts
        SynthDef(\eqFx, { |inBus = 0, outBus = 0, lowCut = 20, highCut = 20000, lowGain = 0, midGain = 0, highGain = 0|
            var sig;
            sig = In.ar(inBus, 2);
            
            lowCut = Lag.kr(lowCut.clip(10, 5000), 0.1);    // More extreme range
            highCut = Lag.kr(highCut.clip(500, 22000), 0.1);  // More extreme range
            lowGain = Lag.kr(lowGain.clip(-48, 24), 0.1);   // More extreme boost/cut
            midGain = Lag.kr(midGain.clip(-48, 24), 0.1);   // More extreme boost/cut
            highGain = Lag.kr(highGain.clip(-48, 24), 0.1); // More extreme boost/cut
            
            // Apply filters in series for better interaction
            // High-pass filter (cuts lows below lowCut)
            sig = BHiPass.ar(sig, lowCut, 0.5);
            
            // Low-pass filter (cuts highs above highCut)
            sig = BLowPass.ar(sig, highCut, 0.5);
            
            // Apply shelving EQ
            // Low shelf at lowCut frequency
            sig = BLowShelf.ar(sig, lowCut, 1.0, lowGain);
            
            // High shelf at highCut frequency
            sig = BHiShelf.ar(sig, highCut, 1.0, highGain);
            
            // Mid band using parametric EQ at geometric mean of lowCut and highCut
            sig = BPeakEQ.ar(sig, (lowCut * highCut).sqrt, 1.0, midGain);
            
            Out.ar(outBus, sig);
        }).add;
        
        // Final limiter synth for summed output
        SynthDef(\finalLimiter, { |inBus = 0, outBus = 0|
            var sig;
            sig = In.ar(inBus, 2);
            sig = Limiter.ar(sig, 0.99, 0.01);  // Hard limit at 0.99 to prevent clipping
            Out.ar(outBus, sig);
        }).add;
        
        SynthDef(\specBand, { |inBus = 0, outBus = 0, freq = 1000, q = 1.0, level = 0.0, pan = 0.0, meterBus = -1, ampAtk = 0.01, ampRel = 0.08, thresh = 1.0, decimateRate = 48000, decimateSmoothing = 1, filterType = 1, gate = 1|
            var src, sig, gain, bwidth, meter, open, cutoff, dark, outSig, meter_db, meter_normalized, gate_level, gate_open, env;
            var lowpass, bandpass, highpass;

            // Envelope for smooth fade-in/out (open by default with gate=1)
            env = EnvGen.kr(Env.asr(0.01, 1, 0.1), gate, doneAction: 0);

            src = In.ar(inBus, 2);

            bwidth = freq / max(q, 0.001);
            bwidth = Lag.kr(bwidth.clip(1, 20000), 0.02);
            freq   = Lag.kr(freq.clip(20, 20000), 0.02);
            gain   = Lag.kr(level.dbamp, 0.02);
            pan    = Lag.kr(pan.clip(-1, 1), 0.02);

            // Apply sample rate reduction (decimation) - before filter
            sig = SmoothDecimator.ar(src, decimateRate.clip(100, 48000), decimateSmoothing.clip(0, 1));

            // Set filter type levels based on filterType parameter
            // filterType: 0=lowpass, 1=bandpass (default), 2=highpass
            lowpass = Select.kr(filterType.clip(0, 2), [1.0, 0.0, 0.0]);
            bandpass = Select.kr(filterType.clip(0, 2), [0.0, 1.0, 0.0]);
            highpass = Select.kr(filterType.clip(0, 2), [0.0, 0.0, 1.0]);
            
            // SVF with filter type controlled by level parameters
            sig = SVF.ar(
                sig,
                freq,
                (bwidth / freq).clip(0.0005, 1.0), // res
                lowpass,   // lowpass level
                bandpass,  // bandpass level
                highpass,  // highpass level
                0,   // notch
                0    // peak
            );

            // simple gate: signal must exceed threshold to pass
            gate_level = Amplitude.kr((sig[0] + sig[1]) * 0.5, ampAtk, ampRel);
            gate_open = (gate_level > thresh).asFloat; // 1 if above threshold, 0 if below
            gate_open = Lag.kr(gate_open, 0.1); // smooth gate transitions
            sig = sig * gate_open; // simple VCA
    
            outSig = Balance2.ar(sig[0] * gain, sig[1] * gain, pan, 1);
            
            // meter the final output level (after gain and pan)
            meter = Amplitude.kr((outSig[0] + outSig[1]) * 0.5, ampAtk, ampRel);
            meter = Lag.kr(meter, 0.5); // additional smoothing for meter visualization
            // convert meter to dB scale for visualization (0-1 range)
            meter_db = (meter + 0.001).ampdb;
            meter_normalized = (meter_db + 60).clip(0, 60) / 60; // -60dB to 0dB -> 0-1
            Select.kr(meterBus >= 0, [DC.kr(0), Out.kr(meterBus, meter_normalized)]);
            // safety limiting
            outSig = Limiter.ar(outSig, 0.95, 0.01);
            // Apply envelope for smooth fade-in/out
            outSig = outSig * env;
            Out.ar(outBus, outSig);
        }).add;

        // CRITICAL: Wait for all SynthDefs to be compiled before creating synths
        // This prevents clicks on script load
        Server.default.sync;


        freqs = [
            80, 150, 250, 350, 500, 630, 800, 1000,
            1300, 1600, 2000, 2600, 3500, 5000, 8000, 12000
        ];
        // allocate per-band meter buses as individual control buses
        ~meterBuses = freqs.collect { Bus.control(context.server, 1) };

        // Create an internal bus for input source
        ~inputBus = Bus.audio(context.server, 2);
        
        // Create an internal bus for summing all bands
        ~sumBus = Bus.audio(context.server, 2);
        
        // Create buses for effects chain
        ~delayBus = Bus.audio(context.server, 2);
        ~eqBus = Bus.audio(context.server, 2);
        
        // Create a buffer for file playback (initially empty)
        ~fileBuffer = Buffer.alloc(context.server, context.server.sampleRate * 2, 2); // 2 seconds, stereo
        
        // Wait for buffer allocation to complete
        Server.default.sync;

        
        ~bandGroup = Group.head(context.xg);
        
        // Create three separate input source synths at the head of the group
        ~audioInSource = Synth.head(
            ~bandGroup,
            \audioInSource,
            [
                \outBus, ~inputBus,
                \level, 0.0  // Start silent, user brings it up manually
            ]
        );
        
        ~noiseSource = Synth.after(
            ~audioInSource,
            \noiseSource,
            [
                \outBus, ~inputBus,
                \level, 0.0,
                \lfoRate, 0,
                \lfoDepth, 1.0
            ]
        );
        
        ~dustSource = Synth.after(
            ~noiseSource,
            \dustSource,
            [
                \outBus, ~inputBus,
                \level, 0.0,
                \density, 10
            ]
        );
        
        ~oscSource = Synth.after(
            ~dustSource,
            \oscSource,
            [
                \outBus, ~inputBus,
                \level, 0.0,
                \freq, 220,
                \timbre, 0.3,
                \warp, 0.0,
                \modRate, 5.0,
                \modDepth, 0.0
            ]
        );
        
        ~fileSource = Synth.after(
            ~oscSource,
            \fileSource,
            [
                \outBus, ~inputBus,
                \level, 0.0,
                \bufnum, ~fileBuffer,
                \speed, 1.0,
                \gate, 0
            ]
        );
        
        ~bands = freqs.collect { |f, i|
            var ftype;
            // First band = lowpass (0), last band = highpass (2), middle bands = bandpass (1)
            ftype = case
                { i == 0 } { 0 }
                { i == (freqs.size - 1) } { 2 }
                { 1 };
            
            Synth.tail(
                ~bandGroup,
                \specBand,
                [
                    \inBus, ~inputBus,  // Use input bus instead of direct audio in
                    \outBus, ~sumBus,  // Output to sum bus instead of direct out
                    \freq, f,
                    \q, 6.0,
                    \level, -12.0,
                    \pan, (i.linlin(0, (freqs.size - 1).max(1), -0.5, 0.5)),
                    \meterBus, (~meterBuses[i].index),
                    \filterType, ftype,
                    \gate, 1  // Envelope open by default
                ]
            )
        };

        Server.default.sync;

        
        // Create effects chain synths
        ~delayFx = Synth.tail(
            ~bandGroup,
            \delayFx,
            [
                \inBus, ~sumBus,
                \outBus, ~delayBus,
                \time, 0.5,
                \feedback, 0.5,
                \mix, 0.0,
                \width, 0.5
            ]
        );
        
        ~eqFx = Synth.tail(
            ~bandGroup,
            \eqFx,
            [
                \inBus, ~delayBus,
                \outBus, ~eqBus,
                \lowCut, 20,
                \highCut, 20000,
                \lowGain, 0,
                \midGain, 0,
                \highGain, 0
            ]
        );
        
        // Create final limiter synth to process the summed output
        ~finalLimiter = Synth.tail(
            ~bandGroup,
            \finalLimiter,
            [
                \inBus, ~eqBus,
                \outBus, context.out_b
            ]
        );

        // per-band meter polls using getSynchronous pattern
        ~meterPollNames = freqs.collect { |item, i|
            var name = ("meter_" ++ i).asSymbol;
            this.addPoll(name, { ~meterBuses[i].getSynchronous; });
            name
        };

        ~setBandParam = { |i, key, val|
            var idx;
            if(~bands.isNil) { ^nil };
            idx = (i - 1).clip(0, ~bands.size - 1);
            ~bands[idx].set(key, val);
        };

        this.addCommand("level", "if", { arg msg;
            var i, db;
            i = msg[1].asInteger;
            db = msg[2];
            ~setBandParam.(i, \level, db);
        });
        this.addCommand("pan", "if", { arg msg;
            var i, p;
            i = msg[1].asInteger;
            p = msg[2].clip(-1.0, 1.0);
            ~setBandParam.(i, \pan, p);
        });

        // set resonance (Q) for all bands at once
        this.addCommand("q", "f", { arg msg;
            var q;
            q = msg[1].clip(0.1, 200.0);
            if(~bands.notNil) {
                ~bands.do({ |s| s.set(\q, q) });
            };
        });

        // set threshold for a single band (index, value)
        this.addCommand("thresh_band", "if", { arg msg;
            var i, t;
            i = msg[1].asInteger;
            t = msg[2].clip(0.0, 1.0);
            ~setBandParam.(i, \thresh, t);
        });
        
        // set decimate rate for a single band (index, rate in Hz)
        this.addCommand("decimate_band", "if", { arg msg;
            var i, rate;
            i = msg[1].asInteger;
            rate = msg[2].clip(100, 48000);
            ~setBandParam.(i, \decimateRate, rate);
        });
        
        // set decimate smoothing for all bands at once
        this.addCommand("decimate_smoothing", "f", { arg msg;
            var smoothing;
            smoothing = msg[1].clip(0.0, 1.0);
            if(~bands.notNil) {
                ~bands.do({ |s| s.set(\decimateSmoothing, smoothing) });
            };
        });
        
        // set input source type (0=audio in, 1=noise, 2=dust, 3=osc) - for compatibility
        // This sets one source to 1.0 and others to 0
        this.addCommand("input_source", "i", { arg msg;
            var sourceType;
            sourceType = msg[1].clip(0, 3);
            case
                { sourceType == 0 } { 
                    if(~audioInSource.notNil) { ~audioInSource.set(\level, 1.0); };
                    if(~noiseSource.notNil) { ~noiseSource.set(\level, 0.0); };
                    if(~dustSource.notNil) { ~dustSource.set(\level, 0.0); };
                    if(~oscSource.notNil) { ~oscSource.set(\level, 0.0); };
                }
                { sourceType == 1 } { 
                    if(~audioInSource.notNil) { ~audioInSource.set(\level, 0.0); };
                    if(~noiseSource.notNil) { ~noiseSource.set(\level, 0.1); };
                    if(~dustSource.notNil) { ~dustSource.set(\level, 0.0); };
                    if(~oscSource.notNil) { ~oscSource.set(\level, 0.0); };
                }
                { sourceType == 2 } { 
                    if(~audioInSource.notNil) { ~audioInSource.set(\level, 0.0); };
                    if(~noiseSource.notNil) { ~noiseSource.set(\level, 0.0); };
                    if(~dustSource.notNil) { ~dustSource.set(\level, 1.0); };
                    if(~oscSource.notNil) { ~oscSource.set(\level, 0.0); };
                }
                { sourceType == 3 } { 
                    if(~audioInSource.notNil) { ~audioInSource.set(\level, 0.0); };
                    if(~noiseSource.notNil) { ~noiseSource.set(\level, 0.0); };
                    if(~dustSource.notNil) { ~dustSource.set(\level, 0.0); };
                    if(~oscSource.notNil) { ~oscSource.set(\level, 1.0); };
                };
        });
        
        // set audio input level (0.0 to 1.0)
        this.addCommand("audio_in_level", "f", { arg msg;
            var level;
            level = msg[1].clip(0.0, 1.0);
            if(~audioInSource.notNil) {
                ~audioInSource.set(\level, level);
            };
        });
        
        // set noise level for noise source (0.0 to 1.0)
        this.addCommand("noise_level", "f", { arg msg;
            var level;
            level = msg[1].clip(0.0, 1.0);
            if(~noiseSource.notNil) {
                ~noiseSource.set(\level, level);
            };
        });
        
        // set dust level (0.0 to 1.0)
        this.addCommand("dust_level", "f", { arg msg;
            var level;
            level = msg[1].clip(0.0, 1.0);
            if(~dustSource.notNil) {
                ~dustSource.set(\level, level);
            };
        });
        
        // set dust density for dust source (impulses per second)
        this.addCommand("dust_density", "f", { arg msg;
            var density;
            density = msg[1].clip(1, 1000);
            if(~dustSource.notNil) {
                ~dustSource.set(\density, density);
            };
        });
        
        // set noise LFO rate (0 = off, 0.01-20 Hz)
        this.addCommand("noise_lfo_rate", "f", { arg msg;
            var rate;
            rate = msg[1].clip(0, 20);
            if(~noiseSource.notNil) {
                ~noiseSource.set(\lfoRate, rate);
            };
        });
        
        // set noise LFO depth (0.0 = no modulation, 1.0 = full depth)
        this.addCommand("noise_lfo_depth", "f", { arg msg;
            var depth;
            depth = msg[1].clip(0.0, 1.0);
            if(~noiseSource.notNil) {
                ~noiseSource.set(\lfoDepth, depth);
            };
        });
        
        // set oscillator level (0.0 to 1.0)
        this.addCommand("osc_level", "f", { arg msg;
            var level;
            level = msg[1].clip(0.0, 1.0);
            if(~oscSource.notNil) {
                ~oscSource.set(\level, level);
            };
        });
        
        // set oscillator frequency (0.1 to 2000 Hz)
        this.addCommand("osc_freq", "f", { arg msg;
            var freq;
            freq = msg[1].clip(0.1, 2000);
            if(~oscSource.notNil) {
                ~oscSource.set(\freq, freq);
            };
        });
        
        // set oscillator timbre (0.0 to 1.0) - waveshaping intensity & harmonic content
        // Low values: purer tones, High values: complex waveshaped harmonics
        this.addCommand("osc_timbre", "f", { arg msg;
            var timbre;
            timbre = msg[1].clip(0.0, 1.0);
            if(~oscSource.notNil) {
                ~oscSource.set(\timbre, timbre);
            };
        });
        
        // set oscillator morph (0.0 to 1.0) - morphs between 3 waveshaping tables
        // 0.0-0.33: Serge folder, 0.33-0.66: Chebyshev, 0.66-1.0: West Coast asymmetric
        this.addCommand("osc_warp", "f", { arg msg;
            var warp;
            warp = msg[1].clip(0.0, 1.0);
            if(~oscSource.notNil) {
                ~oscSource.set(\warp, warp);
            };
        });
        
        // set oscillator modulation rate (0.1 to 100 Hz) - internal FM oscillator frequency
        this.addCommand("osc_mod_rate", "f", { arg msg;
            var rate;
            rate = msg[1].clip(0.1, 100);
            if(~oscSource.notNil) {
                ~oscSource.set(\modRate, rate);
            };
        });
        
        // set oscillator modulation depth (0.0 to 1.0) - through-zero linear FM amount
        this.addCommand("osc_mod_depth", "f", { arg msg;
            var depth;
            depth = msg[1].clip(0.0, 1.0);
            if(~oscSource.notNil) {
                ~oscSource.set(\modDepth, depth);
            };
        });
        
        // load audio file for file playback source
        this.addCommand("file_load", "s", { arg msg;
            var path;
            path = msg[1].asString;
            if(~fileBuffer.notNil) {
                ~fileBuffer.free;
                ~fileBuffer = Buffer.read(context.server, path, action: { |buf|
                    if(buf.numFrames == 0) {
                        ("Error loading file: " ++ path).postln;
                    } {
                        ("Loaded file: " ++ path ++ " (" ++ buf.duration.asString ++ "s)").postln;
                        // Update the synth's buffer reference
                        if(~fileSource.notNil) {
                            ~fileSource.set(\bufnum, buf);
                        };
                    };
                });
            };
        });
        
        // set file playback level (0.0 to 1.0)
        this.addCommand("file_level", "f", { arg msg;
            var level;
            level = msg[1].clip(0.0, 1.0);
            if(~fileSource.notNil) {
                ~fileSource.set(\level, level);
            };
        });
        
        // set file playback speed (-4.0 to 4.0)
        this.addCommand("file_speed", "f", { arg msg;
            var speed;
            speed = msg[1].clip(-4.0, 4.0);
            if(~fileSource.notNil) {
                ~fileSource.set(\speed, speed);
            };
        });
        
        // start/stop file playback (1 = play, 0 = stop)
        this.addCommand("file_gate", "i", { arg msg;
            var gate;
            gate = msg[1].clip(0, 1);
            if(~fileSource.notNil) {
                ~fileSource.set(\gate, gate);
            };
        });
        
        // Delay effect parameters
        this.addCommand("delay_time", "f", { arg msg;
            var time;
            time = msg[1].clip(0.01, 2.0);
            if(~delayFx.notNil) {
                ~delayFx.set(\time, time);
            };
        });
        
        this.addCommand("delay_feedback", "f", { arg msg;
            var feedback;
            feedback = msg[1].clip(0.0, 0.95);
            if(~delayFx.notNil) {
                ~delayFx.set(\feedback, feedback);
            };
        });
        
        this.addCommand("delay_mix", "f", { arg msg;
            var mix;
            mix = msg[1].clip(0.0, 1.0);
            if(~delayFx.notNil) {
                ~delayFx.set(\mix, mix);
            };
        });
        
        this.addCommand("delay_width", "f", { arg msg;
            var width;
            width = msg[1].clip(0.0, 1.0);
            if(~delayFx.notNil) {
                ~delayFx.set(\width, width);
            };
        });
        
        // EQ effect parameters
        this.addCommand("eq_low_cut", "f", { arg msg;
            var freq;
            freq = msg[1].clip(20, 2000);
            if(~eqFx.notNil) {
                ~eqFx.set(\lowCut, freq);
            };
        });
        
        this.addCommand("eq_high_cut", "f", { arg msg;
            var freq;
            freq = msg[1].clip(1000, 20000);
            if(~eqFx.notNil) {
                ~eqFx.set(\highCut, freq);
            };
        });
        
        this.addCommand("eq_low_gain", "f", { arg msg;
            var gain;
            gain = msg[1].clip(-24, 12);
            if(~eqFx.notNil) {
                ~eqFx.set(\lowGain, gain);
            };
        });
        
        this.addCommand("eq_mid_gain", "f", { arg msg;
            var gain;
            gain = msg[1].clip(-24, 12);
            if(~eqFx.notNil) {
                ~eqFx.set(\midGain, gain);
            };
        });
        
        this.addCommand("eq_high_gain", "f", { arg msg;
            var gain;
            gain = msg[1].clip(-24, 12);
            if(~eqFx.notNil) {
                ~eqFx.set(\highGain, gain);
            };
        });
    }

    // ---- Teardown ------------------------------------------------------------
    free {
        // Free synths first (in reverse order of creation)
        if(~finalLimiter.notNil) { ~finalLimiter.free; ~finalLimiter = nil; };
        if(~eqFx.notNil) { ~eqFx.free; ~eqFx = nil; };
        if(~delayFx.notNil) { ~delayFx.free; ~delayFx = nil; };
        if(~bands.notNil) { ~bands.do({ |x| if(x.notNil) { x.free } }); ~bands = nil; };
        if(~fileSource.notNil) { ~fileSource.free; ~fileSource = nil; };
        if(~oscSource.notNil) { ~oscSource.free; ~oscSource = nil; };
        if(~dustSource.notNil) { ~dustSource.free; ~dustSource = nil; };
        if(~noiseSource.notNil) { ~noiseSource.free; ~noiseSource = nil; };
        if(~audioInSource.notNil) { ~audioInSource.free; ~audioInSource = nil; };
        
        // Free group after all synths
        if(~bandGroup.notNil) { ~bandGroup.free; ~bandGroup = nil; };
        
        // Free buffers
        if(~fileBuffer.notNil) { ~fileBuffer.free; ~fileBuffer = nil; };
        
        // Free buses
        if(~eqBus.notNil) { ~eqBus.free; ~eqBus = nil; };
        if(~delayBus.notNil) { ~delayBus.free; ~delayBus = nil; };
        if(~sumBus.notNil) { ~sumBus.free; ~sumBus = nil; };
        if(~inputBus.notNil) { ~inputBus.free; ~inputBus = nil; };
        if(~meterBuses.notNil) { ~meterBuses.do({ |b| if(b.notNil) { b.free } }); ~meterBuses = nil; };
        
        // Clean up function references
        ~setBandParam = nil;
        ~meterPollNames = nil;
        
        super.free;
    }
}


