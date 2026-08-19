# CDC Foundations

A SystemVerilog asynchronous FIFO demonstrating fundamental clock-domain crossing (CDC) techniques for transferring multi-bit data between independently clocked domains.

The design uses dual-clock storage, binary and Gray-coded pointers, two-stage pointer synchronizers, and domain-local full/empty generation. Verification exercises the FIFO across varying asynchronous clock relationships, pointer wraparound, boundary conditions, concurrent traffic, and reset behavior.

## Overview

Directly synchronizing every bit of a multi-bit bus does not guarantee a coherent destination value. Individual bits can be sampled at different points in their transitions, potentially producing a combination that never existed in the source domain.

This asynchronous FIFO avoids directly synchronizing the payload bus. Instead:

1. Data is written into shared storage using the write clock.
2. The write pointer advances and is converted to Gray code.
3. The registered Gray-coded write pointer crosses into the read domain through a two-stage synchronizer.
4. The read domain uses the synchronized pointer to determine whether unread data is available.
5. The read side accesses the stored payload only after the control information has safely propagated.

The reverse process communicates read progress back to the write domain.

Only the Gray-coded pointers cross clock domains. Binary pointers remain local to their respective domains.

## Interface

The FIFO is parameterized by data width and address width:

```systemverilog
parameter int DATA_WIDTH = 32;
parameter int ADDR_WIDTH = 3;
```

FIFO depth is:

```text
DEPTH = 2^ADDR_WIDTH
```

With the default parameters, the FIFO stores eight 32-bit entries.

### Write domain

```text
wr_clk      Write-domain clock
wr_en       Write request
wr_data     Input data
full        FIFO cannot currently accept another write
```

A write occurs only when:

```systemverilog
wr_en && !full
```

### Read domain

```text
rd_clk      Read-domain clock
rd_en       Read request
rd_data     Registered read result
empty       FIFO currently contains no readable entries
```

A read occurs only when:

```systemverilog
rd_en && !empty
```

`rd_data` is registered on a successful read. The value of `rd_data` alone does not indicate validity; read validity is determined by the FIFO protocol and whether a legal read occurred.

## Pointer Architecture

Each domain maintains both a binary pointer and a Gray-coded pointer.

For an address width of `N`, each pointer is `N + 1` bits wide:

```systemverilog
localparam int PTR_WIDTH = ADDR_WIDTH + 1;
```

The lower `ADDR_WIDTH` bits select a memory location. The additional bit tracks pointer wraparound and allows the design to differentiate otherwise equivalent memory addresses to determine if the FIFO is full or empty.

For example, with `ADDR_WIDTH = 3`:

```text
0_101
1_101
```

both address `mem[5]`, but represent different logical pointer positions.

### Binary pointers

Binary pointers are used locally because incrementing and indexing memory are straightforward in binary.

The write pointer advances only after a legal write:

```systemverilog
wr_bin_next = wr_bin + PTR_WIDTH'(wr_en && !full);
```

The read pointer similarly advances only after a legal read:

```systemverilog
rd_bin_next = rd_bin + PTR_WIDTH'(rd_en && !empty);
```

### Gray-coded pointers

Before pointer state is communicated across a clock-domain boundary, the next binary pointer is converted to Gray code:

```systemverilog
gray = binary ^ (binary >> 1);
```

Adjacent Gray-code values differ by only one bit, limiting the multi-bit transition ambiguity that would occur if a binary counter were synchronized directly.

The Gray-coded pointers are registered in their source domains before crossing the CDC boundary. This prevents combinational encoding glitches from being presented directly to the destination synchronizers.

## Pointer Synchronization

Each Gray-coded pointer crosses into the opposite domain through a two-stage synchronizer.

Write pointer into read domain:

```text
wr_gray
   |
   v
wr_gray_sync1
   |
   v
wr_gray_sync2
```

Read pointer into write domain:

```text
rd_gray
   |
   v
rd_gray_sync1
   |
   v
rd_gray_sync2
```

The first synchronizer stage may encounter metastability when sampling the asynchronous input. The second stage provides additional settling time before the synchronized value is used by functional logic.

The synchronizer does not detect or correct logically incorrect data. Its purpose is to reduce the probability that metastability propagates into functional logic.

Only the second synchronizer stage is used for FIFO state decisions.

## Full and Empty Detection

Each status flag is generated entirely within the domain that consumes it.

### Empty

`empty` belongs to the read domain.

The FIFO will be empty after the current read-domain operation when the next read pointer equals the synchronized write pointer:

```systemverilog
empty_next = (rd_gray_next == wr_gray_sync2);
```

### Full

`full` belongs to the write domain.

Full detection compares the next write pointer against the appropriately wrap-adjusted synchronized read pointer:

```systemverilog
full_next =
    (wr_gray_next ==
        {
            ~rd_gray_sync2[ADDR_WIDTH:ADDR_WIDTH-1],
             rd_gray_sync2[ADDR_WIDTH-2:0]
        });
```

This is the standard relationship for the power-of-two Gray-pointer FIFO architecture used here.

Because remote pointer information must cross synchronizers, `full` and `empty` can be conservative.

For example, after the writer adds the first entry, the read domain may continue reporting `empty` for several read-clock cycles while the updated write pointer propagates through the synchronizer. Similarly, the write domain may temporarily continue reporting `full` after the reader frees an entry.

These delays reduce throughput temporarily but do not compromise correctness.

## Reset Strategy

The FIFO accepts a common active-low reset:

```text
reset_n
```

Reset assertion is asynchronous, while reset deassertion is synchronized independently to each clock domain.

```text
                       +--> write reset synchronizer --> wr_reset_n
reset_n ---------------+
                       +--> read reset synchronizer  --> rd_reset_n
```

Each reset synchronizer uses two sequential stages. This allows either domain to enter reset immediately while ensuring that it leaves reset only relative to its own local clock.

The read and write domains are not required to leave reset simultaneously.

After reset:

```text
wr_bin  = 0
wr_gray = 0
full    = 0

rd_bin  = 0
rd_gray = 0
empty   = 1
rd_data = 0
```

The memory array itself is not cleared. FIFO validity is determined by pointer and flag state, so stale physical memory contents are not considered valid entries after reset. `rd_data` is set to zero just to give it a known state upon reset, but this has no functional effect.

## Storage

The payload is stored in:

```systemverilog
logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];
```

Writes occur under `wr_clk`, while reads occur under `rd_clk`.

The FIFO does not synchronize every bit of `wr_data` into the read domain. Instead, complete words are placed into storage, and synchronized pointer state communicates when those locations are available to the other domain.

Correct physical implementation therefore requires storage capable of the required independent-clock read/write behavior, such as an appropriate dual-port memory structure or equivalent implementation.

The exact inferred or instantiated memory structure is technology-dependent and is not addressed by this project.

## Verification

The FIFO is verified with a self-checking SystemVerilog testbench. AI assistance was used to generate and refine portions of the SystemVerilog verification testbench. All verification code was  manually reviewed and exercised through simulation and regression.

A reference queue tracks accepted transactions:

```text
accepted write -> push expected data
accepted read  -> pop and compare expected data
```

The scoreboard changes only for legal transactions:

```systemverilog
write_fire = wr_en && !full;
read_fire  = rd_en && !empty;
```

### Asynchronous clocks

Write and read clock periods are randomized independently at the beginning of each simulation run.

The clocks then remain fixed for that run, providing realistic free-running clocks while allowing different regression seeds to exercise different frequency ratios and phase relationships.

This produces cases where:

- the writer is faster than the reader,
- the reader is faster than the writer,
- clock edges occur at varying relative phases.

Keeping the selected periods fixed during an individual simulation also makes failures reproducible from the simulation seed.

### Directed verification

The testbench checks:

- reset state,
- basic ordered transfers,
- FIFO fill behavior,
- FIFO drain behavior,
- overflow rejection,
- underflow rejection,
- pointer wraparound across multiple complete FIFO cycles,
- reset while entries are queued,
- concurrent asynchronous reads and writes.

A longer concurrent test performs 100 writes and 100 reads while both clock domains operate independently.

### Regression

The design is exercised across 1200 regression seeds (seeds 1-1200) so that each run can use a different asynchronous clock relationship.

Successful reads are checked against the reference queue to verify that data is neither lost, duplicated, reordered, nor incorrectly accepted during full/empty conditions.

### Waveform inspection

Waveforms were also inspected to confirm the expected CDC propagation sequence.

For a write becoming visible to the read domain:

```text
accepted write
    |
    v
wr_gray changes
    |
    v
wr_gray_sync1
    |
    v
wr_gray_sync2
    |
    v
empty updates
```

The corresponding read-pointer propagation into the write domain was also inspected.

The observed synchronization delay is intentional: remote state is not expected to become visible immediately.

## CDC Properties Demonstrated

This project demonstrates several core CDC principles:

- independently clocked domains cannot assume deterministic sampling relationships,
- metastability cannot be eliminated simply by digital logic,
- two-stage synchronizers reduce the probability of metastability reaching functional logic,
- synchronizers do not repair logically invalid data,
- multi-bit buses should not generally be synchronized independently bit-by-bit,
- Gray coding allows incrementing pointer state to cross a CDC boundary with only one logical bit changing per step,
- CDC source signals should be registered to avoid propagating combinational glitches,
- remote-domain information may safely arrive late when the resulting decision is conservative,
- reset deassertion must be synchronized independently to each clock domain,
- asynchronous FIFOs separate payload storage from synchronized control-state transfer.

## Limitations

This project is intended to demonstrate CDC architecture and verification fundamentals rather than provide production-ready asynchronous FIFO IP.

Notable limitations include:

- RTL simulation does not model the analog behavior of metastability.
- The implementation assumes a power-of-two FIFO depth.
- The full-detection expression assumes `ADDR_WIDTH >= 2`.
- The physical implementation of the dual-clock storage is technology-dependent.
- Production implementation would require appropriate CDC analysis and timing/physical constraints, including consideration of Gray-pointer inter-bit skew.
- Formal CDC verification and technology-specific memory characterization are outside the scope of this project.

## Files

```text
rtl/
    async_fifo.sv

tb/
    async_fifo_tb.sv
```

The RTL contains the asynchronous FIFO implementation, while the testbench provides directed and randomized self-checking verification.

Note: This README was generated with AI assistance and manually verified by the author.