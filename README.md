# macunit — Multiply-Accumulate Unit with AXI-Stream Handshake

A personal IC design project exploring the fundamental building block of AI accelerators and inference engines: a pipelined Multiply-Accumulate (MAC) unit.

📄 **Full writeup / design documentation:** [IC Project 1: MAC Unit Documentation](https://docs.google.com/document/d/1UoCRIFNNci7FxWnKNwOGujuK3Nf-7zGUwzDJemCEfBY/edit?usp=sharing)

## Overview

This repo implements a **5-stage pipelined MAC engine** built around:

- **Radix-4 (Modified Booth) encoding** for partial-product generation
- A **Dadda adder tree** (Dadda multiplier) to compress partial products efficiently
- An **AXI-Stream skid buffer** handshake at the interface, so the unit can slot into a larger streaming datapath (e.g. an inference/accelerator pipeline) without stalling upstream producers

The project is carried end-to-end: RTL design → functional verification → FPGA synthesis (Intel MAX 10 / Quartus) → full ASIC hardening on the Sky130 PDK via [LibreLane](https://github.com/librelane/librelane).

## Repository Structure

| Path | Description |
|---|---|
| `mac_engine_2.sv` | Top-level MAC engine RTL (5-stage pipeline) |
| `dadda_tree_gen.sv` | Generated Dadda adder tree partial-product compressor |
| `dadda_tree_generator.py` | Python generator script that emits `dadda_tree_gen.sv` for a given operand width |
| `axi_skid_buffer.sv` | AXI-Stream skid buffer used for handshake/backpressure at the I/O boundary |
| `mac_verification/` | Testbench(es), golden model, and simulation artifacts |
| `config.json` | LibreLane flow configuration for the Sky130 ASIC hardening flow |
| `RUN_2026-07-28_11-52-35/` | A recorded LibreLane run (logs, reports, layout artifacts) |
| `Makefile` | Single entry point for simulation, linting, FPGA synthesis, and the ASIC (LibreLane) flow — see the [User Guide](USER_GUIDE.md) |

## Getting Started

See **[USER_GUIDE.md](USER_GUIDE.md)** for full environment setup and step-by-step instructions for:

- Running functional verification (Icarus Verilog / Verilator / GTKWave)
- Running the FPGA synthesis flow (Intel Quartus, MAX 10)
- Running the ASIC implementation flow (LibreLane, Sky130 PDK)

Quick reference once your environment is set up:

```bash
make run          # compile + simulate the testbench
make lint         # lint RTL with Verilator
make flow         # run the full LibreLane ASIC flow
make parse-asic   # print area/timing/power/DRC-LVS summary from the latest LibreLane run
```

## Status

Actively evolving — RTL, verification, and PPA metrics are being iterated on. See the linked writeup for design rationale, pipeline breakdown, and results.

## Author

Thein Hong Yi — Universiti Teknologi Malaysia (UTM)
