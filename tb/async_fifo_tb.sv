`timescale 1ns/1ps

module async_fifo_tb;

    localparam int DATA_WIDTH = 32;
    localparam int ADDR_WIDTH = 3;
    localparam int DEPTH      = 1 << ADDR_WIDTH;

    logic reset_n;

    logic wr_clk;
    logic wr_en;
    logic [DATA_WIDTH-1:0] wr_data;
    logic full;

    logic rd_clk;
    logic rd_en;
    logic [DATA_WIDTH-1:0] rd_data;
    logic empty;

    logic [DATA_WIDTH-1:0] expected_q[$];

    int wr_half_period;
    int rd_half_period;
    int rd_phase_offset;

    async_fifo #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) dut (
        .reset_n(reset_n),

        .wr_clk(wr_clk),
        .wr_en(wr_en),
        .wr_data(wr_data),
        .full(full),

        .rd_clk(rd_clk),
        .rd_en(rd_en),
        .rd_data(rd_data),
        .empty(empty)
    );

    // ------------------------------------------------------------
    // Randomized but fixed clock relationship for this simulation
    // ------------------------------------------------------------

    initial begin
        wr_half_period = $urandom_range(2, 10);
        rd_half_period = $urandom_range(2, 10);
        rd_phase_offset = $urandom_range(1, 9);

        $display(
            "CLOCK CONFIG: wr_period=%0d ns rd_period=%0d ns rd_phase=%0d ns",
            2 * wr_half_period,
            2 * rd_half_period,
            rd_phase_offset
        );
    end

    initial begin
        wr_clk = 1'b0;

        wait (wr_half_period != 0);

        forever #(wr_half_period)
            wr_clk = ~wr_clk;
    end

    initial begin
        rd_clk = 1'b0;

        wait (rd_half_period != 0);

        #(rd_phase_offset);

        forever #(rd_half_period)
            rd_clk = ~rd_clk;
    end

    // ------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------

    task automatic reset_dut();
        reset_n = 1'b0;
        wr_en   = 1'b0;
        rd_en   = 1'b0;
        wr_data = '0;

        expected_q.delete();

        repeat (3) @(posedge wr_clk);
        repeat (3) @(posedge rd_clk);

        reset_n = 1'b1;

        // Each domain requires two local clock edges to release
        // synchronized reset. Give one additional cycle of margin.
        repeat (3) @(posedge wr_clk);
        repeat (3) @(posedge rd_clk);
    endtask

    task automatic write_one(
        input logic [DATA_WIDTH-1:0] data
    );
        while (full)
            @(posedge wr_clk);

        @(negedge wr_clk);
        wr_data = data;
        wr_en   = 1'b1;

        @(posedge wr_clk);

        // wr_en && !full is true at this edge.
        expected_q.push_back(data);

        @(negedge wr_clk);
        wr_en = 1'b0;
    endtask

    task automatic read_one();
        logic [DATA_WIDTH-1:0] expected;

        while (empty)
            @(posedge rd_clk);

        @(negedge rd_clk);
        rd_en = 1'b1;

        @(posedge rd_clk);

        expected = expected_q.pop_front();

        // Wait until the DUT's nonblocking assignment to rd_data commits.
        #1ps;

        assert (rd_data === expected)
            else $fatal(
                1,
                "Read mismatch: expected=%h actual=%h",
                expected,
                rd_data
            );

        @(negedge rd_clk);
        rd_en = 1'b0;
    endtask

    initial begin
        $dumpfile("results/waveform.vcd");
        $dumpvars(1, async_fifo_tb);
    end

    // ------------------------------------------------------------
    // Main verification
    // ------------------------------------------------------------

    initial begin
        reset_n = 1'b0;
        wr_en   = 1'b0;
        rd_en   = 1'b0;
        wr_data = '0;

        // --------------------------------------------------------
        // Reset
        // --------------------------------------------------------
        reset_dut();

        assert (empty)
            else $fatal(1, "FIFO not empty after reset");

        assert (!full)
            else $fatal(1, "FIFO full after reset");

        // --------------------------------------------------------
        // Basic ordering
        // --------------------------------------------------------
        write_one(32'hAAAA_AAAA);
        write_one(32'hBBBB_BBBB);
        write_one(32'hCCCC_CCCC);

        read_one();
        read_one();
        read_one();

        while (!empty)
            @(posedge rd_clk);

        assert (expected_q.size() == 0)
            else $fatal(1, "Scoreboard not empty after basic transfer");

        // --------------------------------------------------------
        // Fill FIFO
        // --------------------------------------------------------
        for (int i = 0; i < DEPTH; i++) begin
            write_one(32'h1000_0000 + i);
        end

        assert (full)
            else $fatal(1, "FIFO did not become full");

        assert (expected_q.size() == DEPTH)
            else $fatal(
                1,
                "Expected queue size incorrect after fill: %0d",
                expected_q.size()
            );

        // --------------------------------------------------------
        // Overflow rejection
        // --------------------------------------------------------
        @(negedge wr_clk);
        wr_data = 32'hDEAD_BEEF;
        wr_en   = 1'b1;

        @(posedge wr_clk);

        assert (full)
            else $fatal(1, "FIFO unexpectedly deasserted full");

        // Do not push DEAD_BEEF into scoreboard.
        // wr_en && !full was false.

        @(negedge wr_clk);
        wr_en = 1'b0;

        assert (expected_q.size() == DEPTH)
            else $fatal(1, "Overflow attempt changed scoreboard");

        // --------------------------------------------------------
        // Drain FIFO
        // --------------------------------------------------------
        for (int i = 0; i < DEPTH; i++) begin
            read_one();
        end

        while (!empty)
            @(posedge rd_clk);

        assert (expected_q.size() == 0)
            else $fatal(1, "Scoreboard not empty after drain");

        // --------------------------------------------------------
        // Underflow rejection
        // --------------------------------------------------------
        @(negedge rd_clk);
        rd_en = 1'b1;

        @(posedge rd_clk);

        assert (empty)
            else $fatal(1, "FIFO unexpectedly deasserted empty");

        @(negedge rd_clk);
        rd_en = 1'b0;

        assert (expected_q.size() == 0)
            else $fatal(1, "Underflow attempt changed scoreboard");

        // --------------------------------------------------------
        // Wraparound
        // --------------------------------------------------------
        for (int round = 0; round < 4; round++) begin
            for (int i = 0; i < DEPTH; i++) begin
                write_one(
                    DATA_WIDTH'((round << 16) | i)
                );
            end

            for (int i = 0; i < DEPTH; i++) begin
                read_one();
            end
        end

        assert (expected_q.size() == 0)
            else $fatal(1, "Scoreboard nonempty after wraparound");

        // --------------------------------------------------------
        // Reset with queued data
        // --------------------------------------------------------
        write_one(32'h1111_1111);
        write_one(32'h2222_2222);
        write_one(32'h3333_3333);

        assert (expected_q.size() == 3)
            else $fatal(1, "Pre-reset scoreboard state incorrect");

        reset_dut();

        assert (empty)
            else $fatal(1, "FIFO not empty after mid-traffic reset");

        assert (!full)
            else $fatal(1, "FIFO full after mid-traffic reset");

        assert (expected_q.size() == 0)
            else $fatal(1, "Scoreboard not cleared by reset");

        // --------------------------------------------------------
        // Concurrent asynchronous traffic
        // --------------------------------------------------------
        fork
            begin : writer
                for (int i = 0; i < 100; i++) begin
                    write_one(
                        DATA_WIDTH'(32'h8000_0000 + i)
                    );
                end
            end

            begin : reader
                for (int i = 0; i < 100; i++) begin
                    read_one();
                end
            end
        join

        assert (expected_q.size() == 0)
            else $fatal(
                1,
                "Scoreboard contains %0d unread entries after concurrent traffic",
                expected_q.size()
            );

        while (!empty)
            @(posedge rd_clk);

        assert (!full)
            else $fatal(1, "FIFO unexpectedly full after final drain");

        $display("PASS: asynchronous FIFO verification completed");
        $finish;
    end

endmodule