#!/usr/bin/env node
// Generates the dictation chime WAVs into Tinycast/Resources/DictationSounds/.
// Run once; the WAVs are committed, so building the app never needs Node.
// Zero dependencies — writes 16-bit mono 48 kHz PCM by direct sample synthesis.
//
//   node Scripts/gen-dictation-chimes.mjs

import { mkdirSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const outDir = join(root, "Tinycast", "Resources", "DictationSounds");
const rate = 48_000;
const peak = 0.28;

// A note is a sine with one quieter second partial and an exponential decay.
function note(samples, { start, duration, frequency, tau, amplitude }) {
  const first = Math.floor(start * rate);
  const last = Math.min(samples.length, first + Math.ceil(duration * rate));
  for (let i = first; i < last; i++) {
    const t = (i - first) / rate;
    const envelope = Math.exp(-t / tau) * (1 - Math.exp(-t / 0.002));
    const value =
      Math.sin(2 * Math.PI * frequency * t) +
      0.25 * Math.sin(2 * Math.PI * 2 * frequency * t);
    samples[i] += amplitude * envelope * value;
  }
}

// Start: two ascending soft notes, A5 then E6, the second overlapping the first's tail.
function startChime() {
  const samples = new Float64Array(Math.ceil(0.30 * rate));
  note(samples, { start: 0.0, duration: 0.14, frequency: 880, tau: 0.045, amplitude: 1 });
  note(samples, { start: 0.07, duration: 0.20, frequency: 1318.51, tau: 0.055, amplitude: 1 });
  return normalize(samples);
}

// Stop: the same pair resolved downward, E6 then A5, a single quiet gesture.
function stopChime() {
  const samples = new Float64Array(Math.ceil(0.28 * rate));
  note(samples, { start: 0.0, duration: 0.12, frequency: 1318.51, tau: 0.04, amplitude: 1 });
  note(samples, { start: 0.06, duration: 0.18, frequency: 880, tau: 0.06, amplitude: 1 });
  return normalize(samples);
}

function normalize(samples) {
  let largest = 0;
  for (const value of samples) largest = Math.max(largest, Math.abs(value));
  const gain = largest > 0 ? peak / largest : 0;
  const pcm = Buffer.alloc(samples.length * 2);
  for (let i = 0; i < samples.length; i++) {
    pcm.writeInt16LE(Math.round(Math.max(-1, Math.min(1, samples[i] * gain)) * 32767), i * 2);
  }
  return pcm;
}

function wav(pcm) {
  const header = Buffer.alloc(44);
  header.write("RIFF", 0);
  header.writeUInt32LE(36 + pcm.length, 4);
  header.write("WAVE", 8);
  header.write("fmt ", 12);
  header.writeUInt32LE(16, 16);
  header.writeUInt16LE(1, 20); // PCM
  header.writeUInt16LE(1, 22); // mono
  header.writeUInt32LE(rate, 24);
  header.writeUInt32LE(rate * 2, 28);
  header.writeUInt16LE(2, 32);
  header.writeUInt16LE(16, 34);
  header.write("data", 36);
  header.writeUInt32LE(pcm.length, 40);
  return Buffer.concat([header, pcm]);
}

mkdirSync(outDir, { recursive: true });
writeFileSync(join(outDir, "dictation-start.wav"), wav(startChime()));
writeFileSync(join(outDir, "dictation-stop.wav"), wav(stopChime()));
console.log(`Wrote dictation-start.wav and dictation-stop.wav to ${outDir}`);
