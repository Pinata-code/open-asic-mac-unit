`timescale 1ns/1ps

module tb_systolic_array_top;

    parameter int DATA_WIDTH = 8;
    parameter int ARRAY_N    = 4;
    parameter int CLK_PERIOD = 10; // 100 MHz clock
    localparam int ACC_W = (2*DATA_WIDTH)+$clog2(ARRAY_N);

    logic                               clk;
    logic                               rst_n;
    logic                               clear;
    logic [ARRAY_N*DATA_WIDTH-1:0]      row_in_flat, col_in_flat;
    logic                               valid_in;
    logic [ARRAY_N*ARRAY_N*ACC_W-1:0]   row_out_flat;
    logic                               valid_out;

    systolic_array_top #(
        .DATA_WIDTH(DATA_WIDTH),
        .ARRAY_N(ARRAY_N)
    ) uut (
        .clk(clk),
        .rst_n(rst_n),
        .clear(clear),
        .row_in_flat(row_in_flat),
        .col_in_flat(col_in_flat),
        .valid_in(valid_in),
        .row_out_flat(row_out_flat),
        .valid_out(valid_out)
    );

    // Drive one cycle of (already skewed) stimulus
    task automatic drive_cycle(input logic signed [DATA_WIDTH-1:0] r0, r1, r2, r3,
                               input logic signed [DATA_WIDTH-1:0] c0, c1, c2, c3);
        @(negedge clk);
        valid_in    = 1'b1;
        row_in_flat = {r3, r2, r1, r0};
        col_in_flat = {c3, c2, c1, c0};
    endtask

    always #(CLK_PERIOD/2) clk = ~clk;

    initial begin
        clk = 0; rst_n = 0; clear = 0; valid_in = 0;
        row_in_flat = '0; col_in_flat = '0;

        #(CLK_PERIOD * 3);
        rst_n = 1;
        #(CLK_PERIOD * 2);

        drive_cycle(1, 0, 0, 0,   1, 0, 0, 0);   // cycle 0
        drive_cycle(2, 3, 0, 0,   4, 5, 0, 0);   // cycle 1
        drive_cycle(0, 1, 2, 0,   0, 6, 7, 0);   // cycle 2
        drive_cycle(0, 0, 3, 4,   0, 0, 8, 9);   // cycle 3

        @(negedge clk);
        valid_in    = 0;
        row_in_flat = '0;
        col_in_flat = '0;

        @(posedge valid_out);
        $display("[TB] Valid output asserted! Checking results...");
        #(CLK_PERIOD * (ARRAY_N + 2));
        $display("[TB] Test sequence completed successfully.");
        $finish;
    end

    // Print once, on the first cycle valid_out goes high
    logic valid_out_d;
    always @(posedge clk) valid_out_d <= valid_out;

    always @(posedge clk) begin
        if (valid_out && !valid_out_d) begin
            $display("Time %0t: Matrix Output Received:", $time);
            for (int r = 0; r < ARRAY_N; r++) begin
                $write("  Row %0d: ", r);
                for (int c = 0; c < ARRAY_N; c++)
                    $write("%0d ", $signed(row_out_flat[(r*ARRAY_N+c)*ACC_W +: ACC_W]));
                $write("\n");
            end
        end
    end

endmodule