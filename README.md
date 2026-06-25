# Fault-Tolerant-I2C-Master-For-CUBESATS
# Fault Tolerant I2C Master Controller for CubeSat Applications

> A radiation-hardened I2C Master Controller implemented in Verilog HDL, designed to survive the harsh radiation environment of Low Earth Orbit.

[![Language](https://img.shields.io/badge/HDL-Verilog-blue)](https://en.wikipedia.org/wiki/Verilog)
[![Tool](https://img.shields.io/badge/Tool-Xilinx%20Vivado-orange)](https://www.xilinx.com/products/design-tools/vivado.html)
[![Standard](https://img.shields.io/badge/Standard-IEEE%201364-green)](https://standards.ieee.org/)
[![Status](https://img.shields.io/badge/Status-Simulation%20Verified-brightgreen)]()

---

## Table of Contents

- [Overview](#overview)
- [The Problem](#the-problem)
- [Architecture](#architecture)
  - [System Block Diagram](#system-block-diagram)
  - [9-State FSM](#9-state-fsm)
  - [Digital Temporal Voting Filter](#digital-temporal-voting-filter)
  - [Clock Division](#clock-division)
- [Key Features](#key-features)
- [Repository Structure](#repository-structure)
- [Getting Started](#getting-started)
  - [Prerequisites](#prerequisites)
  - [Running the Simulation](#running-the-simulation)
- [Test Cases & Results](#test-cases--results)
- [Module Interface](#module-interface)
- [Design Parameters](#design-parameters)
- [Future Work](#future-work)
- [Team](#team)
- [References](#references)

---

## Overview

This project presents the design and simulation of a custom, **radiation-hardened I2C Master Controller** for CubeSat telemetry systems. Standard software-driven I2C controllers are highly vulnerable to **Single Event Upsets (SEUs)** and **Single Event Transients (SETs)** caused by high-energy cosmic particles in Low Earth Orbit (LEO).

The proposed solution replaces fragile software bit-banging with a deterministic **9-state Finite State Machine (FSM)** and integrates a **3-stage Digital Temporal Voting Filter** to autonomously identify and reject sub-cycle radiation-induced voltage spikes — all without any physical shielding.

Simulated fault-injection testing confirms the controller successfully traps a **15-nanosecond radiation strike** and maintains data transmission without entering infinite wait states.

---

## The Problem

Almost every CubeSat uses the I2C protocol to connect its On-Board Computer (OBC) to critical telemetry sensors (gyroscopes, magnetometers, temperature gauges). I2C is simple, space-efficient, and cost-effective — but it is fundamentally fragile in a radiation environment.

A single high-energy particle strike can:
- Flip a bit on the SDA wire, creating a false voltage spike
- Be misinterpreted as a false STOP condition or an ACK failure
- **Permanently lock up the sensor bus**, corrupting vital mission data

Traditional physical shielding (lead, aluminum casing) is impossible on a CubeSat due to strict mass and volume constraints. This project implements a **purely digital, embeddable shielding solution** instead.

---

## Architecture

### System Block Diagram

The architecture is divided into three primary modules:

```
┌─────────────────────┐     ┌───────────────────────┐     ┌────────────────────────┐
│   HOST INTERFACE    │     │    I2C MASTER FSM     │     │      PHYSICAL I/O      │
│   (Capture Logic)   │────▶│      (The Brain)      │────▶│  (Drivers & Timing)   │
│                     │     │                       │     │                        │
│ • Latches 7-bit     │     │ • 9-State Mealy FSM   │     │ • SCL Generation       │
│   address           │     │ • Negative-edge       │     │ • Tri-State SDA Driver │
│ • Latches 8-bit     │     │   triggered           │     │ • Temporal Voting      │
│   payload           │     │ • Deterministic       │     │   Filter (Glitch Guard)│
│ • Clock sync        │     │   execution           │     │                        │
└─────────────────────┘     └───────────────────────┘     └────────────────────────┘
```

### 9-State FSM

The controller's core logic is a **9-state Mealy FSM** triggered on the **negative edge** of the I2C clock (strictly obeying the I2C spec: data must be stable while SCL is high).

| State | Description |
|---|---|
| `IDLE` (0) | Default state. Bus held High-Z. Awaits `enable` trigger. |
| `START` (1) | Pulls SDA low while SCL is high — generates START condition. |
| `ADDRESS` (2) | Serially transmits 7-bit slave address + 1-bit R/W over 8 clock cycles. |
| `READ_ACK` (3) | Releases bus, samples SDA for slave acknowledgment (ACK = 0). |
| `WRITE_DATA` (4) | Shifts out 8-bit payload to the slave. |
| `WRITE_ACK` (5) | Processes the slave's acknowledgment for the data byte. |
| `READ_DATA` (6) | Samples 8 incoming bits from the slave into `data_out`. |
| `READ_ACK2` (7) | Master sends ACK/NACK after receiving data byte. |
| `STOP` (8) | Releases SDA high while SCL is high — generates STOP condition. Returns to IDLE. |

### Digital Temporal Voting Filter

The most critical innovation in this design. A high-energy particle striking the SDA line creates a transient voltage spike that a standard controller would misread as a NACK or STOP condition, killing the transaction.

**How it works:**

```
Physical SDA ──▶ [ 3-Stage Shift Register ] ──▶ [ Majority Vote Logic ] ──▶ filtered_sda (to FSM)
                      S1 ──▶ S2 ──▶ S3
```

The raw SDA pin is sampled continuously at **50 MHz** into a 3-bit shift register (`sda_sr`). The `filtered_sda` output — which is the *only* signal the FSM ever reads — updates **only if all 3 consecutive samples agree**:

```verilog
// Strict majority voting — only 3'b111 or 3'b000 cause an update
if (sda_sr == 3'b111)      filtered_sda <= 1'b1;  // Stable HIGH
else if (sda_sr == 3'b000) filtered_sda <= 1'b0;  // Stable LOW
// Any mixed pattern (e.g., 3'b010) = transient detected → hold last value
```

This means any pulse shorter than **60 nanoseconds** (3 × 20ns clock cycles) is automatically rejected as radiation noise. The FSM remains unaware that any glitch occurred.

### Clock Division

To prevent the FSM from reading the filter output before it has stabilized, the 50 MHz system clock is divided by 20 to generate a **2.5 MHz internal I2C clock** (400 ns period).

```
Filter latency:   60 ns  (3 samples @ 50 MHz)
I2C clock period: 400 ns (20 × 20 ns)
Safety margin:    6.7× — eliminates all read-before-write race conditions
```

---

## Key Features

- **Hardware-Driven Determinism** — Protocol managed entirely by a hardware FSM, not software interrupts. Eliminates delta-cycle timing violations and race conditions.
- **Radiation Glitch Filtering** — 3-stage Temporal Voting Filter rejects transient spikes under 60 ns, protecting against Single Event Transients (SETs).
- **Correct Open-Drain Implementation** — Tri-state SDA driver prevents bus contention; the controller only drives `0` or releases to High-Z (`z`), never forces a `1`.
- **No Physical Shielding Required** — Purely digital solution; no custom analog PCB components needed.
- **Verified via Fault Injection** — Tested against artificially injected 15 ns radiation strikes at the most critical transaction phase (slave acknowledgment).
- **Standard I2C Compatible** — Supports standard 7-bit addressing with Read and Write operations.

---

## Repository Structure

```
.
├── src/
│   └── i2c_master.v          # Top-level I2C Master Controller (RTL Design)
├── sim/
│   └── tb_i2c_master.v       # Comprehensive Verilog Testbench
├── docs/
│   └── I2C_Documentation.pdf # Full project report
└── README.md
```

---

## Getting Started

### Prerequisites

- **Xilinx Vivado Design Suite** (2020.x or later recommended)
- Basic knowledge of Verilog HDL simulation

### Running the Simulation

1. **Clone the repository:**
   ```bash
   git clone https://github.com/<your-username>/<repo-name>.git
   cd <repo-name>
   ```

2. **Open Vivado** and create a new project.

3. **Add sources:**
   - Add `src/i2c_master.v` as a **Design Source**.
   - Add `sim/tb_i2c_master.v` as a **Simulation Source**.

4. **Set the testbench as the top module** for simulation.

5. **Run Behavioral Simulation.** The testbench will automatically execute all three test cases sequentially:
   - Write transaction to address `0x50` with data `0xAB`
   - Fault injection (15 ns radiation strike)
   - Read transaction from address `0x50` (slave returns `0xC3`)

6. **Observe the waveforms.** Key signals to monitor:
   - `i2c_sda`, `i2c_scl` — Physical bus lines
   - `filtered_sda` — Filter output (should remain stable during glitch)
   - `data_out` — Should resolve to `0xC3` after the read transaction
   - `ready` — Goes high when FSM returns to IDLE

---

## Test Cases & Results

### Test Case 1: Standard Write Operation
- **Address:** `0x50` | **Data:** `0xAB` | **R/W:** `0` (Write)
- **Result ✅** — FSM generates correct START, transmits address + data byte, receives ACK, generates clean STOP condition.

### Test Case 2: Standard Read Operation
- **Address:** `0x50` | **Slave Data:** `0xC3` | **R/W:** `1` (Read)
- **Result ✅** — Master releases SDA to High-Z during data phase, correctly captures all 8 bits from the simulated slave, `data_out` resolves to `0xC3`.

### Test Case 3: Radiation Fault Injection
- **Injection:** SDA line force-driven HIGH for **15 ns** during the slave ACK phase
- **Result ✅** — Physical `i2c_sda` shows a sharp spike. `filtered_sda` **remains completely stable at 0**. Transaction completes normally — no deadlock, no restart required.

---

## Module Interface

```verilog
module i2c_master (
    input  wire       clk,        // System clock (50 MHz)
    input  wire [6:0] addr,       // 7-bit slave address
    input  wire [7:0] data_in,    // 8-bit write payload
    input  wire       rst,        // Active-high synchronous reset
    input  wire       enable,     // Assert high to start a transaction
    input  wire       rw,         // 0 = Write, 1 = Read
    output reg  [7:0] data_out,   // Received data (valid after read transaction)
    output wire       ready,      // High when FSM is IDLE and ready for next command
    inout             i2c_scl,    // I2C Serial Clock Line (open-drain)
    inout             i2c_sda     // I2C Serial Data Line (open-drain)
);
```

---

## Design Parameters

| Parameter | Value | Description |
|---|---|---|
| System Clock | 50 MHz | FPGA input clock frequency |
| I2C Clock | 2.5 MHz | Internal clock after division |
| Clock Divider | 20 | `DIVIDE_BY` localparam |
| Filter Window | 60 ns | 3 samples × 20 ns per sample |
| Filter Stages | 3 | Shift register depth (`sda_sr`) |
| Max Rejectable Glitch | < 60 ns | Pulses shorter than this are filtered |
| FSM States | 9 | IDLE through STOP |
| Address Width | 7 bits | Standard I2C addressing |
| Data Width | 8 bits | Single byte per transaction |

---

## Future Work

1. **Deadlock Recovery Sequence** — Implement an autonomous 9-clock-cycle SCL generation sequence to force a stuck slave to release SDA if a transaction hangs indefinitely (to handle permanent SEUs, not just transient SETs).

2. **Multi-Master Arbitration** — Expand the FSM to support multi-master collision detection and bus arbitration, enabling multiple redundant OBCs to share the same telemetry bus.

3. **CRC Integration** — Add hardware-level Cyclic Redundancy Check (CRC) computation on outgoing and incoming data bytes for end-to-end data integrity verification.

4. **FPGA Deployment** — Port and test the verified IP core on a physical space-grade FPGA (e.g., Xilinx Kintex UltraScale+) for hardware-in-the-loop validation.

---

## Team

**B.V. Raju Institute of Technology** — Department of Electronics & Communication Engineering  
*(Affiliated to JNTU, Hyderabad)*

| Name | Roll Number |
|---|---|
| N. Sathwik Reddy | 24211A04G1 |
| Odugu Sruthi | 24211A04G8 |
| P.V. Lalith Surya | 24211A04G9 |

**Project Guide:** Dr. K. Madhava Rao, M.Tech, Ph.D (Assistant Professor)  
**HOD:** Dr. B R Sanjeeva Reddy, B.E, M.Tech, PhD  
**Academic Year:** 2025–2026

---

## References

1. Texas Instruments — *I2C Stuck Bus: Prevention and Workarounds*, SCPA069, Mar. 2003
2. NXP Semiconductors — *UM10204: I2C-bus Specification and User Manual*, 7th Rev., Oct. 2021
3. J. Bouwmeester et al. — *Survey on the implementation and reliability of CubeSat electrical bus interfaces*, CEAS Space Journal, 2016
4. A. Albalooshi et al. — *Fault Analysis and Mitigation Techniques of the I2C Bus for Nanosatellite Missions*, IEEE Access, 2023
5. O. T. Amer et al. — *Fault-Tolerant FPGA-Based System for Mitigating SEUs in Configuration and User Bits*, 2024
6. P. Maillard — *Radiation Effects in FPGAs and SoCs*, NSREC Short Course Archive, 2025

---

*Minor Project submitted in partial fulfillment of the requirements for the award of B.Tech in Electronics & Communication Engineering.*
