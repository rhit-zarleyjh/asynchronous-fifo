# CDC Foundations

This SystemVerilog asynchronous FIFO demonstrates fundamental clock-domain crossing (CDC) techniques. Two external devices that do not share a clock do not know how to communicate with each other. One may send data at a certain rate, and the other may be reading far less frequently, missing data. There is also the consideration of metastability in the registers we use to store data, where changing inputs may cause unknown outputs temporarily. This may cause issues with downstream logic.

The design uses dual-clock storage, binary and Gray-coded pointers, two-stage pointer synchronizers, and domain-local full/empty generation. Essentially, we transform standard pointers, which allow us to read to and write from memory, into Gray-coded pointers. This allows us to safely change our pointer value such that, even with metastability, we will never pass a dangerous value downstream, where it might cause true issues. Instead, we will either pass a fresh value, or a past value, both of which will be safe. The input-side domain checks for the FIFO being full to prevent the module claiming to be able to hold data while being full, resulting in data loss. Likewise, the output-side domain checks for the FIFO being empty, preventing us from accidentally outputting a value that was never truly given.

Developing this project changed my understanding of CDC from a generic register-level technique to something that requires reasoning about which information can safely cross a domain boundary and how delated remote state affects correctness. In particular, this project taught me why independently synchronizing a multi-bit bus is unsafe, why synchronization latency is an acceptable tradeoff for safety, and why Gray-coded pointers naturally fit this situation.

```
                                       ┌──────────────────┐                                        
                      wr_data─────────►│       MEM[]      ├──────────►rd_data                      
                                       │DATA_WIDTH x DEPTH│                                        
                                       └▲───▲────────▲───▲┘                                        
                                        │   │        │   │                                         
                                        │   │        │   │                                         
          ┌────────────────────────────full │        │  empty──────────────────────────┐           
          │        ┌────────────────────────┘        └────────────────────────┐        │           
          │        │          ┌────┐                           ┌────┐         │        │           
          │    write_ptr──────►2-FF├─────────────────────┐     │2-FF◄──────read_ptr    │           
          │        │          │Sync│ ┌───────────────────┼─────┤Sync│         │        │           
          │        │          └────┘ │                   │     └────┘         │        │           
          │ ┌──────┴─────┐           │                   │               ┌────┴──────┐ │           
          └─┤Write Domain│           │                   │               │Read Domain┼─┘           
            │            │        Synced               Synced            │           │             
wr_clk─────►│    Full    ◄───────read_ptr             write_ptr──────────►   Empty   │◄──────rd_clk
            │   Control  │                                               │  Control  │             
            └────────────┘                                               └───────────┘             
          WRITE CLOCK DOMAIN                                           READ CLOCK DOMAIN           
```

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