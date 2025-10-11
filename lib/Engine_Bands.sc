Engine_Bands : CroneEngine {
    
    *new { arg context, doneCallback; ^super.new(context, doneCallback); }
    
    // ---- Boot / Alloc --------------------------------------------------------
    alloc {
        var freqs;
        
        // Final limiter synth for summed output
        SynthDef(\finalLimiter, { |inBus = 0, outBus = 0|
            var sig;
            sig = In.ar(inBus, 2);
            sig = Limiter.ar(sig, 0.99, 0.01);  // Hard limit at 0.99 to prevent clipping
            Out.ar(outBus, sig);
        }).add;
        
        SynthDef(\specBand, { |inBus = 0, outBus = 0, freq = 1000, q = 1.0, level = 0.0, pan = 0.0, meterBus = -1, ampAtk = 0.01, ampRel = 0.08, thresh = 1.0, decimateRate = 48000, decimateSmoothing = 1, filterType = 1|
            var src, sig, gain, bwidth, meter, open, cutoff, dark, outSig, meter_db, meter_normalized, gate_level, gate_open;
            var lowpass, bandpass, highpass;

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
            Out.ar(outBus, outSig);
        }).add;

        freqs = [
            80, 150, 250, 350, 500, 630, 800, 1000,
            1300, 1600, 2000, 2600, 3500, 5000, 8000, 12000
        ];
        // allocate per-band meter buses as individual control buses
        ~meterBuses = freqs.collect { Bus.control(context.server, 1) };

        // Create an internal bus for summing all bands
        ~sumBus = Bus.audio(context.server, 2);
        
        ~bandGroup = Group.head(context.xg);
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
                    \inBus, context.in_b,
                    \outBus, ~sumBus,  // Output to sum bus instead of direct out
                    \freq, f,
                    \q, 6.0,
                    \level, -12.0,
                    \pan, (i.linlin(0, (freqs.size - 1).max(1), -0.5, 0.5)),
                    \meterBus, (~meterBuses[i].index),
                    \filterType, ftype
                ]
            )
        };

        context.server.sync;
        
        // Create final limiter synth to process the summed output
        ~finalLimiter = Synth.tail(
            ~bandGroup,
            \finalLimiter,
            [
                \inBus, ~sumBus,
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
    }

    // ---- Teardown ------------------------------------------------------------
    free {
        if(~finalLimiter.notNil) { ~finalLimiter.free; ~finalLimiter = nil; };
        if(~bands.notNil) { ~bands.do({ |x| x.free }); ~bands = nil; };
        if(~bandGroup.notNil) { ~bandGroup.free; ~bandGroup = nil; };
        if(~sumBus.notNil) { ~sumBus.free; ~sumBus = nil; };
        if(~meterBuses.notNil) { ~meterBuses.do({ |b| if(b.notNil) { b.free } }); ~meterBuses = nil; };
        super.free;
    }
}


