# UART Controller in Verilog HDL

Design and verification of a synthesizable UART (Universal Asynchronous Receiver Transmitter) with a programmable-by-parameter baud rate, optional even/odd parity, 16x oversampled reception, and parity, framing and break error detection.

Project review work for M.Tech VLSI Design, Amrita Vishwa Vidyapeetham.

**Team:** K Sai Akhil, Indiresh, Hemanth B R, Hanuman K, B Vallabha

## Overview

A UART converts parallel bytes into a serial bit stream and back. No clock is sent on the wire: both ends are configured to the same baud rate, each runs from its own local clock, and the receiver resynchronizes on the falling edge of every start bit.

This design targets a 50 MHz system clock at 115,200 baud with 8 data bits, optional parity and 1 stop bit.

### UART vs SPI vs I2C

| | UART | SPI | I2C |
| --- | --- | --- | --- |
| Signal wires | 2 (TX, RX) | 4 | 2 (SDA, SCL) |
| Clock line | None | From master | From master |
| Duplex | Full | Full | Half |
| Topology | Point-to-point | Master + chip selects | Multi-device, addressed |
| Typical speed | 9.6 kbps to ~3 Mbps | Tens of Mbps | 100 kbps to 3.4 Mbps |
| Error check | Parity | None built in | ACK bit |

## Features

- Full-duplex: TX and RX share only the clock, reset, baud ticks and parity settings
- Baud generator derived from parameters (`CLK_FREQ`, `BAUD_RATE`, `OVERSAMPLE`)
- 8-bit data, LSB first, 1 start bit, 1 stop bit
- Optional parity, selectable even or odd
- 16x oversampling receiver with false-start (glitch) rejection
- Detection of parity error, framing error and break condition
- All logic is synchronous to a single clock; ticks are enables, not divided clocks

## Repository structure

| File | Module | Description |
| --- | --- | --- |
| `baudgenerator.v` | `baudrate` | Two free-running counters producing `tx_tick` (1x baud) and `rx_tick` (16x baud) |
| `uart_tx.v` | `uart_tx` | Transmitter FSM: IDLE, START, DATA, PARITY, STOP |
| `uart_rx.v` | `uart_rx` | Receiver FSM: IDLE, START, DATA, PARITY, STOP, WAIT |
| `uart_top.v` | `uart_top` | Top level wiring the baud generator, transmitter and receiver together |

## Architecture

```
            +-----------+  tx_tick   +---------+
 clk,rst_n->| baudrate  |----------->| uart_tx |--> txd
            |           |  rx_tick   +---------+
            |           |----------->+---------+
            +-----------+            | uart_rx |<-- rxd
                                     +---------+--> rx_data, rx_valid,
                                                    par_err, frm_err, brk
```

`uart_top` has no FIFOs, register interface or input synchronizer. `txd` comes straight from `uart_tx` and `rxd` goes straight into `uart_rx`.

## Module details

### Baud generator (`baudrate`)

```
TX_DIV = CLK_FREQ / BAUD_RATE                  = 434  (50 MHz, 115200)
RX_DIV = CLK_FREQ / (BAUD_RATE * OVERSAMPLE)   = 27
```

- `tx_tick` is a one-clock pulse every `TX_DIV` cycles (one bit period)
- `rx_tick` is a one-clock pulse every `RX_DIV` cycles (16 per bit period)

With integer division the effective receive bit time is 27 x 16 = 432 clocks (8.64 us), about +0.47% faster than ideal, well within the roughly +/-2% per-device budget.

| Target baud | Divisor (50 MHz) | Actual baud | Error |
| --- | --- | --- | --- |
| 9,600 | 326 | 9,586 | -0.15% |
| 19,200 | 163 | 19,172 | -0.15% |
| 57,600 | 54 | 57,870 | +0.47% |
| 115,200 | 27 | 115,741 | +0.47% |
| 230,400 | 14 | 223,214 | -3.12% (out of budget) |
| 921,600 | 3 | 1,041,667 | +13.03% (out of budget) |

Divisors are for the 16x receive tick: `divisor = f_clk / (16 x baud)`.

### Transmitter (`uart_tx`)

| State | Action |
| --- | --- |
| IDLE | Line high; wait for `tx_start`; latch data and compute parity |
| START | Drive 0 for one bit period |
| DATA | Drive `shreg[0]`, shift right each bit period, count 8 bits (LSB first) |
| PARITY | Drive the parity bit (only if `par_en = 1`) |
| STOP | Drive 1 for one bit period, then return to IDLE |

- Parity: `^tx_data ^ par_odd` (reduction XOR, inverted for odd parity)
- `tx_busy = (state != IDLE)`
- `txd` is a register, so glitches cannot reach the pin; reset value is 1 (idle high)

### Receiver (`uart_rx`)

| State | Action |
| --- | --- |
| IDLE | Wait for `rxd` to fall |
| START | After 8 ticks (mid-bit) re-check: low means valid start, high means glitch, back to IDLE |
| DATA | Every 16 ticks shift `rxd` in from the left, 8 times (LSB first) |
| PARITY | Capture the parity bit (only if `par_en = 1`) |
| STOP | Sample the stop bit; output byte, `rx_valid` and error flags |
| WAIT | After a framing error or break, wait for the line to return high |

Error flags, refreshed at each stop bit:

| Flag | Meaning |
| --- | --- |
| `par_err` | `^shreg ^ par_odd ^ par_bit` is 1 (only when parity is enabled) |
| `frm_err` | Stop bit sampled as 0 |
| `brk` | Stop bit low, data is `0x00`, and parity bit low (if enabled) |

`rx_valid` is a one-clock pulse.

## Frame format

Example: `0x4B`, 8E1 (8 data bits, even parity, 1 stop bit), LSB first.

```
idle  start  D0 D1 D2 D3 D4 D5 D6 D7  parity  stop  idle
  1     0     1  1  0  1  0  0  1  0     0      1     1
```

`0x4B = 0100 1011` has four 1s, so the even parity bit is 0. An 8E1 frame is 11 bits (72.7% line efficiency); 8N1 is 10 bits.

## Receiver clock tolerance

The receiver samples at the middle of every bit using 16x oversampling. Clock mismatch shifts each sample slightly more, so the stop bit (about 9.5 bit times after the start edge) drifts the most. Half a bit of slack over 9.5 bits is roughly 5%; after sampling uncertainty this leaves about 4.5% total mismatch, or about +/-2% per device. In the project's analysis, +5% mismatch still decodes correctly but marginally, and +6% moves the stop sample into D7 and causes a framing error.

## Ports (`uart_top`)

| Port | Dir | Width | Description |
| --- | --- | --- | --- |
| `clk` | in | 1 | System clock (50 MHz by default) |
| `rst_n` | in | 1 | Active-low reset |
| `rxd` | in | 1 | Serial receive input |
| `txd` | out | 1 | Serial transmit output |
| `tx_data` | in | 8 | Byte to transmit |
| `tx_start` | in | 1 | Pulse to start a transmission (accepted in IDLE) |
| `par_en` | in | 1 | Enable parity |
| `par_odd` | in | 1 | 1 = odd parity, 0 = even parity |
| `tx_busy` | out | 1 | High while a frame is being sent |
| `rx_data` | out | 8 | Received byte |
| `rx_valid` | out | 1 | One-clock pulse when a byte has been received |
| `par_err` | out | 1 | Parity error |
| `frm_err` | out | 1 | Framing error |
| `brk` | out | 1 | Break condition |

Parameters: `CLK_FREQ` (default 50,000,000), `BAUD_RATE` (default 115,200), `OVERSAMPLE` (default 16).

## Simulation

The design is verified in loopback (`txd` connected to `rxd` in the testbench) with the free [Icarus Verilog](https://steveicarus.github.io/iverilog/) simulator:

```sh
iverilog -g2005 -o sim uart_top_tb.v uart_top.v baudgenerator.v uart_tx.v uart_rx.v
vvp sim
```

The testbench is not yet part of this repository. It generates a 50 MHz clock, holds reset for 100 ns, sends `8'hA5` and `8'h3C` with parity disabled, and prints each received byte with its `par_err`, `frm_err` and `brk` flags.

Waveform results for one `0x4B` frame in loopback:

- `txd` falls at 0.25 us; each bit lasts 8.64 us (27 x 16 x 20 ns)
- The receiver enters DATA at 4.43 us, half a bit after the start edge
- `rx_valid` pulses at 90.83 us with `rx_data = 0x4B`

## Future scope

- Fractional baud-rate divider for lower baud error and higher speeds
- Majority-vote sampling around the bit centre for better noise tolerance
- Input synchronizer on `rxd` (two flip-flops) for metastability robustness
- Configurable data bits (5 to 9) and stop bits (1, 1.5, 2)
- FIFO buffering for continuous transfers
- Expanded verification: parity-enabled cases, framing error, break detection and clock-skew scenarios

## Author

K Sai Akhil, M.Tech VLSI Design, Amrita Vishwa Vidyapeetham
