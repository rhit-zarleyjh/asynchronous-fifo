`timescale 1ns/1ps
module async_fifo #(
    parameter int DATA_WIDTH = 32,
    parameter int ADDR_WIDTH = 3
) (
    input logic reset_n,
    
    // Write domain
    input logic wr_clk,
    input logic wr_en,
    input logic [DATA_WIDTH-1:0] wr_data,
    output logic full,

    // Read domain
    input logic rd_clk,
    input logic rd_en,
    output logic [DATA_WIDTH-1:0] rd_data,
    output logic empty
);
    // Local parameters
    localparam int PTR_WIDTH = ADDR_WIDTH + 1;
    localparam int DEPTH = 1 << ADDR_WIDTH;

    // Storage
    logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    // Reset synchronizers
    logic wr_reset_n;
    logic wr_sync_reset;
    
    always_ff @(posedge wr_clk or negedge reset_n) begin
        if (!reset_n) begin
            wr_sync_reset <= 1'b0;
            wr_reset_n <= 1'b0;
        end
        else begin
            wr_sync_reset <= 1'b1;
            wr_reset_n <= wr_sync_reset;
        end
    end

    logic rd_reset_n;
    logic rd_sync_reset;
        
    always_ff @(posedge rd_clk or negedge reset_n) begin
        if (!reset_n) begin
            rd_sync_reset <= 1'b0;
            rd_reset_n <= 1'b0;
        end
        else begin
            rd_sync_reset <= 1'b1;
            rd_reset_n <= rd_sync_reset;
        end
    end

    // ------------------- Write Domain
    // Write pointer state
    logic [PTR_WIDTH-1:0] wr_bin;
    logic [PTR_WIDTH-1:0] wr_bin_next;
    logic [PTR_WIDTH-1:0] wr_gray;
    logic [PTR_WIDTH-1:0] wr_gray_next;
    logic full_next;

    // Cross-domain synchronized from read to write domain
    logic [PTR_WIDTH-1:0] rd_gray_sync1;
    logic [PTR_WIDTH-1:0] rd_gray_sync2;

    always_ff @(posedge wr_clk or negedge wr_reset_n) begin
        if (!wr_reset_n) begin
            rd_gray_sync1 <= '0;
            rd_gray_sync2 <= '0;
        end
        else begin
            rd_gray_sync1 <= rd_gray;
            rd_gray_sync2 <= rd_gray_sync1;
        end
    end

    // ------------------- Read Domain
    // Read pointer state
    logic [PTR_WIDTH-1:0] rd_bin;
    logic [PTR_WIDTH-1:0] rd_bin_next;
    logic [PTR_WIDTH-1:0] rd_gray;
    logic [PTR_WIDTH-1:0] rd_gray_next;
    logic empty_next;

    // Cross-domain synchronized from write to read domain
    logic [PTR_WIDTH-1:0] wr_gray_sync1;
    logic [PTR_WIDTH-1:0] wr_gray_sync2;

    always_ff @(posedge rd_clk or negedge rd_reset_n) begin
        if (!rd_reset_n) begin
            wr_gray_sync1 <= '0;
            wr_gray_sync2 <= '0;
        end
        else begin
            wr_gray_sync1 <= wr_gray;
            wr_gray_sync2 <= wr_gray_sync1;
        end
    end

    // Write-domain combinational next-state logic
    always_comb begin
        wr_bin_next = wr_bin + PTR_WIDTH'(wr_en && !full);
        wr_gray_next = wr_bin_next ^ (wr_bin_next >> 1);
        
        full_next = (wr_gray_next == {~rd_gray_sync2[ADDR_WIDTH:ADDR_WIDTH-1], rd_gray_sync2[ADDR_WIDTH-2:0]});
    end
    
    // Read-domain combinational next-state logic
    always_comb begin
        rd_bin_next = rd_bin + PTR_WIDTH'(rd_en && !empty);
        rd_gray_next = rd_bin_next ^ (rd_bin_next >> 1);

        empty_next = (rd_gray_next == wr_gray_sync2);
    end

    // Write-domain pointer/flag state, memory write
    always_ff @(posedge wr_clk or negedge wr_reset_n) begin
        if (!wr_reset_n) begin
            wr_bin <= '0;
            wr_gray <= '0;
            full <= 1'b0;
        end
        else begin
            wr_bin <= wr_bin_next;
            wr_gray <= wr_gray_next;
            full <= full_next;

            if (wr_en && !full) begin    
                mem[wr_bin[ADDR_WIDTH-1:0]] <= wr_data;
            end
        end
    end
    
    // Read-domain pointer/flag state, memory read
    always_ff @(posedge rd_clk or negedge rd_reset_n) begin
        if (!rd_reset_n) begin
            rd_bin <= '0;
            rd_gray <= '0;
            empty <= 1'b1;
            rd_data <= '0;
        end
        else begin
            rd_bin <= rd_bin_next;
            rd_gray <= rd_gray_next;
            empty <= empty_next;

            if (rd_en && !empty) begin
                rd_data <= mem[rd_bin[ADDR_WIDTH-1:0]];
            end
        end
    end


endmodule